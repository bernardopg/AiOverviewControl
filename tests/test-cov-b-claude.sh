#!/usr/bin/env bash
# Offline coverage for Claude profile validation, OAuth, and native normalization.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/claude" AIOC_NO_LITELLM=1 TZ=UTC
export CURL_USAGE_LOG="$TMP/usage-requests"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/projects/-repo" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '2.5.1 (fixture)\n'
SH
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
# Adapters pass secret headers through --config files; expand them back to -H.
_cfg=(); while [ $# -gt 0 ]; do if [ "$1" = --config ] || [ "$1" = -K ]; then while IFS= read -r _l; do case "$_l" in 'header = "'*) _v="${_l#header = \"}"; _cfg+=(-H "${_v%\"}") ;; esac; done < "$2"; shift 2; else _cfg+=("$1"); shift; fi; done; set -- "${_cfg[@]}"
out=""; headers=""; prev=""
for arg in "$@"; do [ "$prev" != -o ] || out="$arg"; [ "$prev" != -D ] || headers="$arg"; prev="$arg"; done
case "$*" in *oauth/usage*) printf '%s\n' "${CLAUDE_HTTP:-200}" >> "$CURL_USAGE_LOG" ;; esac
if [ -n "$headers" ]; then
  printf 'HTTP/2 %s\r\n' "${CLAUDE_HTTP:-200}" > "$headers"
  [ -z "${CLAUDE_RETRY_AFTER:-}" ] || printf 'retry-after: %s\r\n' "$CLAUDE_RETRY_AFTER" >> "$headers"
fi
case "${CLAUDE_HTTP:-200}" in
  200) printf '%s' '{"five_hour":{},"limits":[{"kind":"session","percent":37,"resets_at":"2030-01-02T03:04:05Z"},{"kind":"weekly_all","percent":44},{"kind":"weekly_scoped","percent":70,"is_active":false,"scope":{"model":{"display_name":"old"}}},{"kind":"weekly_scoped","percent":52,"is_active":true,"scope":{"model":{"display_name":"new"}}}],"extra_usage":{"is_enabled":true,"utilization":20,"used_credits":4.5,"monthly_limit":10,"currency":"USD"}}' > "$out"; printf 200 ;;
  limits-only) printf '%s' '{"limits":[{"kind":"session","percent":61},{"kind":"weekly_all","percent":15}]}' > "$out"; printf 200 ;;
  *) printf '{"message":"offline fixture"}' > "$out"; printf '%s' "$CLAUDE_HTTP" ;;
esac
SH
chmod +x "$TMP/bin/claude" "$TMP/bin/curl"
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { bash "$ROOT/providers/get-claude-usage"; }

# Profile lookup accepts a real absolute path and rejects malformed ids/config.
source "$ROOT/providers/claude-profile-common"
AIOC_CLAUDE_PROFILES="$(jq -nc --arg d "$CLAUDE_CONFIG_DIR" '{"claude-work":{configDir:$d}}')"
export AIOC_CLAUDE_PROFILES
[ "$(claude_profile_dir claude-work)" = "$CLAUDE_CONFIG_DIR" ] || fail "valid profile lookup"
for bad in 'claude-' 'Claude-work' 'claude-../escape' 'claude-$(id)' ; do
  ! claude_profile_dir "$bad" >/dev/null 2>&1 || fail "accepted unsafe profile id: $bad"
done
for profiles in '{broken' '[]' '{"claude-work":{}}' '{"claude-work":{"configDir":"relative"}}' '{"claude-work":{"configDir":7}}' '{"claude-work":{"configDir":"/tmp\nother"}}'; do
  ! AIOC_CLAUDE_PROFILES="$profiles" claude_profile_dir claude-work >/dev/null 2>&1 || fail "accepted invalid profile mapping"
done

