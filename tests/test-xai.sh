#!/usr/bin/env bash
# xAI / Grok usage — fake-curl unit test.
# Verifies grok login CLI-proxy billing, omitted-percent = 0%, Management API
# prepaid cents, XAI_API_KEY auth-only fallback, and health/credential errors.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HDR_LOG="$TMP/headers.log"
GROK_LOG="$TMP/grok.log"
BILLING_CALL_LOG="$TMP/billing-calls.log"
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin"

# Fake curl that mimics real curl behavior:
#   -o file   → writes body to file, suppresses body on stdout
#   -w FORMAT → writes FORMAT to stdout (independent of -o)
# The stub MUST exit 0 in every branch — the parent script runs a settings
# curl without -w and treats a non-zero exit as a network error.
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Adapters pass secret headers through --config files; expand them back to -H.
_cfg=(); while [ $# -gt 0 ]; do if [ "$1" = --config ] || [ "$1" = -K ]; then while IFS= read -r _l; do case "$_l" in 'header = "'*) _v="${_l#header = \"}"; _cfg+=(-H "${_v%\"}") ;; esac; done < "$2"; shift 2; else _cfg+=("$1"); shift; fi; done; set -- "${_cfg[@]}"
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
  *format=credits*)
    previous_calls=0
    if [ -f "${BILLING_CALL_LOG:-}" ]; then
      previous_calls="$(wc -l < "$BILLING_CALL_LOG")"
    fi
    printf 'billing\n' >> "${BILLING_CALL_LOG:-/dev/null}"
    case "${XAI_BILLING_MODE:-ok}" in
      ok)     [ -n "$out" ] && cp "${XAI_FIXTURE_DIR}/xai-cli-billing-credits.json" "$out"; status=200 ;;
      zero)   [ -n "$out" ] && cp "${XAI_FIXTURE_DIR}/xai-cli-billing-credits-zero.json" "$out"; status=200 ;;
      monthly) [ -n "$out" ] && cp "${XAI_FIXTURE_DIR}/xai-cli-billing-credits-monthly.json" "$out"; status=200 ;;
      down)   [ -n "$out" ] && printf '' > "$out"; status=500 ;;
      deny)   [ -n "$out" ] && printf '{"error":"Access denied"}' > "$out"; status=403 ;;
      deny_once)
        if [ "$previous_calls" -eq 0 ]; then
          [ -n "$out" ] && printf '{"error":"Access denied"}' > "$out"
          status=403
        else
          [ -n "$out" ] && cp "${XAI_FIXTURE_DIR}/xai-cli-billing-credits.json" "$out"
          status=200
        fi
        ;;
    esac
    ;;
  */settings)
    [ -n "$out" ] && cp "${XAI_FIXTURE_DIR}/xai-cli-settings.json" "$out"
    status=200
    ;;
  *prepaid/balance*)
    case "${XAI_MGMT_MODE:-ok}" in
      ok)     [ -n "$out" ] && cp "${XAI_FIXTURE_DIR}/xai-management-balance.json" "$out"; status=200 ;;
      deny)   [ -n "$out" ] && printf '{"error":"unauthorized"}' > "$out"; status=401 ;;
    esac
    ;;
  */v1/api-key)
    [ -n "$out" ] && cp "${XAI_FIXTURE_DIR}/xai-api-key.json" "$out"
    status=200
    ;;
  *)
    [ -n "$out" ] && printf '' > "$out"
    status=404
    ;;
esac
if [ "$write_code" -eq 1 ]; then printf '%s' "$status"; fi
exit 0
STUB
chmod +x "$TMP/bin/curl"

cat > "$TMP/bin/grok" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GROK_LOG:-/dev/null}"
[ "${1:-}" = "models" ] || exit 2
if [ "${GROK_REFRESH_MODE:-fail}" = "success" ]; then
  cp "${GROK_REFRESH_AUTH:?}" "${GROK_HOME:?}/auth.json"
  exit 0
