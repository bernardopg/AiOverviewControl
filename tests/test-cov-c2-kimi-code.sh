#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do case "${a[$i]}" in -o) out="${a[$((i+1))]}";; http*) url="${a[$i]}";; esac; done
if [ "$CASE" = fail ]; then printf '%s' '{"message":"bad key"}' >"$out"; [ "${url%/usages}" != "$url" ] && { printf 404; exit; }; printf 401; exit; fi
if [[ "$url" == */usages ]]; then printf '%s' '{}' >"$out"; printf 404; exit; fi
printf '%s' '{"usage":{"limit":"20","remaining":"5","reset_in":20},"limits":[{"detail":{"limit_amount":10,"used_amount":2,"name":"weekly"},"window":{"duration":1,"timeUnit":"DAY"}},{"detail":{"limit":5,"used":1,"title":"month"},"window":{"duration":1,"time_unit":"MONTH"}}],"usages":{"limit_5h":{"used_ratio":0.5,"reset_time":1793000000},"limit_7d":{"usedRatio":0.4},"limit_month_total":{"used_ratio":0.3},"limit_month_code":{"used_ratio":0.9}}}' >"$out"; printf 200
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" kimi-code 2>/dev/null; }
out="$(run ok)"; jq -e '.[0].provider == "kimi-code" and .[0].usage.identity.providerID == "kimi-code" and .[0].usage.primary != null and .[0].usage.tertiary != null' <<<"$out" >/dev/null || fail mappings
out="$(run fail)"; jq -e '.[0].error.code == 401 and .[0].error.message == "bad key"' <<<"$out" >/dev/null || fail auth
out="$(env -u KIMI_CODING_API_KEY -u KIMI_API_KEY -u MOONSHOT_API_KEY PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" kimi-code 2>/dev/null)"; jq -e '.[0].error' <<<"$out" >/dev/null || fail missing-key
echo 'OK: test-cov-c2-kimi-code'
