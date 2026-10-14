#!/usr/bin/env bash
# Groq rate-limit probe — fake-curl test. Header values are the ones a live
# 1-token openai/gpt-oss-120b completion returned on a free-tier key.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin"

# Fake curl: /models answers 200; chat completions write $FAKE_HEADERS to the
# -D file and answer $FAKE_STATUS. Every completion is logged.
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; dump=""; url=""; write_code=0; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -D) dump="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    http*) url="${args[$i]}" ;;
  esac
done
case "$url" in
  */models) [ -z "$out" ] || printf '{"data":[]}' >"$out"; status=200 ;;
  */chat/completions)
    printf 'COMPLETION %s\n' "$(cat)" >>"$FAKE_LOG"
    [ -z "$dump" ] || cp "$FAKE_HEADERS" "$dump"
    [ -z "$out" ] || printf '{}' >"$out"
    status="$FAKE_STATUS" ;;
esac
[ "$write_code" -eq 0 ] || printf '%s' "$status"
exit 0
STUB
chmod +x "$TMP/bin/curl"

printf '%s\r\n' 'HTTP/2 200' 'x-groq-region: bra' \
  'x-ratelimit-limit-requests: 1000' 'x-ratelimit-limit-tokens: 8000' \
  'x-ratelimit-remaining-requests: 750' 'x-ratelimit-remaining-tokens: 7927' \
  'x-ratelimit-reset-requests: 1m26.4s' 'x-ratelimit-reset-tokens: 547ms' '' >"$TMP/ok.headers"
printf '%s\r\n' 'HTTP/2 429' 'retry-after: 30' \
  'x-ratelimit-limit-requests: 1000' 'x-ratelimit-limit-tokens: 8000' \
  'x-ratelimit-remaining-requests: 0' 'x-ratelimit-remaining-tokens: 8000' \
  'x-ratelimit-reset-requests: 2h0m30s' 'x-ratelimit-reset-tokens: 0s' '' >"$TMP/429.headers"

fail() { echo "FAIL: $1" >&2; exit 1; }
run() {
  PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_HEADERS="$1" FAKE_STATUS="$2" \
    GROQ_API_KEY=gsk_test "${@:3}" "$ROOT/providers/get-provider-usage" groq 2>/dev/null
}
field() { jq -r ".[0].$1" <<<"$out"; }

# 1. Without GROQ_QUOTA_MODEL nothing is spent: auth-only card.
: >"$TMP/log"
out="$(run "$TMP/ok.headers" 200)"
[ "$(field source)" = "groq-api" ] || fail "auth-only source"
[ ! -s "$TMP/log" ] || fail "no completion without opt-in"

# 2. Opt-in probe: requests/day and tokens/minute from the headers.
before="$(date +%s)"
out="$(run "$TMP/ok.headers" 200 env GROQ_QUOTA_MODEL=openai/gpt-oss-120b)"
[ "$(field source)" = "groq-ratelimit" ] || fail "probe source"
[ "$(field usage.primary.displayValue)" = "250 / 1000 requests" ] || fail "requests display"
[ "$(field usage.primary.usedPercent)" = "25" ] || fail "requests percent"
[ "$(field usage.primary.windowMinutes)" = "1440" ] || fail "daily window"
reset="$(jq -r '.[0].usage.primary.resetsAt | fromdateiso8601' <<<"$out")"
[ $((reset - before)) -ge 85 ] && [ $((reset - before)) -le 88 ] || fail "1m26.4s reset"
[ "$(field usage.secondary.displayValue)" = "73 / 8000 tokens" ] || fail "tokens display"
[ "$(field usage.accountEmail)" = "Groq · openai/gpt-oss-120b" ] || fail "model in identity"
jq -e '.model == "openai/gpt-oss-120b" and .max_completion_tokens == 1' <<<"$(sed 's/^COMPLETION //' "$TMP/log")" >/dev/null || fail "1-token request"

# 3. Cached within the TTL: no second completion.
out="$(run "$TMP/ok.headers" 200 env GROQ_QUOTA_MODEL=openai/gpt-oss-120b)"
[ "$(grep -c '^COMPLETION' "$TMP/log")" -eq 1 ] || fail "probe must be cached"

# 4. TTL 0 re-probes; a 429 with nothing left reads as exhausted.
out="$(run "$TMP/429.headers" 429 env GROQ_QUOTA_MODEL=openai/gpt-oss-120b GROQ_QUOTA_TTL=0)"
[ "$(grep -c '^COMPLETION' "$TMP/log")" -eq 2 ] || fail "TTL 0 re-probes"
[ "$(field usage.primary.usedPercent)" = "100" ] || fail "429 exhausted"
reset="$(jq -r '.[0].usage.primary.resetsAt | fromdateiso8601' <<<"$out")"
[ $((reset - $(date +%s))) -ge 7200 ] || fail "2h0m30s reset"

echo "OK: test-groq"
