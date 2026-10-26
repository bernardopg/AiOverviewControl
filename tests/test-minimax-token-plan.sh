#!/usr/bin/env bash
# MiniMax Token Plan quota tracking — fake-curl unit test.
#
# Verifies:
#   - MINIMAX_TOKEN_PLAN_KEY priority over MINIMAX_API_KEY.
#   - sk-cp MINIMAX_API_KEY → token plan path (back-compat).
#   - sk-api MINIMAX_API_KEY → /v1/models auth-only path.
#   - 5h primary, weekly secondary, both ms→ISO reset conversion.
#   - status 2 (exhausted) → 100% used, status 3 with totals==0 → window omitted,
#     never a fabricated "Unlimited" or 0% card.
#   - per-window availability: an unavailable 5h window keeps the weekly one.
#   - counts-only buckets fall back to (total - usage) / total.
#   - malformed/empty/sparse model_remains → json_error, not a 0% usage and not
#     an empty stdout that the wrapper reports as invalid JSON.
#   - non-`general` bucket fallback when `general` is not part of the plan.
#   - Token Plan failure degrades to the PAYG card when a sk-api key exists.
#   - MINIMAX_API_BASE retargets both endpoints (gateway / mirror).
#   - get-provider-health recognises MINIMAX_TOKEN_PLAN_KEY.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HDR_LOG="$TMP/headers.log"
URL_LOG="$TMP/urls.log"
# Sandbox the dispatcher history so fixture runs never touch the developer's
# real chart cache, regardless of calling environment.
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin"

# Fake curl that mimics real curl behaviour: -o writes the body to a file,
# -w writes the HTTP status code to stdout, and -H echoes each header into
# HDR_LOG so the test can prove the Bearer token was forwarded. Always exits
# 0 to keep curl-as-error-handling paths inert (see test-commandcode.sh for the
# same note). MM_MODE selects the fixture the stub serves for the Token Plan
# endpoint and the simulated HTTP status.
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Adapters pass secret headers through --config files; expand them back to -H.
_cfg=(); while [ $# -gt 0 ]; do if [ "$1" = --config ] || [ "$1" = -K ]; then while IFS= read -r _l; do case "$_l" in 'header = "'*) _v="${_l#header = \"}"; _cfg+=(-H "${_v%\"}") ;; esac; done < "$2"; shift 2; else _cfg+=("$1"); shift; fi; done; set -- "${_cfg[@]}"
out=""
url=""
write_code=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o)        out="${args[$((i + 1))]}" ;;
    -w)        write_code=1 ;;
    -H)        printf '%s\n' "${args[$((i + 1))]}" >> "${HDR_LOG:-/dev/null}" ;;
    http*)     url="${args[$i]}" ;;
  esac
done
status=200
printf '%s\n' "$url" >> "${URL_LOG:-/dev/null}"
case "$url" in
  *v1/token_plan/remains*)
    case "${MM_MODE:-valid}" in
      bad_status)  [ -n "$out" ] && printf '%s' '{"base_resp":{"status_code":1,"status_msg":"plan quota exceeded"}}' >"$out"; status=200 ;;
      server_500)  [ -n "$out" ] && printf '' > "$out"; status=500 ;;
      empty_200)   [ -n "$out" ] && printf '' > "$out"; status=200 ;;
      # Any other mode names a fixture: minimax-token-plan-<MM_MODE>.json.
      *)           [ -n "$out" ] && cp "$MM_FIXTURE_DIR/minimax-token-plan-${MM_MODE:-valid}.json" "$out"; status=200 ;;
    esac
    ;;
  *v1/models*)
    status="${MM_MODELS_STATUS:-200}"
    ;;
esac
if [ "$write_code" -eq 1 ]; then printf '%s' "$status"; fi
exit 0
STUB
chmod +x "$TMP/bin/curl"

