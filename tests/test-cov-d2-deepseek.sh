#!/usr/bin/env bash
set -euo pipefail
# Offline branch coverage for the deepseek native adapter.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" TMPDIR="$TMP"
mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out= url= headers= write=0
while (($#)); do case "$1" in -o) out="$2"; shift 2;; -D) headers="$2"; shift 2;; -w) write=1; shift 2;; http*) url="$1"; shift;; *) shift;; esac; done
status="${COV_STATUS:-200}"; body="${COV_BODY-}"; [ -n "$body" ] || body='{"balance_infos":[{"currency":"USD","total_balance":"12.5","granted_balance":"5","topped_up_balance":"7.5","is_available":true}]}'
case "$url" in */api/tags) body='{"models":[{"name":"llama:latest"}]}';;
*/api/ps) body='{"models":[{"name":"llama:latest"}]}';;
https://api.cloudflare.com/client/v4/graphql) body="${COV_GRAPH_BODY:-{"data":{"viewer":{"accounts":[{"aiInferenceAdaptiveGroups":[]}]}}}}";;
esac
[ -z "$out" ] || printf '%s' "$body" >"$out"
if [ -n "$headers" ]; then printf 'x-ratelimit-limit-requests: 100\nx-ratelimit-remaining-requests: 80\nx-ratelimit-reset-requests: 2m\nx-ratelimit-limit-tokens: 1000\nx-ratelimit-remaining-tokens: 500\nx-ratelimit-reset-tokens: 547ms\n' >"$headers"; fi
[ "$write" -eq 0 ] || printf '%s' "$status"
STUB
cat >"$TMP/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
case "$*" in *print-access-token*) echo token;; *"get-value account"*) echo test@example.com;; esac
STUB
chmod +x "$TMP/bin/curl" "$TMP/bin/gcloud"
export PATH="$TMP/bin:$PATH"
run() { "$ROOT/providers/get-deepseek-usage"; }
# Missing credential guard (where this adapter uses a credential).
unset DEEPSEEK_API_KEY
provider=deepseek
case "$provider" in ollama|vertexai) ;; *) jq -e '.[0].error.code == 2' <<<"$(run)" >/dev/null;; esac
export DEEPSEEK_API_KEY=sk-test-0000
export COV_STATUS=200 COV_BODY='{"balance_infos":[{"currency":"USD","total_balance":"12.5","granted_balance":"5","topped_up_balance":"7.5","is_available":true}]}'
result="$(run)"
jq -e '.[0].provider == "deepseek"' <<<"$result" >/dev/null
export COV_STATUS=401 COV_BODY='{"message":"denied"}'
result="$(run)"
jq -e '.[0].provider == "deepseek"' <<<"$result" >/dev/null
export COV_STATUS=500 COV_BODY='{}'
result="$(run)"
jq -e '.[0].provider == "deepseek"' <<<"$result" >/dev/null

# Missing balance fields use zero/default currency; unavailable funds show depleted.
export DEEPSEEK_API_KEY=sk-test-0000 COV_STATUS=200 COV_BODY='{"balance_infos":[]}'
result="$(run)"; jq -e '.[0].usage.primary.displayValue == "CNY 0"' <<<"$result" >/dev/null
export COV_BODY='{"balance_infos":[{"is_available":false}]}'
result="$(run)"; jq -e '.[0].usage.primary.usedPercent == 100 and .[0].usage.tertiary.displayValue == "CNY 0"' <<<"$result" >/dev/null
# DeepSeek's nested error message and empty-body fallback are both surfaced.
export DEEPSEEK_API_KEY=sk-test-0000 COV_STATUS=403 COV_BODY='{"error":{"message":"forbidden"}}'
result="$(run)"; jq -e '.[0].error.message == "forbidden"' <<<"$result" >/dev/null
export COV_STATUS=503 COV_BODY='not-json'
result="$(run)"; jq -e '.[0].error.message | contains("HTTP 503")' <<<"$result" >/dev/null
