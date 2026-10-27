#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do case "${a[$i]}" in -o) out="${a[$((i+1))]}";; http*) url="${a[$i]}";; esac; done
case "$CASE:$url" in
  success:*/quota/limit) printf '%s' '{"success":true,"data":{"level":"max","limits":[]}}' >"$out"; printf 200;;
  reject:*/quota/limit) printf '%s' '{}' >"$out"; printf 401;;
  fallback:*/quota/limit) printf '%s' '{bad' >"$out"; printf 503;;
  fallback:*/models) printf '%s' '{}' >"$out"; printf 500;;
  *) printf '%s' '{}' >"$out"; printf 200;;
esac
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" ZAI_API_KEY=sk-test GLM_API_KEY=sk-test "$ROOT/providers/get-provider-usage" "$2" 2>/dev/null; }
for p in zai z.ai glm zhipu; do
  out="$(run success "$p")"; jq -e '.[0].usage.primary == null and (.[0].usage.accountEmail | type == "string")' <<<"$out" >/dev/null || fail "$p empty limits"
  out="$(run reject "$p")"; jq -e '.[0].error.code == 401' <<<"$out" >/dev/null || fail "$p reject"
  out="$(run fallback "$p")"
  if [[ "$p" == glm || "$p" == zhipu ]]; then jq -e '.[0].error.code == 500' <<<"$out" >/dev/null || fail "$p fallback failure"
  else jq -e '.[0].usage.accountEmail == "Z.ai account"' <<<"$out" >/dev/null || fail "$p fallback note"; fi
done
# Without any key the card says which variables to set, and never calls out.
for p in zai glm; do
  out="$(PATH="$TMP/bin:$PATH" env -u ZAI_API_KEY -u GLM_API_KEY -u ZHIPU_API_KEY "$ROOT/providers/get-provider-usage" "$p" 2>/dev/null)"
  jq -e '.[0].error.code == 2 and (.[0].error.message | contains("is not set"))' <<<"$out" >/dev/null || fail "$p missing key: $out"
done
echo 'OK: test-cov-c2-zai-glm'
