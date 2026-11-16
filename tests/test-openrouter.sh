#!/usr/bin/env bash
# OpenRouter key limit, key balance and account credits — fake-curl unit test.
# /api/v1/key reports `usage` as lifetime spend while `limit` resets with
# `limit_reset`. The key-limit bar must measure the current window, not
# lifetime spend over the windowed cap.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin" "$TMP/fixtures"

# Weekly $15 cap on a key with $78.92 lifetime spend and $0.11 this week.
cat >"$TMP/fixtures/weekly.json" <<'EOF'
{"data":{"label":"sk-or-v1-test","limit":15,"usage":78.919239068,"limit_remaining":14.89404923,
 "limit_reset":"weekly","usage_daily":0.05,"usage_weekly":0.10595077,"usage_monthly":3.2,
 "byok_usage":0,"include_byok_in_limit":false,"is_free_tier":false}}
EOF

# Same key without limit_remaining: the weekly counter must be used.
cat >"$TMP/fixtures/weekly-no-remaining.json" <<'EOF'
{"data":{"label":"sk-or-v1-test","limit":15,"usage":78.919239068,
 "limit_reset":"weekly","usage_daily":0.05,"usage_weekly":3,"usage_monthly":9,
 "byok_usage":0,"include_byok_in_limit":false}}
EOF

# A cap with no reset is a lifetime cap: lifetime spend is the right figure.
cat >"$TMP/fixtures/lifetime.json" <<'EOF'
{"data":{"label":"sk-or-v1-test","limit":20,"usage":5,"limit_remaining":15,"limit_reset":null,
 "usage_daily":1,"usage_weekly":2,"usage_monthly":5}}
EOF

cat >"$TMP/fixtures/unlimited.json" <<'EOF'
{"data":{"label":"sk-or-v1-test","limit":null,"usage":12.5,"limit_remaining":null,"limit_reset":null,
 "usage_daily":0,"usage_weekly":1,"usage_monthly":4}}
EOF

# Uncapped key with the free-model daily allowance (live /api/v1/key shape).
cat >"$TMP/fixtures/free-daily.json" <<'EOF'
{"data":{"label":"sk-or-v1-test","limit":null,"usage":0.4,"limit_remaining":null,"limit_reset":null,
 "usage_daily":0,"usage_weekly":0,"usage_monthly":0.4,"is_free_tier":false,
 "free_model_daily_requests":{"used":250,"limit":1000,"remaining":750}}}
EOF

# A capped key keeps the cap as its bar even with the free allowance present.
jq '.data.free_model_daily_requests = {used: 900, limit: 1000, remaining: 100}' \
  "$TMP/fixtures/weekly.json" >"$TMP/fixtures/capped-free.json"

cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""
url=""
auth=""
write_code=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    --config) auth="$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p' "${args[$((i + 1))]}")" ;;
    http*) url="${args[$i]}" ;;
  esac
done
# Which key reached which endpoint, for the management-key checks.
printf '%s %s\n' "${url##*/api/v1/}" "$auth" >>"${OPENROUTER_FIXTURES}/requests.log"
case "$url" in
  */api/v1/key)
    cp "${OPENROUTER_FIXTURES}/${OPENROUTER_MODE}.json" "$out"
    [ "$write_code" -eq 1 ] && printf '200'
    ;;
  */api/v1/activity)
    cat "${OPENROUTER_FIXTURES}/activity.json"
    ;;
  */api/v1/credits)
    status="${OPENROUTER_CREDITS_STATUS:-200}"
    cp "${OPENROUTER_FIXTURES}/${OPENROUTER_CREDITS:-credits}.json" "$out"
    [ "$write_code" -eq 1 ] && printf '%s' "$status"
    ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/curl"

# Account credits (the live answer for an account that bought $80 and spent
# $70.21), a refusal body, a negative balance, a body that is not JSON, and
# the management-key activity rollup.
printf '%s' '{"data":{"total_credits":80,"total_usage":70.213689496}}' >"$TMP/fixtures/credits.json"
printf '%s' '{"error":{"code":403,"message":"Only management keys can perform this operation"}}' >"$TMP/fixtures/refused.json"
printf '%s' '{"data":{"total_credits":10,"total_usage":11.5}}' >"$TMP/fixtures/negative.json"
printf '%s' '<html>bad gateway</html>' >"$TMP/fixtures/html.json"
: >"$TMP/fixtures/empty.json"
printf '%s' '{"data":[{"model":"anthropic/claude-sonnet-4.6","usage":1.5},{"model":"openai/gpt-5.4","usage":0.25},{"model":"anthropic/claude-sonnet-4.6","usage":0.5}]}' >"$TMP/fixtures/activity.json"

