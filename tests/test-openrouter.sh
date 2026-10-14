#!/usr/bin/env bash
# OpenRouter key limit — fake-curl unit test.
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
write_code=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    http*) url="${args[$i]}" ;;
  esac
done
case "$url" in
  */api/v1/key)
    cp "${OPENROUTER_FIXTURES}/${OPENROUTER_MODE}.json" "$out"
    [ "$write_code" -eq 1 ] && printf '200'
    ;;
  */api/v1/activity)
    printf '{"data":[]}'
    ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/curl"

run() {
  PATH="$TMP/bin:$PATH" OPENROUTER_API_KEY="sk-or-v1-test" OPENROUTER_FIXTURES="$TMP/fixtures" \
    OPENROUTER_MODE="$1" bash "$ROOT/providers/get-provider-usage" openrouter
}
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

# 5. Uncapped key: the free-model daily allowance is the bar, resetting at UTC midnight.
out="$(run free-daily)"
[ "$(field usage.primary.usedPercent)" = "25" ] || fail "free percent"
[ "$(field usage.primary.displayValue)" = "250 / 1000 requests" ] || fail "free display"
[ "$(field usage.primary.resetDescription)" = "Free model requests" ] || fail "free label"
[ "$(field usage.primary.resetsAt)" = "$(date -u -d 'tomorrow 00:00' +%Y-%m-%dT%H:%M:%SZ)" ] || fail "free reset"

# 6. Capped key: the cap stays primary.
out="$(run capped-free)"
[ "$(field usage.primary.resetDescription)" = "Key limit" ] || fail "cap wins over free allowance"

echo "ok"
