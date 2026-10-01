#!/usr/bin/env bash
# Third-party network calls are documented and optional:
#  - Claude and Hermes pricing fetch (raw.githubusercontent.com) runs by
#    default, AIOC_NO_LITELLM=1 suppresses it
#  - Copilot DoH fallback (dns.google) runs only after a regional
#    api.github.com failure, AIOC_NO_DOH_FALLBACK=1 suppresses it
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/claude"
export TZ=UTC GITHUB_TOKEN="test-token" CURL_LOG="$TMP/curl.log"
mkdir -p "$CLAUDE_CONFIG_DIR" "$HOME" "$TMP/bin"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake curl: logs every invocation, answers HTTP 000 with an empty body —
# enough to force the Copilot adapter onto its DoH fallback path.
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && : > "$out"
printf '000'
EOF
# Deterministic token resolution: fake gh holds no token.
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMP/bin/curl" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
echo '{}' > "$CLAUDE_CONFIG_DIR/.credentials.json"

# --- Claude pricing fetch: on by default, off with AIOC_NO_LITELLM=1 ---
: > "$CURL_LOG"
bash "$ROOT/providers/get-claude-usage" > /dev/null
grep -q "raw.githubusercontent.com/BerriAI/litellm" "$CURL_LOG" \
  || fail "default run did not attempt the LiteLLM pricing fetch"

: > "$CURL_LOG"
AIOC_NO_LITELLM=1 bash "$ROOT/providers/get-claude-usage" > /dev/null
! grep -q "raw.githubusercontent.com" "$CURL_LOG" \
  || fail "AIOC_NO_LITELLM=1 did not suppress the LiteLLM pricing fetch"

# --- Hermes per-model pricing uses the same table and the same opt-out ---
HERMES_HOME="$TMP/hermes"
mkdir -p "$HERMES_HOME"
sqlite3 "$HERMES_HOME/state.db" "CREATE TABLE sessions(id TEXT, source TEXT, started_at REAL, cwd TEXT, git_repo_root TEXT);
CREATE TABLE session_model_usage(session_id TEXT, model TEXT, api_call_count INT, input_tokens INT, output_tokens INT,
  cache_read_tokens INT, cache_write_tokens INT, estimated_cost_usd REAL, actual_cost_usd REAL);"
: > "$CURL_LOG"
HERMES_HOME="$HERMES_HOME" bash "$ROOT/providers/get-hermes-analytics" > /dev/null
grep -q "raw.githubusercontent.com/BerriAI/litellm" "$CURL_LOG" \
  || fail "default Hermes run did not attempt the LiteLLM pricing fetch"
rm -f "$XDG_CACHE_HOME/AiOverviewControl/hermes-analytics-v2-cache.json"
: > "$CURL_LOG"
AIOC_NO_LITELLM=1 HERMES_HOME="$HERMES_HOME" bash "$ROOT/providers/get-hermes-analytics" > /dev/null
! grep -q "raw.githubusercontent.com" "$CURL_LOG" \
  || fail "AIOC_NO_LITELLM=1 did not suppress the Hermes pricing fetch"

# --- Copilot DoH fallback: reached after a 000, off with AIOC_NO_DOH_FALLBACK=1 ---
: > "$CURL_LOG"
bash "$ROOT/providers/get-copilot-usage" > /dev/null
grep -q "dns.google/resolve?name=api.github.com" "$CURL_LOG" \
  || fail "DoH fallback not reached after api.github.com returned 000"

: > "$CURL_LOG"
AIOC_NO_DOH_FALLBACK=1 bash "$ROOT/providers/get-copilot-usage" > /dev/null
! grep -q "dns.google" "$CURL_LOG" \
  || fail "AIOC_NO_DOH_FALLBACK=1 did not suppress the DoH fallback"

echo "ok: LiteLLM and dns.google calls are default-on, documented, and env-gated"
