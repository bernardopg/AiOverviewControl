#!/usr/bin/env bash
# OpenCode Go subscription quota tracking — fake-curl unit test.
# Verifies /zen/go/v1/usage maps to 5h (primary) + weekly (secondary) +
# monthly (tertiary) percentages, with graceful fallback to
# /zen/go/v1/models on usage failure, and hard errors on 401/403.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HDR_LOG="$TMP/headers.log"
# The dispatcher appends non-zero quota snapshots; keep fixtures out of the
# developer's real history store, regardless of the calling environment.
export XDG_CACHE_HOME="$TMP/cache"
export OPENCODE_USAGE_SOURCE=api
mkdir -p "$TMP/bin"

# Fake curl that mimics real curl behavior:
#   -o file   → writes body to file, suppresses body on stdout
#   -w FORMAT → writes FORMAT (here: the simulated HTTP status) to stdout
# OC_USAGE_MODE picks the fixture/status served for /zen/go/v1/usage; the
# stub always exits 0 so a simulated non-200 never looks like a curl network
# failure to the parent script (see test-commandcode.sh for the same note).
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""
url=""
write_code=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    -H) printf '%s\n' "${args[$((i + 1))]}" >> "${HDR_LOG:-/dev/null}" ;;
    http*) url="${args[$i]}" ;;
  esac
done
status=200
case "$url" in
  *zen/go/v1/usage*)
    case "${OC_USAGE_MODE:-ok}" in
      ok)           [ -n "$out" ] && cp "${OC_FIXTURE_DIR}/opencode-usage.json" "$out"; status=200 ;;
      unauthorized) [ -n "$out" ] && cp "${OC_FIXTURE_DIR}/opencode-error-401.json" "$out"; status=401 ;;
      forbidden)    [ -n "$out" ] && cp "${OC_FIXTURE_DIR}/opencode-error-403.json" "$out"; status=403 ;;
      down)         [ -n "$out" ] && printf '' > "$out"; status=500 ;;
      balance)      [ -n "$out" ] && cp "${OC_FIXTURE_DIR}/opencode-usage-balance.json" "$out"; status=200 ;;
      malformed)    [ -n "$out" ] && cp "${OC_FIXTURE_DIR}/opencode-usage-malformed.json" "$out"; status=200 ;;
    esac
    ;;
  *zen/go/v1/models*)
    [ -n "$out" ] && cp "${OC_FIXTURE_DIR}/opencode-models.json" "$out"
    status=200
    ;;
esac
if [ "$write_code" -eq 1 ]; then printf '%s' "$status"; fi
exit 0
STUB
chmod +x "$TMP/bin/curl"

