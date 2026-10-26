#!/usr/bin/env bash
# Credits, extra usage and consumable limit resets for Claude and Codex:
#  - get-claude-usage reports spend, usage credits and reset grants, and the
#    dispatcher normalizes them into billing/limitResets
#  - get-codex-usage reports credits, spend control and reset credits
#  - reset-provider-limits redeems one reset per call with an idempotency id,
#    never POSTs without a usable grant, maps every refusal to a result that
#    says nothing was used, and drops the cached usage after a reset
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/claude" AIOC_NO_LITELLM=1 TZ=UTC
export CURL_LOG="$TMP/curl.log" CODEX_LOG="$TMP/codex.log"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/projects" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
ORG="0b8d1d7e-1111-4222-8333-444455556666"
jq -n '{claudeAiOauth:{accessToken:"fixture-token",subscriptionType:"pro",expiresAt:9999999999999}}' > "$CLAUDE_CONFIG_DIR/.credentials.json"
jq -n --arg o "$ORG" '{oauthAccount:{organizationUuid:$o}}' > "$CLAUDE_CONFIG_DIR/.claude.json"

cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '2.5.1 (fixture)\n'
SH
# Fake curl: answers by URL. GRANTS selects the cedar_ember block, CLAIM the
# claim answer ("reset", "not_limited", "http429", ...).
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; prev=""; url=""; method=GET; body=""
for arg in "$@"; do
  [ "$prev" != -o ] || out="$arg"
  [ "$prev" != -X ] || method="$arg"
  case "$arg" in https://*) url="$arg" ;; esac
  prev="$arg"
done
[ "$method" != POST ] || body="$(cat)"
printf '%s %s %s\n' "$method" "$url" "$body" >> "$CURL_LOG"
case "${GRANTS:-ready}" in
  ready) grants='{"eligible":true,"at_limit":true,"next_grant_id":"g_two","grants":[{"id":"g_one","label":"Session reset","type":"session","resets_left":1,"usable_now":false,"use_requires_limit":true},{"id":"g_two","label":"Full reset","type":"full","resets_left":2,"usable_now":true,"ends_at":"2030-01-02T00:00:00Z"}]}' ;;
  none) grants='{"eligible":false,"ineligible_reason":"no_grant","grants":[]}' ;;
esac
case "$url" in
  *"/api/oauth/usage"*)
    printf '%s' "{\"limits\":[{\"kind\":\"session\",\"percent\":91},{\"kind\":\"weekly_all\",\"percent\":40}],
      \"extra_usage\":{\"is_enabled\":true,\"monthly_limit\":2500,\"used_credits\":1250,\"currency\":\"BRL\",\"spend_limit_reached\":false},
      \"spend\":{\"enabled\":true,\"used\":{\"amount_minor\":1250,\"currency\":\"BRL\",\"exponent\":2},\"limit\":{\"amount_minor\":2500,\"currency\":\"BRL\",\"exponent\":2},\"percent\":50},
      \"cedar_ember\":$grants}" > "$out"; printf 200 ;;
  *"/prepaid/credits")
    printf '%s' '{"amount":5500,"currency":"BRL","balance":{"money":{"amount_minor":5500,"currency":"BRL","exponent":2}},"promo_tranches":[{"remaining_amount_minor_units":5500}],"next_expires_at":"2027-10-22T00:00:00Z"}' > "$out"; printf 200 ;;
  *"/reset_rate_limits")
    case "${CLAIM:-reset}" in
      http*) printf '{}' > "$out"; printf '%s' "${CLAIM#http}" ;;
      *) jq -cn --arg r "${CLAIM:-reset}" '{result:$r, resets_left:1, cleared:["five_hour"]}' > "$out"; printf 200 ;;
    esac ;;
  *) printf '{}' > "$out"; printf 404 ;;
esac
SH
# Fake Codex app-server: answers JSON-RPC by id; CODEX_OUTCOME drives consume.
cat > "$TMP/bin/codex" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = app-server ] || exit 2
while IFS= read -r line; do
  printf '%s\n' "$line" >> "$CODEX_LOG"
  id="$(jq -r '.id // empty' <<<"$line")"
  case "$(jq -r '.method' <<<"$line")" in
    account/read) printf '{"id":%s,"result":{"account":{"email":"dev@example.test","planType":"plus"}}}\n' "$id" ;;
    account/rateLimits/read) printf '{"id":%s,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":1900000000},"secondary":null,"credits":{"hasCredits":true,"unlimited":false,"balance":"12.5"},"individualLimit":{"limit":"100","used":"40","remainingPercent":60,"resetsAt":1900000000},"spendControlReached":false,"planType":"plus"},"rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"c1","resetType":"codexRateLimits","status":"available","grantedAt":1,"expiresAt":1900000000,"title":"Full reset"},{"id":"c0","resetType":"codexRateLimits","status":"redeemed","grantedAt":1}]}}}\n' "$id" ;;
    account/rateLimitResetCredit/consume)
      if [ "${CODEX_OUTCOME:-reset}" = error ]; then
        printf '{"id":%s,"error":{"code":-32000,"message":"backend unavailable"}}\n' "$id"
      else
        printf '{"id":%s,"result":{"outcome":"%s"}}\n' "$id" "${CODEX_OUTCOME:-reset}"
      fi ;;
  esac
done
SH
chmod +x "$TMP/bin/claude" "$TMP/bin/curl" "$TMP/bin/codex"

