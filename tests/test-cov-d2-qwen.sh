#!/usr/bin/env bash
set -euo pipefail
# Offline branch coverage for the qwen native adapter.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" TMPDIR="$TMP"
mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out= url= headers= write=0
while (($#)); do case "$1" in -o) out="$2"; shift 2;; -D) headers="$2"; shift 2;; -w) write=1; shift 2;; http*) url="$1"; shift;; *) shift;; esac; done
status="${COV_STATUS:-200}"; body="${COV_BODY-}"; [ -n "$body" ] || body='{}'
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
run() { "$ROOT/providers/get-qwen-usage"; }
# Missing credential guard (where this adapter uses a credential).
unset DASHSCOPE_API_KEY
provider=qwen
case "$provider" in ollama|vertexai) ;; *) jq -e '.[0].error.code == 2' <<<"$(run)" >/dev/null;; esac
export DASHSCOPE_API_KEY=sk-test-0000
export COV_STATUS=200 COV_BODY='{}'
result="$(run)"
jq -e '.[0].provider == "qwen"' <<<"$result" >/dev/null
export COV_STATUS=401 COV_BODY='{"message":"denied"}'
result="$(run)"
jq -e '.[0].provider == "qwen"' <<<"$result" >/dev/null
export COV_STATUS=500 COV_BODY='{}'
result="$(run)"
jq -e '.[0].provider == "qwen"' <<<"$result" >/dev/null