# Scoped OAuth credentials and transcript analytics take the canonical limits array.
jq -n '{claudeAiOauth:{accessToken:"fixture-token",subscriptionType:"pro",rateLimitTier:"max"}}' > "$CLAUDE_CONFIG_DIR/.credentials.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
jq -nc --arg ts "$NOW" '{type:"assistant",timestamp:$ts,sessionId:"s1",cwd:"/repo",message:{model:"claude-sonnet-4",usage:{input_tokens:100,output_tokens:50}}}' > "$CLAUDE_CONFIG_DIR/projects/-repo/a.jsonl"
jq -nc --arg ts "$NOW" '{type:"assistant",timestamp:$ts,sessionId:"s1",cwd:"/repo",message:{model:"<synthetic>",usage:{input_tokens:900}}}' > "$CLAUDE_CONFIG_DIR/projects/-repo/synthetic.jsonl"
out="$(run)"
grep -q '^SCOPED_LIMIT_MODEL=new$' <<<"$out" || fail "active scoped limit not preferred"
grep -q '^WEEK_TOKENS=150$' <<<"$out" || fail "transcript totals or synthetic exclusion"
grep -q '^EXTRA_USAGE_CURRENCY=USD$' <<<"$out" || fail "extra usage fields"
out="$(bash "$ROOT/providers/get-provider-usage" claude-work)"
jq -e '.[0].provider == "claude-work" and .[0].usage.primary.usedPercent == 37 and .[0].usage.tertiary.usedPercent == 52 and .[0].analytics.weekTokens == 150 and .[0].analytics.extraUsage.enabled' <<<"$out" >/dev/null || fail "Claude output normalization"

# A valid cached API result survives transient failure; auth failure does not.
usage_cache="$(find "$XDG_CACHE_HOME/AiOverviewControl/claude-profiles" -name claude-usage-cache.json -print -quit)"
backoff="$(dirname "$usage_cache")/claude-usage-backoff.json"
jq '.cached_at=(now|floor - 121)' "$usage_cache" > "$TMP/stale-cache.json"
mv "$TMP/stale-cache.json" "$usage_cache"
out="$(CLAUDE_HTTP=503 run)"
grep -q '^FIVE_HOUR_UTIL=37$' <<<"$out" || fail "transient failure did not use prior response cache"
grep -q "^USAGE_UPDATED_AT=$(jq -r .cached_at "$usage_cache")$" <<<"$out" || fail "fallback snapshot lost its fetch time"
grep -q '^USAGE_RETRY_REASON=server_error$' <<<"$out" || fail "5xx did not start a backoff"
rm -f "$backoff"
# The fallback snapshot keeps its fetch time so the card reads as stale
# (issue #89), and a window whose reset has passed no longer shows its old
# percentage. A live fetch is stamped with the current time.
jq '.cached_at = 1700000000 | .data.limits[1].resets_at = "2020-01-01T00:00:00.123456+00:00"' \
  "$usage_cache" > "$TMP/stale-cache.json"
mv "$TMP/stale-cache.json" "$usage_cache"
out="$(CLAUDE_HTTP=429 bash "$ROOT/providers/get-provider-usage" claude-work)"
jq -e '.[0].usage.updatedAt == "2023-11-14T22:13:20Z"
  and .[0].usage.primary.usedPercent == 37 and .[0].usage.primary.resetsAt == "2030-01-02T03:04:05Z"
  and .[0].usage.secondary.usedPercent == 0 and .[0].usage.secondary.resetsAt == null' <<<"$out" >/dev/null \
  || fail "stale fallback reported as fresh: $out"
rm -f "$backoff"
out="$(bash "$ROOT/providers/get-provider-usage" claude-work)"
jq -e '(.[0].usage.updatedAt | fromdateiso8601) >= (now - 60) and .[0].usage.secondary.usedPercent == 44
  and .[0].usage.retryAt == null and .[0].usage.retryReason == null' <<<"$out" >/dev/null \
  || fail "live snapshot not stamped now: $out"

