#!/usr/bin/env bash
# Claude Code status line bridge (providers/claude-statusline-bridge) and how
# get-claude-usage uses its readings:
#  - the bridge keeps only the two rate-limit windows, owner-only, in the
#    account cache of its CLAUDE_CONFIG_DIR, and hands the same stdin to the
#    chained status line command, whose output and exit status pass through
#  - input without rate limits, malformed input or a missing jq never breaks
#    the status line
#  - a reading only moves on real progress: more of the same window used, or
#    a later window; an idle session repeating older numbers changes nothing
#  - a fresh reading newer than the endpoint snapshot supplies the session and
#    weekly numbers (source claude-statusline), stretches the endpoint cache
#    so it is not asked again, and stands in for a failed endpoint without a
#    snapshot; it never hides rejected credentials
#  - a stale reading is ignored; a limit reset drops the reading
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/claude"
export AIOC_NO_LITELLM=1 TZ=UTC CURL_LOG="$TMP/curl.log"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/projects/-repo" "$TMP/bin"
: >"$CURL_LOG"
ACCOUNT="$XDG_CACHE_HOME/AiOverviewControl/claude-profiles/$(printf '%s' "$(realpath -m -- "$CLAUDE_CONFIG_DIR")" | sha256sum | cut -d ' ' -f 1)"
READING="$ACCOUNT/claude-statusline.json"
BRIDGE="$ROOT/providers/claude-statusline-bridge"

cat >"$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '2.5.1 (fixture)\n'
SH
# Usage endpoint: CLAUDE_HTTP picks the answer; every request is logged.
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; headers=""; prev=""
for arg in "$@"; do [ "$prev" != -o ] || out="$arg"; [ "$prev" != -D ] || headers="$arg"; prev="$arg"; done
case "$*" in *oauth/usage*) printf 'usage %s\n' "${CLAUDE_HTTP:-200}" >>"$CURL_LOG" ;; *) printf 'other\n' >>"$CURL_LOG" ;; esac
[ -z "$headers" ] || printf 'HTTP/2 %s\r\n' "${CLAUDE_HTTP:-200}" >"$headers"
if [ "${CLAUDE_HTTP:-200}" = 200 ]; then
  printf '%s' '{"limits":[{"kind":"session","percent":10,"resets_at":"2099-01-01T05:00:00Z"},{"kind":"weekly_all","percent":20,"resets_at":"2099-01-07T00:00:00Z"}]}' >"$out"
else
  printf '{}' >"$out"
fi
printf '%s' "${CLAUDE_HTTP:-200}"
SH
chmod +x "$TMP/bin/claude" "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
jq -n '{claudeAiOauth: {accessToken: "fixture-token", expiresAt: 4102444800000, subscriptionType: "max"}}' \
  >"$CLAUDE_CONFIG_DIR/.credentials.json"

NOW="$(date +%s)"
FIVE_RESET=$(( NOW + 3600 ))
WEEK_RESET=$(( NOW + 86400 ))
# input <five%> <week%> [five reset] [week reset]: a status line payload.
input() {
  jq -cn --argjson f "$1" --argjson w "$2" --argjson fr "${3:-$FIVE_RESET}" --argjson wr "${4:-$WEEK_RESET}" '
    {session_id: "s1", cwd: "/secret/project", transcript_path: "/secret/t.jsonl",
     model: {id: "claude-opus-5-5"},
     rate_limits: {five_hour: {used_percentage: $f, resets_at: $fr},
                   seven_day: {used_percentage: $w, resets_at: $wr}}}'
}
field() { jq -r "$1" "$READING"; }

# --- Bridge ----------------------------------------------------------------
out="$(input 23.5 41 | bash "$BRIDGE" cat)"
[ "$(jq -r '.session_id' <<<"$out")" = s1 ] || fail "chained command did not receive the status line input: $out"
[ "$(field '.five_hour.usedPercent')" = 23.5 ] && [ "$(field '.seven_day.resetsAt')" = "$WEEK_RESET" ] \
  || fail "reading not recorded: $(cat "$READING")"
