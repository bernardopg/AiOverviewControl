#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Isolate every cache and config path so no real credential or history is read.
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$TMP/bin" "$HOME"

cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '{"error":"offline fixture"}'
SH
chmod +x "$TMP/bin/curl"

# Copy each thin adapter beside a recording wrapper so the test never reads
# credentials, caches, or databases from the invoking user's home directory.
for stub in "$ROOT"/providers/get-*-usage; do
  grep -q 'get-provider-wrapper' "$stub" || continue
  id="${stub##*/get-}"
  id="${id%-usage}"
  stub_dir="$TMP/$id"
  mkdir -p "$stub_dir"
  cp "$stub" "$stub_dir/$(basename "$stub")"
  cat >"$stub_dir/get-provider-wrapper" <<'SH'
#!/usr/bin/env bash
jq -cn --arg provider "${1:?}" '{provider:$provider}'
SH
  chmod +x "$stub_dir/get-provider-wrapper"
  output="$(bash "$stub_dir/$(basename "$stub")")"
  jq -e --arg id "$id" '.provider == $id' <<<"$output" >/dev/null
done

# Wrapper validates its required argument before invoking the dispatcher.
if "$ROOT/providers/get-provider-wrapper" >/dev/null 2>&1; then
  echo 'wrapper accepted a missing provider id' >&2
  exit 1
fi

# Dispatcher returns an error envelope for an unknown provider, rejects an
# invalid profile before touching credentials, and handles informational
# providers and multi-provider output without network or local data access.
unknown="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-provider-usage" 'not-a-provider')"
jq -e '.[0].provider == "not-a-provider" and .[0].error.kind == "provider"' <<<"$unknown" >/dev/null
profile="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-provider-usage" 'claude-invalid-profile')"
jq -e '.[0].provider == "claude-invalid-profile" and .[0].error.kind == "configuration"' <<<"$profile" >/dev/null
info="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-provider-usage" 'perplexity,amp')"
jq -e 'length == 2 and .[0].provider == "perplexity" and .[1].provider == "amp"' <<<"$info" >/dev/null
normalized="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-provider-usage" '  PERPLEXITY , AMP  , , KIMI-CODE')"
jq -e 'length == 3 and .[0].provider == "perplexity" and .[1].provider == "amp" and .[2].provider == "kimi-code" and .[2].error.kind == "provider"' <<<"$normalized" >/dev/null

# Hide optional provider CLIs and credentials while retaining only the tools
# needed to run health checks; assert each missing-prerequisite result.
mkdir -p "$TMP/no-cli"
for cmd in bash jq xargs tr grep date stat dirname echo; do
  target="$(type -P "$cmd")"
  [ -n "$target" ] && ln -s "$target" "$TMP/no-cli/$cmd"
done
health="$(env -u GH_TOKEN -u GITHUB_TOKEN -u COPILOT_GITHUB_TOKEN \
  -u GEMINI_API_KEY -u GOOGLE_API_KEY -u GOOGLE_GENERATIVE_AI_API_KEY \
  -u DEEPSEEK_API_KEY -u COMMAND_CODE_API_KEY -u HERMES_HOME \
  -u ANTIGRAVITY_STATE_DB -u CURSOR_STATE_DB -u CURSOR_AUTH_FILE \
  -u OPENCODE_DATA_DIR -u OPENCODE_USAGE_SOURCE -u CLAUDE_CONFIG_DIR \
  -u AIOC_CLAUDE_PROFILES -u GROK_HOME \
  PATH="$TMP/no-cli" HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  bash "$ROOT/providers/get-provider-health" codex,claude,copilot,gemini,deepseek,commandcode,antigravity)"
jq -e 'length == 7 and all(.[]; .status == "missing")
  and .[0].detail == "codex CLI"
  and .[1].detail == "claude CLI, ~/.claude or CLAUDE_CONFIG_DIR"
  and .[2].detail == "gh CLI or GitHub token"
  and .[3].detail == "gemini CLI or API key"
  and .[4].detail == "DEEPSEEK_API_KEY"
  and .[5].detail == "COMMAND_CODE_API_KEY or ~/.commandcode/auth.json"
  and .[6].detail == "CLI keyring, valid token file, or IDE state with sqlite3"' \
  <<<"$health" >/dev/null || { echo "unexpected missing-health output: $health" >&2; exit 1; }

