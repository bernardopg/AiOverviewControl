#!/usr/bin/env bash
# QwenCloud adapter — fixture test with a fake `qwencloud` CLI. The real
# adapter shells out to the official CLI (auth status / subscription status /
# usage summary, all --format json and read-only); the fake dispatches on the
# subcommand pair and cats per-command fixture files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$TMP/bin" "$TMP/nobin" "$TMP/fix"
# HOME with the CLI only under the npm prefix (fallback discovery), and an
# empty HOME where no fallback exists.
FAKE_HOME="$TMP/home"
NO_HOME="$TMP/nohome"
mkdir -p "$FAKE_HOME/.local/share/npm/bin" "$NO_HOME"

cat >"$TMP/bin/qwencloud" <<'STUB'
#!/usr/bin/env bash
# Fake qwencloud CLI: the adapter always calls `<sub> <sub2> --format json`.
case "$1 $2" in
  "auth status")         cat "$FAKE_AUTH" ;;
  "subscription status") cat "$FAKE_SUB" ;;
  "usage summary")       cat "$FAKE_SUMMARY" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/qwencloud"

export FAKE_AUTH="$TMP/fix/auth.json" FAKE_SUB="$TMP/fix/sub.json" FAKE_SUMMARY="$TMP/fix/summary.json"

cat >"$FAKE_AUTH" <<'EOF'
{
  "authenticated": true,
  "auth_mode": "device_flow",
  "user": {"aliyunId": "t*@example.com"},
  "token": {"expires_at": "2026-12-24T03:05:29Z", "scopes": ["inference:read", "usage:read"]}
}
EOF

cat >"$FAKE_SUB" <<'EOF'
{
  "individual": {
    "status": "active",
    "name": "Pro",
    "monthlyCredits": {"usedPct": 42.3456789, "resetTime": "2026-12-08T16:00:00.000Z", "remainingPct": 57.6543211}
  },
  "team": {"status": "not_subscribed"}
}
EOF

cat >"$FAKE_SUMMARY" <<'EOF'
{
  "period": {"from": "2026-11-01", "to": "2026-11-22"},
  "free_tier": [
    {"model_id": "qwen4-max", "quota": {"remaining": 900000, "total": 1000000, "unit": "tokens", "used_pct": 10, "status": "valid", "resetDate": "2027-02-14T06:00:00.000Z"}},
    {"model_id": "qwen3-tts-flash", "quota": {"remaining": 0, "total": 10000, "unit": "characters", "used_pct": 100, "status": "exhaust", "resetDate": "2027-02-07T06:00:00.000Z"}},
    {"model_id": "wan2.1-vace-plus", "quota": null}
  ],
  "coding_plan": {"subscribed": false},
  "token_plan": {"subscribed": false},
  "pay_as_you_go": {"models": [], "total": {"cost": 3.5, "currency": "USD"}}
}
EOF

usage() { PATH="$1:/usr/bin:/bin" bash "$ROOT/providers/get-provider-usage" qwencloud; }
field() { jq -r ".[0].$1" <<<"$out"; }

# Happy path: Token Plan Pro primary, PAYG secondary, free tier tertiary.
out="$(usage "$TMP/bin")"
[ "$(field provider)" = "qwencloud" ] || fail "provider"
[ "$(field source)" = "qwencloud-cli" ] || fail "source"
[ "$(field usage.accountEmail)" = "t*@example.com" ] || fail "account email"
[ "$(field usage.primary.resetDescription)" = "Token Plan" ] || fail "primary label"
[ "$(field usage.primary.hasLimit)" = "true" ] || fail "primary hasLimit"
[ "$(field usage.primary.displayValue)" = "42.3% · Token Plan Pro" ] || fail "primary value: $(field usage.primary.displayValue)"
[ "$(field usage.primary.resetsAt)" = "2026-12-08T16:00:00Z" ] || fail "reset normalized: $(field usage.primary.resetsAt)"
jq -e '.[0].usage.primary.usedPercent > 42.3 and .[0].usage.primary.usedPercent < 42.4' <<<"$out" >/dev/null \
  || fail "primary usedPercent: $(field usage.primary.usedPercent)"
[ "$(field usage.secondary.resetDescription)" = "PAYG this month" ] || fail "secondary label"
[ "$(field usage.secondary.displayValue)" = '$3.50' ] || fail "secondary value: $(field usage.secondary.displayValue)"
[ "$(field usage.secondary.hasLimit)" = "false" ] || fail "secondary is a plain reading"
[ "$(field usage.tertiary.resetDescription)" = "Free tier" ] || fail "tertiary label"
[ "$(field usage.tertiary.displayValue)" = "1/3 models" ] || fail "tertiary value: $(field usage.tertiary.displayValue)"
[ "$(field credits.remaining)" = "57.7% left" ] || fail "credits: $(field credits.remaining)"

