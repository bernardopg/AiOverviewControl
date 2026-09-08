#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_DATA_HOME="$TMP/data"
export CODEX_HOME="$TMP/codex" OPENCODE_DATA_DIR="$TMP/opencode"
export OPENCODE_USAGE_SOURCE=local TZ=UTC
PI_SESSIONS="$HOME/.pi/agent/sessions/project"
mkdir -p "$CODEX_HOME/sessions" "$CODEX_HOME/archived_sessions" "$OPENCODE_DATA_DIR" "$PI_SESSIONS"
fail() { echo "FAIL: $*" >&2; exit 1; }
check() { jq -e "$1" >/dev/null || fail "$2"; }

# Repeated cumulative snapshots do not count twice. Model changes and counter
# resets retain attribution, cached input and reasoning are not added to totals.
jq -cn --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  {type:"session_meta",payload:{cwd:"/project",model_provider:"custom"}},
  {type:"turn_context",payload:{model:"gpt-test"}},
  ([100,100,150][] as $n | {timestamp:$timestamp,type:"event_msg",payload:{type:"token_count",info:{total_token_usage:{total_tokens:$n,input_tokens:($n-10),output_tokens:10,cached_input_tokens:40,reasoning_output_tokens:5}}}}),
  {type:"turn_context",payload:{model:"gpt-other"}},
  {timestamp:$timestamp,type:"event_msg",payload:{type:"token_count",info:{total_token_usage:{total_tokens:20,input_tokens:15,output_tokens:5}}}}
' >"$CODEX_HOME/sessions/test.jsonl"
printf '\nnot-json\n' >>"$CODEX_HOME/sessions/test.jsonl"
result="$(bash "$ROOT/providers/get-local-analytics" codex)"
printf '%s' "$result" | check '.today.tokens == 170 and .today.calls == 3 and .today.sessions == 1 and .today.cost == null and .today.cacheRead == 40 and .today.reasoning == 5 and (.topModels | length) == 2' 'Codex cumulative deduplication and cost unknown'
printf '%s' "$result" | check '.topModels[0].model == "custom/gpt-test" and .topModels[0].tokens == 150 and .topProjects[0].cwd == "/project"' 'Codex model/project attribution'

sqlite3 "$OPENCODE_DATA_DIR/opencode.db" "
CREATE TABLE session(id TEXT PRIMARY KEY, directory TEXT);
CREATE TABLE message(id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT);
INSERT INTO session VALUES('s','/local');
INSERT INTO message VALUES('a','s',unixepoch()*1000, '{\"role\":\"assistant\",\"modelID\":\"free\",\"providerID\":\"other\",\"cost\":0,\"tokens\":{\"input\":10,\"output\":5,\"reasoning\":2,\"cache\":{\"read\":20,\"write\":3}}}');
INSERT INTO message VALUES('b','s',unixepoch()*1000, '{\"role\":\"assistant\",\"modelID\":\"paid\",\"providerID\":\"other\",\"cost\":0.001,\"tokens\":{\"total\":50,\"input\":30,\"output\":20}}');
INSERT INTO message VALUES('user','s',unixepoch()*1000, '{\"role\":\"user\",\"tokens\":{\"total\":9999}}');
"
result="$(bash "$ROOT/providers/get-local-analytics" opencode)"
printf '%s' "$result" | check '.today.tokens == 88 and .today.cost == 0.001 and .today.calls == 2 and .today.cacheRead == 20' 'OpenCode tokens/cost from non-Zen providers'
bash "$ROOT/providers/get-provider-usage" opencode | check '.[0].source == "opencode-local" and .[0].error == null' 'OpenCode without any API credentials'
# A fresh scan is only skipped inside the TTL window; the second assertion
# below depends on re-reading the mutated database.
[ -f "$XDG_CACHE_HOME/AiOverviewControl/local-analytics-opencode-cache.json" ] || fail 'OpenCode analytics cache written'
sqlite3 "$OPENCODE_DATA_DIR/opencode.db" "UPDATE message SET data=json_remove(data,'\$.cost') WHERE id='b';"
bash "$ROOT/providers/get-local-analytics" opencode \
  | check '.today.cost == 0.001' 'OpenCode serves the cached snapshot inside the TTL'
rm -f "$XDG_CACHE_HOME/AiOverviewControl/local-analytics-opencode-cache.json"
bash "$ROOT/providers/get-local-analytics" opencode \
  | check '.today.cost == null and .topModels[1].cost == 0' 'OpenCode unknown distinct from recorded zero'

# Pi SDK may emit zero for unpriced/custom models: do not claim free billing.
jq -cn --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
 {type:"session",cwd:"/project",timestamp:$timestamp},
 {type:"message",message:{role:"assistant",model:"unpriced",usage:{input:10,output:5,cost:{total:0}}}},
 {type:"message",message:{role:"assistant",model:"priced",usage:{input:10,output:5,cost:{total:0.001}}}}
' >"$PI_SESSIONS/test.jsonl"
bash "$ROOT/providers/get-pi-analytics" \
  | check '.today.cost == null and .today.tokens == 30 and (.topModels | any(.model == "unknown/priced" and .cost == 0.001))' \
    'Pi unknown costs do not become zero or partial totals'

# Hermes actual=0 is a schema default, not an actual measured cost.
# shellcheck source=providers/local-cost-common
source "$ROOT/providers/local-cost-common"
sqlite3 "$TMP/hermes.db" "CREATE TABLE session_model_usage(cost_status TEXT, actual_cost_usd REAL, estimated_cost_usd REAL);
INSERT INTO session_model_usage VALUES('estimated',0,1.25),('included',0,5),('unknown',0,999999);"
expression="$(hermes_cost_expression "$TMP/hermes.db")"
sqlite3 -json "$TMP/hermes.db" "SELECT $expression AS cost FROM session_model_usage u;" | check '.[0].cost == 1.25 and .[1].cost == 0 and .[2].cost == null' 'Hermes excludes unknown estimates'
sum="$(hermes_cost_sum "$TMP/hermes.db")"
sqlite3 -json "$TMP/hermes.db" "SELECT $sum AS cost FROM session_model_usage u;" | check '.[0].cost == null' 'Hermes incomplete total'
# A cached snapshot belongs to the source it was taken from; a source that has
# gone away must not be answered from cache.
CODEX_HOME=/nonexistent bash "$ROOT/providers/get-local-analytics" codex \
  | check '.error == "Codex local sessions not found"' 'Codex missing source is not served from cache'
OPENCODE_DATA_DIR=/nonexistent bash "$ROOT/providers/get-local-analytics" opencode \
  | check '.error == "OpenCode local database not found"' 'OpenCode missing source is not served from cache'

echo 'OK: local harness analytics and cost semantics'
