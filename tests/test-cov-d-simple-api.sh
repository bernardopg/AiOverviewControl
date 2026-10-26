#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$HOME"
mkdir -p "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""
url=""
write=0
for ((i=1; i<=$#; i++)); do
  case "${!i}" in
    -o) j=$((i+1)); out="${!j}" ;;
    -w) write=1 ;;
    http*) url="${!i}" ;;
  esac
done
status="${COV_STATUS:-200}"
body="${COV_BODY-}"
[ -n "$body" ] || body='{}'
if [[ "$url" == */api/ps ]]; then body='{"models":[{"name":"local:latest"}]}' ; fi
if [ -n "$out" ]; then printf '%s' "$body" >"$out"; fi
if [ "$write" -eq 1 ]; then printf '%s' "$status"; fi
exit 0
STUB
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

set_credential() {
  case "$1" in
    cloudflare) export CLOUDFLARE_AI_TOKEN=sk-test-0000 CLOUDFLARE_ACCOUNT_ID=acct-test ;;
    deepseek) export DEEPSEEK_API_KEY=sk-test-0000 ;;
    ollama) export OLLAMA_HOST=http://localhost:11434 ;;
    fireworks) export FIREWORKS_API_KEY=sk-test-0000 FIREWORKS_ACCOUNT_ID=acct-test ;;
    replicate) export REPLICATE_API_TOKEN=sk-test-0000 ;;
    gemini) export GEMINI_API_KEY=sk-test-0000 ;;
    kilo) export KILO_API_KEY=sk-test-0000 ;;
    together) export TOGETHER_API_KEY=sk-test-0000 ;;
    cohere) export COHERE_API_KEY=sk-test-0000 ;;
    byteplus) export BYTEPLUS_API_KEY=sk-test-0000 ;;
    ai21) export AI21_API_KEY=sk-test-0000 ;;
    qwen) export DASHSCOPE_API_KEY=sk-test-0000 ;;
    mistral) export MISTRAL_API_KEY=sk-test-0000 ;;
    vertexai) ;;
  esac
}
run() { "$ROOT/providers/get-$1-usage"; }
assert_provider() { jq -e --arg p "$1" '.[0].provider == $p and (.[0].usage.identity.providerID == $p or .[0].error != null)' >/dev/null; }

# Missing credentials cover the local auth guard for credential-backed adapters.
for provider in cloudflare deepseek fireworks replicate gemini kilo together cohere byteplus ai21 qwen mistral; do
  result="$(
    unset CLOUDFLARE_AI_TOKEN CLOUDFLARE_API_TOKEN DEEPSEEK_API_KEY FIREWORKS_API_KEY
    unset REPLICATE_API_TOKEN GEMINI_API_KEY GOOGLE_API_KEY GOOGLE_GENERATIVE_AI_API_KEY
    unset KILO_API_KEY TOGETHER_API_KEY COHERE_API_KEY BYTEPLUS_API_KEY AI21_API_KEY
    unset DASHSCOPE_API_KEY MISTRAL_API_KEY
    run "$provider"
  )"
  jq -e --arg p "$provider" '.[0].provider == $p and .[0].error.code == 2' <<<"$result" >/dev/null
done

for provider in cloudflare deepseek fireworks replicate gemini kilo together cohere byteplus ai21 qwen mistral ollama; do
  set_credential "$provider"
  case "$provider" in
    cloudflare) export COV_BODY='{"success":true}' ;;
    deepseek) export COV_BODY='{"balance_infos":[{"currency":"USD","total_balance":"12.5","granted_balance":"5","topped_up_balance":"7.5","is_available":true}]}' ;;
    fireworks) export COV_BODY='{"quotas":[{"name":"/model/day","usage":25,"value":100,"maxValue":200}]}' ;;
    replicate) export COV_BODY='{"username":"test-user","github_url":"https://github.com/test-user"}' ;;
    gemini|kilo|together|cohere|byteplus|ai21|qwen|mistral) export COV_BODY='{}' ;;
    ollama) export COV_BODY='{"models":[{"name":"llama3:latest"}]}' ;;
  esac
  result="$(run "$provider")"
  jq -e --arg p "$provider" '.[0].provider == $p' <<<"$result" >/dev/null
done
set_credential deepseek
export COV_BODY='{"balance_infos":[{"currency":"USD","total_balance":"12.5","granted_balance":"5","topped_up_balance":"7.5","is_available":true}]}'
jq -e '.[0].usage.primary.displayValue == "USD 12.5" and .[0].usage.secondary.displayValue == "USD 5" and .[0].usage.tertiary.displayValue == "USD 7.5" and .[0].credits.remaining == "USD 12.5"' <<<"$(run deepseek)" >/dev/null
export COV_STATUS=401 COV_BODY='{"message":"denied"}'
for provider in cloudflare deepseek fireworks replicate gemini kilo together cohere byteplus ai21 qwen mistral; do
  set_credential "$provider"
  result="$(run "$provider")"
  assert_provider "$provider" <<<"$result"
done
export COV_STATUS=500 COV_BODY='{"message":"offline"}'
result="$(run deepseek)"; jq -e '.[0].error.code == 500' <<<"$result" >/dev/null
export COV_STATUS=200 COV_BODY='not-json'
result="$(run replicate)"; jq -e '.[0].provider == "replicate"' <<<"$result" >/dev/null 2>&1
