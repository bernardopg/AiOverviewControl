#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do case "${a[$i]}" in -o) out="${a[$((i+1))]}";; http*) url="${a[$i]}";; esac; done
if [ "$CASE" = auth ]; then printf '%s' '{}' >"$out"; printf 403; exit; fi
if [[ "$url" == *moonshot.ai* && "$CASE" = cn ]]; then printf '%s' '{}' >"$out"; printf 500; exit; fi
printf '%s' '{"data":{"available_balance":"0","voucher_balance":"2","cash_balance":"3"}}' >"$out"; printf 200
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" kimi 2>/dev/null; }
out="$(CASE=cn PATH="$TMP/bin:$PATH" MOONSHOT_API_KEY=sk-test MOONSHOT_API_BASE=https://api.moonshot.cn "$ROOT/providers/get-provider-usage" kimi 2>/dev/null)"; jq -e '.[0].usage.primary.displayValue == "¥0" and .[0].usage.primary.usedPercent == 100' <<<"$out" >/dev/null || fail cn-currency
out="$(CASE=auth PATH="$TMP/bin:$PATH" KIMI_API_KEY=sk-test "$ROOT/providers/get-provider-usage" kimi 2>/dev/null)"; jq -e '.[0].error.code == 403' <<<"$out" >/dev/null || fail auth-stop
out="$(env -u MOONSHOT_API_KEY -u KIMI_API_KEY -u KIMI_CODING_API_KEY PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" moonshot 2>/dev/null)"; jq -e '.[0].error' <<<"$out" >/dev/null || fail missing-key
echo 'OK: test-cov-c2-kimi'