[ "$(stat -c %a "$READING")" = 600 ] || fail "reading is not owner-only"
if grep -q secret "$READING"; then fail "the reading kept more than the rate limits"; fi
[ -z "$(find "$CLAUDE_CONFIG_DIR" -newer "$CLAUDE_CONFIG_DIR/.credentials.json" -type f)" ] \
  || fail "the bridge wrote into the Claude config directory"

# The chained command's output and exit status pass through; no command
# prints nothing.
set +e
input 23.5 41 | bash "$BRIDGE" sh -c 'cat >/dev/null; echo line; exit 3' >"$TMP/chain.out"
status=$?
set -e
[ "$status" = 3 ] && [ "$(cat "$TMP/chain.out")" = line ] || fail "chained status/output lost ($status)"
[ -z "$(input 23.5 41 | bash "$BRIDGE")" ] || fail "the bridge alone printed output"

# Only progress moves the reading: the same or lower numbers of the same
# window (an idle session) change nothing, more use or a later window does.
jq '.at = 1000' "$READING" >"$TMP/r" && mv "$TMP/r" "$READING"
input 20 41 | bash "$BRIDGE"
[ "$(field '.at')" = 1000 ] && [ "$(field '.five_hour.usedPercent')" = 23.5 ] || fail "older numbers overwrote the reading"
input 30 41 | bash "$BRIDGE"
[ "$(field '.five_hour.usedPercent')" = 30 ] && [ "$(field '.at')" -ge "$NOW" ] || fail "progress was not recorded"
input 2 41 $(( FIVE_RESET + 18000 )) | bash "$BRIDGE"
[ "$(field '.five_hour.usedPercent')" = 2 ] || fail "a new window was not recorded"
input 50 41 $(( FIVE_RESET - 18000 )) | bash "$BRIDGE"
[ "$(field '.five_hour.usedPercent')" = 2 ] || fail "an earlier window overwrote the reading"

# No rate limits (API-key sign-in, before the first response), malformed input
# or no jq: the status line still runs and nothing changes.
before="$(cat "$READING")"
[ "$(printf '{"session_id":"x"}' | bash "$BRIDGE" echo ok)" = ok ] || fail "input without rate limits broke the chain"
[ "$(printf 'not json' | bash "$BRIDGE" echo ok)" = ok ] || fail "malformed input broke the chain"
mkdir -p "$TMP/nojq"
for cmd in bash cat echo; do ln -sf "$(type -P "$cmd")" "$TMP/nojq/$cmd"; done
[ "$(input 99 99 | PATH="$TMP/nojq" "$TMP/nojq/bash" "$BRIDGE" echo ok)" = ok ] || fail "a missing jq broke the chain"
[ "$(cat "$READING")" = "$before" ] || fail "invalid input changed the reading"

# A profile's reading goes to that profile's account cache.
mkdir -p "$TMP/work"
input 5 6 | CLAUDE_CONFIG_DIR="$TMP/work" bash "$BRIDGE"
work="$XDG_CACHE_HOME/AiOverviewControl/claude-profiles/$(printf '%s' "$TMP/work" | sha256sum | cut -d ' ' -f 1)"
[ "$(jq -r '.five_hour.usedPercent' "$work/claude-statusline.json")" = 5 ] || fail "profile reading misplaced"

# --- Adapter ---------------------------------------------------------------
# kv <output> <KEY>: one value of get-claude-usage's key=value output.
kv() { sed -n "s/^$2=//p" <<<"$1"; }
reading() { # reading <at> <five%> <week%>
  jq -cn --argjson at "$1" --argjson f "$2" --argjson w "$3" --argjson fr "$FIVE_RESET" --argjson wr "$WEEK_RESET" \
    '{at: $at, five_hour: {usedPercent: $f, resetsAt: $fr}, seven_day: {usedPercent: $w, resetsAt: $wr}}' >"$READING"
}

