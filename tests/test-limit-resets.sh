#!/usr/bin/env bash
# Credits, extra usage and consumable limit resets for Claude and Codex:
#  - get-claude-usage reports spend, usage credits and reset grants, and the
#    dispatcher normalizes them into billing/limitResets
#  - get-codex-usage reports credits, spend control and reset credits
#  - reset-provider-limits redeems one reset per call with an idempotency id,
#    never POSTs without a usable grant, maps every refusal to a result that
#    says nothing was used, and drops the cached usage after a reset
#  - a refused credits read (403/404) is recorded for a day per organization,
#    and a 429 there pauses the usage endpoint too and names the next try
#    (issue #123); the record is replaced atomically
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
# Adapters pass secret headers through --config files; expand them back to -H.
_cfg=(); while [ $# -gt 0 ]; do if [ "$1" = --config ] || [ "$1" = -K ]; then while IFS= read -r _l; do case "$_l" in 'header = "'*) _v="${_l#header = \"}"; _cfg+=(-H "${_v%\"}") ;; esac; done < "$2"; shift 2; else _cfg+=("$1"); shift; fi; done; set -- "${_cfg[@]}"
out=""; prev=""; url=""; method=GET; body=""; HEADERS_OUT=/dev/null
for arg in "$@"; do
  [ "$prev" != -o ] || out="$arg"
  [ "$prev" != -X ] || method="$arg"
  [ "$prev" != -D ] || HEADERS_OUT="$arg"
  case "$arg" in https://*) url="$arg" ;; esac
  prev="$arg"
done
[ "$method" != POST ] || body="$(cat)"
printf '%s %s %s\n' "$method" "$url" "$body" >> "$CURL_LOG"
case "${GRANTS:-ready}" in
  ready) grants='{"eligible":true,"at_limit":true,"next_grant_id":"g_two","grants":[{"id":"g_one","label":"Session reset","type":"session","resets_left":1,"usable_now":false,"use_requires_limit":true},{"id":"g_two","label":"Full reset","type":"full","resets_left":2,"usable_now":true,"ends_at":"2030-01-02T00:00:00Z"}]}' ;;
  none) grants='{"eligible":false,"ineligible_reason":"no_grant","grants":[]}' ;;
  malformed) grants='{"eligible":true,"grants":[{"id":"G ONE; rm","resets_left":1,"usable_now":true}]}' ;;
esac
case "$url" in
  *"/api/oauth/usage"*)
    if [ -n "${USAGE_STATUS:-}" ]; then printf '{}' > "$out"; printf '%s' "$USAGE_STATUS"; exit 0; fi
    printf '%s' "{\"limits\":[{\"kind\":\"session\",\"percent\":91},{\"kind\":\"weekly_all\",\"percent\":40}],
      \"extra_usage\":{\"is_enabled\":true,\"monthly_limit\":2500,\"used_credits\":1250,\"currency\":\"BRL\",\"spend_limit_reached\":false},
      \"spend\":{\"enabled\":true,\"used\":{\"amount_minor\":1250,\"currency\":\"BRL\",\"exponent\":2},\"limit\":{\"amount_minor\":2500,\"currency\":\"BRL\",\"exponent\":2},\"percent\":50},
      \"cedar_ember\":$grants}" > "$out"; printf 200 ;;
  *"/prepaid/credits")
    if [ "${PREPAID_STATUS:-}" = 200html ]; then printf '<html>maintenance</html>' > "$out"; printf 200; exit 0; fi
    if [ -n "${PREPAID_STATUS:-}" ]; then
      printf '{"error":{"type":"permission_error"}}' > "$out"
      [ "$PREPAID_STATUS" != 429 ] || printf 'HTTP/2 429\r\nretry-after: 900\r\n\r\n' > "$HEADERS_OUT"
      printf '%s' "$PREPAID_STATUS"; exit 0
    fi
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
for case in 401:auth_error 503:error; do
  out="$(USAGE_STATUS="${case%%:*}" bash "$ROOT/providers/reset-provider-limits" claude)"
  jq -e --arg r "${case##*:}" '.result == $r' <<<"$out" >/dev/null || fail "grant read HTTP ${case%%:*}: $out"