health="$(env -u XDG_DATA_HOME -u OPENROUTER_API_KEY -u DEEPSEEK_API_KEY \
  -u KIMI_CODING_API_KEY -u MOONSHOT_API_KEY -u KIMI_API_KEY \
  -u MINIMAX_API_KEY -u MINIMAX_TOKEN_PLAN_KEY -u OPENCODE_API_KEY \
  -u GLM_API_KEY -u ZHIPU_API_KEY -u ZAI_API_KEY -u MISTRAL_API_KEY \
  -u NVIDIA_API_KEY -u NEURALWATT_API_KEY -u CLINE_API_KEY \
  -u CLOUDFLARE_AI_TOKEN -u CLOUDFLARE_API_TOKEN -u BYTEPLUS_API_KEY \
  -u ARK_API_KEY -u DASHSCOPE_API_KEY -u QWEN_API_KEY -u TOGETHER_API_KEY \
  -u GROQ_API_KEY -u COHERE_API_KEY -u REPLICATE_API_TOKEN -u FIREWORKS_API_KEY \
  -u XAI_API_KEY -u XAI_MANAGEMENT_KEY -u XAI_MANAGEMENT_API_KEY \
  -u KILO_API_KEY -u AI21_API_KEY -u HERMES_HOME -u ANTIGRAVITY_STATE_DB \
  -u CURSOR_STATE_DB -u CURSOR_AUTH_FILE -u OPENCODE_DATA_DIR \
  -u OPENCODE_USAGE_SOURCE -u CLAUDE_CONFIG_DIR -u AIOC_CLAUDE_PROFILES \
  -u GROK_HOME -u XDG_DATA_HOME \
  PATH="$TMP/no-cli" HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  bash "$ROOT/providers/get-provider-health" \
  9router,openrouter,deepseek,kimi-code,kimi,minimax,opencode,glm,zai,mistral,ollama,nvidia,neuralwatt,cline,cloudflare,vertexai,byteplus,qwen,together,groq,cohere,replicate,fireworks,xai,kilo,ai21,pi,hermes,cursor,perplexity)"
jq -e 'length == 30 and all(.[0:29][]; .status == "missing")
  and .[29].status == "info"
  and .[0].detail == "9Router usage database"
  and .[6].detail == "OpenCode local database or OPENCODE_API_KEY"
  and .[14].detail == "Cloudflare API token"
  and .[28].detail == "Cursor IDE session or cursor-agent auth.json"
  and .[29].detail == "No public read-only quota API"' <<<"$health" >/dev/null \
  || { echo "unexpected provider-health matrix: $health" >&2; exit 1; }

# Validate profile-directory errors, the IDE database prerequisite, and the
# unknown-provider vocabulary without accessing real config or credentials.
mkdir -p "$TMP/claude-profile" "$XDG_CONFIG_HOME/Antigravity IDE/User/globalStorage" "$TMP/with-sqlite"
sqlite="$(type -P sqlite3)"
[ -n "$sqlite" ] && ln -s "$sqlite" "$TMP/with-sqlite/sqlite3"
for cmd in bash jq xargs tr grep date stat dirname echo; do
  target="$(type -P "$cmd")"
  [ -n "$target" ] && ln -s "$target" "$TMP/with-sqlite/$cmd"
done
: >"$XDG_CONFIG_HOME/Antigravity IDE/User/globalStorage/state.vscdb"
profile_map="$(jq -nc --arg dir "$TMP/claude-profile" '{"claude-fixture":{configDir:$dir}}')"
health="$(env -u AIOC_CLAUDE_PROFILES AIOC_CLAUDE_PROFILES="$profile_map" \
  PATH="$TMP/no-cli" HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  bash "$ROOT/providers/get-provider-health" claude-fixture,unknown-provider)"
jq -e '.[0].status == "missing" and .[0].detail == "Claude profile credentials"
  and .[1].status == "unknown" and .[1].detail == "Unknown provider"' \
  <<<"$health" >/dev/null || { echo "unexpected profile/unknown-health output: $health" >&2; exit 1; }
health="$(PATH="$TMP/with-sqlite" HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  bash "$ROOT/providers/get-provider-health" antigravity)"
jq -e '.[0].status == "ready" and .[0].detail == "Configured"' <<<"$health" >/dev/null \
  || { echo "Antigravity IDE database was not recognized: $health" >&2; exit 1; }