# No reading: the endpoint answers.
rm -f "$READING"
out="$(bash "$ROOT/providers/get-claude-usage")"
[ "$(kv "$out" FIVE_HOUR_UTIL)" = 10 ] && [ "$(kv "$out" USAGE_SOURCE)" = endpoint ] || fail "endpoint path: $out"
[ "$(grep -c usage "$CURL_LOG")" = 1 ] || fail "expected one usage request"

# A fresh reading newer than the snapshot wins and is the update time.
reading "$(( $(date +%s) + 5 ))" 64 71
out="$(bash "$ROOT/providers/get-claude-usage")"
[ "$(kv "$out" FIVE_HOUR_UTIL)" = 64 ] && [ "$(kv "$out" SEVEN_DAY_UTIL)" = 71 ] \
  && [ "$(kv "$out" USAGE_SOURCE)" = statusline ] || fail "fresh reading ignored: $out"
[ "$(kv "$out" FIVE_HOUR_RESET)" = "$(date -u -d "@$FIVE_RESET" +%Y-%m-%dT%H:%M:%SZ)" ] || fail "reset not converted: $out"

# With a fresh reading the snapshot lives 15 minutes instead of 2: no request.
jq '.cached_at -= 300' "$ACCOUNT/claude-usage-cache.json" >"$TMP/c" && mv "$TMP/c" "$ACCOUNT/claude-usage-cache.json"
: >"$CURL_LOG"
bash "$ROOT/providers/get-claude-usage" >/dev/null
[ "$(grep -c usage "$CURL_LOG" || true)" = 0 ] || fail "the endpoint was asked while a reading is fresh"

# A stale reading is ignored and the 2 minute cache applies again.
reading "$(( $(date +%s) - 700 ))" 64 71
out="$(bash "$ROOT/providers/get-claude-usage")"
[ "$(grep -c usage "$CURL_LOG")" = 1 ] && [ "$(kv "$out" USAGE_SOURCE)" = endpoint ] \
  && [ "$(kv "$out" FIVE_HOUR_UTIL)" = 10 ] || fail "stale reading was used: $out"

# The endpoint is rate limited and has no snapshot: the reading stands in.
rm -f "$ACCOUNT/claude-usage-cache.json" "$ACCOUNT/claude-usage-backoff.json"
reading "$(date +%s)" 33 44
out="$(CLAUDE_HTTP=429 bash "$ROOT/providers/get-claude-usage")"
[ "$(kv "$out" FIVE_HOUR_UTIL)" = 33 ] && [ -z "$(kv "$out" USAGE_ERROR_MESSAGE)" ] \
  && [ -n "$(kv "$out" USAGE_RETRY_AT)" ] || fail "reading did not stand in for a 429: $out"
# Through the dispatcher the card says where the numbers came from.
json="$(CLAUDE_HTTP=429 bash "$ROOT/providers/get-provider-usage" claude)"
jq -e '.[0].source == "claude-statusline" and .[0].usage.primary.usedPercent == 33
  and .[0].usage.retryReason == "rate_limited"' <<<"$json" >/dev/null || fail "dispatcher output: $json"

# Rejected credentials are never hidden behind a reading.
rm -f "$ACCOUNT/claude-usage-backoff.json"
out="$(CLAUDE_HTTP=401 bash "$ROOT/providers/get-claude-usage")"
[ "$(kv "$out" USAGE_ERROR_KIND)" = authentication ] || fail "a reading hid rejected credentials: $out"

# A killed bridge's temporary file is swept once no bridge can own it.
: >"$READING.abcdef"
touch -d '5 minutes ago' "$READING.abcdef"
bash "$ROOT/providers/get-claude-usage" >/dev/null 2>&1 || true
[ ! -e "$READING.abcdef" ] || fail "stale bridge temp file left behind"

echo 'OK: status line bridge readings, chaining, progress-only updates, adapter preference, fallback and expiry'