done
out="$(GRANTS=malformed bash "$ROOT/providers/reset-provider-limits" claude)"
jq -e '.result == "error" and (.message | test("malformed"))' <<<"$out" >/dev/null || fail "malformed grant: $out"
! grep -q '^POST ' "$CURL_LOG" || fail "claimed a malformed grant"
out="$(CLAIM=paused bash "$ROOT/providers/reset-provider-limits" claude)"
jq -e '.result == "unavailable" and .resetsLeft == 1' <<<"$out" >/dev/null || fail "unknown claim result: $out"

# --- Claude: no sign-in or no organization never reaches the API ---
: > "$CURL_LOG"
mkdir -p "$TMP/signed-out" "$TMP/no-org"
cp "$CLAUDE_CONFIG_DIR/.credentials.json" "$TMP/no-org/"
out="$(CLAUDE_CONFIG_DIR="$TMP/signed-out" bash "$ROOT/providers/reset-provider-limits" claude)"
jq -e '.result == "auth_error" and (.message | test("not signed in"))' <<<"$out" >/dev/null || fail "signed out: $out"
out="$(CLAUDE_CONFIG_DIR="$TMP/no-org" bash "$ROOT/providers/reset-provider-limits" claude)"
jq -e '.result == "unavailable" and (.message | test("organization"))' <<<"$out" >/dev/null || fail "no organization: $out"
[ ! -s "$CURL_LOG" ] || fail "reached the API without a sign-in or organization"

# --- Claude profiles resolve their own config dir ---
export AIOC_CLAUDE_PROFILES
AIOC_CLAUDE_PROFILES="$(jq -nc --arg d "$CLAUDE_CONFIG_DIR" '{"claude-work":{configDir:$d}}')"
out="$(env -u CLAUDE_CONFIG_DIR bash "$ROOT/providers/reset-provider-limits" claude-work)"
jq -e '.provider == "claude-work" and .result == "reset"' <<<"$out" >/dev/null || fail "profile reset: $out"
out="$(AIOC_CLAUDE_PROFILES='{"claude-rel":{"configDir":"relative/dir"}}' bash "$ROOT/providers/reset-provider-limits" claude-rel)"
jq -e '.result == "error" and (.message | test("absolute"))' <<<"$out" >/dev/null || fail "relative profile dir: $out"
out="$(bash "$ROOT/providers/reset-provider-limits" gemini)"
jq -e '.result == "error"' <<<"$out" >/dev/null || fail "unsupported provider accepted"

