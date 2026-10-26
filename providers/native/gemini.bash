# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.

# Gemini CLI sign-in: an expired access token is renewed in memory with the
# public installed-app client the CLI itself ships
# (packages/core/src/code_assist/oauth2.ts in google-gemini/gemini-cli).
# The renewed token is never written back to ~/.gemini.
gemini_cli_access_token() {
  local creds="$1" access expiry refresh now_ms tmp_body http_status
  access="$(jq -r '.access_token // empty' "$creds" 2>/dev/null)"
  expiry="$(jq -r '.expiry_date // 0 | tonumber? // 0 | floor' "$creds" 2>/dev/null)"
  now_ms="$(( $(date +%s) * 1000 + 60000 ))"
  if [ -n "$access" ] && [ "${expiry:-0}" -gt "$now_ms" ] 2>/dev/null; then
    printf '%s' "$access"
    return 0
  fi
  refresh="$(jq -r '.refresh_token // empty' "$creds" 2>/dev/null)"
  [ -n "$refresh" ] || return 1
  tmp_body="$(mktemp)"
  # refresh_token@- reads the secret from stdin, so it never reaches argv.
  http_status="$(printf '%s' "$refresh" | curl -sS --max-time 10 -X POST \
    "${GEMINI_CLI_TOKEN_URL:-https://oauth2.googleapis.com/token}" \
    -o "$tmp_body" -w '%{http_code}' \
    --data-urlencode "client_id=${GEMINI_CLI_OAUTH_CLIENT_ID:-681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com}" \
    --data-urlencode "client_secret=${GEMINI_CLI_OAUTH_CLIENT_SECRET:-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}" \
    --data-urlencode "refresh_token@-" \
    --data-urlencode "grant_type=refresh_token" 2>/dev/null || true)"
  access=""
  [ "$http_status" = "200" ] && access="$(jq -r '.access_token // empty' "$tmp_body" 2>/dev/null)"
  rm -f "$tmp_body"
  [ -n "$access" ] || return 1
  printf '%s' "$access"
}

# POST one Code Assist method; the body lands in $3. Prints the HTTP status.
gemini_code_assist_post() {
  local token="$1" method="$2" out="$3" body="$4"
  curl -sS --max-time 10 -X POST \
    "${GEMINI_CODE_ASSIST_ENDPOINT:-https://cloudcode-pa.googleapis.com}/v1internal:${method}" \
    --config <(curl_header_config "Authorization: Bearer ${token}") \
    -H "Content-Type: application/json" \
    -o "$out" -w '%{http_code}' --data "$body" 2>/dev/null || true
}

