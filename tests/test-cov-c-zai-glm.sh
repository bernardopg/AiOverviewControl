#!/usr/bin/env bash
# Z.ai and GLM quota mapping plus auth-only fallback paths.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in -o) out="${args[$((i+1))]}" ;; http*) url="${args[$i]}" ;; esac
done
case "$CASE:$url" in
  quota:*) printf '%s\n' '{"success":true,"data":{"level":"pro","limits":[{"type":"TIME_LIMIT","unit":4,"number":2,"percentage":"120","nextResetTime":1793000000000,"usage":100,"currentValue":120},{"type":"TOKENS_LIMIT","unit":3,"number":1,"percentage":20}]}}' >"$out"; code=200 ;;
  fallback:*/models) printf '%s\n' '{"data":[]}' >"$out"; code=200 ;;
  fallback:*) printf '%s\n' '{"message":"quota unavailable"}' >"$out"; code=503 ;;
  reject:*) printf '%s\n' '{}' >"$out"; code=403 ;;
esac
printf '%s' "$code"
STUB
chmod +x "$TMP/bin/curl"
fail() { echo "FAIL: $1" >&2; exit 1; }
run() { CASE="$1" PATH="$TMP/bin:$PATH" ZAI_API_KEY=sk-test GLM_API_KEY=sk-test "$ROOT/providers/get-provider-usage" "$2" 2>/dev/null; }

for provider in zai glm; do
  out="$(run quota "$provider")"
  jq -e --arg p "$provider" '.[0].provider == $p and .[0].usage.primary.usedPercent == 100 and .[0].usage.primary.windowMinutes == 600' <<<"$out" >/dev/null || fail "$provider quota mapping"
  out="$(run fallback "$provider")"
  jq -e '.[0].source | contains("api")' <<<"$out" >/dev/null || fail "$provider models fallback"
  out="$(run reject "$provider")"
  jq -e '.[0].error.code == 403' <<<"$out" >/dev/null || fail "$provider rejected key"
done
echo "OK: test-cov-c-zai-glm"