# --- Claude: a refused credits read is not asked again on every run (#123) ---
# A Team member gets 403 from prepaid/credits. Without a recorded refusal every
# run (one per monitor, every manual refresh) asked again and the account was
# soon rate limited on the usage endpoint.
team="$TMP/team"
mkdir -p "$team/projects"
cp "$CLAUDE_CONFIG_DIR/.credentials.json" "$CLAUDE_CONFIG_DIR/.claude.json" "$team/"
team_cache="$XDG_CACHE_HOME/AiOverviewControl/claude-profiles/$(printf '%s' "$team" | sha256sum | cut -d ' ' -f 1)"
prepaid_cache="$team_cache/claude-prepaid-cache.json"
team_run() { CLAUDE_CONFIG_DIR="$team" bash "$ROOT/providers/get-claude-usage"; }
prepaid_calls() { grep -c '/prepaid/credits' "$CURL_LOG" || true; }
# Moves the last credits answer $1 seconds into the past.
age_prepaid() { jq -c --argjson s "$1" '.checked_at -= $s' "$prepaid_cache" > "$prepaid_cache.new" && mv "$prepaid_cache.new" "$prepaid_cache"; }
# A first-ever refusal records itself, with no balance to keep.
PREPAID_STATUS=403 team_run >/dev/null
jq -e '.status == "403" and .data == null' "$prepaid_cache" >/dev/null || fail "first 403 not recorded"
rm -f "$prepaid_cache"
team_run >/dev/null
jq -e '.data.balance.money.amount_minor == 5500 and .status == "200"' "$prepaid_cache" >/dev/null || fail "team: first balance not cached"
# A 2.4.0 record ({cached_at, data}) names no organization, so it may hold
# another one's balance: it is re-checked at once and never shown.
jq -c '{cached_at: .checked_at, data: (.data | .balance.money.amount_minor = 99900)}' "$prepaid_cache" > "$TMP/legacy.json"
cp "$TMP/legacy.json" "$prepaid_cache"
: > "$CURL_LOG"
out="$(PREPAID_STATUS=403 team_run)"
[ "$(prepaid_calls)" -eq 1 ] || fail "2.4.0 record not re-checked"
grep -q '^CLAUDE_PREPAID=$' <<<"$out" || fail "2.4.0 record of an unknown organization shown: $(grep PREPAID <<<"$out")"
cp "$TMP/legacy.json" "$prepaid_cache"
grep -q '^CLAUDE_PREPAID={"balance":55,' <<<"$(team_run)" || fail "2.4.0 record not replaced by a fresh read"
jq -e '.org == "0b8d1d7e-1111-4222-8333-444455556666"' "$prepaid_cache" >/dev/null || fail "fresh read not scoped"
# A killed write leaves its temporary file behind and the last record whole:
# the next run under the lock sweeps the leftover.
cp "$prepaid_cache" "$TMP/prepaid-current.json"
printf '{"partial' > "$prepaid_cache.Ab12Cd"
age_prepaid 601
REAL_MV="$(command -v mv)"
printf '#!/usr/bin/env bash\ncase "${*: -1}" in *claude-prepaid-cache.json) exit 1 ;; esac\nexec %q "$@"\n' "$REAL_MV" > "$TMP/bin/mv"
chmod +x "$TMP/bin/mv"
cp "$prepaid_cache" "$TMP/prepaid-aged.json"
out="$(PREPAID_STATUS=500 team_run)"
rm -f "$TMP/bin/mv"
cmp -s "$prepaid_cache" "$TMP/prepaid-aged.json" || fail "a failed rename changed the credits record"
grep -q '^CLAUDE_PREPAID={"balance":55,' <<<"$out" || fail "a failed rename dropped the balance"
[ -z "$(find "$team_cache" -name 'claude-prepaid-cache.json.*')" ] || fail "credits temp files left behind"
cp "$TMP/prepaid-current.json" "$prepaid_cache"
age_prepaid 601
: > "$CURL_LOG"
out="$(PREPAID_STATUS=403 team_run)"
grep -q '^CLAUDE_PREPAID=$' <<<"$out" || fail "403 kept showing a balance the account cannot read: $(grep PREPAID <<<"$out")"
grep -q '^FIVE_HOUR_UTIL=91$' <<<"$out" || fail "403 on credits broke the usage card"
jq -e '.status == "403" and .data == null' "$prepaid_cache" >/dev/null || fail "403 not recorded: $(cat "$prepaid_cache")"
for _ in 1 2 3; do PREPAID_STATUS=403 team_run >/dev/null; done
rm -f "$team_cache/claude-usage-cache.json"
PREPAID_STATUS=403 team_run >/dev/null
[ "$(prepaid_calls)" -eq 1 ] || fail "403 asked again within a day: $(prepaid_calls) requests"
age_prepaid 3600
PREPAID_STATUS=403 team_run >/dev/null
[ "$(prepaid_calls)" -eq 1 ] || fail "403 asked again after an hour"
age_prepaid 86400
PREPAID_STATUS=404 team_run >/dev/null
[ "$(prepaid_calls)" -eq 2 ] || fail "refusal not re-checked after a day"
jq -e '.status == "404"' "$prepaid_cache" >/dev/null || fail "404 not recorded"
# Another organization's refusal is not honoured after a switch.
jq -n '{oauthAccount:{organizationUuid:"11111111-2222-4333-8444-555566667777"}}' > "$team/.claude.json"
: > "$CURL_LOG"
out="$(team_run)"
[ "$(prepaid_calls)" -eq 1 ] || fail "organization switch did not re-check credits"
grep -q '^CLAUDE_PREPAID={"balance":55,' <<<"$out" || fail "new organization balance: $(grep PREPAID <<<"$out")"
jq -e '.org == "11111111-2222-4333-8444-555566667777"' "$prepaid_cache" >/dev/null || fail "cache not scoped to the organization"
# A transient failure keeps the last good balance and is retried after 10 minutes.
age_prepaid 601
: > "$CURL_LOG"
out="$(PREPAID_STATUS=500 team_run)"
grep -q '^CLAUDE_PREPAID={"balance":55,' <<<"$out" || fail "500 dropped the last good balance"
PREPAID_STATUS=500 team_run >/dev/null
[ "$(prepaid_calls)" -eq 1 ] || fail "500 asked again within 10 minutes"
# A 200 whose body is not a credits object is a failure, not a balance.
age_prepaid 601
out="$(PREPAID_STATUS=200html team_run)"
grep -q '^CLAUDE_PREPAID={"balance":55,' <<<"$out" || fail "HTML 200 replaced the balance"
jq -e '.status == "000"' "$prepaid_cache" >/dev/null || fail "HTML 200 recorded as success: $(cat "$prepaid_cache")"
# A corrupt or empty record, or one stamped in the future (the clock moved
# back), is not trusted: credits are asked again at once.
for bad in 'not json' '' '{"checked_at":"soon","status":"403","data":null}'; do
  printf '%s' "$bad" > "$prepaid_cache"
  : > "$CURL_LOG"
  grep -q '^CLAUDE_PREPAID={"balance":55,' <<<"$(team_run)" || fail "record '$bad' not replaced by a fresh read"
  [ "$(prepaid_calls)" -eq 1 ] || fail "record '$bad' did not re-check credits"
