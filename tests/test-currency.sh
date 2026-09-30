#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache" FX_TEST_CALLS="$TMP/calls" FX_TEST_MODE=ok
mkdir "$TMP/bin"
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'call\n' >> "$FX_TEST_CALLS"
case "$FX_TEST_MODE" in
 fail) exit 28 ;;
 malformed) echo 'not json' ;;
 zero) echo '{"base":"USD","date":"2026-09-29","rates":{"BRL":0}}' ;;
 wrong) echo '{"base":"EUR","date":"2026-09-29","rates":{"BRL":5}}' ;;
 missing) echo '{"base":"USD","date":"2026-09-29","rates":{}}' ;;
 ok) sleep 0.1; printf '{"base":"USD","date":"%s","rates":{"BRL":5,"EUR":0.9,"CNY":7}}\n' "$(date -u +%F)" ;;
esac
SH
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
run() { "$ROOT/providers/get-exchange-rates" "$1"; }
run USD | jq -e '.rate == 1 and .currency == "USD"' >/dev/null
run 'BRL; bad' | jq -e '.error == "unsupported_currency"' >/dev/null
[[ ! -e "$FX_TEST_CALLS" ]]
AIOC_NO_FX=1 run BRL | jq -e '.error == "exchange_rate_unavailable"' >/dev/null
[[ ! -e "$FX_TEST_CALLS" ]]
run BRL | jq -e '.base == "USD" and .currency == "BRL" and .rate == 5 and .stale == false' >/dev/null
run BRL | jq -e '.rate == 5' >/dev/null
[[ "$(wc -l < "$FX_TEST_CALLS")" == 1 ]]
CACHE="$XDG_CACHE_HOME/AiOverviewControl/exchange-rate-BRL.json"
[[ "$(stat -c %a "$CACHE")" == 600 ]]
[[ "$(stat -c %a "$(dirname "$CACHE")")" == 700 ]]
age() {
 jq --argjson age "$1" '.fetchedAt = (now | floor) - $age' "$CACHE" > "$TMP/aged"
 cp "$TMP/aged" "$CACHE"
}
age 172800
for FX_TEST_MODE in fail malformed zero wrong missing; do
 export FX_TEST_MODE
 run BRL | jq -e '.rate == 5 and .stale == true' >/dev/null
 done
AIOC_NO_FX=1 run BRL | jq -e '.rate == 5 and .stale == true' >/dev/null
age 691200
run BRL | jq -e '.error == "exchange_rate_unavailable"' >/dev/null
printf 'corrupt\n' > "$CACHE"
run BRL | jq -e '.error == "exchange_rate_unavailable"' >/dev/null
export FX_TEST_MODE=ok
run BRL | jq -e '.rate == 5 and .stale == false' >/dev/null
before="$(wc -l < "$FX_TEST_CALLS")"
for i in {1..5}; do run CNY > "$TMP/concurrent-$i" & done
wait
[[ "$(wc -l < "$FX_TEST_CALLS")" == "$((before + 1))" ]]
for i in {1..5}; do jq -e '.currency == "CNY" and .rate == 7' "$TMP/concurrent-$i" >/dev/null; done
printf 'OK: currencies, opt-out, TTL, stale fallback, corruption, private cache, concurrent refresh\n'
