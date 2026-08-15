#!/usr/bin/env bash
# Hermes local telemetry — fixture-database unit test.
# Builds a minimal ~/.hermes/state.db (sessions + session_model_usage) plus
# config.yaml / auth.json under a fake HERMES_HOME, then verifies:
#   1. the dispatcher envelope (fetch_hermes_native): identity, Today/Week
#      displayValues, credits session count;
#   2. providers/get-hermes-analytics analytics: 7-day buckets, week/month totals,
#      top models, top projects, sources, meta identity;
#   3. the TTL cache round-trip (second call serves the cached snapshot);
#   4. a missing state database surfaces a provider error, not a crash.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_FIX="$TMP/home"
CACHE="$TMP/cache"
mkdir -p "$HOME_FIX" "$CACHE"

NOW=$(date +%s)
YESTERDAY=$((NOW - 86400))
LAST_MONTH=$((NOW - 40 * 86400))

# --- fixture state database: minimal schema the adapter queries ---
sqlite3 "$HOME_FIX/state.db" <<SQL
CREATE TABLE sessions (
  id TEXT PRIMARY KEY, source TEXT NOT NULL, user_id TEXT, model TEXT,
  started_at REAL NOT NULL, ended_at REAL, cwd TEXT, git_repo_root TEXT
);
CREATE TABLE session_model_usage (
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  model TEXT NOT NULL, billing_provider TEXT NOT NULL DEFAULT '',
  api_call_count INTEGER NOT NULL DEFAULT 0,
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  cache_read_tokens INTEGER NOT NULL DEFAULT 0,
  cache_write_tokens INTEGER NOT NULL DEFAULT 0,
  estimated_cost_usd REAL NOT NULL DEFAULT 0,
  actual_cost_usd REAL NOT NULL DEFAULT 0,
  first_seen REAL, last_seen REAL,
  PRIMARY KEY (session_id, model)
);
CREATE TABLE messages (id TEXT);
INSERT INTO sessions VALUES ('s-today-cli',  'cli',      NULL, 'z-ai/glm-5.2', $NOW,        NULL, '/home/user/project-a', NULL);
INSERT INTO sessions VALUES ('s-yest-tg',    'telegram', NULL, 'gpt-5.4',      $YESTERDAY,  NULL, NULL, NULL);
INSERT INTO sessions VALUES ('s-old-tui',    'tui',      NULL, 'claude-opus-4-8', $LAST_MONTH, NULL, NULL, NULL);
INSERT INTO session_model_usage VALUES ('s-today-cli', 'z-ai/glm-5.2', 'openrouter', 3, 1000, 500, 0, 0, 1.5, 0, $NOW, $NOW);
INSERT INTO session_model_usage VALUES ('s-yest-tg',   'gpt-5.4',      'openrouter', 2, 2000, 0,   0, 0, 0.25, 0, $YESTERDAY, $YESTERDAY);
INSERT INTO session_model_usage VALUES ('s-old-tui',   'claude-opus-4-8', 'anthropic', 9, 9000, 1000, 0, 0, 4.0, 0, $LAST_MONTH, $LAST_MONTH);
SQL

cat > "$HOME_FIX/config.yaml" <<YAML
model:
  default: z-ai/glm-5.2
  provider: openrouter
YAML
echo '{"active_provider": "openrouter"}' > "$HOME_FIX/auth.json"

run_env() {
  env HERMES_HOME="$HOME_FIX" XDG_CACHE_HOME="$CACHE" \
    HOME="$TMP" PATH="$PATH" "$@"
}
fail() { echo "FAIL: $1" >&2; exit 1; }

# --- 1. dispatcher envelope ---
out="$(run_env bash "$ROOT/providers/get-provider-usage" hermes '' 2>/dev/null)"
[ "$(jq -r '.[0].provider' <<<"$out")" = "hermes" ] || fail "envelope provider id"
[ "$(jq -r '.[0].source' <<<"$out")" = "hermes-local" ] || fail "envelope source"
[ "$(jq -r '.[0].usage.loginMethod' <<<"$out")" = "openrouter" ] || fail "envelope loginMethod from config provider"
jq -e '.[0].usage.accountEmail | test("openrouter") and test("glm-5.2")' <<<"$out" >/dev/null \
  || fail "envelope account shows provider + default model"