# Issue #96: a 429 or 5xx starts a backoff shared by every run on the account
# (one widget per monitor), so the endpoint is not polled again until it ends.
expire() { jq '.cached_at=(now|floor - 121)' "$usage_cache" > "$TMP/stale-cache.json" && mv "$TMP/stale-cache.json" "$usage_cache"; }
requests() { wc -l < "$CURL_USAGE_LOG" | tr -d ' '; }
expire; : > "$CURL_USAGE_LOG"
before="$(date +%s)"
out="$(CLAUDE_HTTP=429 run)"
jq -e --argjson t "$before" '.failures == 1 and .status == "429" and .until >= $t + 120 and .until <= $t + 125' "$backoff" >/dev/null \
  || fail "first 429 backoff not one cache TTL: $(cat "$backoff")"
grep -q "^USAGE_RETRY_AT=$(jq -r .until "$backoff")$" <<<"$out" || fail "retry time not reported"
grep -q '^USAGE_RETRY_REASON=rate_limited$' <<<"$out" || fail "429 not reported as rate limited"
grep -q '^FIVE_HOUR_UTIL=37$' <<<"$out" || fail "429 did not keep the last snapshot"
for _ in 1 2 3; do out="$(CLAUDE_HTTP=200 run)"; done
[ "$(requests)" = 1 ] || fail "backoff did not stop polling: $(requests) requests"
grep -q '^USAGE_RETRY_REASON=rate_limited$' <<<"$out" || fail "skipped run lost the backoff reason"
out="$(bash "$ROOT/providers/get-provider-usage" claude-work)"
jq -e '.[0].usage.retryReason == "rate_limited" and (.[0].usage.retryAt | fromdateiso8601) > now
  and .[0].usage.primary.usedPercent == 37 and .[0].error == null' <<<"$out" >/dev/null \
  || fail "backoff not exposed in the provider item: $out"
# Consecutive failures double the delay up to the cap; a longer Retry-After
# (seconds or an HTTP date) wins, and a deadline beyond the longest delay
# (clock moved back) is ignored.
jq '.until = 1' "$backoff" > "$TMP/b" && mv "$TMP/b" "$backoff"
before="$(date +%s)"
CLAUDE_HTTP=429 run >/dev/null
jq -e --argjson t "$before" '.failures == 2 and .until >= $t + 240 and .until <= $t + 245' "$backoff" >/dev/null \
  || fail "second failure did not double the delay: $(cat "$backoff")"
jq '.until = 1 | .failures = 9' "$backoff" > "$TMP/b" && mv "$TMP/b" "$backoff"
before="$(date +%s)"
CLAUDE_HTTP=502 run >/dev/null
jq -e --argjson t "$before" '.failures == 10 and .status == "502" and .until >= $t + 1800 and .until <= $t + 1805' "$backoff" >/dev/null \
  || fail "backoff not capped: $(cat "$backoff")"
jq '.until = 1 | .failures = 0' "$backoff" > "$TMP/b" && mv "$TMP/b" "$backoff"
before="$(date +%s)"
CLAUDE_HTTP=429 CLAUDE_RETRY_AFTER=900 run >/dev/null
jq -e --argjson t "$before" '.until >= $t + 900 and .until <= $t + 905' "$backoff" >/dev/null \
  || fail "Retry-After seconds not honoured: $(cat "$backoff")"
jq '.until = 1 | .failures = 0' "$backoff" > "$TMP/b" && mv "$TMP/b" "$backoff"
before="$(date +%s)"
CLAUDE_HTTP=429 CLAUDE_RETRY_AFTER="$(LC_ALL=C date -u -d '+600 seconds' '+%a, %d %b %Y %H:%M:%S GMT')" run >/dev/null
jq -e --argjson t "$before" '.until >= $t + 595 and .until <= $t + 605' "$backoff" >/dev/null \
  || fail "Retry-After date not honoured: $(cat "$backoff")"
