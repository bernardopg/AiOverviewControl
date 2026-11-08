#!/usr/bin/env bash
# Claude's daily LiteLLM pricing refresh: a usable table is cached atomically,
# a table without Claude prices is ignored, and a cache path that cannot be
# replaced leaves no temporary file behind. Offline: curl is a fixture.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/claude" TZ=UTC
export PRICING_TABLE="$TMP/table.json"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR" "$TMP/bin"
echo '{}' > "$CLAUDE_CONFIG_DIR/.credentials.json"
unset AIOC_NO_LITELLM || true

# The LiteLLM table comes from $PRICING_TABLE; every other request fails.
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *BerriAI/litellm*) cat "$PRICING_TABLE" ;;
  *) out=""; prev=""; for a in "$@"; do [ "$prev" != -o ] || out="$a"; prev="$a"; done
     [ -z "$out" ] || : > "$out"; printf '000' ;;
esac
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/gh"
printf '#!/usr/bin/env bash\nprintf "2.5.1 (fixture)\\n"\n' > "$TMP/bin/claude"
chmod +x "$TMP/bin/curl" "$TMP/bin/gh" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
CACHE="$XDG_CACHE_HOME/AiOverviewControl/claude-pricing-cache.json"
run() { bash "$ROOT/providers/get-claude-usage" >/dev/null; }

# 1. A table with Claude prices is cached: the newest version per family, in
#    the schema the cost code reads.
cat > "$PRICING_TABLE" <<'JSON'
{"claude-opus-4-1":{"input_cost_per_token":0.000015,"output_cost_per_token":0.000075,"cache_read_input_token_cost":0.0000015,"cache_creation_input_token_cost":0.00001875},
 "claude-opus-4":{"input_cost_per_token":0.00002,"output_cost_per_token":0.0001},
 "claude-fable-5":{"input_cost_per_token":0.000003,"output_cost_per_token":0.000015},
 "bedrock/claude-opus-4-1":{"input_cost_per_token":1},
 "gpt-5":{"input_cost_per_token":0.00001}}
JSON
run
[ -f "$CACHE" ] || fail "a usable table was not cached"
jq -e --arg today "$(date +%F)" '
  .schema == 2 and .updated == $today
  and (.models | keys) == ["fable", "opus"]
  and .models.opus.input == 0.000015 and .models.opus.cache_write == 0.00001875
' "$CACHE" >/dev/null || fail "cached pricing: $(cat "$CACHE")"
[ -z "$(find "$(dirname "$CACHE")" -maxdepth 1 -name 'claude-pricing-cache.json.*')" ] || fail "temporary file left behind"

# 2. A table without Claude prices never replaces the cache.
rm -f "$CACHE"
printf '%s\n' '{"gpt-5":{"input_cost_per_token":0.00001},"claude-opus-4-1":{"input_cost_per_token":0}}' > "$PRICING_TABLE"
run
[ ! -e "$CACHE" ] || fail "a table without Claude prices was cached"

# 3. A cache path that cannot be replaced (here a directory) fails the write
#    instead of moving the new table inside it, and cleans up its temp file.
mkdir -p "$CACHE"
cat > "$PRICING_TABLE" <<'JSON'
{"claude-opus-4-1":{"input_cost_per_token":0.000015,"output_cost_per_token":0.000075}}
JSON
run
[ -d "$CACHE" ] && [ -z "$(ls -A "$CACHE")" ] || fail "the table was written inside the directory"
[ -z "$(find "$(dirname "$CACHE")" -maxdepth 1 -name 'claude-pricing-cache.json.*')" ] || fail "temporary file left behind after a failed write"

echo 'OK: Claude LiteLLM pricing cache: usable table, no Claude prices, failed atomic write'
