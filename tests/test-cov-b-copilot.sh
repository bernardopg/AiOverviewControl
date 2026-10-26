#!/usr/bin/env bash
# Offline coverage for the Copilot API, cache, and DNS fallback paths.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" GH_LOG="$TMP/gh.log" CURL_LOG="$TMP/curl.log"
mkdir -p "$HOME" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
[ "${GH_MODE:-ok}" = ok ] || exit 1
printf 'gh-test-token\n'
SH
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CURL_LOG"
url="${*: -1}"
if [[ "$url" == https://dns.google/* ]]; then
  [ "${DOH_MODE:-ok}" = ok ] && printf '{"Answer":[{"type":1,"data":"192.0.2.7"}]}'
  exit 0
fi
out=""; prev=""
for arg in "$@"; do [ "$prev" != -o ] || out="$arg"; prev="$arg"; done
case "${API_MODE:-ok}" in
  ok) printf '%s' '{"login":"b-user","copilot_plan":"individual","quota_reset_date_utc":"2026-11-01T00:00:00Z","quota_snapshots":{"premium_interactions":{"entitlement":100,"remaining":25,"overage_count":2},"chat":{"entitlement":50,"remaining":40},"completions":{"unlimited":true,"entitlement":0}}}' > "$out"; printf 200 ;;
  empty)
    if [[ "$*" == *--resolve* ]]; then
      printf '%s' '{"login":"b-user","copilot_plan":"individual","quota_snapshots":{"premium_interactions":{"entitlement":100,"remaining":25}}}' > "$out"
      printf 200
    else
      : > "$out"; printf 000
    fi ;;
  badjson) printf '{bad' > "$out"; printf 200 ;;
  auth) printf '{"message":"bad credentials"}' > "$out"; printf 401 ;;
  *) printf '{"message":"server busy"}' > "$out"; printf 503 ;;
esac
SH
chmod +x "$TMP/bin/gh" "$TMP/bin/curl"
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { bash "$ROOT/providers/get-copilot-usage"; }

out="$(run)"
jq -e '.provider == "copilot" and .source == "github-copilot-api" and .usage.primary.usedPercent == 75 and .usage.secondary.usedPercent == 20 and .usage.tertiary == null and .credits.remaining == "25" and (.usage.accountEmail | contains("b-user · Pro"))' <<<"$out" >/dev/null || fail "API quota normalization"
grep -qx 'auth token' "$GH_LOG" || fail "gh credential lookup"

# A transient HTTP error serves a fresh snapshot and marks its source.
out="$(API_MODE=server run)"
jq -e '.source == "github-copilot-cache" and .usage.primary.usedPercent == 75' <<<"$out" >/dev/null || fail "cached response fallback"

# DNS fallback resolves one IPv4 answer, passes --resolve, and succeeds.
rm -f "$XDG_CACHE_HOME/AiOverviewControl/copilot-usage.json"
: > "$CURL_LOG"
out="$(API_MODE=empty run)"
jq -e '.error == null and .source == "github-copilot-api"' <<<"$out" >/dev/null || fail "DoH retry success"
grep -q 'dns.google/resolve' "$CURL_LOG" || fail "DoH lookup not called"
grep -q -- '--resolve api.github.com:443:192.0.2.7' "$CURL_LOG" || fail "resolved edge not used"

# The opt-out skips DoH and keeps the transport failure structured.
rm -f "$XDG_CACHE_HOME/AiOverviewControl/copilot-usage.json"
: > "$CURL_LOG"
out="$(AIOC_NO_DOH_FALLBACK=1 API_MODE=empty run)"
jq -e '.error.code == 1 and .error.kind == "runtime" and (.error.message | contains("HTTP 000"))' <<<"$out" >/dev/null || fail "DoH opt-out error"
! grep -q 'dns.google/resolve' "$CURL_LOG" || fail "DoH opt-out made a DNS request"

# Token absence, invalid JSON, and explicit API rejection are independent errors.
out="$(env -u GH_TOKEN -u GITHUB_TOKEN GH_MODE=missing bash "$ROOT/providers/get-copilot-usage")"
jq -e '.error.code == 2 and (.error.message | contains("token not found"))' <<<"$out" >/dev/null || fail "missing token"
rm -f "$XDG_CACHE_HOME/AiOverviewControl/copilot-usage.json"
out="$(API_MODE=badjson run)"
jq -e '.error.code == 3 and (.error.message | contains("invalid JSON"))' <<<"$out" >/dev/null || fail "malformed success body"
rm -f "$XDG_CACHE_HOME/AiOverviewControl/copilot-usage.json"
out="$(API_MODE=auth run)"
jq -e '.error.code == 401 and .error.message == "bad credentials"' <<<"$out" >/dev/null || fail "HTTP auth failure"

echo 'OK: Copilot API, cache, and DoH coverage'