jq '.until = 1 | .failures = 0' "$backoff" > "$TMP/b" && mv "$TMP/b" "$backoff"
before="$(date +%s)"
CLAUDE_HTTP=429 CLAUDE_RETRY_AFTER=99999999 run >/dev/null
jq -e --argjson t "$before" '.until >= $t + 120 and .until <= $t + 125' "$backoff" >/dev/null \
  || fail "absurd Retry-After not ignored: $(cat "$backoff")"
jq '.until = 1 | .failures = 0' "$backoff" > "$TMP/b" && mv "$TMP/b" "$backoff"
before="$(date +%s)"
CLAUDE_HTTP=429 CLAUDE_RETRY_AFTER=86400 run >/dev/null
jq -e --argjson t "$before" '.until >= $t + 3600 and .until <= $t + 3605' "$backoff" >/dev/null \
  || fail "long Retry-After not capped: $(cat "$backoff")"
jq '.until = (now | floor) + 999999' "$backoff" > "$TMP/b" && mv "$TMP/b" "$backoff"
: > "$CURL_USAGE_LOG"
out="$(run)"
[ "$(requests)" = 1 ] && grep -q '^USAGE_RETRY_AT=$' <<<"$out" || fail "far-future backoff (clock skew) not ignored"
[ ! -e "$backoff" ] || fail "a successful request did not clear the backoff"
# A network failure (HTTP 000) is not the server asking for a pause.
expire
out="$(CLAUDE_HTTP=000 run)"
[ ! -e "$backoff" ] && grep -q '^USAGE_RETRY_AT=$' <<<"$out" || fail "network failure started a backoff"
# Without a snapshot to fall back on, the error names the next attempt; a
# corrupt backoff file is ignored.
mv "$usage_cache" "$TMP/kept-cache.json"
out="$(CLAUDE_HTTP=429 run)"
grep -q '^USAGE_ERROR_MESSAGE=Claude usage endpoint is rate limited (HTTP 429). Next attempt after [0-2][0-9]:[0-5][0-9]\.$' <<<"$out" \
  || fail "429 without a snapshot: $(grep ERROR <<<"$out")"
out="$(bash "$ROOT/providers/get-provider-usage" claude-work)"
jq -e '.[0].error.kind == "network" and (.[0].error.message | test("rate limited")) and .[0].analytics.weekTokens == 150' <<<"$out" >/dev/null \
  || fail "skipped request without a snapshot: $out"
jq '.status = "503" | .failures = 1' "$backoff" > "$TMP/b" && mv "$TMP/b" "$backoff"
out="$(run)"
grep -q '^USAGE_ERROR_MESSAGE=Claude usage request failed with HTTP 503. Next attempt after ' <<<"$out" || fail "5xx backoff message"
printf 'not json' > "$backoff"
: > "$CURL_USAGE_LOG"
out="$(run)"
[ "$(requests)" = 1 ] && grep -q '^USAGE_ERROR_KIND=$' <<<"$out" || fail "corrupt backoff file blocked the request"
mv "$TMP/kept-cache.json" "$usage_cache"
rm -f "$backoff"
jq '.cached_at=(now|floor - 121)' "$usage_cache" > "$TMP/stale-cache.json"
mv "$TMP/stale-cache.json" "$usage_cache"
out="$(CLAUDE_HTTP=401 run)"
grep -q '^USAGE_ERROR_KIND=authentication$' <<<"$out" || fail "rejected OAuth reported as transient"

# A canonical response with only limits[] (no flat five_hour) is accepted
# and cached rather than reported as a failed request.
rm -f "$usage_cache"
out="$(CLAUDE_HTTP=limits-only run)"
grep -q '^FIVE_HOUR_UTIL=61$' <<<"$out" || fail "limits-only response rejected"
grep -q '^USAGE_ERROR_KIND=$' <<<"$out" || fail "limits-only response reported an error"
out="$(CLAUDE_HTTP=503 run)"
grep -q '^SEVEN_DAY_UTIL=15$' <<<"$out" || fail "limits-only snapshot not served from cache"
rm -f "$usage_cache"

