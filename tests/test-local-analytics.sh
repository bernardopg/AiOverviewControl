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

# OpenCode v2 (2026) replaced session/message with session_v2/session_message
# and nests the model under model.{id,providerID}. The database path is
# unchanged, so both schemas must coexist behind runtime detection. A stale v1
# session duplicated in v2 must be ignored, while a legacy-only session remains
# visible; an errored assistant message carries no tokens and is not a call.
rm -f "$XDG_CACHE_HOME/AiOverviewControl/local-analytics-opencode-cache.json"
export OPENCODE_DATA_DIR="$TMP/opencode-v2"
mkdir -p "$OPENCODE_DATA_DIR"
sqlite3 "$OPENCODE_DATA_DIR/opencode.db" "
CREATE TABLE session_v2(id TEXT PRIMARY KEY, directory TEXT);
CREATE TABLE session_message(id TEXT PRIMARY KEY, session_id TEXT, type TEXT, time_created INTEGER, data TEXT);
CREATE TABLE session(id TEXT PRIMARY KEY, directory TEXT);
CREATE TABLE message(id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT);
INSERT INTO session VALUES('s','/stale'),('legacy','/legacy');
INSERT INTO message VALUES('stale','s',unixepoch()*1000, '{\"role\":\"assistant\",\"providerID\":\"stale\",\"modelID\":\"stale\",\"tokens\":{\"total\":9999}}');
INSERT INTO message VALUES('legacy','legacy',unixepoch()*1000, '{\"role\":\"assistant\",\"providerID\":\"other\",\"modelID\":\"legacy\",\"cost\":0,\"tokens\":{\"total\":7}}');
INSERT INTO session_v2 VALUES('s','/local');
INSERT INTO session_message VALUES('a','s','assistant',unixepoch()*1000, '{\"model\":{\"id\":\"free\",\"providerID\":\"other\"},\"cost\":0,\"tokens\":{\"input\":10,\"output\":5,\"reasoning\":2,\"cache\":{\"read\":20,\"write\":3}}}');
INSERT INTO session_message VALUES('b','s','assistant',unixepoch()*1000, '{\"model\":{\"id\":\"paid\",\"providerID\":\"other\"},\"cost\":0.001,\"tokens\":{\"total\":50,\"input\":30,\"output\":20}}');
INSERT INTO session_message VALUES('user','s','user',unixepoch()*1000, '{\"tokens\":{\"total\":9999}}');
INSERT INTO session_message VALUES('err','s','assistant',unixepoch()*1000, '{\"model\":{\"id\":\"free\",\"providerID\":\"other\"},\"error\":\"boom\"}');
"
result="$(bash "$ROOT/providers/get-local-analytics" opencode)"
printf '%s' "$result" | check '.today.tokens == 95 and .today.cost == 0.001 and .today.calls == 3 and .today.sessions == 2 and .today.cacheRead == 20' 'OpenCode v2 tokens/cost, legacy retention and duplicate suppression'
printf '%s' "$result" | check '.topModels[0].model == "other/paid" and .topProjects[0].cwd == "/local" and any(.topProjects[]; .cwd == "/legacy") and all(.topModels[]; .model != "stale/stale")' 'OpenCode v2 model/project attribution and generation precedence'
bash "$ROOT/providers/get-provider-usage" opencode | check '.[0].source == "opencode-local" and .[0].error == null' 'OpenCode v2 card without any API credentials'
# The same unknown-vs-recorded-zero rule holds on the v2 schema.
rm -f "$XDG_CACHE_HOME/AiOverviewControl/local-analytics-opencode-cache.json"
sqlite3 "$OPENCODE_DATA_DIR/opencode.db" "UPDATE session_message SET data=json_remove(data,'\$.cost') WHERE id='b';"
bash "$ROOT/providers/get-local-analytics" opencode \
  | check '.today.cost == null and .topModels[1].cost == 0' 'OpenCode v2 unknown distinct from recorded zero'

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

