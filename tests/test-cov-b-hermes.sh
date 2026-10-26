#!/usr/bin/env bash
# Hermes cost/status coverage with a real temporary SQLite ledger when available.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" HERMES_HOME="$TMP/home/.hermes" XDG_CACHE_HOME="$TMP/cache" AIOC_NO_LITELLM=1
mkdir -p "$HERMES_HOME" "$XDG_CACHE_HOME/AiOverviewControl"
fail() { echo "FAIL: $*" >&2; exit 1; }
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo 'SKIP: Hermes SQLite fixture coverage requires sqlite3; missing-database checks remain covered elsewhere.'
  out="$(bash "$ROOT/providers/get-hermes-analytics")"
  jq -e '.error|contains("state database not found")' <<<"$out" >/dev/null || fail "missing database response"
  echo 'OK: Hermes missing-database coverage'
  exit 0
fi

NOW="$(date +%s)"
sqlite3 "$HERMES_HOME/state.db" <<SQL
CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT NOT NULL, started_at REAL NOT NULL, cwd TEXT, git_repo_root TEXT);
CREATE TABLE session_model_usage (
 session_id TEXT NOT NULL, model TEXT NOT NULL, input_tokens INTEGER NOT NULL,
 output_tokens INTEGER NOT NULL, cache_read_tokens INTEGER NOT NULL, cache_write_tokens INTEGER NOT NULL,
 estimated_cost_usd REAL NOT NULL, actual_cost_usd REAL NOT NULL, api_call_count INTEGER NOT NULL,
 cost_status TEXT NOT NULL
);
CREATE TABLE messages (id TEXT);
INSERT INTO sessions VALUES ('known','cli',$NOW,'/work/known',NULL);
INSERT INTO sessions VALUES ('free','telegram',$NOW,NULL,'/work/free');
INSERT INTO sessions VALUES ('unknown','cli',$NOW,'/work/unknown',NULL);
INSERT INTO session_model_usage VALUES ('known','priced-model',1000,500,100,50,0.2,0.3,2,'estimated');
INSERT INTO session_model_usage VALUES ('free','free-model:free',300,100,0,0,0,0,1,'included');
INSERT INTO session_model_usage VALUES ('unknown','not-listed',10,5,0,0,0,0,1,'unknown');
INSERT INTO messages VALUES ('m1');
SQL
jq -n --arg today "$(date +%F)" '{updated:$today,models:{"priced-model":[0.00001,0.00002,0.00003,0.00004]}}' > "$XDG_CACHE_HOME/AiOverviewControl/litellm-prices.json"
cat > "$HERMES_HOME/config.yaml" <<'YAML'
model:
  default: priced-model
  provider: test-provider
YAML
printf '{"active_provider":"local-router"}\n' > "$HERMES_HOME/auth.json"

# Analytics retains unknown cost as null, while pricing unknown rows when a matching price exists.
analytics="$(bash "$ROOT/providers/get-hermes-analytics")"
jq -e '.days|length==7' <<<"$analytics" >/dev/null || fail "trailing week buckets"
jq -e '.today.tokens==2065 and .today.cost==null and .week.tokens==2065 and .week.cost==null and .meta.sessions==3 and .meta.messages==1 and .topProjects[0].cwd=="/work/known" and .meta.defaultModel=="priced-model" and .meta.activeProvider=="local-router"' <<<"$analytics" >/dev/null || fail "analytics cost/status and metadata"

# The native card aggregates included rows as free, uses estimated known cost, and keeps the total unknown.
out="$(bash "$ROOT/providers/get-provider-usage" hermes '' 2>/dev/null)"
jq -e '.[0].provider=="hermes" and .[0].usage.accountEmail=="local-router · priced-model" and .[0].usage.loginMethod=="test-provider" and (.[0].usage.primary.displayValue|contains("—")) and (.[0].usage.secondary.displayValue|contains("2.1K tok")) and .[0].credits.remaining=="agent · 3 sessions"' <<<"$out" >/dev/null || fail "native Hermes normalization"

# Snapshot round-trip bypasses the SQLite work and remains JSON-identical.
cache="$XDG_CACHE_HOME/AiOverviewControl/hermes-analytics-v2-cache.json"
[ -s "$cache" ] || fail "analytics cache not written"
first="$(jq -r '.cached_at' "$cache")"
cached="$(bash "$ROOT/providers/get-hermes-analytics")"
[ "$cached" = "$analytics" ] || fail "cache round-trip changed analytics JSON"
[ "$(jq -r '.cached_at' "$cache")" = "$first" ] || fail "fresh analytics cache was rewritten"

# Drop the cache and point at an invalid schema to cover the honest query failure.
rm -f "$cache"
mv "$HERMES_HOME/state.db" "$TMP/state.db"
: > "$HERMES_HOME/state.db"
out="$(bash "$ROOT/providers/get-hermes-analytics")"
jq -e '.error|contains("could not be read")' <<<"$out" >/dev/null || fail "unsupported schema response"

echo 'OK: Hermes SQLite analytics, status pricing, and native coverage'