# Missing token and missing credentials keep local analytics available.
jq -n '{claudeAiOauth:{subscriptionType:"free"}}' > "$CLAUDE_CONFIG_DIR/.credentials.json"
out="$(run)"
grep -q '^USAGE_ERROR_KIND=authentication$' <<<"$out" || fail "missing OAuth token"
rm "$CLAUDE_CONFIG_DIR/.credentials.json"
out="$(run)"
grep -q '^USAGE_ERROR_KIND=authentication$' <<<"$out" || fail "missing credentials"

# A corrupt credentials file (found by the local-reader fuzzer) is an
# authentication error, not a crash that hides the local analytics; values
# with line breaks cannot forge extra KEY=VALUE lines.
printf '{"claudeAiOauth": {' > "$CLAUDE_CONFIG_DIR/.credentials.json"
out="$(run)" || fail "corrupt credentials crashed the helper"
grep -q '^USAGE_ERROR_KIND=authentication$' <<<"$out" || fail "corrupt credentials not reported"
grep -q '^WEEK_TOKENS=150$' <<<"$out" || fail "corrupt credentials hid local analytics"
jq -n '{claudeAiOauth:{subscriptionType:"pro\nUSAGE_ERROR_KIND=forged",accessToken:"has space"}}' > "$CLAUDE_CONFIG_DIR/.credentials.json"
out="$(run)"
! grep -q '^USAGE_ERROR_KIND=forged' <<<"$out" || fail "line break forged a KEY=VALUE line"
grep -q '^USAGE_ERROR_KIND=authentication$' <<<"$out" || fail "malformed token not treated as missing"
rm "$CLAUDE_CONFIG_DIR/.credentials.json"

# Sourced native adapter handles helper output, helper failure, and missing helper.
json_error() { jq -cn --arg p "$1" --arg s "$2" --argjson c "$3" --arg k "$4" --arg m "$5" '{provider:$p,source:$s,error:{code:$c,kind:$k,message:$m}}'; }
source "$ROOT/providers/native/claude.bash"
CLAUDE_SCRIPT="$TMP/helper"
cat > "$CLAUDE_SCRIPT" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'SUBSCRIPTION_TYPE=pro' 'FIVE_HOUR_UTIL=140' 'SCOPED_LIMIT_MODEL=Fable' 'SCOPED_LIMIT_UTIL=-1' 'WEEK_TOKENS=23' 'DAILY=1,2,3' 'USAGE_ERROR_KIND=' 'USAGE_ERROR_MESSAGE='
SH
out="$(fetch_claude_native)"
jq -e '.provider == "claude" and .usage.primary.usedPercent == 100 and .usage.tertiary.usedPercent == 0 and .analytics.weekTokens == 23 and (.analytics.dailyTokens | length) == 3' <<<"$out" >/dev/null || fail "native successful mapping/clamping"
printf '#!/usr/bin/env bash\necho helper-broke >&2\nexit 7\n' > "$CLAUDE_SCRIPT"
out="$(fetch_claude_native)"
jq -e '.error.code == 7 and .error.message == "helper-broke"' <<<"$out" >/dev/null || fail "native helper failure mapping"
cat > "$CLAUDE_SCRIPT" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'WEEK_TOKENS=9' 'USAGE_ERROR_KIND=network' 'USAGE_ERROR_MESSAGE=usage unavailable'
SH
out="$(fetch_claude_native)"
jq -e '.error.kind=="network" and .error.message=="usage unavailable" and .analytics.weekTokens==9' <<<"$out" >/dev/null || fail "native provider error with analytics"
CLAUDE_SCRIPT="$TMP/absent"
out="$(fetch_claude_native)"
jq -e '.error.code == 127' <<<"$out" >/dev/null || fail "native missing helper mapping"

echo 'OK: Claude profile, OAuth, transcript, and native coverage'
