#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
CONFIG_HOME="$TMP_ROOT/.config"
DB="$CONFIG_HOME/Antigravity IDE/User/globalStorage/state.vscdb"
mkdir -p "$FAKE_BIN" "$(dirname "$DB")"
: > "$DB"

export FAKE_CURL_LOG="$TMP_ROOT/curl-argv.log"
export FAKE_CURL_STDIN="$TMP_ROOT/curl-stdin.log"
export FAKE_FETCH_COUNT_FILE="$TMP_ROOT/fetch-count"
export REFRESH_ONE='1//ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef'
export REFRESH_TWO='1//zyxwvutsrqponmlkjihgfedcba987654'

cat > "$FAKE_BIN/sqlite3" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$REFRESH_ONE"
SH

cat > "$FAKE_BIN/secret-tool" <<'SH'
#!/usr/bin/env bash
printf '{"refresh_token":"%s"}\n' "$REFRESH_TWO"
SH

cat > "$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >> "$FAKE_CURL_LOG"
printf '\n' >> "$FAKE_CURL_LOG"

out=""
url=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o)
      out="${args[$((i + 1))]}"
      i=$((i + 1))
      ;;
    http://*|https://*)
      url="${args[$i]}"
      ;;
  esac
done

write_body() {
  printf '%s' "$1" > "$out"
}

case "$url" in
  */token)
    refresh="$(cat)"
    printf '%s\n' "$refresh" >> "$FAKE_CURL_STDIN"
    if [ "$refresh" = "$REFRESH_TWO" ]; then
      email="two@example.invalid"
      access="access-two"
    else
      email="one@example.invalid"
      access="access-one"
    fi
    payload="$(printf '{"email":"%s"}' "$email" | base64 | tr -d '\n=' | tr '+/' '-_')"
    write_body "{\"access_token\":\"$access\",\"id_token\":\"x.$payload.x\"}"
    printf '200'
    ;;
  */v1internal:loadCodeAssist)
    case "${FAKE_LOAD_MODE:-success}" in
      missing)
        write_body '{}'
        printf '200'
        ;;
      forbidden)
        write_body '{"error":{"message":"forbidden"}}'
        printf '403'
        ;;
      *)
        write_body '{"cloudaicompanionProject":{"id":"project-1"}}'
        printf '200'
        ;;
    esac
    ;;
  */v1internal:fetchAvailableModels)
    count=0
    [ ! -f "$FAKE_FETCH_COUNT_FILE" ] || count="$(cat "$FAKE_FETCH_COUNT_FILE")"
    count=$((count + 1))
    printf '%s' "$count" > "$FAKE_FETCH_COUNT_FILE"
    mode="${FAKE_FETCH_MODE:-success}"
    if [ "$mode" = "partial" ] && [ "$count" -ge 2 ]; then mode="rate"; fi
    case "$mode" in
      rate)
        write_body '{"error":{"message":"rate limited"}}'
        printf '429'
        ;;
      schema)
        write_body '{"unexpected":true}'
        printf '200'
        ;;
      *)
        write_body '{"models":{"gemini-pro":{"displayName":"Gemini Pro","quotaInfo":{"remainingFraction":0.2,"resetTime":"2026-07-20T00:00:00Z"}}}}'
        printf '200'
        ;;
    esac
    ;;
  *)
    write_body '{"error":{"message":"unexpected fake URL"}}'
    printf '500'
    ;;
esac
SH

chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/sqlite3" "$FAKE_BIN/secret-tool"

run_adapter() {
  PATH="$FAKE_BIN:$PATH" \
    XDG_CONFIG_HOME="$CONFIG_HOME" \
    ANTIGRAVITY_API_BASE_URL="https://fake.antigravity.invalid" \
    "$ROOT/providers/get-provider-usage" antigravity ""
}

: > "$FAKE_CURL_LOG"
: > "$FAKE_CURL_STDIN"
rm -f "$FAKE_FETCH_COUNT_FILE"
MISSING_PROJECT="$(FAKE_LOAD_MODE=missing ANTIGRAVITY_STATE_DB="$DB" run_adapter)"
printf '%s' "$MISSING_PROJECT" | jq -e '
  .[0].error.code == 1
  and .[0].accountErrors[0].stage == "loadCodeAssist"
  and (.[0].error.message | contains("cloudaicompanionProject"))
' >/dev/null
if grep -q 'fetchAvailableModels' "$FAKE_CURL_LOG"; then
  echo "fetchAvailableModels was called without a Cloud Code Assist project" >&2
  exit 1
fi
if grep -Fq "$REFRESH_ONE" "$FAKE_CURL_LOG"; then
  echo "refresh token leaked into curl argv" >&2
  exit 1
fi
grep -Fxq "$REFRESH_ONE" "$FAKE_CURL_STDIN"

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_FETCH_COUNT_FILE"
FORBIDDEN="$(FAKE_LOAD_MODE=forbidden ANTIGRAVITY_STATE_DB="$DB" run_adapter)"
printf '%s' "$FORBIDDEN" | jq -e '
  .[0].error.code == 403
  and .[0].accountErrors[0].stage == "loadCodeAssist"
' >/dev/null

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_FETCH_COUNT_FILE"
RATE_LIMITED="$(FAKE_FETCH_MODE=rate ANTIGRAVITY_STATE_DB="$DB" run_adapter)"
printf '%s' "$RATE_LIMITED" | jq -e '
  .[0].error.code == 429
  and .[0].accountErrors[0].stage == "fetchAvailableModels"
' >/dev/null

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_FETCH_COUNT_FILE"
SCHEMA_CHANGED="$(FAKE_FETCH_MODE=schema ANTIGRAVITY_STATE_DB="$DB" run_adapter)"
printf '%s' "$SCHEMA_CHANGED" | jq -e '
  .[0].error.code == 1
  and (.[0].error.message | contains("models object is missing"))
' >/dev/null

: > "$FAKE_CURL_LOG"
rm -f "$FAKE_FETCH_COUNT_FILE"
PARTIAL="$(FAKE_FETCH_MODE=partial run_adapter)"
printf '%s' "$PARTIAL" | jq -e '
  .[0].provider == "antigravity"
  and .[0].error == null
  and (.[0].accounts | length) == 1
  and .[0].accounts[0].email == "one@example.invalid"
  and (.[0].accountErrors | length) == 1
  and .[0].accountErrors[0].email == "two@example.invalid"
  and .[0].accountErrors[0].code == 429
' >/dev/null

echo "Antigravity live safeguards: OK"