fi
exit 1
STUB
chmod +x "$TMP/bin/grok"

write_auth() {
  local dest="$1" token="$2" expiry="$3" refresh="${4:-}"
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<EOF
{
  "https://auth.x.ai::test-client": {
    "key": "${token}",
    "auth_mode": "oidc",
    "email": "test@example.com",
    "team_id": "team-test",
    "principal_type": "User",
    "refresh_token": "${refresh}",
    "expires_at": "${expiry}"
  }
}
EOF
  chmod 600 "$dest"
}

run() {
  local adapter_path="${XAI_TEST_PATH:-$TMP/bin:$PATH}"
  PATH="$adapter_path" HDR_LOG="$HDR_LOG" GROK_LOG="$GROK_LOG" \
    BILLING_CALL_LOG="$BILLING_CALL_LOG" XAI_FIXTURE_DIR="$ROOT/tests/fixtures" \
    "$@" "$ROOT/providers/get-provider-usage" xai 2>/dev/null
}
fail() { echo "FAIL: $1" >&2; exit 1; }

CLI_HOME="$TMP/cli-home"
write_auth "$CLI_HOME/.grok/auth.json" "cli_test_token" "2099-01-01T00:00:00Z"

# 1. grok login + credits payload with creditUsagePercent.
: > "$HDR_LOG"
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$CLI_HOME" GROK_HOME="$CLI_HOME/.grok" XAI_BILLING_MODE=ok)"
[ "$(jq -r '.[0].source' <<<"$out")" = "grok-cli-billing" ] || fail "cli source: $out"
[ "$(jq -r '.[0].usage.primary.usedPercent|floor' <<<"$out")" = "32" ] || fail "cli percent"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "10080" ] || fail "cli weekly minutes"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "Weekly" ] || fail "cli weekly label"
[ "$(jq -r '.[0].usage.identity.accountEmail' <<<"$out")" = "test@example.com" ] || fail "cli email"
[ "$(jq -r '.[0].usage.identity.loginMethod' <<<"$out")" = "SuperGrok" ] || fail "cli plan from settings"
[ "$(jq -r '.[0].credits.remaining' <<<"$out")" = "SuperGrok" ] || fail "cli credits plan"
grep -q '^Authorization: Bearer cli_test_token$' "$HDR_LOG" || fail "cli auth header"
grep -q '^x-xai-token-auth: xai-grok-cli$' "$HDR_LOG" || fail "cli token-auth header"
health="$(env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$CLI_HOME" GROK_HOME="$CLI_HOME/.grok" \
  "$ROOT/providers/get-provider-health" xai 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "cli health ready"

# 2. Omitted creditUsagePercent on a valid period is 0%, not an error.
: > "$HDR_LOG"
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$CLI_HOME" GROK_HOME="$CLI_HOME/.grok" XAI_BILLING_MODE=zero)"
[ "$(jq -r '.[0].source' <<<"$out")" = "grok-cli-billing" ] || fail "zero source"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "0" ] || fail "zero percent"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "10080" ] || fail "zero still weekly"

# 3. grok login billing 403 falls through to Management API prepaid balance.
: > "$HDR_LOG"
out="$(run env -u XAI_API_KEY \
  HOME="$CLI_HOME" GROK_HOME="$CLI_HOME/.grok" \
  XAI_BILLING_MODE=deny XAI_MGMT_MODE=ok \
  XAI_MANAGEMENT_KEY=mgmt_test XAI_TEAM_ID=team-test)"
[ "$(jq -r '.[0].source' <<<"$out")" = "xai-management" ] || fail "mgmt source: $out"
[ "$(jq -r '.[0].credits.remaining' <<<"$out")" = '$12.50' ] || fail "mgmt remaining"
grep -q '^Authorization: Bearer mgmt_test$' "$HDR_LOG" || fail "mgmt auth header"