run() {
  PATH="$TMP/bin:$PATH" \
  HDR_LOG="$HDR_LOG" \
  URL_LOG="$URL_LOG" \
  MM_FIXTURE_DIR="$ROOT/tests/fixtures" \
  MM_MODE="${MM_MODE:-valid}" \
  "$@" "$ROOT/providers/get-provider-usage" minimax 2>/dev/null
}
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Dedicated MINIMAX_TOKEN_PLAN_KEY → Token Plan path with quota windows.
: > "$HDR_LOG"
out="$(MM_MODE=valid run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].source'                          <<<"$out")" = "minimax-token-plan" ]   || fail "source token-plan"
[ "$(jq -r '.[0].usage.primary.windowMinutes'     <<<"$out")" = "300" ]                 || fail "5h minutes"
[ "$(jq -r '.[0].usage.primary.resetDescription'  <<<"$out")" = "null" ]                || fail "5h label (must be null for known 5h window)"
[ "$(jq -r '.[0].usage.primary.usedPercent|floor' <<<"$out")" = "27" ]                 || fail "5h percent (100-73)"
[ "$(jq -r '.[0].usage.secondary.windowMinutes'   <<<"$out")" = "10080" ]               || fail "weekly minutes"
[ "$(jq -r '.[0].usage.secondary.usedPercent|floor' <<<"$out")" = "9" ]                || fail "weekly percent (100-91)"
# resetsAt from end_time=1789480800000ms → 2026-09-15T14:00:00Z (UTC), regardless of TZ
[ "$(jq -r '.[0].usage.primary.resetsAt'          <<<"$out")" = "$(TZ=UTC jq -r '1789480800000 / 1000 | todateiso8601' <<<'null')" ] || fail "5h reset ms→ISO"
[ "$(jq -r '.[0].usage.identity.loginMethod'      <<<"$out")" = "subscription-key" ]   || fail "login method"
[ "$(jq -r '.[0].credits.remaining'               <<<"$out")" = "Token Plan" ]          || fail "credits label"
grep -q '^Authorization: Bearer sk-cp-plan$' "$HDR_LOG" || fail "auth header forwarded"

# 2. Back-compat: sk-cp MINIMAX_API_KEY alone still gets the Token Plan path.
: > "$HDR_LOG"
out="$(MM_MODE=valid run env -u MINIMAX_TOKEN_PLAN_KEY MINIMAX_API_KEY=sk-cp-legacy)"
[ "$(jq -r '.[0].source'                          <<<"$out")" = "minimax-token-plan" ] || fail "back-compat source"
[ "$(jq -r '.[0].usage.primary.usedPercent|floor' <<<"$out")" = "27" ]                || fail "back-compat 5h percent"
grep -q '^Authorization: Bearer sk-cp-legacy$' "$HDR_LOG" || fail "back-compat auth header"

# 3. MINIMAX_TOKEN_PLAN_KEY takes precedence over MINIMAX_API_KEY.
: > "$HDR_LOG"
out="$(MM_MODE=valid run env MINIMAX_TOKEN_PLAN_KEY=sk-cp-primary MINIMAX_API_KEY=sk-cp-secondary)"
grep -q '^Authorization: Bearer sk-cp-primary$' "$HDR_LOG" || fail "priority — primary key wins"
[ "$(jq -r '.[0].source'                          <<<"$out")" = "minimax-token-plan" ] || fail "priority source"

# 4. Pay-as-you-go sk-api MINIMAX_API_KEY stays on /v1/models (auth-only).
: > "$HDR_LOG"
out="$(MM_MODE=valid run env -u MINIMAX_TOKEN_PLAN_KEY MINIMAX_API_KEY=sk-api-payg)"
[ "$(jq -r '.[0].source'                          <<<"$out")" = "minimax-api" ]        || fail "PAYG source"
grep -q '^Authorization: Bearer sk-api-payg$' "$HDR_LOG" || fail "PAYG auth header"
# Auth-only shape: no quotas, just an informational card with the dashboard link.
[ "$(jq -r '.[0].usage.primary.usedPercent'        <<<"$out")" = "0" ]                 || fail "PAYG primary should be 0 (informational)"