# Unpriced Hermes rows get LiteLLM list prices; known and included costs stay.
# Offline: a same-day price snapshot is served, the download never runs.
export HERMES_HOME="$TMP/hermes-home" AIOC_NO_LITELLM=1
mkdir -p "$HERMES_HOME" "$XDG_CACHE_HOME/AiOverviewControl"
jq -n --arg today "$(date +%Y-%m-%d)" '{updated: $today, models: {
  "claude-opus-4-7": [0.000005, 0.000025, 0.0000005, 0.00000625],
  "glm-4.6": [0.0000006, 0.0000022, 0.0000006, 0.0000006]}}' \
  >"$XDG_CACHE_HOME/AiOverviewControl/litellm-prices.json"
now="$(date +%s)"
sqlite3 "$HERMES_HOME/state.db" "CREATE TABLE sessions(id TEXT, source TEXT, started_at REAL, cwd TEXT, git_repo_root TEXT);
CREATE TABLE messages(id TEXT);
CREATE TABLE session_model_usage(session_id TEXT, model TEXT, api_call_count INT, input_tokens INT, output_tokens INT,
  cache_read_tokens INT, cache_write_tokens INT, estimated_cost_usd REAL, actual_cost_usd REAL, cost_status TEXT);
INSERT INTO sessions VALUES('s1','cli',$now,'/p',NULL);
INSERT INTO session_model_usage VALUES
  ('s1','cc/claude-opus-4.7',1,1000000,100000,2000000,0,0,0,'unknown'),
  ('s1','glm-4.6',1,500,500,0,0,0.5,0,'estimated'),
  ('s1','glm-4.6',1,1000000,0,0,0,0,0,'unknown'),
  ('s1','nvidia/nemotron-x:free',1,999,1,0,0,0,0,'unknown'),
  ('s1','claude-opus-4-7',1,7,7,0,0,0,0,'included');"
# opus: 1M*5e-6 + 100k*25e-6 + 2M*0.5e-6 = 5 + 2.5 + 1 = 8.5
# glm-4.6: known 0.5 + 1M*0.6e-6 = 1.1; ":free" route = 0; included = 0
bash "$ROOT/providers/get-hermes-analytics" | check '
  (.today.cost * 1000 | round) == 9600 and .today.tokens == 4102014
  and (.topModels | map({(.model): (.cost * 1000 | round)}) | add)
      == {"cc/claude-opus-4.7": 8500, "glm-4.6": 1100, "nvidia/nemotron-x:free": 0, "claude-opus-4-7": 0}' \
  'Hermes prices unknown rows from LiteLLM and keeps known and included costs'
# shellcheck disable=SC2016 # "$9.6" is literal output, not an expansion
bash "$ROOT/providers/get-provider-usage" hermes '' \
  | check '.[0].usage.primary.displayValue | startswith("$9.6 · 4.1M tok")' 'Hermes card total uses the same pricing'
# A model with no price keeps the total honest: unknown, not partial.
rm -f "$XDG_CACHE_HOME/AiOverviewControl/hermes-analytics-v2-cache.json"
sqlite3 "$HERMES_HOME/state.db" "INSERT INTO session_model_usage VALUES('s1','gemma4:31b',1,10,10,0,0,0,0,'unknown');"
bash "$ROOT/providers/get-hermes-analytics" \
  | check '.today.cost == null and (.topModels | any(.model == "glm-4.6" and (.cost * 1000 | round) == 1100))' \
    'Hermes unpriced model makes the total unknown'
# Without any snapshot (opted out, never downloaded) unknown rows stay unknown.
rm -f "$XDG_CACHE_HOME/AiOverviewControl/hermes-analytics-v2-cache.json" "$XDG_CACHE_HOME/AiOverviewControl/litellm-prices.json"
bash "$ROOT/providers/get-hermes-analytics" | check '.today.cost == null' 'Hermes without prices stays unknown'
unset HERMES_HOME AIOC_NO_LITELLM
# A cached snapshot belongs to the source it was taken from; a source that has
# gone away must not be answered from cache.
CODEX_HOME=/nonexistent bash "$ROOT/providers/get-local-analytics" codex \
  | check '.error == "Codex local sessions not found"' 'Codex missing source is not served from cache'
OPENCODE_DATA_DIR=/nonexistent bash "$ROOT/providers/get-local-analytics" opencode \
  | check '.error == "OpenCode local database not found"' 'OpenCode missing source is not served from cache'

echo 'OK: local harness analytics and cost semantics'