# Gemini CLI quota from the Code Assist API the CLI uses for /stats
# (loadCodeAssist for the project, then retrieveUserQuota). Prints one result
# object and returns 0, or returns 1 so the caller falls back.
fetch_gemini_cli_quota() {
  local creds="$1" account="$2" token tmp_load tmp_quota http_status project
  token="$(gemini_cli_access_token "$creds")" || return 1
  tmp_load="$(mktemp)"
  tmp_quota="$(mktemp)"
  http_status="$(gemini_code_assist_post "$token" loadCodeAssist "$tmp_load" \
    '{"metadata":{"ideType":"IDE_UNSPECIFIED","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}}')"
  if [ "$http_status" != "200" ] || ! jq -e 'type == "object"' "$tmp_load" >/dev/null 2>&1; then
    rm -f "$tmp_load" "$tmp_quota"
    return 1
  fi
  project="${GOOGLE_CLOUD_PROJECT:-${GOOGLE_CLOUD_PROJECT_ID:-}}"
  [ -n "$project" ] || project="$(jq -r '.cloudaicompanionProject // empty | strings' "$tmp_load")"
  if [ -z "$project" ]; then
    # No Code Assist project: say why (Google retired the individual free
    # tier for this client) instead of a bare "authenticated" note.
    local reason
    reason="$(jq -r '[.ineligibleTiers[]?.reasonMessage | strings] | first // empty' "$tmp_load")"
    rm -f "$tmp_load" "$tmp_quota"
    # A configured API key still gives a useful card; prefer it.
    [ -z "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-${GOOGLE_GENERATIVE_AI_API_KEY:-}}}" ] || return 1
    [ -n "$reason" ] || reason="Gemini CLI has no Code Assist project; set GOOGLE_CLOUD_PROJECT for a Standard or Enterprise license."
    json_error gemini gemini-cli 403 provider "$reason"
    return 0
  fi
  http_status="$(gemini_code_assist_post "$token" retrieveUserQuota "$tmp_quota" \
    "$(jq -cn --arg project "$project" '{project:$project}')")"
  if [ "$http_status" != "200" ] || ! jq -e '.buckets | type == "array" and length > 0' "$tmp_quota" >/dev/null 2>&1; then
    local message
    message="$(jq -r '.error.message // empty | strings' "$tmp_quota" 2>/dev/null)"
    [ -n "$message" ] || message="Gemini CLI quota returned HTTP ${http_status:-0}."
    rm -f "$tmp_load" "$tmp_quota"
    json_error gemini gemini-cli "${http_status:-1}" provider "$message"
    return 0
  fi
  # Each bucket is one model's daily allowance; the most used ones become
  # the card windows.
  jq -c --arg account "$account" --arg tier "$(jq -r '.currentTier.name // .paidTier.name // empty' "$tmp_load")" '
    [.buckets[] | select(type == "object" and (.remainingFraction | type) == "number")
      | {
          usedPercent: ((1 - .remainingFraction) * 100 | if . < 0 then 0 elif . > 100 then 100 else . end),
          windowMinutes: 1440,
          resetsAt: (.resetTime // null),
          resetDescription: ("Daily · " + (.modelId // "Gemini")
            + (if (.tokenType // "") != "" and .tokenType != "REQUESTS" then " " + (.tokenType | ascii_downcase) else "" end)),
          displayValue: null
        }]
    | sort_by(-.usedPercent) as $w
    | ($account + (if $tier != "" then " · " + $tier else "" end)) as $identity
    | {
        provider: "gemini",
        source: "gemini-cli",
        usage: {
          identity: {providerID: "gemini", accountEmail: $identity, loginMethod: "oauth"},
          accountEmail: $identity,
          loginMethod: "oauth",
          primary: ($w[0] // null),
          secondary: ($w[1] // null),
          tertiary: ($w[2] // null),
          updatedAt: (now | todateiso8601)
        }
      }
    | if .usage.primary == null then
        {provider: "gemini", source: "gemini-cli",
         error: {code: 1, kind: "provider", message: "Gemini CLI quota returned no usable bucket."}}
      else . end
  ' "$tmp_quota"
  rm -f "$tmp_load" "$tmp_quota"
}

fetch_gemini_native() {
  local creds="$HOME/.gemini/oauth_creds.json" account=""
  if [ -f "$creds" ] && jq -e '.access_token or .refresh_token' "$creds" >/dev/null 2>&1; then
    account="$(jq -r '.active // empty | strings' "$HOME/.gemini/google_accounts.json" 2>/dev/null || true)"
    [ -n "$account" ] || account="Gemini CLI"
    # The CLI sign-in carries real quota; an API key only proves it is valid.
    fetch_gemini_cli_quota "$creds" "$account" && return 0
  fi

  local key="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-${GOOGLE_GENERATIVE_AI_API_KEY:-}}}"
  if [ -n "$key" ]; then
    local tmp_body http_status
    tmp_body="$(mktemp)"
    # Key goes in a header, not the query string — URLs leak through process
    # listings and proxy logs.
    http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
      --config <(curl_header_config "x-goog-api-key: ${key}") \
      "https://generativelanguage.googleapis.com/v1beta/models" 2>/dev/null || true)"
    if [ "$http_status" = "200" ]; then
      rm -f "$tmp_body"
      json_note_usage gemini gemini-api-key "Gemini API key" "api-key" "Quota visible in AI Studio" "AI Studio"
      return 0
    fi

    local message
    message="$(jq -r '.error.message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Gemini API key check returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error gemini gemini-api-key "${http_status:-1}" provider "$message"
    return 0
  fi

  if [ -n "$account" ]; then
    json_note_usage gemini gemini-cli "$account" "oauth" "Gemini CLI authenticated" "AI Studio"
    return 0
  fi

  json_error gemini gemini-local 2 provider "Gemini is not authenticated locally. Run gemini once, or set GEMINI_API_KEY/GOOGLE_API_KEY."
}
