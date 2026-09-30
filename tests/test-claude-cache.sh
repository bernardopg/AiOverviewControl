#!/usr/bin/env bash
# get-claude-usage cache behavior:
#  - plugin-owned caches live in the XDG cache dir, never in ~/.claude
#  - legacy ~/.claude cache files are migrated once, then gone
#  - transcripts are parsed once per (size, mtime); a refresh re-parses only
#    changed files, and a UTC-offset change rebuilds the date-bucketed rows
#  - claude --version is probed at most once per 24h
#  - stats-cache.json in ~/.claude stays read-only input
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/claude"
export TZ=UTC AIOC_NO_LITELLM=1
export CURL_LOG="$TMP/curl.log" CLAUDE_VERSION_CALLS="$TMP/claude-calls"
# Real project dirs are the cwd with "/" mapped to "-", so they start with "-".
CLAUDE_PROJECTS="$CLAUDE_CONFIG_DIR/projects/-home-user-proj"
mkdir -p "$CLAUDE_PROJECTS" "$HOME" "$TMP/bin"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake curl: logs every invocation, answers HTTP 000 with an empty body.
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && : > "$out"
printf '000'
EOF
# Fake claude CLI: counts --version probes.
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo 1 >> "$CLAUDE_VERSION_CALLS"
echo "2.1.0 (Claude Code)"
EOF
# jq wrapper: logs which transcripts each call parses, then runs the real jq.
REAL_JQ="$(command -v jq)"
export JQ_LOG="$TMP/jq.log"
cat > "$TMP/bin/jq" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in *.jsonl) printf '%s\n' "\$a" >> "\$JQ_LOG"; [ -z "\${JQ_FAIL:-}" ] || exit 5 ;; esac; done
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$TMP/bin/curl" "$TMP/bin/claude" "$TMP/bin/jq"
export PATH="$TMP/bin:$PATH"

NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
jq -cn --arg ts "$NOW" \
  '{type:"assistant",timestamp:$ts,sessionId:"s1",cwd:"/proj",message:{model:"claude-sonnet-4",usage:{input_tokens:1000,output_tokens:500}}}' \
  > "$CLAUDE_PROJECTS/session1.jsonl"
echo '{"totalSessions":7,"totalMessages":42,"firstSessionDate":"2025-01-01T00:00:00Z"}' \
  > "$CLAUDE_CONFIG_DIR/stats-cache.json"
echo '{}' > "$CLAUDE_CONFIG_DIR/.credentials.json"

# --- Legacy migration: files move out of ~/.claude exactly once ---
echo '{"schema":2,"updated":"2099-01-01","models":{}}' > "$CLAUDE_CONFIG_DIR/pricing-cache.json"
echo '{"cached_at":1,"data":{"five_hour":{"utilization":1}}}' > "$CLAUDE_CONFIG_DIR/usage-cache.json"
bash "$ROOT/providers/get-claude-usage" > /dev/null
[ ! -e "$CLAUDE_CONFIG_DIR/pricing-cache.json" ] || fail "legacy pricing cache left in CLAUDE_CONFIG_DIR"
[ ! -e "$CLAUDE_CONFIG_DIR/usage-cache.json" ] || fail "legacy usage cache left in CLAUDE_CONFIG_DIR"
[ -f "$XDG_CACHE_HOME/AiOverviewControl/claude-pricing-cache.json" ] || fail "pricing cache not migrated to XDG dir"
[ -f "$XDG_CACHE_HOME/AiOverviewControl/claude-usage-cache.json" ] || fail "usage cache not migrated to XDG dir"

# --- Caches never pollute ~/.claude; stats-cache.json is still read ---
! find "$CLAUDE_CONFIG_DIR" -name "*cache*.json" ! -name "stats-cache.json" | grep -q . \
  || fail "plugin wrote a cache into CLAUDE_CONFIG_DIR"
bash "$ROOT/providers/get-claude-usage" | grep -q '^ALLTIME_MESSAGES=42$' \
  || fail "stats-cache.json no longer read"