jq -e '.[0].usage.primary.displayValue | test("1.5K tok") and test("1.5")' <<<"$out" >/dev/null \
  || fail "envelope today tokens+cost"
jq -e '.[0].usage.secondary.displayValue | test("3.5K tok")' <<<"$out" >/dev/null \
  || fail "envelope week tokens (today + yesterday)"
[ "$(jq -r '.[0].credits.remaining' <<<"$out")" = "agent · 3 sessions" ] || fail "envelope credits session count"

# --- 2. analytics ---
out="$(run_env bash "$ROOT/providers/get-hermes-analytics")"
[ "$(jq '.days | length' <<<"$out")" = "7" ] || fail "seven day buckets"
[ "$(jq -r '.days[6].tokens' <<<"$out")" = "1500" ] || fail "today bucket tokens"
[ "$(jq -r '.days[5].tokens' <<<"$out")" = "2000" ] || fail "yesterday bucket tokens"
[ "$(jq -r '.today.tokens' <<<"$out")" = "1500" ] || fail "today total"
[ "$(jq -r '.week.tokens' <<<"$out")" = "3500" ] || fail "week total (today + yesterday)"
[ "$(jq -r '.month.tokens' <<<"$out")" = "3500" ] || fail "month total excludes last-month session"
[ "$(jq -r '.topModels[0].model' <<<"$out")" = "gpt-5.4" ] || fail "top model by tokens"
[ "$(jq -r '.topProjects[0].cwd' <<<"$out")" = "/home/user/project-a" ] || fail "top project cwd"
jq -e 'any(.meta.sources[]; .source == "cli" and .sessions == 1)' <<<"$out" >/dev/null || fail "sources breakdown"
[ "$(jq -r '.meta.defaultModel' <<<"$out")" = "z-ai/glm-5.2" ] || fail "meta default model"
[ "$(jq -r '.meta.activeProvider' <<<"$out")" = "openrouter" ] || fail "meta active provider"
[ "$(jq -r '.meta.sessions' <<<"$out")" = "3" ] || fail "meta session count"

# --- 3. cache round-trip: the snapshot written for call #2 serves call #3 ---
[ -f "$CACHE/AiOverviewControl/hermes-analytics-cache.json" ] || fail "cache file written"
first_ts="$(jq -r '.cached_at' "$CACHE/AiOverviewControl/hermes-analytics-cache.json")"
out2="$(run_env bash "$ROOT/providers/get-hermes-analytics")"
[ "$out2" = "$out" ] || fail "cached output identical"
[ "$(jq -r '.cached_at' "$CACHE/AiOverviewControl/hermes-analytics-cache.json")" = "$first_ts" ] \
  || fail "TTL cache reused (cached_at unchanged)"

# --- 4. missing database -> provider error, clean exit ---
rm -f "$HOME_FIX/state.db"
out="$(run_env bash "$ROOT/providers/get-provider-usage" hermes '' 2>/dev/null)"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "missing db error kind"
jq -e '.[0].error.message | test("state database not found")' <<<"$out" >/dev/null || fail "missing db message"

# --- 5. health check reports the same prerequisite ---
out="$(run_env bash "$ROOT/providers/get-provider-health" hermes 2>/dev/null)"
[ "$(jq -r '.[0].provider' <<<"$out")" = "hermes" ] || fail "health provider id"
jq -e '.[0].status | . == "missing" or . == "ready"' <<<"$out" >/dev/null || fail "health status vocabulary"

