#!/usr/bin/env bash
# Ori (OpenRouter's coding agent CLI) local session telemetry — fixture test.
# Ori records every session in its global workspace as
# ~/.ori/global/.ori/logs/sessions/<id>/metadata.json with the session's
# cumulative usage; the adapter sums them into Today / Week / Month.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
fail() { echo "FAIL: $1" >&2; exit 1; }

FAKE_HOME="$TMP/home"
SESSIONS="$FAKE_HOME/.ori/global/.ori/logs/sessions"
mkdir -p "$SESSIONS" "$TMP/bin" "$TMP/nobin"

iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.123Z; }
session() { # id, epoch, cost (JSON), input, output, model
  local dir="$SESSIONS/$1"
  mkdir -p "$dir"
  cat >"$dir/metadata.json" <<EOF
{
  "completedTurns": 1,
  "endedAt": "$(iso "$2")",
  "harness": "ori",
  "runIds": [{"model": "$6", "runId": "r-$1"}],
  "sessionId": "$1",
  "startedAt": "$(iso "$(( $2 - 60 ))")",
  "usage": {"costUsd": $3, "inputTokens": $4, "outputTokens": $5, "model": "$6"}
}
EOF
  touch -d "@$2" "$dir/metadata.json"
}

now="$(date +%s)"
today_start="$(date -d 'today 00:00' +%s)"
month_start="$(date -d "$(date +%Y-%m-01) 00:00" +%s)"
# Today: two sessions. Three days ago: one. Forty days ago: outside every window.
session s-today-1 "$(( now - 30 ))" 0.25 1000 200 "google/gemini-2.5-flash"
session s-today-2 "$(( now - 20 ))" 0.5 3000 800 "anthropic/claude-sonnet-4.6"
three_days=$(( today_start - 3 * 86400 + 3600 ))
session s-recent "$three_days" 1.0 10000 2000 "openai/gpt-5.4"
session s-old "$(( today_start - 40 * 86400 ))" 9.0 90000 9000 "openai/gpt-5.4"
# A damaged file and a session without a timestamp are skipped, not fatal.
mkdir -p "$SESSIONS/broken" "$SESSIONS/no-time"
printf '{"usage":' >"$SESSIONS/broken/metadata.json"
printf '{"usage":{"costUsd":5,"inputTokens":5,"outputTokens":5}}' >"$SESSIONS/no-time/metadata.json"
printf '{"loginMode":"oauth","region":"global"}' >"$FAKE_HOME/.ori/config.json"

usage() { HOME="$FAKE_HOME" PATH="$1:/usr/bin:/bin" bash "$ROOT/providers/get-provider-usage" ori; }
field() { jq -r ".[0].$1" <<<"$out"; }

out="$(usage "$TMP/nobin")"
[ "$(field provider)" = "ori" ] || fail "provider"
[ "$(field source)" = "ori-local" ] || fail "source"
[ "$(field usage.loginMethod)" = "oauth" ] || fail "login mode from ~/.ori/config.json"
[ "$(field usage.accountEmail)" = "Ori · OpenRouter · anthropic/claude-sonnet-4.6" ] \
  || fail "account names the latest model: $(field usage.accountEmail)"
[ "$(field usage.primary.resetDescription)" = "Today" ] || fail "today label"
[ "$(field usage.primary.displayValue)" = '$0.75 · 5K tok' ] || fail "today $(field usage.primary.displayValue)"
[ "$(field usage.secondary.displayValue)" = '$1.75 · 17K tok' ] || fail "week $(field usage.secondary.displayValue)"
# The month counts the session three days ago only when it fell in this month.
if [ "$three_days" -ge "$month_start" ]; then month='$1.75 · 17K tok'; else month='$0.75 · 5K tok'; fi
[ "$(field usage.tertiary.displayValue)" = "$month" ] || fail "month $(field usage.tertiary.displayValue)"
[ "$(field credits.remaining)" = "agent · 6 sessions" ] || fail "session count $(field credits.remaining)"
[ "$(field usage.primary.usedPercent)" = "0" ] || fail "analytics never fill a bar"
for slot in primary secondary tertiary; do
  [ "$(field "usage.$slot.hasLimit")" = "false" ] || fail "$slot is a plain reading (hasLimit false)"
done

# A session that reported no cost makes the window's cost unknown, not partial.
session s-unpriced "$(( now - 10 ))" null 500 0 "x/unknown"
out="$(usage "$TMP/nobin")"
[ "$(field usage.primary.displayValue)" = '— · 5.5K tok' ] || fail "unknown cost $(field usage.primary.displayValue)"
rm -rf "$SESSIONS/s-unpriced"

# Tiny spend reads "<$0.01".
rm -rf "${SESSIONS:?}"/*
session s-tiny "$(( now - 5 ))" 0.00662316 5632 133 "google/gemini-4-hydrogen"
out="$(usage "$TMP/nobin")"
[ "$(field usage.primary.displayValue)" = '<$0.01 · 5.8K tok' ] || fail "tiny $(field usage.primary.displayValue)"

# No config file: the login method reads "local".
rm -f "$FAKE_HOME/.ori/config.json"
out="$(usage "$TMP/nobin")"
[ "$(field usage.loginMethod)" = "local" ] || fail "missing config login"

# No session directory: a note when the CLI is installed, an error otherwise.
rm -rf "$FAKE_HOME/.ori"
out="$(usage "$TMP/nobin")"
[ "$(field error.kind)" = "provider" ] || fail "missing directory without CLI must be an error"
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/ori"
chmod +x "$TMP/bin/ori"
out="$(usage "$TMP/bin")"
[ "$(field error)" = "null" ] || fail "installed CLI without sessions is not an error"
[ "$(field usage.primary.resetDescription)" = "No Ori sessions recorded yet" ] || fail "empty note"

# Readiness: the session directory or the CLI.
health() { HOME="$FAKE_HOME" PATH="$1:/usr/bin:/bin" bash "$ROOT/providers/get-provider-health" ori; }
[ "$(health "$TMP/nobin" | jq -r '.[0].status')" = "missing" ] || fail "health missing"
[ "$(health "$TMP/bin" | jq -r '.[0].status')" = "ready" ] || fail "health via CLI"
mkdir -p "$SESSIONS"
health "$TMP/nobin" | jq -e '.[0].status == "ready" and .[0].evidence.kind == "local"' >/dev/null \
  || fail "health via session directory"

# The stub entrypoint reaches the same adapter.
session s-stub "$(( now - 5 ))" 0.1 10 10 "m/a"
HOME="$FAKE_HOME" PATH="$TMP/nobin:/usr/bin:/bin" "$ROOT/providers/get-ori-usage" \
  | jq -e '.[0].provider == "ori"' >/dev/null || fail "get-ori-usage stub"

echo "OK: test-ori"