run() { PATH="$TMP/bin:$PATH" HDR_LOG="$HDR_LOG" OC_FIXTURE_DIR="$ROOT/tests/fixtures" "$@" "$ROOT/providers/get-provider-usage" opencode 2>/dev/null; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Happy path — /zen/go/v1/usage returns 5h + weekly + monthly percentages.
out="$(OC_USAGE_MODE=ok run env -u OPENCODE_API_KEY OPENCODE_API_KEY=user_test)"
[ "$(jq -r '.[0].source'                            <<<"$out")" = "opencode-usage" ]         || fail "source"
[ "$(jq -r '.[0].usage.primary.windowMinutes'       <<<"$out")" = "300" ]                    || fail "5h minutes"
[ "$(jq -r '.[0].usage.primary.resetDescription'    <<<"$out")" = "5h" ]                     || fail "5h label"
[ "$(jq -r '.[0].usage.primary.usedPercent'         <<<"$out")" = "42" ]                     || fail "5h percent"
[ "$(jq -r '.[0].usage.secondary.windowMinutes'     <<<"$out")" = "10080" ]                  || fail "weekly minutes"
[ "$(jq -r '.[0].usage.secondary.resetDescription'  <<<"$out")" = "weekly" ]                 || fail "weekly label"
[ "$(jq -r '.[0].usage.secondary.usedPercent'       <<<"$out")" = "18" ]                     || fail "weekly percent"
[ "$(jq -r '.[0].usage.tertiary.resetDescription'   <<<"$out")" = "monthly" ]                || fail "monthly label"
[ "$(jq -r '.[0].usage.tertiary.usedPercent'        <<<"$out")" = "7" ]                      || fail "monthly percent"
[ "$(jq -r '.[0].credits.remaining'                 <<<"$out")" = "OpenCode Go" ]            || fail "credits remaining"
[ "$(jq -r '.[0].usage.identity.accountEmail'       <<<"$out")" = "OpenCode Go account" ]    || fail "identity"
[ "$(grep -c '^Authorization: Bearer user_test$' "$HDR_LOG")" -ge 1 ]                          || fail "auth header forwarded"

# 2. A local auth.json credential is a safe fallback for graphical sessions.
CLI_HOME="$TMP/cli-home"
mkdir -p "$CLI_HOME/.local/share/opencode"
printf '%s\n' '{"opencode":{"type":"api","key":"cli_test"}}' > "$CLI_HOME/.local/share/opencode/auth.json"
chmod 600 "$CLI_HOME/.local/share/opencode/auth.json"
: > "$HDR_LOG"
out="$(OC_USAGE_MODE=ok run env -u OPENCODE_API_KEY -u XDG_DATA_HOME HOME="$CLI_HOME")"
[ "$(jq -r '.[0].source' <<<"$out")" = "opencode-usage" ] || fail "CLI auth source"
grep -q '^Authorization: Bearer cli_test$' "$HDR_LOG" || fail "CLI auth header"
health="$(OC_USAGE_MODE=ok env -u OPENCODE_API_KEY -u XDG_DATA_HOME HOME="$CLI_HOME" "$ROOT/providers/get-provider-health" opencode 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "CLI auth health"

# 2b. Legacy flat {"apiKey": ...} shape (hand-edited or older opencode build)
# still resolves to a usable credential — same file path, just the old key name.
CLI_HOME_LEGACY="$TMP/cli-home-legacy"
mkdir -p "$CLI_HOME_LEGACY/.local/share/opencode"
printf '%s\n' '{"apiKey":"cli_legacy"}' > "$CLI_HOME_LEGACY/.local/share/opencode/auth.json"
chmod 600 "$CLI_HOME_LEGACY/.local/share/opencode/auth.json"
out="$(OC_USAGE_MODE=ok run env -u OPENCODE_API_KEY -u XDG_DATA_HOME HOME="$CLI_HOME_LEGACY")"
[ "$(jq -r '.[0].source' <<<"$out")" = "opencode-usage" ] || fail "legacy cli auth source"
health="$(OC_USAGE_MODE=ok env -u OPENCODE_API_KEY -u XDG_DATA_HOME HOME="$CLI_HOME_LEGACY" "$ROOT/providers/get-provider-health" opencode 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "legacy cli auth health"

# 3. No supported credential source.
EMPTY_HOME="$TMP/empty-home"
mkdir -p "$EMPTY_HOME"
out="$(OC_USAGE_MODE=ok run env -u OPENCODE_API_KEY -u XDG_DATA_HOME HOME="$EMPTY_HOME")"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "no-key error kind"
health="$(env -u OPENCODE_API_KEY -u XDG_DATA_HOME HOME="$EMPTY_HOME" "$ROOT/providers/get-provider-health" opencode 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "missing" ] || fail "no-key health"

# 4. A caller-provided XDG data directory is honored by both adapter and health check.
XDG_HOME="$TMP/xdg-data"
mkdir -p "$XDG_HOME/opencode"
printf '%s\n' '{"opencode":{"type":"api","key":"xdg_test"}}' > "$XDG_HOME/opencode/auth.json"
out="$(OC_USAGE_MODE=ok run env -u OPENCODE_API_KEY HOME="$EMPTY_HOME" XDG_DATA_HOME="$XDG_HOME")"
[ "$(jq -r '.[0].source' <<<"$out")" = "opencode-usage" ] || fail "XDG auth source"
grep -q '^Authorization: Bearer xdg_test$' "$HDR_LOG" || fail "XDG auth header"
health="$(env -u OPENCODE_API_KEY HOME="$EMPTY_HOME" XDG_DATA_HOME="$XDG_HOME" "$ROOT/providers/get-provider-health" opencode 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "XDG auth health"

# 5. useBalance is an enabled fallback, not a numerical balance the endpoint provides.
out="$(OC_USAGE_MODE=balance run env -u OPENCODE_API_KEY OPENCODE_API_KEY=user_test)"
[ "$(jq -r '.[0].credits.remaining' <<<"$out")" = "OpenCode Go · balance fallback enabled" ] || fail "balance fallback label"

# 6. A malformed quota payload must degrade to auth-only rather than invent a value.
out="$(OC_USAGE_MODE=malformed run env -u OPENCODE_API_KEY OPENCODE_API_KEY=user_test)"
[ "$(jq -r '.[0].source' <<<"$out")" = "opencode-models" ] || fail "malformed payload fallback"

# 7. 401 → hard error, no fabricated percentage.
out="$(OC_USAGE_MODE=unauthorized run env -u OPENCODE_API_KEY OPENCODE_API_KEY=user_test)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "401" ]                     || fail "401 code"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ]                || fail "401 kind"
[ "$(jq -r '.[0].error.message' <<<"$out")" = "Missing API key." ]     || fail "401 message"

# 8. 403 (valid key, no Go subscription) → hard error.
out="$(OC_USAGE_MODE=forbidden run env -u OPENCODE_API_KEY OPENCODE_API_KEY=user_test)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "403" ]                                          || fail "403 code"
[ "$(jq -r '.[0].error.message' <<<"$out")" = "OpenCode Go subscription required." ]        || fail "403 message"

# 9. /zen/go/v1/usage down (non-401/403 failure) → fallback to /zen/go/v1/models.
: > "$HDR_LOG"
out="$(OC_USAGE_MODE=down run env -u OPENCODE_API_KEY OPENCODE_API_KEY=user_test)"
[ "$(jq -r '.[0].source' <<<"$out")" = "opencode-models" ] || fail "fallback source"
grep -q '^Authorization: Bearer user_test$' "$HDR_LOG" || fail "auth header forwarded to models fallback"

echo "OK: test-opencode"
