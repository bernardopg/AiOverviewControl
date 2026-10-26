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

echo "exchange-rate coverage OK"