# 5. status=2 (exhausted) → 100% used for both windows.
out="$(MM_MODE=exhausted run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].source'                          <<<"$out")" = "minimax-token-plan" ] || fail "exhausted source"
[ "$(jq -r '.[0].usage.primary.usedPercent'       <<<"$out")" = "100" ]               || fail "exhausted primary"
[ "$(jq -r '.[0].usage.secondary.usedPercent'     <<<"$out")" = "100" ]               || fail "exhausted secondary"

# 6. Genuinely unavailable bucket (status=3 with zero totals) must NOT silently
#    render as `Unlimited` — that's how we would visually claim a model bucket
#    that is not actually part of the plan. The adapter must surface a
#    provider error instead.
out="$(MM_MODE=unavailable run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "unavailable bucket must error"

# 7. Empty / malformed model_remains → provider error, never 0% usage.
out="$(MM_MODE=malformed run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "malformed must error"
[ "$(jq -r '.[0].usage'                           <<<"$out")" = "null" ]              || fail "malformed must not emit a usage object"

# 8. API-level error (base_resp.status_code != 0) → provider error.
out="$(MM_MODE=bad_status run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "API-level error must error"
[ "$(jq -r '.[0].error.message'                   <<<"$out")" = "plan quota exceeded" ] || fail "API-level error message surfacing"

# 9. Network-level 500 → provider error, no quota payload.
out="$(MM_MODE=server_500 run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "500 must error"

# 10. 200 OK with empty body → provider error (not "0% used" success).
out="$(MM_MODE=empty_200 run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "empty body must error"

# 11. No credential at all → provider error naming both env vars.
out="$(run env -u MINIMAX_API_KEY -u MINIMAX_TOKEN_PLAN_KEY)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "no-credentials kind"
[ "$(jq -r '.[0].error.message'                   <<<"$out")" = "MINIMAX_API_KEY or MINIMAX_TOKEN_PLAN_KEY is not set." ] || fail "no-credentials message"

# 12. Health check recognises MINIMAX_TOKEN_PLAN_KEY alone.
health="$(MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan "$ROOT/providers/get-provider-health" minimax 2>/dev/null)"
[ "$(jq -r '.[0].status'                          <<<"$health")" = "ready" ]           || fail "Token Plan key health"
[ "$(jq -r '.[0].detail'                          <<<"$health")" = "Configured" ]      || fail "Token Plan key health detail"

# 13. Health check accepts the legacy sk-cp MINIMAX_API_KEY too.
health="$(MINIMAX_API_KEY=sk-cp-legacy "$ROOT/providers/get-provider-health" minimax 2>/dev/null)"
[ "$(jq -r '.[0].status'                          <<<"$health")" = "ready" ]           || fail "back-compat sk-cp health"

# 14. Health check still recognises sk-api PAYG keys.
health="$(MINIMAX_API_KEY=sk-api-payg "$ROOT/providers/get-provider-health" minimax 2>/dev/null)"
[ "$(jq -r '.[0].status'                          <<<"$health")" = "ready" ]           || fail "PAYG key health"

# 15. Health check reports both env vars when neither is set.
health="$(env -u MINIMAX_API_KEY -u MINIMAX_TOKEN_PLAN_KEY "$ROOT/providers/get-provider-health" minimax 2>/dev/null)"
[ "$(jq -r '.[0].status'                          <<<"$health")" = "missing" ]         || fail "no-credentials health status"
[ "$(jq -r '.[0].detail'                          <<<"$health")" = "MINIMAX_API_KEY or MINIMAX_TOKEN_PLAN_KEY" ] || fail "no-credentials health detail"

# 16. A 5h window that is not part of the plan (status 3, zero counted quota)
#     must be omitted entirely — no `Unlimited`, no 0% — while the weekly
#     window it coexists with is still reported.
out="$(MM_MODE=partial run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].usage.primary'                   <<<"$out")" = "null" ]              || fail "unavailable 5h window must be omitted"
[ "$(jq -r '.[0].usage.secondary.usedPercent'     <<<"$out")" = "9" ]                 || fail "weekly window must survive an unavailable 5h window"
! grep -q 'Unlimited' <<<"$out" || fail "must never fabricate an Unlimited window"

