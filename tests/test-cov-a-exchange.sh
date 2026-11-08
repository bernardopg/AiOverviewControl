#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/aioc-cov-a.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
# Isolate every cache and config path so no real user data is read or written.
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$HOME"
mkdir -p "$TMP/bin"
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '{"base":"USD","date":"2026-10-25","rates":{"EUR":0.92}}'
SH
chmod +x "$TMP/bin/curl"

usd="$(bash "$ROOT/providers/get-exchange-rates" USD)"
jq -e '.rate == 1 and .currency == "USD" and .stale == false' <<<"$usd" >/dev/null
unsupported="$(bash "$ROOT/providers/get-exchange-rates" BTC)"
jq -e '.error == "unsupported_currency"' <<<"$unsupported" >/dev/null

# A valid fresh cache is consumed without curl.
no_cache="$(AIOC_NO_FX=1 bash "$ROOT/providers/get-exchange-rates" EUR)"
jq -e '.error == "exchange_rate_unavailable"' <<<"$no_cache" >/dev/null


# A fetched quote is validated, cached and then served from the cache.
fetched="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-exchange-rates" EUR)"
jq -e '.base == "USD" and .currency == "EUR" and .rate == 0.92 and .stale == false' <<<"$fetched" >/dev/null
cached="$(PATH="/nonexistent:/usr/bin:/bin" bash "$ROOT/providers/get-exchange-rates" EUR)"
jq -e '.currency == "EUR" and .rate == 0.92' <<<"$cached" >/dev/null

# Opted out with a cache older than a day: served as stale, never refreshed.
cache="$XDG_CACHE_HOME/AiOverviewControl/exchange-rate-EUR.json"
jq --argjson at "$(( $(date +%s) - 2 * 86400 ))" '.fetchedAt = $at' "$cache" > "$TMP/old.json"
mv "$TMP/old.json" "$cache"
stale="$(AIOC_NO_FX=1 PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-exchange-rates" EUR)"
jq -e '.rate == 0.92 and .stale == true' <<<"$stale" >/dev/null

# Another reader holding the refresh lock past the 10 second wait: the stale
# quote is served rather than blocking the widget or fetching twice.
( flock -x 9; exec sleep 14 ) 9>"$cache.lock" &
holder=$!
sleep 1
started=$SECONDS
locked="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-exchange-rates" EUR)"
elapsed=$((SECONDS - started))
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true
jq -e '.rate == 0.92 and .stale == true' <<<"$locked" >/dev/null
[ "$elapsed" -ge 9 ] && [ "$elapsed" -le 13 ]

echo "exchange-rate coverage OK"
