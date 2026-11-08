# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
#
# Grok Bot maintains its own weekly quota pool (Grok Bot Plan) separate from
# Cursor's monthly allowance. This adapter reads the signed-in session from the
# Grok Bot desktop config directory, queries GetSandUsageStatus over Connect-RPC
# with the secret header in a curl --config pipe, and falls back to the local
# weekly-usage persistence snapshot on transient network failures.

# The 3-byte Electron safeStorage version prefix of a base64 secret: "v10"
# for the basic text store, "v11" when the desktop keyring holds the key, or
# nothing when the value is not a safeStorage blob.
grokbot_secret_version() {
  local raw_b64="$1" prefix
  [ -n "$raw_b64" ] || return 0
  prefix="$(printf '%s' "$raw_b64" | head -c 8 | base64 -d 2>/dev/null | head -c 3 || true)"
  case "$prefix" in v10|v11) printf '%s' "$prefix" ;; esac
}

grokbot_decrypt_secret() {
  local raw_b64="$1"
  [ -n "$raw_b64" ] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  # Only the basic text store (v10) has a fixed key. A v11 secret is
  # encrypted with a key kept in the desktop keyring, which this adapter
  # does not read.
  [ "$(grokbot_secret_version "$raw_b64")" = "v10" ] || return 1

  # Linux Electron SafeStorage encrypts secrets under PBKDF2("peanuts", "saltysalt", 1, 16)
  # -> key fd621fe5a2b402539dfa147ca9272778, 16-space IV, prefixed with 3-byte "v10".
  # The key is Chromium's published constant for that store, not a secret.
  printf '%s' "$raw_b64" \
    | base64 -d 2>/dev/null \
    | tail -c +4 \
    | openssl enc -d -aes-128-cbc \
        -K fd621fe5a2b402539dfa147ca9272778 \
        -iv 20202020202020202020202020202020 2>/dev/null
}

