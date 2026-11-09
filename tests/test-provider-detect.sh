#!/usr/bin/env bash
# Provider detection reads the evidence get-provider-health records for each
# ready provider: the kind of source (key, login, local, vault, cli, keyring)
# and a label (variable name, command or ~ path). The dashboard and settings
# tick strong evidence and leave the CLI-only and keyring-tool-only providers
# unticked, so each source must report the kind that matches it.
#
# Hermetic: a fake HOME and PATH, an empty environment apart from the
# variables each case sets, and no command that talks to a keyring or network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

HOME_DIR="$TMP/home"
mkdir -p "$TMP/base" "$TMP/tools" "$HOME_DIR"
for cmd in bash jq xargs tr grep date dirname cat echo; do
  target="$(type -P "$cmd")"
  [ -n "$target" ] && ln -s "$target" "$TMP/base/$cmd"
done
for cmd in codex claude gh gemini gcloud ollama secret-tool pi hermes; do
  printf '#!/bin/sh\nexit 0\n' >"$TMP/tools/$cmd"
  chmod +x "$TMP/tools/$cmd"
done

# health <PATH> <providers> [VAR=value...]: run the helper in a clean env.
# kcov's BASH_ENV and trace descriptor are kept so scripts/coverage still
# traces the helper.
health() {
  local path="$1" providers="$2"
  shift 2
  env -i ${BASH_ENV:+BASH_ENV="$BASH_ENV"} ${BASH_XTRACEFD:+BASH_XTRACEFD="$BASH_XTRACEFD"} \
    ${KCOV_BASH_XTRACEFD:+KCOV_BASH_XTRACEFD="$KCOV_BASH_XTRACEFD"} HOME="$HOME_DIR" PATH="$path" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" XDG_DATA_HOME="$HOME_DIR/.local/share" "$@" \
    bash "$ROOT/providers/get-provider-health" "$providers"
}

