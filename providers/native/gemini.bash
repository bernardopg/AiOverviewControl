# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_gemini_native() {
  local key="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-${GOOGLE_GENERATIVE_AI_API_KEY:-}}}"
  if [ -n "$key" ]; then
    local tmp_body http_status
    tmp_body="$(mktemp)"
    # Key goes in a header, not the query string — URLs leak through process
    # listings and proxy logs.
    http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
      -H "x-goog-api-key: ${key}" \
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

  local creds="$HOME/.gemini/oauth_creds.json"
  if [ -f "$creds" ] && jq -e '.access_token or .refresh_token' "$creds" >/dev/null 2>&1; then
    local account
    account="$(jq -r '.active // "Gemini CLI"' "$HOME/.gemini/google_accounts.json" 2>/dev/null || printf 'Gemini CLI')"
    [ -n "$account" ] && [ "$account" != "null" ] || account="Gemini CLI"
    json_note_usage gemini gemini-cli "$account" "oauth" "Gemini CLI authenticated" "AI Studio"
    return 0
  fi

  json_error gemini gemini-local 2 provider "Gemini is not authenticated locally. Run gemini once, or set GEMINI_API_KEY/GOOGLE_API_KEY."
}