# The alias reaches the same adapter.
out="$(PATH="$TMP/bin:/usr/bin:/bin" bash "$ROOT/providers/get-provider-usage" qwen-cloud)"
[ "$(field provider)" = "qwencloud" ] || fail "alias qwen-cloud"

# CLI discoverable outside PATH under the npm prefix: the widget's PATH is
# leaner than an interactive shell's.
cp "$TMP/bin/qwencloud" "$FAKE_HOME/.local/share/npm/bin/qwencloud"
out="$(HOME="$FAKE_HOME" usage "$TMP/nobin")"
[ "$(field provider)" = "qwencloud" ] || fail "CLI found under the npm prefix"
[ "$(field usage.primary.resetDescription)" = "Token Plan" ] || fail "fallback CLI output"

# Team subscription is used when there is no active individual one.
jq '.individual.status = "not_subscribed" | .team = {status: "active", monthlyCredits: {usedPct: 10, resetTime: "2026-12-01T00:00:00.000Z", remainingPct: 90}}' \
  "$FAKE_SUB" >"$TMP/fix/sub-team.json" && mv "$TMP/fix/sub-team.json" "$FAKE_SUB"
out="$(usage "$TMP/bin")"
[ "$(field usage.primary.displayValue)" = "10% · Token Plan Team" ] || fail "team plan: $(field usage.primary.displayValue)"

# No subscription at all: the free tier leads and the plan slot says so.
jq '.team.status = "not_subscribed"' "$FAKE_SUB" >"$TMP/fix/sub-none.json" && mv "$TMP/fix/sub-none.json" "$FAKE_SUB"
out="$(usage "$TMP/bin")"
[ "$(field usage.primary.resetDescription)" = "Free tier" ] || fail "free tier leads without a plan"
[ "$(field usage.tertiary.displayValue)" = "Not subscribed" ] || fail "plan note: $(field usage.tertiary.displayValue)"
[ "$(field credits.remaining)" = "pay-as-you-go" ] || fail "payg credits note"

# No subscription and no free tier: PAYG leads.
jq '.free_tier = []' "$FAKE_SUMMARY" >"$TMP/fix/sum-nofree.json" && mv "$TMP/fix/sum-nofree.json" "$FAKE_SUMMARY"
out="$(usage "$TMP/bin")"
[ "$(field usage.primary.resetDescription)" = "PAYG this month" ] || fail "payg leads when nothing else exists"
[ "$(field usage.secondary.displayValue)" = "No free-tier quota" ] || fail "free tier note"

# A broken subscription response degrades instead of failing the card.
printf 'not json' >"$FAKE_SUB"
out="$(usage "$TMP/bin")"
[ "$(field provider)" = "qwencloud" ] || fail "broken sub still yields a card"
[ "$(field usage.primary.resetDescription)" = "PAYG this month" ] || fail "broken sub degrades to payg"

# Not signed in: actionable error.
cat >"$FAKE_AUTH" <<'EOF'
{"authenticated": false}
EOF
out="$(usage "$TMP/bin")"
[ "$(field error.kind)" = "provider" ] || fail "signed-out error kind"
case "$(field error.message)" in
  *"qwencloud auth login"*) ;;
  *) fail "signed-out message: $(field error.message)" ;;
esac

# CLI missing: install hint. An empty HOME, or the real home's npm prefix
# would satisfy the fallback on machines that have the CLI installed.
out="$(HOME="$NO_HOME" usage "$TMP/nobin")"
[ "$(field error.kind)" = "provider" ] || fail "missing CLI error kind"
case "$(field error.message)" in
  *"@qwencloud/qwencloud-cli"*) ;;
  *) fail "missing CLI message: $(field error.message)" ;;
esac

# Readiness: the CLI on PATH, or at a known install location.
health() { PATH="$1:/usr/bin:/bin" bash "$ROOT/providers/get-provider-health" qwencloud; }
[ "$(health "$TMP/bin" | jq -r '.[0].status')" = "ready" ] || fail "health ready"
[ "$(HOME="$FAKE_HOME" health "$TMP/nobin" | jq -r '.[0].status')" = "ready" ] || fail "health via npm prefix"
[ "$(HOME="$NO_HOME" health "$TMP/nobin" | jq -r '.[0].status')" = "missing" ] || fail "health missing"
[ "$(HOME="$NO_HOME" health "$TMP/nobin" | jq -r '.[0].detail')" = "qwencloud CLI (npm i -g @qwencloud/qwencloud-cli)" ] || fail "health detail"

# The stub entrypoint reaches the same adapter.
PATH="$TMP/bin:/usr/bin:/bin" "$ROOT/providers/get-qwencloud-usage" \
  | jq -e '.[0].provider == "qwencloud"' >/dev/null || fail "get-qwencloud-usage stub"

echo "OK: test-qwencloud"