# 4. Management key without grok login.
EMPTY_HOME="$TMP/empty-home"
mkdir -p "$EMPTY_HOME"
: > "$HDR_LOG"
out="$(run env -u XAI_API_KEY \
  HOME="$EMPTY_HOME" GROK_HOME="$EMPTY_HOME/.grok" \
  XAI_MGMT_MODE=ok XAI_MANAGEMENT_KEY=mgmt_test XAI_TEAM_ID=team-test)"
[ "$(jq -r '.[0].source' <<<"$out")" = "xai-management" ] || fail "mgmt-only source"
[ "$(jq -r '.[0].credits.remaining' <<<"$out")" = '$12.50' ] || fail "mgmt-only remaining"

# 5. Inference API key is auth-only (no quota).
: > "$HDR_LOG"
out="$(run env -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$EMPTY_HOME" GROK_HOME="$EMPTY_HOME/.grok" XAI_API_KEY=user_test)"
[ "$(jq -r '.[0].source' <<<"$out")" = "xai-api" ] || fail "api-key source"
[ "$(jq -r '.[0].usage.identity.accountEmail' <<<"$out")" = "desktop" ] || fail "api-key name"
grep -q '^Authorization: Bearer user_test$' "$HDR_LOG" || fail "api-key auth header"

# 6. Expired grok login with no other creds.
EXPIRED_HOME="$TMP/expired-home"
write_auth "$EXPIRED_HOME/.grok/auth.json" "expired_token" "2020-01-01T00:00:00Z"
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$EXPIRED_HOME" GROK_HOME="$EXPIRED_HOME/.grok")"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "expired kind"
echo "$(jq -r '.[0].error.message' <<<"$out")" | grep -q 'expired' || fail "expired message"

# 7. An expired OIDC access token is renewed through the official CLI. The
# health helper treats the session as ready because both a refresh token and
# the Grok executable are present.
REFRESH_HOME="$TMP/refresh-home"
REFRESHED_AUTH="$TMP/refreshed-auth.json"
REFRESH_PATH="$TMP/refresh-path"
write_auth "$REFRESH_HOME/.grok/auth.json" "expired_token" "2020-01-01T00:00:00Z" "refresh_test"
write_auth "$REFRESHED_AUTH" "renewed_token" "2099-01-01T00:00:00Z" "rotated_refresh"
mkdir -p "$REFRESH_HOME/.grok/bin" "$REFRESH_PATH"
cp "$TMP/bin/grok" "$REFRESH_HOME/.grok/bin/grok"
ln -s "$TMP/bin/curl" "$REFRESH_PATH/curl"
: > "$GROK_LOG"
: > "$HDR_LOG"
: > "$BILLING_CALL_LOG"
health="$(PATH="$REFRESH_PATH:/usr/bin:/bin" env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$REFRESH_HOME" GROK_HOME="$REFRESH_HOME/.grok" \
  "$ROOT/providers/get-provider-health" xai 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "refreshable health ready"
out="$(XAI_TEST_PATH="$REFRESH_PATH:/usr/bin:/bin" run \
  env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$REFRESH_HOME" GROK_HOME="$REFRESH_HOME/.grok" \
  GROK_REFRESH_MODE=success GROK_REFRESH_AUTH="$REFRESHED_AUTH" XAI_BILLING_MODE=ok)"
[ "$(jq -r '.[0].source' <<<"$out")" = "grok-cli-billing" ] || fail "refreshed source: $out"
[ "$(wc -l < "$GROK_LOG")" -eq 1 ] || fail "expired token did not refresh exactly once"
grep -q '^models$' "$GROK_LOG" || fail "refresh command"
grep -q '^Authorization: Bearer renewed_token$' "$HDR_LOG" || fail "renewed bearer token"

# 8. A 403 before the recorded expiry triggers one renewal and one billing
# retry. The adapter does not keep retrying after that.
REJECT_HOME="$TMP/reject-home"
write_auth "$REJECT_HOME/.grok/auth.json" "rejected_token" "2099-01-01T00:00:00Z" "refresh_test"
: > "$GROK_LOG"
: > "$HDR_LOG"
: > "$BILLING_CALL_LOG"
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$REJECT_HOME" GROK_HOME="$REJECT_HOME/.grok" \
  GROK_REFRESH_MODE=success GROK_REFRESH_AUTH="$REFRESHED_AUTH" XAI_BILLING_MODE=deny_once)"
