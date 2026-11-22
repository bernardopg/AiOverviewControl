#!/usr/bin/env bash
# Claude transcript dedup: Claude Code writes one JSONL line per content block
# and repeats the full message.usage on every line. Counting each line inflates
# tokens/cost (issue #131). The extractor deduplicates by message.id, first
# occurrence wins; id-less assistant lines pass through defensively.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/claude"
export TZ=UTC AIOC_NO_LITELLM=1
CLAUDE_PROJECTS="$CLAUDE_CONFIG_DIR/projects/-home-user-proj"
mkdir -p "$CLAUDE_PROJECTS" "$HOME" "$TMP/bin"

# Fake curl/claude/gh: offline, no endpoint calls.
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; prev=""; for a in "$@"; do [ "$prev" = -o ] && out="$a"; prev="$a"; done
[ -n "$out" ] && : > "$out"
printf '000'
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/gh"
printf '#!/usr/bin/env bash\nprintf "2.5.1 (fixture)\\n"\n' > "$TMP/bin/claude"
chmod +x "$TMP/bin/curl" "$TMP/bin/gh" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
TRANSCRIPT="$CLAUDE_PROJECTS/session.jsonl"

# Three lines share msg_dup (same usage repeated per content block) = count once.
# msg_other is a different message. One assistant line has no message.id and
# must pass through defensively. A user line is ignored.
jq -cn --arg ts "$NOW" --arg model "claude-sonnet-4-6" '
  def msg($id; $in; $out; $cr; $cw): {
    type:"assistant", timestamp:$ts, sessionId:"s1", cwd:"/proj",
    message:({model:$model, usage:{input_tokens:$in, output_tokens:$out,
      cache_read_input_tokens:$cr, cache_creation_input_tokens:$cw}}
      + (if $id == null then {} else {id:$id} end))
  };
  msg("msg_dup"; 100; 20; 5; 3),
  msg("msg_dup"; 100; 20; 5; 3),
  msg("msg_dup"; 100; 20; 5; 3),
  msg("msg_other"; 10; 2; 1; 0),
  msg(null; 7; 1; 0; 0),
  {type:"user", timestamp:$ts, sessionId:"s1", message:{content:"hi"}}
' > "$TRANSCRIPT"

out="$(bash "$ROOT/providers/get-claude-usage")"
week_tokens="$(printf '%s\n' "$out" | sed -n 's/^WEEK_TOKENS=//p')"
week_messages="$(printf '%s\n' "$out" | sed -n 's/^WEEK_MESSAGES=//p')"

# msg_dup once (128) + msg_other (13) + id-less (8) = 149 tokens, 3 messages.
[ "$week_tokens" = "149" ] || fail "WEEK_TOKENS=$week_tokens, expected 149 (dedup by message.id)"
[ "$week_messages" = "3" ] || fail "WEEK_MESSAGES=$week_messages, expected 3"

# Same message.id in a different file must not be deduped across files.
OTHER="$CLAUDE_PROJECTS/session2.jsonl"
jq -cn --arg ts "$NOW" '{
  type:"assistant", timestamp:$ts, sessionId:"s2", cwd:"/proj",
  message:{id:"msg_dup", model:"claude-sonnet-4-6",
    usage:{input_tokens:50, output_tokens:0, cache_read_input_tokens:0, cache_creation_input_tokens:0}}
}' > "$OTHER"
out2="$(bash "$ROOT/providers/get-claude-usage")"
week_tokens2="$(printf '%s\n' "$out2" | sed -n 's/^WEEK_TOKENS=//p')"
# 149 + 50 = 199
[ "$week_tokens2" = "199" ] || fail "cross-file dedup wrong: WEEK_TOKENS=$week_tokens2, expected 199 (same id in different file counts separately)"

echo "OK: claude transcript dedup by message.id"