done
printf '' > "$prepaid_cache"
PREPAID_STATUS=500 team_run >/dev/null
jq -e '.status == "500" and .data == null' "$prepaid_cache" >/dev/null || fail "500 over an empty record: $(cat "$prepaid_cache")"
jq -c '.checked_at += 7200 | .status = "403"' "$prepaid_cache" > "$prepaid_cache.new" && mv "$prepaid_cache.new" "$prepaid_cache"
: > "$CURL_LOG"
team_run >/dev/null
[ "$(prepaid_calls)" -eq 1 ] || fail "a refusal stamped in the future was honoured"
# A 429 on credits pauses the usage endpoint too: they share one rate limit.
age_prepaid 601
rm -f "$team_cache/claude-usage-cache.json"
: > "$CURL_LOG"
out="$(PREPAID_STATUS=429 team_run)"
jq -e '.status == "429" and .until > now + 800' "$team_cache/claude-usage-backoff.json" >/dev/null \
  || fail "429 on credits did not record the shared backoff"
until="$(jq -r .until "$team_cache/claude-usage-backoff.json")"
grep -q "^USAGE_RETRY_AT=$until$" <<<"$out" && grep -q '^USAGE_RETRY_REASON=rate_limited$' <<<"$out" \
  || fail "credits 429 did not name the next try: $(grep USAGE_RETRY <<<"$out")"
# The usage snapshot is still fresh: it is served, and the card still names
# the pause.
out="$(team_run)"
grep -q "^USAGE_RETRY_AT=$until$" <<<"$out" || fail "fresh snapshot hid the backoff: $(grep USAGE_RETRY <<<"$out")"
grep -q '^FIVE_HOUR_UTIL=91$' <<<"$out" || fail "fresh snapshot not served during the backoff"
rm -f "$team_cache/claude-usage-cache.json"
out="$(team_run)"
[ "$(grep -c '/api/oauth/usage' "$CURL_LOG")" -eq 1 ] || fail "usage asked again during the credits backoff"
[ "$(prepaid_calls)" -eq 1 ] || fail "credits asked again during the backoff"
grep -q '^CLAUDE_PREPAID={"balance":55,' <<<"$out" || fail "backoff dropped the last good balance"

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
for case in nothingToReset:nothing_to_reset noCredit:no_credit alreadyRedeemed:reset error:error pending:error; do
  out="$(CODEX_OUTCOME="${case%%:*}" bash "$ROOT/providers/reset-provider-limits" codex)"
  jq -e --arg r "${case##*:}" '.result == $r' <<<"$out" >/dev/null || fail "codex ${case%%:*}: $out"
done

# --- Codex: a missing CLI is reported, not run ---
mkdir -p "$TMP/no-codex"
ln -s "$(command -v jq)" "$TMP/no-codex/jq"
ln -s "$(command -v dirname)" "$TMP/no-codex/dirname"
out="$(PATH="$TMP/no-codex" "$BASH" "$ROOT/providers/reset-provider-limits" codex)"
jq -e '.result == "unavailable" and (.message | test("not installed"))' <<<"$out" >/dev/null || fail "missing codex: $out"

echo "OK: Claude/Codex credits, extra usage and consumable limit resets"