[ "$(jq -r '.[0].source' <<<"$out")" = "grok-cli-billing" ] || fail "auth retry source: $out"
[ "$(wc -l < "$GROK_LOG")" -eq 1 ] || fail "rejected token refresh count"
[ "$(wc -l < "$BILLING_CALL_LOG")" -eq 2 ] || fail "billing retry count"
grep -q '^Authorization: Bearer renewed_token$' "$HDR_LOG" || fail "retry renewed bearer token"

# 9. A rejected login with no refresh token reports the auth failure without
# claiming that an automatic renewal ran.
NO_REFRESH_HOME="$TMP/no-refresh-home"
write_auth "$NO_REFRESH_HOME/.grok/auth.json" "rejected_token" "2099-01-01T00:00:00Z"
: > "$GROK_LOG"
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$NO_REFRESH_HOME" GROK_HOME="$NO_REFRESH_HOME/.grok" XAI_BILLING_MODE=deny)"
[ ! -s "$GROK_LOG" ] || fail "non-refreshable rejection invoked grok"
[ "$(jq -r '.[0].error.message' <<<"$out")" = "Grok login was rejected. Run grok login." ] \
  || fail "non-refreshable rejection detail: $out"

# 10. Server failures are not authentication failures and must not invoke Grok.
: > "$GROK_LOG"
: > "$BILLING_CALL_LOG"
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$CLI_HOME" GROK_HOME="$CLI_HOME/.grok" XAI_BILLING_MODE=down)"
[ ! -s "$GROK_LOG" ] || fail "server failure invoked grok refresh"
echo "$(jq -r '.[0].error.message' <<<"$out")" | grep -q 'HTTP 500' || fail "server failure detail: $out"

# 11. A failed automatic renewal explains the recovery action without leaking
# the refresh token or the CLI's output.
FAILED_REFRESH_HOME="$TMP/failed-refresh-home"
write_auth "$FAILED_REFRESH_HOME/.grok/auth.json" "expired_token" "2020-01-01T00:00:00Z" "secret_refresh_value"
: > "$GROK_LOG"
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$FAILED_REFRESH_HOME" GROK_HOME="$FAILED_REFRESH_HOME/.grok" GROK_REFRESH_MODE=fail)"
echo "$(jq -r '.[0].error.message' <<<"$out")" | grep -q 'automatic renewal failed' || fail "refresh failure detail: $out"
echo "$out" | grep -q 'secret_refresh_value' && fail "refresh token leaked"

# 12. A refreshable token without an installed CLI is not reported healthy.
NO_GROK_HOME="$TMP/no-grok-home"
NO_GROK_BIN="$TMP/no-grok-bin"
mkdir -p "$NO_GROK_BIN"
ln -s "$TMP/bin/curl" "$NO_GROK_BIN/curl"
write_auth "$NO_GROK_HOME/.grok/auth.json" "expired_token" "2020-01-01T00:00:00Z" "refresh_test"
out="$(XAI_TEST_PATH="$NO_GROK_BIN:/usr/bin:/bin" run \
  env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$NO_GROK_HOME" GROK_HOME="$NO_GROK_HOME/.grok")"
echo "$(jq -r '.[0].error.message' <<<"$out")" | grep -q 'CLI was not found' || fail "missing CLI detail: $out"
health="$(PATH="$NO_GROK_BIN:/usr/bin:/bin" \
  env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$NO_GROK_HOME" GROK_HOME="$NO_GROK_HOME/.grok" \
  "$ROOT/providers/get-provider-health" xai 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "missing" ] || fail "expired no-CLI health missing"

