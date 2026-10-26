#!/usr/bin/env bash
# Credentials never reach a process command line, which every local user can
# read (ps, /proc/<pid>/cmdline): each API-key adapter passes its secret header
# to curl through --config on a pipe. Caches are created owner-only, and a
# pre-2.1.0 cache directory is tightened.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
SECRET="sk-argv-sentinel-0000"
mkdir -p "$TMP/bin" "$TMP/home"
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
export AIOC_NO_LITELLM=1 AIOC_NO_DOH_FALLBACK=1 AIOC_NO_FX=1 ARGV_LOG="$TMP/argv.log" CFG_LOG="$TMP/cfg.log"
# Fake curl: records its argv and any --config contents, answers 401.
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ARGV_LOG"
out=""; prev=""
for arg in "$@"; do
  [ "$prev" != -o ] || out="$arg"
  if [ "$prev" = --config ]; then cat "$arg" >> "$CFG_LOG"; fi
  prev="$arg"
done
[ -z "$out" ] || printf '{}' > "$out"
printf 401
SH
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

# Same provider set the response fuzzer covers.
declare -A vars=(
  [ai21]=AI21_API_KEY [byteplus]=ARK_API_KEY [cline]=CLINE_API_KEY [cloudflare]=CLOUDFLARE_API_TOKEN
  [cohere]=COHERE_API_KEY [deepseek]=DEEPSEEK_API_KEY [fireworks]=FIREWORKS_API_KEY [gemini]=GEMINI_API_KEY
  [glm]=GLM_API_KEY [groq]=GROQ_API_KEY [kilo]=KILO_API_KEY [kimi]=MOONSHOT_API_KEY
  [minimax]=MINIMAX_API_KEY [mistral]=MISTRAL_API_KEY [neuralwatt]=NEURALWATT_API_KEY
  [openrouter]=OPENROUTER_API_KEY [qwen]=DASHSCOPE_API_KEY [replicate]=REPLICATE_API_TOKEN
  [together]=TOGETHER_API_KEY [zai]=ZAI_API_KEY [commandcode]=COMMAND_CODE_API_KEY [kimi-code]=KIMI_CODING_API_KEY
)
for provider in "${!vars[@]}"; do
  : > "$ARGV_LOG"; : > "$CFG_LOG"
  env "${vars[$provider]}=$SECRET" CLOUDFLARE_ACCOUNT_ID=acct FIREWORKS_ACCOUNT_ID=acct \
    bash "$ROOT/providers/get-provider-usage" "$provider" >/dev/null 2>&1 || true
  [ -s "$ARGV_LOG" ] || fail "$provider made no request"
  ! grep -qF "$SECRET" "$ARGV_LOG" || fail "$provider put its credential on the curl command line"
  grep -qF "$SECRET" "$CFG_LOG" || fail "$provider did not send its credential through --config"
done

# Header values with quotes or backslashes survive the config syntax.
# shellcheck source=providers/http-common
source "$ROOT/providers/http-common"
[ "$(curl_header_config 'X-Test: a"b\c')" = 'header = "X-Test: a\"b\\c"' ] || fail "config escaping"

# Owner-only caches, and an old world-readable cache directory is tightened.
mkdir -p "$XDG_CACHE_HOME/AiOverviewControl"
chmod 755 "$XDG_CACHE_HOME/AiOverviewControl"
printf '{}' > "$XDG_CACHE_HOME/AiOverviewControl/old.json"
chmod 644 "$XDG_CACHE_HOME/AiOverviewControl/old.json"
DEEPSEEK_API_KEY="$SECRET" bash "$ROOT/providers/get-provider-usage" deepseek >/dev/null 2>&1 || true
[ "$(stat -c %a "$XDG_CACHE_HOME/AiOverviewControl")" = 700 ] || fail "cache directory not owner-only"
[ "$(stat -c %a "$XDG_CACHE_HOME/AiOverviewControl/old.json")" = 600 ] || fail "old cache file still readable by others"
rm -rf "$XDG_CACHE_HOME"
bash "$ROOT/providers/get-local-analytics" codex >/dev/null 2>&1 || true
AIOC_NO_LITELLM=1 CLAUDE_CONFIG_DIR="$TMP/claude" bash "$ROOT/providers/get-claude-usage" >/dev/null 2>&1 || true
while IFS= read -r -d '' path; do
  mode="$(stat -c %a "$path")"
  case "$mode" in 700 | 600) ;; *) fail "$path created with mode $mode" ;; esac
done < <(find "$XDG_CACHE_HOME" -mindepth 1 -print0)

echo "OK: credentials stay off the command line; caches are owner-only"