# 17. Buckets that report counts but no remaining_percent use (total - usage) / total.
out="$(MM_MODE=counts run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].usage.primary.usedPercent'       <<<"$out")" = "25" ]                || fail "counts fallback 5h (50/200)"
[ "$(jq -r '.[0].usage.secondary.usedPercent'     <<<"$out")" = "25" ]                || fail "counts fallback weekly (250/1000)"

# 18. A bucket with every numeric field missing must surface a provider error.
#     `tonumber?` yields empty, so without the `// null` pin the whole jq object
#     collapses to empty stdout and the user sees "returned invalid JSON".
out="$(MM_MODE=sparse run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "sparse bucket must error"
[ "$(jq -r '.[0].source'                          <<<"$out")" = "minimax-token-plan" ] || fail "sparse bucket error must stay on the token-plan source"

# 19. When `general` is not part of the plan, the first usable bucket wins.
out="$(MM_MODE=multibucket run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].usage.primary.usedPercent'       <<<"$out")" = "60" ]                || fail "non-general bucket fallback (100-40)"
[ "$(jq -r '.[0].usage.secondary.usedPercent'     <<<"$out")" = "45" ]                || fail "non-general bucket weekly (100-55)"

# 20. Token Plan probe failure + a separate PAYG key → degrade to the auth-only
#     card instead of blanking the provider.
out="$(MM_MODE=server_500 run env MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan MINIMAX_API_KEY=sk-api-payg)"
[ "$(jq -r '.[0].source'                          <<<"$out")" = "minimax-api" ]       || fail "Token Plan failure must degrade to PAYG"
[ "$(jq -r '.[0].error'                           <<<"$out")" = "null" ]              || fail "degraded PAYG card must not carry an error"

# 21. Token Plan probe failure with no PAYG key → the quota error is surfaced.
out="$(MM_MODE=server_500 run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "Token Plan failure without PAYG must error"
[ "$(jq -r '.[0].source'                          <<<"$out")" = "minimax-token-plan" ] || fail "Token Plan failure source"

# 22. A sk-cp MINIMAX_API_KEY is a Token Plan key, not a PAYG fallback: it must
#     never be replayed against /v1/models after a quota failure.
: > "$URL_LOG"
out="$(MM_MODE=server_500 run env -u MINIMAX_TOKEN_PLAN_KEY MINIMAX_API_KEY=sk-cp-legacy)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "sk-cp-only failure must error"
! grep -q 'v1/models' "$URL_LOG" || fail "sk-cp key must not be replayed against /v1/models"

# 23. MINIMAX_API_BASE retargets both endpoints, trailing slash tolerated.
: > "$URL_LOG"
MM_MODE=valid run env -u MINIMAX_API_KEY MINIMAX_TOKEN_PLAN_KEY=sk-cp-plan \
  MINIMAX_API_BASE=https://minimax.example.internal/ >/dev/null
grep -q '^https://minimax.example.internal/v1/token_plan/remains$' "$URL_LOG" || fail "MINIMAX_API_BASE must retarget the quota endpoint"
: > "$URL_LOG"
MM_MODE=valid run env -u MINIMAX_TOKEN_PLAN_KEY MINIMAX_API_KEY=sk-api-payg \
  MINIMAX_API_BASE=https://minimax.example.internal >/dev/null
grep -q '^https://minimax.example.internal/v1/models$' "$URL_LOG" || fail "MINIMAX_API_BASE must retarget the models endpoint"

# 24. An invalid PAYG key still reports the auth failure.
out="$(MM_MODE=valid run env -u MINIMAX_TOKEN_PLAN_KEY MM_MODELS_STATUS=401 MINIMAX_API_KEY=sk-api-bad)"
[ "$(jq -r '.[0].error.kind'                      <<<"$out")" = "provider" ]          || fail "invalid PAYG key must error"

echo "OK: test-minimax-token-plan"
