#!/usr/bin/env bash
# Cline account adapter — fake-curl fixture test. Covers the CLINE_API_KEY and
# Cline CLI sign-in credential paths, micro-USD balance conversion, the active
# organization balance, the ClinePass plan and expired/rejected credentials.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin" "$TMP/routes"
FIX="$ROOT/tests/fixtures"

# Fake curl: answers each URL from $FAKE_ROUTES/<route>.json (+ optional
# <route>.status) and logs the URL and headers.
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Adapters pass secret headers through --config files; expand them back to -H.
_cfg=(); while [ $# -gt 0 ]; do if [ "$1" = --config ] || [ "$1" = -K ]; then while IFS= read -r _l; do case "$_l" in 'header = "'*) _v="${_l#header = \"}"; _cfg+=(-H "${_v%\"}") ;; esac; done < "$2"; shift 2; else _cfg+=("$1"); shift; fi; done; set -- "${_cfg[@]}"
out=""; url=""; write_code=0; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    -H) printf 'H %s\n' "${args[$((i + 1))]}" >>"$FAKE_LOG" ;;
    http*) url="${args[$i]}" ;;
  esac
done
printf 'U %s\n' "$url" >>"$FAKE_LOG"
case "$url" in
  *"/usages?"*cursor=*) route=usages-2 ;;
  *"/usages?"*) route=usages ;;
  */users/me) route=me ;;
  */users/me/plan) route=plan ;;
  */organizations/*/balance) route=org-balance ;;
  */balance) route=balance ;;
  *) route=missing ;;
esac
status=404
if [ -f "$FAKE_ROUTES/$route.json" ]; then
  [ -z "$out" ] || cp "$FAKE_ROUTES/$route.json" "$out"
  status="$(cat "$FAKE_ROUTES/$route.status" 2>/dev/null || echo 200)"
fi
[ "$write_code" -eq 0 ] || printf '%s' "$status"
exit 0
STUB
chmod +x "$TMP/bin/curl"

fail() { echo "FAIL: $1" >&2; exit 1; }
# Usage log pages, newest first: page 1 holds two of today's rows and points to
# page 2, whose last row is from yesterday, so paging stops there.
now_iso="$(date -u +%Y-%m-%dT%H:%M:%S.123456Z)"
yesterday_iso="$(date -u -d "@$(( $(date -d 'today 00:00' +%s) - 3600 ))" +%Y-%m-%dT%H:%M:%S.5Z)"
jq -n --arg now "$now_iso" '{success:true,data:{nextToken:"usg-page2",total:0,items:[
  {createdAt:$now,aiModelTypeName:"cline-free",totalTokens:1500,creditsUsed:0},
  {createdAt:$now,aiModelTypeName:"anthropic",totalTokens:500,creditsUsed:250000}]}}' >"$TMP/usages-1.json"
jq -n --arg now "$now_iso" --arg old "$yesterday_iso" '{success:true,data:{nextToken:"usg-page3",total:0,items:[
  {createdAt:$now,aiModelTypeName:"cline-free",totalTokens:1000000,creditsUsed:0},
  {createdAt:$old,aiModelTypeName:"cline-free",totalTokens:99999,creditsUsed:0}]}}' >"$TMP/usages-2.json"