# evidence <json> <provider>: "status kind label" for one provider.
evidence() {
  jq -r --arg id "$2" '.[] | select(.provider == $id)
    | [.status, (.evidence.kind // "-"), (.evidence.label // "-")] | join(" ")' <<<"$1"
}

expect() {
  local got
  got="$(evidence "$1" "$2")"
  [ "$got" = "$3" ] || fail "$2: expected '$3', got '$got'"
}

# Nothing installed or configured: nothing is ready and no evidence leaks.
out="$(health "$TMP/base" codex,claude,copilot,gemini,ollama,vertexai,pi,hermes,9router)"
jq -e 'all(.[]; .status == "missing" and .evidence == null)' <<<"$out" >/dev/null \
  || fail "missing providers carried evidence: $out"

# Installed CLIs without a saved sign-in are weak evidence.
out="$(health "$TMP/base:$TMP/tools" codex,claude,copilot,gemini,ollama,vertexai,pi,hermes)"
expect "$out" codex "ready cli codex"
expect "$out" claude "ready cli claude"
expect "$out" copilot "ready cli gh"
expect "$out" gemini "ready cli gemini"
expect "$out" ollama "ready cli ollama"
expect "$out" vertexai "ready cli gcloud"
expect "$out" pi "ready cli pi"
expect "$out" hermes "ready cli hermes"

# Saved sign-ins and local data upgrade the same providers, with ~ paths.
mkdir -p "$HOME_DIR/.codex" "$HOME_DIR/.claude" "$HOME_DIR/.config/gh" "$HOME_DIR/.gemini" \
  "$HOME_DIR/.pi/agent/sessions" "$HOME_DIR/.hermes" "$HOME_DIR/.9router/db" "$HOME_DIR/.config/antigravity-cli"
: >"$HOME_DIR/.codex/auth.json"
: >"$HOME_DIR/.config/gh/hosts.yml"
: >"$HOME_DIR/.gemini/oauth_creds.json"
: >"$HOME_DIR/.hermes/state.db"
: >"$HOME_DIR/.9router/db/data.sqlite"
out="$(health "$TMP/base:$TMP/tools" codex,claude,copilot,gemini,pi,hermes,9router,openrouter)"
expect "$out" codex "ready login ~/.codex/auth.json"
expect "$out" claude "ready cli claude"
expect "$out" copilot "ready login ~/.config/gh/hosts.yml"
expect "$out" gemini "ready login ~/.gemini/oauth_creds.json"
expect "$out" pi "ready local ~/.pi/agent/sessions"
expect "$out" hermes "ready local ~/.hermes/state.db"
expect "$out" 9router "ready local ~/.9router/db/data.sqlite"
expect "$out" openrouter "ready local ~/.9router/db/data.sqlite"

# Claude: the credentials file wins over the CLI, the bare directory is local.
: >"$HOME_DIR/.claude/.credentials.json"
out="$(health "$TMP/base:$TMP/tools" claude)"
expect "$out" claude "ready login ~/.claude/.credentials.json"
rm "$HOME_DIR/.claude/.credentials.json"
out="$(health "$TMP/base" claude)"
expect "$out" claude "ready local ~/.claude"

# The codex sign-in alone is not enough: the adapter needs the CLI.
out="$(health "$TMP/base" codex)"
expect "$out" codex "missing - -"

# Keys report the variable name and never its value.
out="$(health "$TMP/base:$TMP/tools" deepseek,copilot,gemini,kimi-code,openrouter \
  DEEPSEEK_API_KEY=sk-secret-deepseek GH_TOKEN=ghp-secret GOOGLE_API_KEY=g-secret \
  KIMI_CODING_API_KEY=kc-secret OPENROUTER_API_KEY=or-secret)"
expect "$out" deepseek "ready key DEEPSEEK_API_KEY"
expect "$out" copilot "ready key GH_TOKEN"
expect "$out" gemini "ready key GOOGLE_API_KEY"
expect "$out" kimi-code "ready key KIMI_CODING_API_KEY"
expect "$out" openrouter "ready key OPENROUTER_API_KEY"
if grep -q 'secret' <<<"$out"; then fail "a key value reached the health output: $out"; fi

# Kimi Code accepts an sk-kimi- key in either Moonshot variable.
out="$(health "$TMP/base" kimi-code MOONSHOT_API_KEY=sk-kimi-a)"
expect "$out" kimi-code "ready key MOONSHOT_API_KEY"
out="$(health "$TMP/base" kimi-code KIMI_API_KEY=sk-kimi-b)"
expect "$out" kimi-code "ready key KIMI_API_KEY"
out="$(health "$TMP/base" kimi-code MOONSHOT_API_KEY=sk-plain)"
expect "$out" kimi-code "missing - -"

# A configured keyring entry is strong; secret-tool alone is only the weak
# "keyring" kind for Antigravity, and a token file beats it.
out="$(health "$TMP/base:$TMP/tools" zai,antigravity AIOC_VAULT_ZAI='service zai')"
expect "$out" zai "ready vault zai"
expect "$out" antigravity "ready keyring secret-tool"
printf '{"token":{"refresh_token":"r"}}' >"$HOME_DIR/.config/antigravity-cli/antigravity-oauth-token"
out="$(health "$TMP/base:$TMP/tools" antigravity)"
expect "$out" antigravity "ready login ~/.config/antigravity-cli/antigravity-oauth-token"

# Informational providers stay "info" without evidence. IDs are trimmed and
# lowercased, empty entries skipped, and one JSON array covers the whole list.
out="$(health "$TMP/base" ' PERPLEXITY , ,unknown-x')"
expect "$out" perplexity "info - -"
jq -e 'length == 2 and .[1].status == "unknown"' <<<"$out" >/dev/null || fail "unexpected list parsing: $out"
[ "$(health "$TMP/base" ',')" = '[]' ] || fail "an empty list did not print []"

echo 'OK: provider detection evidence per source, ~ paths, no key values'
