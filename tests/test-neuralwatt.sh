#!/usr/bin/env bash
# Neuralwatt quota adapter — fake-curl fixture test. The base fixture is the
# documented /v1/quota example (docs.neuralwatt.com/api/quota); variants are
# derived from it with jq so every branch stays tied to the real schema.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin"
FIXTURE="$ROOT/tests/fixtures/neuralwatt-quota.json"

# Fake curl: writes $FAKE_BODY to the -o file, prints $FAKE_STATUS for -w and
# logs headers and the URL, like the real transport the adapter uses.
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Adapters pass secret headers through --config files; expand them back to -H.
_cfg=(); while [ $# -gt 0 ]; do if [ "$1" = --config ] || [ "$1" = -K ]; then while IFS= read -r _l; do case "$_l" in 'header = "'*) _v="${_l#header = \"}"; _cfg+=(-H "${_v%\"}") ;; esac; done < "$2"; shift 2; else _cfg+=("$1"); shift; fi; done; set -- "${_cfg[@]}"
out=""; write_code=0; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    -H) printf 'H %s\n' "${args[$((i + 1))]}" >>"$FAKE_LOG" ;;
    http*) printf 'U %s\n' "${args[$i]}" >>"$FAKE_LOG" ;;
  esac
done
[ -z "$out" ] || cp "$FAKE_BODY" "$out"
[ "$write_code" -eq 0 ] || printf '%s' "${FAKE_STATUS:-200}"
exit 0
STUB
chmod +x "$TMP/bin/curl"

fail() { echo "FAIL: $1" >&2; exit 1; }
run() {
  : >"$TMP/log"
  PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_BODY="$1" FAKE_STATUS="${2:-200}" \
    NEURALWATT_API_KEY="${3-sk-test}" "$ROOT/providers/get-provider-usage" neuralwatt 2>/dev/null
}

# 1. Subscription account: kWh allowance is the primary window, the prepaid
# balance second; no key allowance configured.
out="$(run "$FIXTURE")"
[ "$(jq -r '.[0].source' <<<"$out")" = "neuralwatt-api" ] || fail "source"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "43200" ] || fail "monthly kWh window"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "null" ] || fail "standard window keeps label null"
[ "$(jq -r '.[0].usage.primary.usedPercent | floor' <<<"$out")" = "69" ] || fail "kWh percent (13.9023/20)"
[ "$(jq -r '.[0].usage.primary.resetsAt' <<<"$out")" = "2026-05-11T05:05:25Z" ] || fail "period end"
[ "$(jq -r '.[0].usage.primary.displayValue' <<<"$out")" = "13.90 / 20.00 kWh" ] || fail "kWh display"
[ "$(jq -r '.[0].usage.secondary.resetDescription' <<<"$out")" = "Balance" ] || fail "balance label"
[ "$(jq -r '.[0].usage.secondary.usedPercent | floor' <<<"$out")" = "37" ] || fail "balance percent (19.66/52.34)"
# shellcheck disable=SC2016 # literal dollar amounts
[ "$(jq -r '.[0].usage.secondary.displayValue' <<<"$out")" = '$32.68 / $52.34' ] || fail "balance display"
[ "$(jq -r '.[0].usage.tertiary' <<<"$out")" = "null" ] || fail "no key allowance"
# shellcheck disable=SC2016
[ "$(jq -r '.[0].credits.remaining' <<<"$out")" = '$32.68' ] || fail "credits"
[ "$(jq -r '.[0].usage.accountEmail' <<<"$out")" = "Neuralwatt standard" ] || fail "identity"
[ "$(jq -r '.[0].usage.updatedAt' <<<"$out")" = "2026-04-16T18:30:00Z" ] || fail "snapshot time"
grep -qx 'H Authorization: Bearer sk-test' "$TMP/log" || fail "auth header"
grep -qx 'U https://api.neuralwatt.com/v1/quota' "$TMP/log" || fail "quota URL"

# 2. Prepaid-only account with a blocked per-key allowance: balance becomes the
# primary window and a blocked key reads as exhausted.
jq '.subscription = null | .key.allowance = {limit_usd: 10, period: "weekly", spent_usd: 10.5, remaining_usd: 0, blocked: true}' \
  "$FIXTURE" >"$TMP/prepaid.json"
out="$(run "$TMP/prepaid.json")"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "Balance" ] || fail "prepaid primary"
[ "$(jq -r '.[0].usage.secondary.resetDescription' <<<"$out")" = "Key limit · weekly" ] || fail "key allowance label"
[ "$(jq -r '.[0].usage.secondary.usedPercent' <<<"$out")" = "100" ] || fail "blocked key"
[ "$(jq -r '.[0].usage.accountEmail' <<<"$out")" = "Neuralwatt prepaid" ] || fail "prepaid identity"

# 3. Overage and a non-active subscription status are surfaced.
jq '.subscription.in_overage = true | .subscription.kwh_used = 21.5 | .subscription.status = "past_due"' \
  "$FIXTURE" >"$TMP/overage.json"
out="$(run "$TMP/overage.json")"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "100" ] || fail "overage percent"
[ "$(jq -r '.[0].usage.accountEmail' <<<"$out")" = "Neuralwatt standard (past_due)" ] || fail "status in identity"

# 4. Errors: missing key, rejected key, rate limit.
out="$(run "$FIXTURE" 200 "")"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "missing key"
printf '%s\n' '{"detail":"Invalid API key"}' >"$TMP/401.json"
out="$(run "$TMP/401.json" 401)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "401" ] || fail "401 code"
[ "$(jq -r '.[0].error.message' <<<"$out")" = "Invalid API key" ] || fail "401 message"
out="$(run "$TMP/401.json" 429)"
jq -e '.[0].error.message | test("rate limited")' <<<"$out" >/dev/null || fail "429 message"

# 5. Settings health.
health="$(NEURALWATT_API_KEY=sk-test "$ROOT/providers/get-provider-health" neuralwatt)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "health ready"
health="$(env -u NEURALWATT_API_KEY "$ROOT/providers/get-provider-health" neuralwatt)"
[ "$(jq -r '.[0].status' <<<"$health")" = "missing" ] || fail "health missing"

echo "OK: test-neuralwatt"
