#!/usr/bin/env bash
# Cursor plan usage from the dashboard session the IDE already stored.
# Offline: a sqlite fixture plus a curl stub. Never reads the developer session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
HDR_LOG="$TMP/headers.log"
mkdir -p "$TMP/bin" "$TMP/fixtures"

python3 - <<'PY' >"$TMP/token"
import base64, json, sys
def b64(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()
exp = int(sys.argv[1]) if len(sys.argv) > 1 else 9999999999
print(b64({"alg": "none"}) + "." + b64({"sub": "auth0|user_test", "exp": exp}) + ".sig", end="")
PY
TOKEN="$(cat "$TMP/token")"

make_db() {
  local db="$1" exp_token="$2"
  rm -f "$db"
  sqlite3 "$db" "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT);"
  sqlite3 "$db" "INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', '$(printf '%s' "$exp_token" | sed "s/'/''/g")');"
  sqlite3 "$db" "INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/cachedEmail', 'dev@example.com');"
  sqlite3 "$db" "INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/stripeMembershipType', 'pro');"
}

cat >"$TMP/fixtures/summary.json" <<'EOF'
{
  "billingCycleStart": "2026-09-18T18:22:06.000Z",
  "billingCycleEnd": "2026-10-18T18:22:06.000Z",
  "membershipType": "pro",
  "isUnlimited": false,
  "individualUsage": {
    "plan": {
      "enabled": true,
      "used": 2000,
      "limit": 2000,
      "remaining": 0,
      "autoPercentUsed": 14.06,
      "apiPercentUsed": 0,
      "totalPercentUsed": 12.96
    },
    "onDemand": {"enabled": false, "used": 0, "limit": null}
  }
}
EOF

cat >"$TMP/fixtures/summary-ondemand.json" <<'EOF'
{
  "billingCycleStart": "2026-09-01T00:00:00.000Z",
  "billingCycleEnd": "2026-10-01T00:00:00.000Z",
  "membershipType": "pro",
  "individualUsage": {
    "plan": {"enabled": true, "used": 10, "limit": 100, "autoPercentUsed": 4, "apiPercentUsed": 1},
    "onDemand": {"enabled": true, "used": 90, "limit": 100}
  }
}
EOF

cat >"$TMP/fixtures/summary-empty.json" <<'EOF'
{"membershipType":"pro","individualUsage":{"plan":{"enabled":false,"autoPercentUsed":0,"apiPercentUsed":0,"totalPercentUsed":0}}}
EOF

cat >"$TMP/fixtures/legacy.json" <<'EOF'
{"gpt-4":{"numRequests":250,"maxRequestUsage":500},"startOfMonth":"2026-09-01T00:00:00.000Z"}
EOF

cat >"$TMP/fixtures/unlimited.json" <<'EOF'
{"membershipType":"ultra","isUnlimited":true}
EOF

cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""
url=""
write_code=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    -H) printf '%s\n' "${args[$((i + 1))]}" >>"${HDR_LOG:-/dev/null}" ;;
    http*) url="${args[$i]}" ;;
  esac
done
status=200
case "$url" in
  *api/usage-summary*)
    case "${CURSOR_MODE:-ok}" in
      ok) cp "${CURSOR_FIXTURES}/summary.json" "$out" ;;
      ondemand) cp "${CURSOR_FIXTURES}/summary-ondemand.json" "$out" ;;
      empty) cp "${CURSOR_FIXTURES}/summary-empty.json" "$out" ;;
      unlimited) cp "${CURSOR_FIXTURES}/unlimited.json" "$out" ;;
      malformed) printf '{' >"$out" ;;
      unauthorized) status=401; : >"$out" ;;
      limited) status=429; : >"$out" ;;
      down) status=500; : >"$out" ;;
    esac
    ;;
  *api/usage\?*)
    cp "${CURSOR_FIXTURES}/legacy.json" "$out"
    ;;
esac
if [ "$write_code" -eq 1 ]; then printf '%s' "$status"; fi
exit 0
STUB
chmod +x "$TMP/bin/curl"

run() {
  PATH="$TMP/bin:$PATH" HDR_LOG="$HDR_LOG" CURSOR_FIXTURES="$TMP/fixtures" \
    bash "$ROOT/providers/get-provider-usage" cursor
}
fail() { echo "FAIL: $1" >&2; exit 1; }

make_db "$TMP/state.vscdb" "$TOKEN"
export CURSOR_STATE_DB="$TMP/state.vscdb"
export CURSOR_AUTH_FILE=""