# 13. No credential source.
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$EMPTY_HOME" GROK_HOME="$EMPTY_HOME/.grok")"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "no-key kind"
echo "$(jq -r '.[0].error.message' <<<"$out")" | grep -q 'grok login' || fail "no-key mentions grok login"
health="$(env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$EMPTY_HOME" GROK_HOME="$EMPTY_HOME/.grok" \
  "$ROOT/providers/get-provider-health" xai 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "missing" ] || fail "empty health missing"

# 14. grok alias dispatches the same adapter.
out="$(PATH="$TMP/bin:$PATH" HDR_LOG="$HDR_LOG" XAI_FIXTURE_DIR="$ROOT/tests/fixtures" \
  env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$CLI_HOME" GROK_HOME="$CLI_HOME/.grok" XAI_BILLING_MODE=ok \
  "$ROOT/providers/get-provider-usage" grok 2>/dev/null)"
[ "$(jq -r '.[0].provider' <<<"$out")" = "xai" ] || fail "grok alias provider"
[ "$(jq -r '.[0].source' <<<"$out")" = "grok-cli-billing" ] || fail "grok alias source"

# 15. The proxy timestamp is normalized to whole seconds with a Z suffix,
# which is the shape every other adapter emits and the widget parses.
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$CLI_HOME" GROK_HOME="$CLI_HOME/.grok" XAI_BILLING_MODE=ok)"
[ "$(jq -r '.[0].usage.primary.resetsAt' <<<"$out")" = "2026-09-21T18:26:15Z" ] \
  || fail "resetsAt normalization: $out"

# 16. A monthly period maps to 43200 minutes, an on-demand cap without
# creditUsagePercent drives the percentage, and a prepaid balance is rendered
# as money instead of the plan label.
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$CLI_HOME" GROK_HOME="$CLI_HOME/.grok" XAI_BILLING_MODE=monthly)"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "43200" ] || fail "monthly minutes: $out"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "Monthly" ] || fail "monthly label"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "25" ] || fail "on-demand cap percent"
[ "$(jq -r '.[0].usage.primary.resetsAt' <<<"$out")" = "2026-10-01T00:00:00Z" ] || fail "monthly resetsAt"
[ "$(jq -r '.[0].credits.remaining' <<<"$out")" = '$12.50' ] || fail "prepaid credits"

# 17. A failed renewal is not retried on every poll. The second invocation
# reuses the recorded attempt instead of spawning the CLI again.
COOLDOWN_HOME="$TMP/cooldown-home"
write_auth "$COOLDOWN_HOME/.grok/auth.json" "expired_token" "2020-01-01T00:00:00Z" "refresh_test"
rm -rf "$XDG_CACHE_HOME/AiOverviewControl"
: > "$GROK_LOG"
for _ in 1 2; do
  out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
    HOME="$COOLDOWN_HOME" GROK_HOME="$COOLDOWN_HOME/.grok" GROK_REFRESH_MODE=fail)"
done
[ "$(wc -l < "$GROK_LOG")" -eq 1 ] || fail "refresh cooldown spawned grok twice"
echo "$(jq -r '.[0].error.message' <<<"$out")" | grep -q 'expired' || fail "cooldown still reports expiry: $out"

# 18. The cooldown is a delay, not a permanent stop: once it lapses the next
# poll renews and recovers without user action.
out="$(run env -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  HOME="$COOLDOWN_HOME" GROK_HOME="$COOLDOWN_HOME/.grok" XAI_REFRESH_COOLDOWN=0 \
  GROK_REFRESH_MODE=success GROK_REFRESH_AUTH="$REFRESHED_AUTH" XAI_BILLING_MODE=ok)"
[ "$(jq -r '.[0].source' <<<"$out")" = "grok-cli-billing" ] || fail "cooldown lapse recovery: $out"
[ "$(wc -l < "$GROK_LOG")" -eq 2 ] || fail "cooldown lapse refresh count"
[ ! -f "$XDG_CACHE_HOME/AiOverviewControl/xai-grok-refresh" ] || fail "successful refresh left cooldown stamp"

echo "OK: test-xai"