# --- Per-file cache: unreadable-but-unchanged transcripts still served from cache ---
first="$(bash "$ROOT/providers/get-claude-usage" | grep -E '^(WEEK_TOKENS|WEEK_PROJECTS)=')"
[ "$first" = $'WEEK_TOKENS=1500\nWEEK_PROJECTS=/proj:1500' ] || fail "cold aggregation wrong: $first"
chmod 000 "$CLAUDE_PROJECTS/session1.jsonl"
second="$(bash "$ROOT/providers/get-claude-usage" | grep -E '^(WEEK_TOKENS|WEEK_PROJECTS)=')"
chmod 644 "$CLAUDE_PROJECTS/session1.jsonl"
[ "$second" = "$first" ] || fail "per-file cache did not serve unchanged transcripts"

# --- Mutation invalidates the fingerprint ---
jq -cn --arg ts "$NOW" \
  '{type:"assistant",timestamp:$ts,sessionId:"s2",cwd:"/proj2",message:{model:"claude-opus-4",usage:{input_tokens:2000,output_tokens:1000}}}' \
  > "$CLAUDE_PROJECTS/session2.jsonl"
bash "$ROOT/providers/get-claude-usage" | grep -q '^WEEK_TOKENS=4500$' \
  || fail "added transcript not picked up"

# --- Per-file cache: an appended transcript is the only one re-parsed ---
: > "$JQ_LOG"
bash "$ROOT/providers/get-claude-usage" > /dev/null
[ ! -s "$JQ_LOG" ] || fail "unchanged transcripts re-parsed: $(tr '\n' ' ' < "$JQ_LOG")"
jq -cn --arg ts "$NOW" \
  '{type:"assistant",timestamp:$ts,sessionId:"s2",cwd:"/proj2",message:{model:"claude-opus-4",usage:{input_tokens:100,output_tokens:0}}}' \
  >> "$CLAUDE_PROJECTS/session2.jsonl"
: > "$JQ_LOG"
bash "$ROOT/providers/get-claude-usage" | grep -q '^WEEK_TOKENS=4600$' \
  || fail "appended row not counted"
[ "$(cat "$JQ_LOG")" = "./-home-user-proj/session2.jsonl" ] \
  || fail "expected only session2 re-parsed, got: $(tr '\n' ' ' < "$JQ_LOG")"

# --- A failed parse caches nothing, so the file is retried next refresh ---
printf '%s\n' '{"type":"user"}' >> "$CLAUDE_PROJECTS/session1.jsonl"
JQ_FAIL=1 bash "$ROOT/providers/get-claude-usage" > /dev/null
: > "$JQ_LOG"
bash "$ROOT/providers/get-claude-usage" | grep -q '^WEEK_TOKENS=4600$' || fail "retry after failed parse wrong"
[ "$(cat "$JQ_LOG")" = "./-home-user-proj/session1.jsonl" ] || fail "failed parse was cached instead of retried"

# --- A UTC-offset change rebuilds the date-bucketed rows ---
sed -i '1s/.*/#aioc-claude-transcripts v1 +9999/' "$XDG_CACHE_HOME/AiOverviewControl/claude-transcripts.tsv"
: > "$JQ_LOG"
bash "$ROOT/providers/get-claude-usage" | grep -q '^WEEK_TOKENS=4600$' || fail "rebuild after offset change wrong"
[ "$(wc -l < "$JQ_LOG")" -eq 2 ] || fail "offset change did not re-parse every transcript"

# --- claude --version probed once across runs (24h TTL cache) ---
[ -f "$CLAUDE_VERSION_CALLS" ] || fail "claude --version never probed"
[ "$(wc -l < "$CLAUDE_VERSION_CALLS")" -eq 1 ] || fail "claude --version probed more than once"

# --- AIOC_NO_LITELLM=1 suppresses the third-party pricing fetch ---
: > "$CURL_LOG"
bash "$ROOT/providers/get-claude-usage" > /dev/null
grep -q "raw.githubusercontent.com" "$CURL_LOG" \
  && fail "LiteLLM fetch attempted despite AIOC_NO_LITELLM=1"

echo "ok: claude cache placement, migration, per-file transcript cache, version TTL, LiteLLM opt-out"