grokbot_resolve_config_dir() {
  if [ -n "${GROKBOT_CONFIG_DIR+x}" ]; then
    [ -n "${GROKBOT_CONFIG_DIR}" ] && printf '%s\n' "${GROKBOT_CONFIG_DIR}"
    return 0
  fi
  local dir
  for dir in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/Grok Bot" \
    "$HOME/Library/Application Support/Grok Bot"; do
    if [ -r "$dir/sand-secrets.json" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

# Print the active account's encrypted access token (base64), or nothing.
grokbot_token_blob() {
  local secrets_file="$1"
  [ -r "$secrets_file" ] || return 0
  jq -r '
    .["cursor-accounts"] // empty
    | fromjson? // empty
    | .accounts[.active // empty]["cursor-access-token"] // empty
  ' "$secrets_file" 2>/dev/null || true
}

grokbot_read_token() {
  grokbot_decrypt_secret "$(grokbot_token_blob "$1")" || true
}

grokbot_read_email() {
  local config_dir="$1" secrets_file="$1/sand-secrets.json" sentry_file="$1/sentry/scope_v3.json"
  local prof_b64 profile email=""
  if [ -r "$secrets_file" ]; then
    prof_b64="$(jq -r '
      .["cursor-accounts"] // empty
      | fromjson? // empty
      | .accounts[.active // empty]["cursor-account-profile"] // empty
    ' "$secrets_file" 2>/dev/null || true)"
    if [ -n "$prof_b64" ]; then
      profile="$(grokbot_decrypt_secret "$prof_b64" || true)"
      email="$(printf '%s' "$profile" | jq -r 'if (.email | type) == "string" then .email else empty end' 2>/dev/null || true)"
    fi
  fi
  if [ -z "$email" ] && [ -r "$sentry_file" ]; then
    email="$(jq -r '.scope.user.email // empty' "$sentry_file" 2>/dev/null || true)"
  fi
  printf '%s' "${email:-Grok Bot account}"
}

grokbot_read_offline_cache() {
  local persist_dir="$1/sand-client-persistence" blob reading
  [ -d "$persist_dir" ] || return 1
  for blob in "$persist_dir"/*.blob; do
    [ -r "$blob" ] || continue
    reading="$(jq -c '
      select((.value.reading.usage | type) == "object" and (.value.reading.usage.percentUsed != null))
      | .value.reading
    ' "$blob" 2>/dev/null || true)"
    if [ -n "$reading" ]; then
      printf '%s\n' "$reading"
      return 0
    fi
  done
  return 1
}

# Print the Grok Bot app's own persisted weekly reading as a usage payload,
# keeping the time the app fetched it, or fail when there is none. It needs
# no token, so it also serves a session the adapter cannot decrypt.
grokbot_emit_offline_cache() {
  local config_dir="$1" email="$2" cached
  cached="$(grokbot_read_offline_cache "$config_dir")" || return 1
  jq -c --arg email "$email" '
    def clamp($n):
      if $n == null then 0 else ([0, $n] | max | [100, .] | min | (. * 100 | round) / 100) end;
    .usage as $u
    | ((.readAtMs // (now * 1000)) / 1000 | floor | todateiso8601) as $updated
    | ($u.nextResetMs // null) as $reset_ms
    | ($reset_ms != null and (now * 1000) >= $reset_ms) as $expired
    | (if $expired then 0 else clamp($u.percentUsed) end) as $pct
    | (if $reset_ms == null or $expired then null else (($reset_ms / 1000 | floor) | todateiso8601) end) as $resets
    | (($u.grokPlanLabel // "") | tostring | gsub("^\\s+|\\s+$"; "")) as $plan
    | (($u.unifiedPlanName // "") | tostring | gsub("^\\s+|\\s+$"; "")) as $tier
    | (if ($plan | length) > 0 and ($tier | length) > 0 then ($plan + " (" + $tier + ")")
        elif ($plan | length) > 0 then $plan
        elif ($tier | length) > 0 then $tier
        else "desktop" end) as $login
    | {
        provider: "grokbot",
        source: "grokbot-offline-cache",
        usage: {
          identity: { providerID: "grokbot", accountEmail: $email, loginMethod: $login },
          accountEmail: $email,
          loginMethod: $login,
          primary: {
            usedPercent: $pct,
            windowMinutes: 10080,
            resetsAt: $resets,
            resetDescription: null
          },
          secondary: null,
          tertiary: null,
          updatedAt: $updated
        },
        credits: { remaining: $login }
      }
  ' <<<"$cached"
}

fetch_grokbot_native() {
  local config_dir secrets_file token email endpoint tmp_body http_status curl_status=0
  config_dir="$(grokbot_resolve_config_dir || true)"
  secrets_file="${config_dir:+$config_dir/sand-secrets.json}"

  if [ -z "$config_dir" ] || [ ! -r "$secrets_file" ]; then
    json_error grokbot grokbot-desktop 2 provider "No Grok Bot sign-in on this computer. Launch Grok Bot and sign in."
    return 0
  fi

  if [ "$(grokbot_secret_version "$(grokbot_token_blob "$secrets_file")")" = "v11" ]; then
    # The app's last reading needs no token; without one the session cannot
    # be read at all.
    grokbot_emit_offline_cache "$config_dir" "$(grokbot_read_email "$config_dir")" && return 0
    json_error grokbot grokbot-desktop 2 provider "Grok Bot keeps its session key in the desktop keyring, which this plugin does not read. Start Grok Bot with --password-store=basic and sign in again."
    return 0
  fi

  token="$(grokbot_read_token "$secrets_file")"
  if [ -z "$token" ]; then
    json_error grokbot grokbot-desktop 2 provider "Could not read Grok Bot desktop session. Sign in with Grok Bot again."
    return 0
  fi

  email="$(grokbot_read_email "$config_dir")"
  endpoint="${GROKBOT_API_URL:-https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus}"
  tmp_body="$(mktemp)"

  http_status="$(curl -sS --max-time 10 --proto '=https' -o "$tmp_body" -w '%{http_code}' \
    -X POST "$endpoint" \
    -H "Content-Type: application/json" \
    -H "Connect-Protocol-Version: 1" \
    --config <(curl_header_config "Authorization: Bearer ${token}") \
    -d '{}' 2>/dev/null)" || curl_status=$?

  if [ "$curl_status" -eq 0 ] && [ "$http_status" = "200" ]; then
    if jq -e '(.usagePercent | type) == "number" or ((.usagePercent | type) == "string" and (.usagePercent | test("^-?[0-9]+([.][0-9]+)?$")))' "$tmp_body" >/dev/null 2>&1; then
      jq -c --arg email "$email" '
        def num($v):
          if ($v | type) == "number" then
            if (($v | isnan) or ($v | isinfinite)) then null else $v end
          elif ($v | type) == "string" and ($v | test("^-?[0-9]+([.][0-9]+)?$")) then ($v | tonumber)
          else null end;
        def clamp($n):
          if $n == null then 0 else ([0, $n] | max | [100, .] | min | (. * 100 | round) / 100) end;
        def ts_sec($v):
          if ($v | type) == "string" and ($v | length) > 0 then
            try ($v | sub("[.][0-9]+"; "") | sub("[+]00:00$"; "Z") | fromdateiso8601) catch null
          else null end;

        (clamp(num(.usagePercent))) as $pct
        | (ts_sec(.currentPeriodStart)) as $start
        | (ts_sec(.nextResetTimestampUtc)) as $end
        | (if $start != null and $end != null and $end > $start
            then (((($end - $start) / 60) | round) | if . < 1 then 10080 else . end)
            else 10080 end) as $minutes
        | (if (.nextResetTimestampUtc | type) == "string" and (.nextResetTimestampUtc | length) > 0
            then .nextResetTimestampUtc else null end) as $resets
        | ((.grokPlanLabel // "") | tostring | gsub("^\\s+|\\s+$"; "")) as $plan
        | ((.cursorPlanName // "") | tostring | gsub("^\\s+|\\s+$"; "")) as $tier
        | (if ($plan | length) > 0 and ($tier | length) > 0 then ($plan + " (" + $tier + ")")
            elif ($plan | length) > 0 then $plan
            elif ($tier | length) > 0 then $tier
            else "desktop" end) as $login
        | {
            provider: "grokbot",
            source: "grokbot-desktop",
            usage: {
              identity: { providerID: "grokbot", accountEmail: $email, loginMethod: $login },
              accountEmail: $email,
              loginMethod: $login,
              primary: {
                usedPercent: $pct,
                windowMinutes: $minutes,
                resetsAt: $resets,
                resetDescription: null
              },
              secondary: null,
              tertiary: null,
              updatedAt: (now | todateiso8601)
            },
            credits: { remaining: $login }
          }
      ' "$tmp_body"
      rm -f "$tmp_body"
      return 0
    fi
    rm -f "$tmp_body"
    json_error grokbot grokbot-desktop 1 provider "Grok Bot usage response schema changed."
    return 0
  fi
  rm -f "$tmp_body"

  if [ "$http_status" = "401" ] || [ "$http_status" = "403" ]; then
    json_error grokbot grokbot-desktop "$http_status" provider "Grok Bot session expired. Open Grok Bot and sign in again."
    return 0
  fi

  # Transient failure: serve the app's own persisted snapshot with its
  # original fetch time.
  grokbot_emit_offline_cache "$config_dir" "$email" && return 0

  if [ "$http_status" = "429" ]; then
    json_error grokbot grokbot-desktop 429 provider "Grok Bot usage endpoint is rate-limited. Retry later."
    return 0
  fi
  json_error grokbot grokbot-desktop "${http_status:-1}" runtime "Grok Bot usage request failed (HTTP ${http_status:-0})."
  return 0
}