# 1. The included screen is the two pools. used/limit is 2000/2000 here and
#    must not become a 100% Plan bar over a 14% Cursor Models pool.
: >"$HDR_LOG"
out="$(CURSOR_MODE=ok run)"
[ "$(jq -r '.[0].source' <<<"$out")" = "cursor-dashboard" ] || fail "source"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "Cursor Models" ] || fail "cursor models label"
awk 'BEGIN{exit !(ARGV[1] > 14 && ARGV[1] < 14.1)}' "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" || fail "cursor models percent"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "43200" ] || fail "cycle minutes"
[ "$(jq -r '.[0].usage.primary.resetsAt' <<<"$out")" = "2026-10-18T18:22:06Z" ] || fail "reset $(jq -r '.[0].usage.primary.resetsAt' <<<"$out")"
[ "$(jq -r '.[0].usage.secondary.resetDescription' <<<"$out")" = "Other Models" ] || fail "other models label"
[ "$(jq -r '.[0].usage.secondary.usedPercent' <<<"$out")" = "0" ] || fail "other models percent"
[ "$(jq -r '.[0].usage.tertiary' <<<"$out")" = "null" ] || fail "no plan bar"
jq -e '[.[0].usage.primary, .[0].usage.secondary, .[0].usage.tertiary] | map(select(. != null) | .usedPercent) | all(. < 50)' <<<"$out" >/dev/null || fail "allowance ratio leaked into a bar"
[ "$(jq -r '.[0].usage.identity.accountEmail' <<<"$out")" = "dev@example.com" ] || fail "email"
[ "$(jq -r '.[0].usage.identity.loginMethod' <<<"$out")" = "pro" ] || fail "plan name"
grep -q '^Cookie: WorkosCursorSessionToken=auth0%7Cuser_test%3A%3A'"$TOKEN"'$' "$HDR_LOG" || fail "session cookie"
grep -q '^Origin: https://cursor.com$' "$HDR_LOG" || fail "origin"
! grep -q 'Authorization:' "$HDR_LOG" || fail "bearer header"
jq -e '.[0] | tostring | contains("user_test") | not' <<<"$out" >/dev/null || fail "token leaked into output"

# 2. On-demand is the third bar, after the two included pools.
out="$(CURSOR_MODE=ondemand run)"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "4" ] || fail "ondemand cursor models"
[ "$(jq -r '.[0].usage.secondary.usedPercent' <<<"$out")" = "1" ] || fail "ondemand other models"
[ "$(jq -r '.[0].usage.tertiary.resetDescription' <<<"$out")" = "On-demand" ] || fail "ondemand label"
[ "$(jq -r '.[0].usage.tertiary.usedPercent' <<<"$out")" = "90" ] || fail "ondemand percent"

# 3. A plan the account does not own falls through to the request-quota route.
out="$(CURSOR_MODE=empty run)"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "50" ] || fail "legacy percent"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "Plan" ] || fail "legacy label"
[ "$(jq -r '.[0].usage.primary.resetsAt' <<<"$out")" = "2026-10-01T00:00:00Z" ] || fail "legacy reset $(jq -r '.[0].usage.primary.resetsAt' <<<"$out")"
[ "$(jq -r '.[0].usage.secondary' <<<"$out")" = "null" ] || fail "legacy secondary"

# 4. Unlimited plans do not invent a percentage window.
out="$(CURSOR_MODE=unlimited run)"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "Unlimited" ] || fail "unlimited label"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "null" ] || fail "unlimited window"

# 5. Transport and auth failures stay structured and do not invent 0% usage.
out="$(CURSOR_MODE=unauthorized run)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "401" ] || fail "401"
out="$(CURSOR_MODE=limited run)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "429" ] || fail "429"
out="$(CURSOR_MODE=malformed run)"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "malformed"
out="$(CURSOR_MODE=down run)"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "runtime" ] || fail "http 500"

# 6. An expired session is reported without a dashboard request.
python3 -c 'import base64,json
def b64(o):
    return base64.urlsafe_b64encode(json.dumps(o,separators=(",",":")).encode()).rstrip(b"=").decode()
open("'"$TMP/expired"'","w").write(b64({"alg":"none"})+"."+b64({"sub":"auth0|user_test","exp":1})+".sig")'
make_db "$TMP/expired.vscdb" "$(cat "$TMP/expired")"
: >"$HDR_LOG"
out="$(CURSOR_STATE_DB="$TMP/expired.vscdb" CURSOR_MODE=ok run)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "401" ] || fail "expired token"
[ ! -s "$HDR_LOG" ] || fail "expired token still called the dashboard"

# 7. No local session.
out="$(CURSOR_STATE_DB="$TMP/missing.vscdb" CURSOR_AUTH_FILE="$TMP/missing.json" CURSOR_MODE=ok run)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "2" ] || fail "signed out"

# 8. Health follows the same pinned session and does not look at the real IDE.
health="$(CURSOR_STATE_DB="$TMP/state.vscdb" CURSOR_AUTH_FILE="" bash "$ROOT/providers/get-provider-health" cursor)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "health ready"
health="$(CURSOR_STATE_DB="$TMP/missing.vscdb" CURSOR_AUTH_FILE="$TMP/missing.json" bash "$ROOT/providers/get-provider-health" cursor)"
[ "$(jq -r '.[0].status' <<<"$health")" = "missing" ] || fail "health missing"

echo "ok"