reset_routes() {
  rm -f "$TMP/routes"/*
  cp "$TMP/usages-1.json" "$TMP/routes/usages.json"
  cp "$TMP/usages-2.json" "$TMP/routes/usages-2.json"
  cp "$FIX/cline-me.json" "$TMP/routes/me.json"
  cp "$FIX/cline-balance.json" "$TMP/routes/balance.json"
  cp "$FIX/cline-plan.json" "$TMP/routes/plan.json"
}
run() {
  : >"$TMP/log"
  PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_ROUTES="$TMP/routes" \
    "$@" "$ROOT/providers/get-provider-usage" cline 2>/dev/null
}
EMPTY_HOME="$TMP/empty-home"
mkdir -p "$EMPTY_HOME"

# 1. API key: personal balance (12345678 micro-USD = $12.35) and ClinePass plan.
reset_routes
out="$(run env HOME="$EMPTY_HOME" CLINE_API_KEY=key-test)"
[ "$(jq -r '.[0].source' <<<"$out")" = "cline-api" ] || fail "source"
# shellcheck disable=SC2016 # literal dollar amounts
[ "$(jq -r '.[0].usage.primary.displayValue' <<<"$out")" = '$12.35' ] || fail "micro-USD balance"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "Credits" ] || fail "personal credits label"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "0" ] || fail "funded balance"
[ "$(jq -r '.[0].usage.tertiary.displayValue' <<<"$out")" = "ClinePass" ] || fail "plan name"
[ "$(jq -r '.[0].usage.tertiary.resetsAt' <<<"$out")" = "2026-11-01T00:00:00Z" ] || fail "plan period end"
# Today across both pages; yesterday's row excluded; credits are micro-USD.
# shellcheck disable=SC2016
[ "$(jq -r '.[0].usage.secondary.displayValue' <<<"$out")" = '3 requests · 1M tokens · 2 free · $0.25' ] || fail "today usage $(jq -r '.[0].usage.secondary.displayValue' <<<"$out")"
grep -q 'U https://api.cline.bot/api/v1/users/usr-test123/usages?limit=200&cursor=usg-page2' "$TMP/log" || fail "usages cursor"
! grep -q 'cursor=usg-page3' "$TMP/log" || fail "paging must stop at yesterday"
[ "$(jq -r '.[0].usage.accountEmail' <<<"$out")" = "dev@example.com" ] || fail "identity"
[ "$(jq -r '.[0].usage.loginMethod' <<<"$out")" = "api-key" ] || fail "login method"
grep -qx 'U https://api.cline.bot/api/v1/users/usr-test123/balance' "$TMP/log" || fail "personal balance URL"
[ "$(grep -c '^H Authorization: Bearer key-test$' "$TMP/log")" -eq 5 ] || fail "auth header on every call"

# 2. Active organization: its balance is billed, not the personal one.
reset_routes
jq '.data.organizations[0].active = true' "$FIX/cline-me.json" >"$TMP/routes/me.json"
printf '%s\n' '{"success":true,"data":{"balance":0,"organizationId":"org-test456"}}' >"$TMP/routes/org-balance.json"
out="$(run env HOME="$EMPTY_HOME" CLINE_API_KEY=key-test)"
grep -qx 'U https://api.cline.bot/api/v1/organizations/org-test456/balance' "$TMP/log" || fail "org balance URL"
grep -q 'U https://api.cline.bot/api/v1/organizations/org-test456/members/mem-1/usages?limit=200' "$TMP/log" || fail "org member usages URL"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "Credits · Example Org" ] || fail "org label"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "100" ] || fail "depleted org balance"

# 3. Cline CLI sign-in with a valid token; plan endpoint unavailable and the
# envelope-free payload shape still parses.
reset_routes
rm -f "$TMP/routes/plan.json"
jq '.data' "$FIX/cline-me.json" >"$TMP/routes/me.json"
CLI_HOME="$TMP/cli-home"
mkdir -p "$CLI_HOME/.cline/data/settings"
future=$(( ($(date +%s) + 3600) * 1000 ))
jq -n --argjson exp "$future" '{providers:{cline:{settings:{auth:{accessToken:"workos:cli-token",expiresAt:$exp}}}}}' \
  >"$CLI_HOME/.cline/data/settings/providers.json"
out="$(run env -u CLINE_API_KEY HOME="$CLI_HOME")"
grep -qx 'H Authorization: Bearer workos:cli-token' "$TMP/log" || fail "CLI token forwarded"
[ "$(jq -r '.[0].usage.loginMethod' <<<"$out")" = "oauth" ] || fail "oauth login method"
[ "$(jq -r '.[0].usage.tertiary' <<<"$out")" = "null" ] || fail "no plan window"
health="$(env -u CLINE_API_KEY HOME="$CLI_HOME" "$ROOT/providers/get-provider-health" cline)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "CLI health"

# 4. Expired CLI token is never sent and never refreshed.
jq -n '{providers:{cline:{settings:{auth:{accessToken:"workos:old",expiresAt:1000}}}}}' \
  >"$CLI_HOME/.cline/data/settings/providers.json"
out="$(run env -u CLINE_API_KEY HOME="$CLI_HOME")"
jq -e '.[0].error.message | test("sign-in expired")' <<<"$out" >/dev/null || fail "expired message"
[ ! -s "$TMP/log" ] || fail "expired token must not reach the network"
health="$(env -u CLINE_API_KEY HOME="$CLI_HOME" "$ROOT/providers/get-provider-health" cline)"
[ "$(jq -r '.[0].status' <<<"$health")" = "missing" ] || fail "expired CLI health"

# 5. Rejected credentials and no credentials.
reset_routes
printf '401' >"$TMP/routes/me.status"
out="$(run env HOME="$EMPTY_HOME" CLINE_API_KEY=bad)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "401" ] || fail "401"
out="$(run env -u CLINE_API_KEY HOME="$EMPTY_HOME")"
jq -e '.[0].error.message | test("CLINE_API_KEY")' <<<"$out" >/dev/null || fail "no credentials"
health="$(env -u CLINE_API_KEY HOME="$EMPTY_HOME" "$ROOT/providers/get-provider-health" cline)"
[ "$(jq -r '.[0].status' <<<"$health")" = "missing" ] || fail "health missing"

echo "OK: test-cline"