# --- Claude: spend, usage credits and grants reach the dispatcher output ---
out="$(bash "$ROOT/providers/get-claude-usage")"
grep -q '^CLAUDE_PREPAID={"balance":55,"currency":"BRL","promo":55,' <<<"$out" || fail "prepaid credits: $(grep PREPAID <<<"$out")"
grep -q '/api/oauth/usage?cedar_ember=1 ' "$CURL_LOG" || fail "usage request does not ask for reset grants"
item="$(bash "$ROOT/providers/get-provider-usage" claude | jq -c '.[0]')"
jq -e '.billing.extraUsage == {enabled:true, used:12.5, limit:25, currency:"BRL", limitReached:false, disabledReason:null}' <<<"$item" >/dev/null \
  || fail "extra usage normalization: $(jq -c .billing.extraUsage <<<"$item")"
jq -e '.billing.credits.balance == 55 and .billing.credits.expiresAt == "2027-10-22T00:00:00Z"' <<<"$item" >/dev/null || fail "credits normalization"
jq -e '.limitResets.supported and .limitResets.available == 3 and .limitResets.usableNow
  and ([.limitResets.items[] | select(.usableNow) | .id] == ["g_two"])' <<<"$item" >/dev/null \
  || fail "reset grants normalization: $(jq -c .limitResets <<<"$item")"
usage_cache="$(find "$XDG_CACHE_HOME" -name claude-usage-cache.json -print -quit)"
[ -f "$usage_cache" ] || fail "usage cache missing"

# --- Claude: a usable grant is claimed once, with the next grant first ---
: > "$CURL_LOG"
res="$(bash "$ROOT/providers/reset-provider-limits" claude)"
jq -e '.result == "reset" and .resetsLeft == 1' <<<"$res" >/dev/null || fail "claude reset result: $res"
claim="$(grep '^POST ' "$CURL_LOG")"
[ "$(grep -c '^POST ' "$CURL_LOG")" -eq 1 ] || fail "expected exactly one claim"
grep -q "/api/organizations/$ORG/reset_rate_limits" <<<"$claim" || fail "claim URL: $claim"
jq -e '.program == "cedar_ember" and .grant_id == "g_two" and (.request_id | test("^[A-Za-z0-9_-]{1,64}$"))' \
  <<<"${claim##* }" >/dev/null || fail "claim body: $claim"
[ ! -e "$usage_cache" ] || fail "usage cache kept after a reset"

# --- Claude: refusals and failures say nothing was used ---
for case in not_limited:not_limited cooldown:cooldown already_used:unavailable http429:cooldown http401:auth_error http500:error; do
  out="$(CLAIM="${case%%:*}" bash "$ROOT/providers/reset-provider-limits" claude)"
  jq -e --arg r "${case##*:}" '.result == $r' <<<"$out" >/dev/null || fail "claim ${case%%:*}: $out"
done
: > "$CURL_LOG"
out="$(GRANTS=none bash "$ROOT/providers/reset-provider-limits" claude)"
jq -e '.result == "unavailable"' <<<"$out" >/dev/null || fail "no grant: $out"
! grep -q '^POST ' "$CURL_LOG" || fail "claimed without a usable grant"

# --- Claude profiles resolve their own config dir ---
export AIOC_CLAUDE_PROFILES
AIOC_CLAUDE_PROFILES="$(jq -nc --arg d "$CLAUDE_CONFIG_DIR" '{"claude-work":{configDir:$d}}')"
out="$(env -u CLAUDE_CONFIG_DIR bash "$ROOT/providers/reset-provider-limits" claude-work)"
jq -e '.provider == "claude-work" and .result == "reset"' <<<"$out" >/dev/null || fail "profile reset: $out"
out="$(bash "$ROOT/providers/reset-provider-limits" gemini)"
jq -e '.result == "error"' <<<"$out" >/dev/null || fail "unsupported provider accepted"

# --- Codex: credits, spend control and reset credits ---
item="$(bash "$ROOT/providers/get-codex-usage")"
jq -e '.billing.credits == {hasCredits:true, unlimited:false, balance:12.5}
  and .billing.spendControl.limit == 100 and .billing.spendControl.used == 40
  and .billing.spendControlReached == false
  and .limitResets.available == 1 and .limitResets.usableNow
  and ([.limitResets.items[].id] == ["c1"])' <<<"$item" >/dev/null || fail "codex billing/resets: $item"
[ -f "$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json" ] || fail "codex cache missing"

: > "$CODEX_LOG"
out="$(bash "$ROOT/providers/reset-provider-limits" codex)"
jq -e '.result == "reset"' <<<"$out" >/dev/null || fail "codex reset: $out"
[ "$(grep -c 'rateLimitResetCredit/consume' "$CODEX_LOG")" -eq 1 ] || fail "expected one consume request"
grep 'rateLimitResetCredit/consume' "$CODEX_LOG" | jq -e '.params.idempotencyKey | length > 8' >/dev/null || fail "consume without idempotency key"
[ ! -e "$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json" ] || fail "codex cache kept after a reset"
for case in nothingToReset:nothing_to_reset noCredit:no_credit alreadyRedeemed:reset error:error; do
  out="$(CODEX_OUTCOME="${case%%:*}" bash "$ROOT/providers/reset-provider-limits" codex)"
  jq -e --arg r "${case##*:}" '.result == $r' <<<"$out" >/dev/null || fail "codex ${case%%:*}: $out"
done

echo "OK: Claude/Codex credits, extra usage and consumable limit resets"