run() {
  PATH="$TMP/bin:$PATH" OPENROUTER_API_KEY="sk-or-v1-test" OPENROUTER_FIXTURES="$TMP/fixtures" \
    OPENROUTER_MODE="$1" bash "$ROOT/providers/get-provider-usage" openrouter
}
REQUESTS="$TMP/fixtures/requests.log"
requests() { cat "$REQUESTS" 2>/dev/null || true; }
reset_log() { : >"$TMP/fixtures/requests.log"; }
unset OPENROUTER_MANAGEMENT_KEY AIOC_VAULT_OPENROUTER_MANAGEMENT AIOC_OPENROUTER_VIEW
fail() { echo "FAIL: $1" >&2; exit 1; }
field() { jq -r ".[0].$1" <<<"$out"; }

# 1. Windowed limit: limit - limit_remaining, not lifetime / limit.
out="$(run weekly)"
[ "$(field source)" = "openrouter-api" ] || fail "source"
awk 'BEGIN{exit !(ARGV[1] > 0.6 && ARGV[1] < 0.8)}' "$(field usage.primary.usedPercent)" \
  || fail "weekly percent $(field usage.primary.usedPercent)"
[ "$(field usage.primary.displayValue)" = '$0.11 / $15.00' ] || fail "weekly display $(field usage.primary.displayValue)"
[ "$(field usage.primary.resetsAt)" = "weekly" ] || fail "weekly reset"
[ "$(field credits.remaining)" = '$14.89' ] || fail "weekly remaining"

# 2. No limit_remaining: the counter matching limit_reset drives bar and remaining.
out="$(run weekly-no-remaining)"
[ "$(field usage.primary.usedPercent)" = "20" ] || fail "fallback percent $(field usage.primary.usedPercent)"
[ "$(field usage.primary.displayValue)" = '$3.00 / $15.00' ] || fail "fallback display"
[ "$(field credits.remaining)" = '$12.00' ] || fail "fallback remaining $(field credits.remaining)"

# 3. Lifetime cap keeps lifetime spend.
out="$(run lifetime)"
[ "$(field usage.primary.usedPercent)" = "25" ] || fail "lifetime percent"
[ "$(field usage.primary.displayValue)" = '$5.00 / $20.00' ] || fail "lifetime display"

# 4. No limit: spend only, no percentage, unlimited credits.
out="$(run unlimited)"
[ "$(field usage.primary.usedPercent)" = "0" ] || fail "unlimited percent"
[ "$(field usage.primary.displayValue)" = '$12.50 used' ] || fail "unlimited display"
[ "$(field credits.remaining)" = "unlimited" ] || fail "unlimited remaining"
[ "$(field usage.primary.hasLimit)" = "false" ] || fail "uncapped spend is a plain reading"
[ "$(field usage.secondary.hasLimit)" = "false" ] || fail "spent today is a plain reading"
[ "$(field usage.tertiary.hasLimit)" = "false" ] || fail "week spend is a plain reading"

# 5. Uncapped key: the free-model daily allowance is the bar, resetting at UTC midnight.
out="$(run free-daily)"
[ "$(field usage.primary.usedPercent)" = "25" ] || fail "free percent"
[ "$(field usage.primary.displayValue)" = "250 / 1000 requests" ] || fail "free display"
[ "$(field usage.primary.resetDescription)" = "Free model requests" ] || fail "free label"
[ "$(field usage.primary.resetsAt)" = "$(date -u -d 'tomorrow 00:00' +%Y-%m-%dT%H:%M:%SZ)" ] || fail "free reset"

# 6. Capped key: the cap stays primary.
out="$(run capped-free)"
[ "$(field usage.primary.resetDescription)" = "Key limit" ] || fail "cap wins over free allowance"
[ "$(field usage.primary.hasLimit)" = "true" ] || fail "a capped key limit is measured"

# 7. An ordinary key never asks /activity (403 for every non-management key)
#    nor /credits outside the account view.
reset_log
out="$(run weekly)"
grep -q '^activity' "$REQUESTS" && fail "activity asked without a management key"
grep -q '^credits' "$REQUESTS" && fail "credits asked outside the account view"
[ "$(field usage.tertiary.resetDescription)" = "Week and month spend" ] || fail "tertiary without activity"
# The translated label names both windows; the value holds amounts only.
case "$(field usage.tertiary.displayValue)" in *Week*|*Month*) fail "untranslated words in the spend value";; esac

# 8. A management key unlocks the per-model rollup, and only it reaches /activity.
reset_log
out="$(OPENROUTER_MANAGEMENT_KEY=sk-or-mgmt run weekly)"
grep -qx 'activity sk-or-mgmt' "$REQUESTS" || fail "activity must use the management key: $(requests)"
grep -qx 'key sk-or-v1-test' "$REQUESTS" || fail "key check must use the inference key"
[ "$(field usage.tertiary.resetDescription)" = "Week and top models" ] || fail "top models label"
[ "$(field usage.tertiary.displayValue)" = '$0.11 · claude-sonnet-4.6 $2.00 · gpt-5.4 $0.25' ] \
  || fail "top models $(field usage.tertiary.displayValue)"

