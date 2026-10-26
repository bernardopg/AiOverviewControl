#!/usr/bin/env bash
# pi coding-agent local telemetry: session aggregation, unknown-cost handling,
# TTL cache, and the dispatcher card built only from that cache.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache"
SESSIONS="$HOME/.pi/agent/sessions"
CACHE="$XDG_CACHE_HOME/AiOverviewControl/pi-analytics-v2-cache.json"
mkdir -p "$HOME"
fail() { echo "FAIL: $*" >&2; exit 1; }
analytics() { bash "$ROOT/providers/get-pi-analytics"; }
card() { bash "$ROOT/providers/get-provider-usage" pi; }

# No sessions directory: the analytics helper and the card both say so.
jq -e '.error == "pi sessions directory not found"' <<<"$(analytics)" >/dev/null \
  || fail "missing sessions directory not reported"
jq -e '.[0].provider == "pi" and .[0].error.code == 2' <<<"$(card)" >/dev/null \
  || fail "card did not report the missing sessions directory"

# Sessions exist but nothing is cached yet: the card is an informational note.
mkdir -p "$SESSIONS/proj"
jq -e '.[0].provider == "pi" and .[0].error == null and .[0].usage.primary.usedPercent == 0' <<<"$(card)" >/dev/null \
  || fail "uncached card is not an informational note"

today_utc="$(date -u +%Y-%m-%dT%H-%M-%S-000Z)"
# Session named with a start timestamp: message-level provider/model, numeric
# and object costs, a model_change fallback, and a malformed line to skip.
{
  jq -nc '{type:"session", cwd:"/work/alpha"}'
  jq -nc '{type:"message", message:{provider:"anthropic", model:"opus", usage:{input:1000, output:500, cost:{total:0.25}}}}'
  echo 'not json'
  jq -nc '{type:"model_change", provider:"openai", modelId:"gpt"}'
  jq -nc '{type:"message", message:{usage:{totalTokens:2000, cost:0.5}}}'
} > "$SESSIONS/proj/${today_utc}_alpha.jsonl"
# Session without a timestamped name (dated by mtime) whose cost is unknown.
{
  jq -nc '{type:"session", cwd:"/work/beta"}'
  jq -nc '{type:"message", message:{provider:"local", model:"llama", usage:{input:300, output:0}}}'
} > "$SESSIONS/proj/unnamed.jsonl"

out="$(analytics)"
jq -e '
  (.days | length) == 7
  and .today.tokens == 3800 and .today.cost == null
  and .week.tokens == 3800 and .month.tokens == 3800
  and (.topModels | map(.model)) == ["openai/gpt", "anthropic/opus", "local/llama"]
  and (.topModels[] | select(.model == "anthropic/opus") | .cost) == 0.25
  and (.topModels[] | select(.model == "local/llama") | .cost) == null
  and .topProjects[0] == {cwd: "/work/alpha", tokens: 3500}
' <<<"$out" >/dev/null || fail "aggregation wrong: $out"
[ -f "$CACHE" ] || fail "analytics cache not written"

# A fresh cache is served without rescanning; a stale one is rebuilt.
rm "$SESSIONS/proj/unnamed.jsonl"
jq -e '.today.tokens == 3800' <<<"$(analytics)" >/dev/null || fail "fresh cache not served"
jq '.cached_at -= 3600' "$CACHE" > "$TMP/stale.json" && mv "$TMP/stale.json" "$CACHE"
jq -e '.today.tokens == 3500 and .today.cost == 0.75' <<<"$(analytics)" >/dev/null || fail "stale cache not rebuilt"

# The card reads only that cache and formats money and compact token counts.
out="$(card)"
jq -e '.[0].source == "pi-local" and .[0].usage.primary.displayValue == "$0.75 · 3.5K tok"
  and .[0].usage.secondary.resetDescription == "Week"' <<<"$out" >/dev/null || fail "card from cache wrong: $out"

# A cache whose data is not an object falls back to the informational note.
echo '{"cached_at":0,"data":[]}' > "$CACHE"
jq -e '.[0].error == null and .[0].usage.primary.usedPercent == 0' <<<"$(card)" >/dev/null \
  || fail "invalid cache not handled"

echo "OK: pi analytics aggregation, cache and card"
