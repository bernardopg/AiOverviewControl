#!/usr/bin/env bash
set -euo pipefail
# Offline branch coverage for the cloudflare native adapter.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" TMPDIR="$TMP"
mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out= url= headers= write=0
while (($#)); do case "$1" in -o) out="$2"; shift 2;; -D) headers="$2"; shift 2;; -w) write=1; shift 2;; http*) url="$1"; shift;; *) shift;; esac; done
status="${COV_STATUS:-200}"; body="${COV_BODY-}"; [ -n "$body" ] || body='{"success":true}'
case "$url" in */api/tags) body='{"models":[{"name":"llama:latest"}]}';;
*/api/ps) body='{"models":[{"name":"llama:latest"}]}';;
https://api.cloudflare.com/client/v4/graphql) body="${COV_GRAPH_BODY:-$body}";;
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
run() { "$ROOT/providers/get-cloudflare-usage"; }
# Missing credential guard (where this adapter uses a credential).
export CLOUDFLARE_ACCOUNT_ID=acct-test
unset CLOUDFLARE_AI_TOKEN
provider=cloudflare
case "$provider" in ollama|vertexai) ;; *) jq -e '.[0].error.code == 2' <<<"$(run)" >/dev/null;; esac
export CLOUDFLARE_AI_TOKEN=sk-test-0000
export CLOUDFLARE_ACCOUNT_ID=acct-test
export COV_STATUS=200 COV_BODY='{"success":true}'
result="$(run)"
jq -e '.[0].provider == "cloudflare"' <<<"$result" >/dev/null
export COV_STATUS=401 COV_BODY='{"message":"denied"}'
result="$(run)"
jq -e '.[0].provider == "cloudflare"' <<<"$result" >/dev/null
export COV_STATUS=500 COV_BODY='{}'
result="$(run)"
jq -e '.[0].provider == "cloudflare"' <<<"$result" >/dev/null

# GraphQL success, schema fallback, and token-only fallback.
export CLOUDFLARE_AI_TOKEN=sk-test-0000 CLOUDFLARE_ACCOUNT_ID=acct-test COV_STATUS=200 COV_GRAPH_BODY='{"data":{"viewer":{"accounts":[{"aiInferenceAdaptiveGroups":[]}]}}}'
result="$(run)"; jq -e '.[0].source == "cloudflare-graphql" and (.[0].usage.primary.displayValue | type == "string")' <<<"$result" >/dev/null
export COV_GRAPH_BODY='{"errors":[{"message":"denied"}]}'
result="$(run)"; jq -e '.[0].source == "cloudflare-api"' <<<"$result" >/dev/null
unset CLOUDFLARE_ACCOUNT_ID
result="$(run)"; jq -e '.[0].source == "cloudflare-api"' <<<"$result" >/dev/null
# Alternate token variable, no account analytics, and both token error fields.
unset CLOUDFLARE_AI_TOKEN CLOUDFLARE_ACCOUNT_ID
export CLOUDFLARE_API_TOKEN=sk-test-0000 COV_STATUS=200 COV_BODY='{}'
result="$(run)"; jq -e '.[0].source == "cloudflare-api" and .[0].usage.accountEmail == "Cloudflare account unknown"' <<<"$result" >/dev/null
export CLOUDFLARE_ACCOUNT_ID=acct-test COV_STATUS=403 COV_BODY='{"errors":[{"message":"scope denied"}]}'
result="$(run)"; jq -e '.[0].error.message == "scope denied"' <<<"$result" >/dev/null