# --- 6. empty ledger: zeroed envelope instead of null/NaN output ---
EMPTY="$TMP/empty"
mkdir -p "$EMPTY"
sqlite3 "$EMPTY/state.db" <<'SQL'
CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT NOT NULL, started_at REAL NOT NULL, cwd TEXT, git_repo_root TEXT);
CREATE TABLE session_model_usage (
  session_id TEXT NOT NULL, model TEXT NOT NULL,
  input_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,
  cache_read_tokens INTEGER NOT NULL DEFAULT 0, cache_write_tokens INTEGER NOT NULL DEFAULT 0,
  estimated_cost_usd REAL NOT NULL DEFAULT 0, actual_cost_usd REAL NOT NULL DEFAULT 0,
  api_call_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE messages (id TEXT);
SQL
out="$(env HERMES_HOME="$EMPTY" XDG_CACHE_HOME="$TMP/cache-empty" HOME="$TMP" \
  bash "$ROOT/providers/get-provider-usage" hermes '' 2>/dev/null)"
[ "$(jq -r '.[0].usage.primary.displayValue' <<<"$out")" = "\$0 · 0 tok" ] || fail "empty ledger envelope"
# No config.yaml/auth.json in this fixture: the account label must still resolve.
[ "$(jq -r '.[0].usage.accountEmail' <<<"$out")" = "hermes agent" ] || fail "account fallback without config"
[ "$(jq -r '.[0].usage.loginMethod' <<<"$out")" = "local" ] || fail "login fallback without config"

out="$(env HERMES_HOME="$EMPTY" XDG_CACHE_HOME="$TMP/cache-empty" HOME="$TMP" \
  bash "$ROOT/providers/get-hermes-analytics" 2>/dev/null)"
[ "$(jq '.days | length' <<<"$out")" = "7" ] || fail "empty ledger still emits 7 buckets"
[ "$(jq -r '.week.tokens' <<<"$out")" = "0" ] || fail "empty ledger week total"
[ "$(jq -r '.meta.sessions' <<<"$out")" = "0" ] || fail "empty ledger session count"

# --- 7. missing sqlite3 degrades to a runtime error, never a crash ---
# PATH is rebuilt from a symlink farm that deliberately omits sqlite3 while
# keeping the coreutils the dispatcher itself needs (xargs shells out to echo).
STUB="$TMP/nosqlite"
mkdir -p "$STUB"
for cmd in bash sh echo dirname basename tr xargs mktemp jq date awk wc head tail \
           cat rm find sort sed grep printf timeout cut uniq stat sleep mkdir \
           chmod ln touch env flock curl; do
  # type -P resolves the on-disk executable only — command -v would return the
  # shell builtin name for echo/printf and link the stub to itself.
  target="$(type -P "$cmd" 2>/dev/null)" && [ -n "$target" ] \
    && ln -sf "$target" "$STUB/$cmd" 2>/dev/null || true
done
command -v sqlite3 >/dev/null 2>&1 && [ -e "$STUB/sqlite3" ] && fail "stub PATH must not expose sqlite3"

out="$(env HERMES_HOME="$EMPTY" XDG_CACHE_HOME="$TMP/cache-nosql" HOME="$TMP" PATH="$STUB" \
  bash "$ROOT/providers/get-provider-usage" hermes '' 2>/dev/null)"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "runtime" ] || fail "missing sqlite3 error kind"
jq -e '.[0].error.message | test("sqlite3")' <<<"$out" >/dev/null || fail "missing sqlite3 message"

out="$(env HERMES_HOME="$EMPTY" XDG_CACHE_HOME="$TMP/cache-nosql2" HOME="$TMP" PATH="$STUB" \
  bash "$ROOT/providers/get-hermes-analytics" 2>/dev/null)"
jq -e '.error | test("sqlite3")' <<<"$out" >/dev/null || fail "analytics reports missing sqlite3"

# --- 8. unreadable database -> provider error, never a healthy-looking zero card ---
CORRUPT="$TMP/corrupt"
mkdir -p "$CORRUPT"
head -c 2048 /dev/urandom > "$CORRUPT/state.db"
out="$(env HERMES_HOME="$CORRUPT" XDG_CACHE_HOME="$TMP/cache-corrupt" HOME="$TMP" \
  bash "$ROOT/providers/get-provider-usage" hermes '' 2>/dev/null)"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "corrupt db must be a provider error"
jq -e '.[0].usage == null' <<<"$out" >/dev/null || fail "corrupt db must not emit usage numbers"
out="$(env HERMES_HOME="$CORRUPT" XDG_CACHE_HOME="$TMP/cache-corrupt" HOME="$TMP" \
  bash "$ROOT/providers/get-hermes-analytics" 2>/dev/null)"
jq -e '.error | test("could not be read")' <<<"$out" >/dev/null || fail "analytics reports unreadable database"

echo "OK: test-hermes-analytics"