# 9. Key balance: what is left of the cap, in dollars, as a balance window.
out="$(AIOC_OPENROUTER_VIEW=key-balance run weekly)"
[ "$(field usage.primary.resetDescription)" = "Key balance" ] || fail "key balance label"
[ "$(field usage.primary.isBalance)" = "true" ] || fail "key balance isBalance"
[ "$(field usage.primary.displayValue)" = '$14.89' ] || fail "key balance value $(field usage.primary.displayValue)"
[ "$(field usage.primary.resetsAt)" = "null" ] || fail "key balance is not paced"
[ "$(field usage.primary.hasLimit)" = "true" ] || fail "key balance is measured against the cap"
awk 'BEGIN{exit !(ARGV[1] > 0.6 && ARGV[1] < 0.8)}' "$(field usage.primary.usedPercent)" \
  || fail "key balance percent $(field usage.primary.usedPercent)"
[ "$(field credits.remaining)" = '$14.89' ] || fail "key balance credits"

# 10. Key balance on an uncapped key: no balance is invented, the key bar stays.
out="$(AIOC_OPENROUTER_VIEW=key-balance run free-daily)"
[ "$(field usage.primary.resetDescription)" = "Free model requests" ] || fail "uncapped key-balance fallback"
[ "$(field usage.primary.isBalance)" = "null" ] || fail "uncapped key-balance must not be a balance"

# 11. Account credits: total_credits - total_usage, asked with the inference key.
reset_log
out="$(AIOC_OPENROUTER_VIEW=account run free-daily)"
[ "$(field usage.primary.resetDescription)" = "Account balance" ] || fail "account label"
[ "$(field usage.primary.isBalance)" = "true" ] || fail "account isBalance"
[ "$(field usage.primary.displayValue)" = '$9.79' ] || fail "account value $(field usage.primary.displayValue)"
[ "$(field credits.remaining)" = '$9.79' ] || fail "account credits"
[ "$(field credits.account.total)" = "80" ] || fail "account total"
# Nothing to compare the account balance with: no bar, no usage colour.
[ "$(field usage.primary.usedPercent)" = "0" ] || fail "account percent $(field usage.primary.usedPercent)"
[ "$(field usage.primary.hasLimit)" = "null" ] || fail "account balance has no limit"
grep -qx 'credits sk-or-v1-test' "$REQUESTS" || fail "credits must use the inference key: $(requests)"
[ "$(field usage.secondary.resetDescription)" = "Spent today" ] || fail "account keeps key windows"

# 12. With a management key, /credits is asked with it.
reset_log
out="$(AIOC_OPENROUTER_VIEW=account OPENROUTER_MANAGEMENT_KEY=sk-or-mgmt run free-daily)"
grep -qx 'credits sk-or-mgmt' "$REQUESTS" || fail "credits must prefer the management key: $(requests)"
[ "$(field usage.primary.displayValue)" = '$9.79' ] || fail "account value with management key"

# 13. A refusal without a management key keeps the key bar and names the fix.
out="$(AIOC_OPENROUTER_VIEW=account OPENROUTER_CREDITS=refused OPENROUTER_CREDITS_STATUS=403 run weekly)"
[ "$(field usage.primary.resetDescription)" = "Key limit" ] || fail "refused account keeps key bar"
[ "$(field credits.remaining)" = "Account balance needs a management key (OPENROUTER_MANAGEMENT_KEY)" ] \
  || fail "refused message $(field credits.remaining)"
[ "$(field error)" = "null" ] || fail "a refused balance is not a card error"

# 14. A refusal with a management key, a server error, a body that is not JSON
#     and an empty body all report the status instead of a balance.
out="$(AIOC_OPENROUTER_VIEW=account OPENROUTER_MANAGEMENT_KEY=sk-or-mgmt OPENROUTER_CREDITS=refused OPENROUTER_CREDITS_STATUS=403 run weekly)"
[ "$(field credits.remaining)" = "Account balance unavailable (HTTP 403)" ] || fail "management refusal $(field credits.remaining)"
out="$(AIOC_OPENROUTER_VIEW=account OPENROUTER_CREDITS=html OPENROUTER_CREDITS_STATUS=502 run weekly)"
[ "$(field credits.remaining)" = "Account balance unavailable (HTTP 502)" ] || fail "html body $(field credits.remaining)"
[ "$(field usage.primary.resetDescription)" = "Key limit" ] || fail "html body keeps key bar"
out="$(AIOC_OPENROUTER_VIEW=account OPENROUTER_CREDITS=empty OPENROUTER_CREDITS_STATUS=200 run weekly)"
[ "$(field credits.remaining)" = "Account balance unavailable (HTTP 200)" ] || fail "empty body $(field credits.remaining)"

# 15. A negative balance reads "-$1.50" and fills the bar.
out="$(AIOC_OPENROUTER_VIEW=account OPENROUTER_CREDITS=negative run weekly)"
[ "$(field usage.primary.displayValue)" = '-$1.50' ] || fail "negative value $(field usage.primary.displayValue)"
[ "$(field usage.primary.usedPercent)" = "100" ] || fail "negative percent"

# 16. An unknown view falls back to the key bar.
out="$(AIOC_OPENROUTER_VIEW=bogus run weekly)"
[ "$(field usage.primary.resetDescription)" = "Key limit" ] || fail "unknown view fallback"

echo "ok"
