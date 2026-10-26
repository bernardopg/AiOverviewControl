#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do case "${a[$i]}" in -o) out="${a[$((i+1))]}";; http*) url="${a[$i]}";; esac; done
status=200
case "$CASE:$url" in
  *:*/activity) if [ "$CASE" = activity ]; then printf '%s' '{"data":[{"model":"openai/a-long-model-name-that-is-truncated","usage":"2.25"},{"model":"openai/a-long-model-name-that-is-truncated","usage":1},{"model":"anthropic/claude","usage":4}]}' ; else printf '{bad'; fi ;;
  err:*) status=429; printf '%s' '{"error":{"message":"rate limited"}}' >"$out";;
  *:*) printf '%s' '{"data":{"label":"test","limit":"10","limit_remaining":"4","usage":"9","usage_daily":"1.25","usage_weekly":2,"usage_monthly":3,"byok_usage":8,"byok_usage_daily":7,"byok_usage_weekly":6,"byok_usage_monthly":5,"include_byok_in_limit":true,"is_free_tier":true,"free_model_daily_requests":{"used":8,"limit":10}}}' >"$out";;
esac
if [[ "$url" == */key ]]; then printf '%s' "$status"; fi
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" OPENROUTER_API_KEY=sk-test "$ROOT/providers/get-provider-usage" openrouter 2>/dev/null; }
out="$(run activity)"; jq -e '.[0].usage.primary.usedPercent == 60 and .[0].usage.primary.windowMinutes == null and (.[0].usage.tertiary.displayValue | contains("claude"))' <<<"$out" >/dev/null || fail activity
out="$(run err)"; jq -e '.[0].error.code == 429 and .[0].error.message == "rate limited"' <<<"$out" >/dev/null || fail error
out="$(env -u OPENROUTER_API_KEY PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" openrouter 2>/dev/null)"; jq -e '.[0].error' <<<"$out" >/dev/null || fail missing-key
echo 'OK: test-cov-c2-openrouter'
