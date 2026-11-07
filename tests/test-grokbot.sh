#!/usr/bin/env bash
# Grok Bot weekly quota adapter from a local desktop session fixture.
# Offline: OpenSSL SafeStorage fixture plus a curl stub. Never reads the developer session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_CACHE_HOME="$TMP/cache"
ARGV_LOG="$TMP/argv.log"
CFG_LOG="$TMP/cfg.log"
mkdir -p "$TMP/bin" "$TMP/fixtures" "$HOME" "$XDG_CONFIG_HOME/Grok Bot"

fail() { echo "FAIL: $*" >&2; exit 1; }

encrypt_v10() {
  local plaintext="$1"
  {
    printf 'v10'
    printf '%s' "$plaintext" | openssl enc -e -aes-128-cbc \
      -K fd621fe5a2b402539dfa147ca9272778 \
      -iv 20202020202020202020202020202020
  } | base64 | tr -d '\n'
}

SECRET_TOKEN="grokbot-sentinel-token-9999"
ENC_TOKEN="$(encrypt_v10 "$SECRET_TOKEN")"
ENC_PROFILE="$(encrypt_v10 '{"email":"dev@example.com"}')"

write_secrets() {
  local dir="$1" tok_b64="$2" prof_b64="${3:-}"
  mkdir -p "$dir"
  jq -nc \
    --arg tok "$tok_b64" \
    --arg prof "$prof_b64" \
    '{
      "cursor-accounts": ({
        active: "acct-1",
        accounts: {
          "acct-1": (
            {"cursor-access-token": $tok}
            + (if $prof == "" then {} else {"cursor-account-profile": $prof} end)
          )
        }
      } | tostring)
    }' > "$dir/sand-secrets.json"
}

write_secrets "$XDG_CONFIG_HOME/Grok Bot" "$ENC_TOKEN" "$ENC_PROFILE"

cat >"$TMP/fixtures/ok.json" <<'EOF'
{
  "currentPeriodStart": "2026-11-05T20:10:57.964Z",
  "nextResetTimestampUtc": "2026-11-12T20:10:57.964Z",
  "usagePercent": 57.9848,
  "grokPlanLabel": "Grok Bot Plan",
  "cursorPlanName": "Premium"
}
EOF

cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ARGV_LOG}"
out=""
write_code=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    --config|-K) cat "${args[$((i + 1))]}" >> "${CFG_LOG}" ;;
  esac
done
status=200
case "${GROKBOT_MODE:-ok}" in
  ok) cp "${GROKBOT_FIXTURES}/ok.json" "$out" ;;
  malformed) printf '{}' > "$out" ;;
  unauthorized) status=401; : > "$out" ;;
  limited) status=429; : > "$out" ;;
  down) status=503; : > "$out" ;;
  transport) exit 7 ;;
esac
if [ "$write_code" -eq 1 ]; then printf '%s' "$status"; fi
exit 0
STUB
chmod +x "$TMP/bin/curl"

run() {
  PATH="$TMP/bin:$PATH" ARGV_LOG="$ARGV_LOG" CFG_LOG="$CFG_LOG" GROKBOT_FIXTURES="$TMP/fixtures" \
    bash "$ROOT/providers/get-provider-usage" "${1:-grokbot}"
}

# 1. Default XDG_CONFIG_HOME discovery + Connect-RPC response + secret kept off argv.
: >"$ARGV_LOG"; : >"$CFG_LOG"
out="$(GROKBOT_MODE=ok run grokbot)"
[ "$(jq -r '.[0].provider' <<<"$out")" = "grokbot" ] || fail "provider id"
[ "$(jq -r '.[0].source' <<<"$out")" = "grokbot-desktop" ] || fail "source"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "57.98" ] || fail "usedPercent $(jq -r '.[0].usage.primary.usedPercent' <<<"$out")"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "10080" ] || fail "windowMinutes"
[ "$(jq -r '.[0].usage.primary.resetsAt' <<<"$out")" = "2026-11-12T20:10:57.964Z" ] || fail "resetsAt"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "null" ] || fail "resetDescription should be null for localization"
[ "$(jq -r '.[0].usage.identity.accountEmail' <<<"$out")" = "dev@example.com" ] || fail "accountEmail"
[ "$(jq -r '.[0].usage.identity.loginMethod' <<<"$out")" = "Grok Bot Plan (Premium)" ] || fail "loginMethod"
! grep -qF "$SECRET_TOKEN" "$ARGV_LOG" || fail "secret token leaked onto curl argv"
grep -qF "Authorization: Bearer $SECRET_TOKEN" "$CFG_LOG" || fail "secret token missing from curl --config"
! grep -qF "$SECRET_TOKEN" <<<"$out" || fail "secret token leaked into output"

# 2. Alias grok-bot and standalone wrapper get-grokbot-usage.
out="$(GROKBOT_MODE=ok run grok-bot)"
[ "$(jq -r '.[0].provider' <<<"$out")" = "grokbot" ] || fail "grok-bot alias"
out="$(PATH="$TMP/bin:$PATH" ARGV_LOG="$ARGV_LOG" CFG_LOG="$CFG_LOG" GROKBOT_FIXTURES="$TMP/fixtures" GROKBOT_MODE=ok bash "$ROOT/providers/get-grokbot-usage")"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "57.98" ] || fail "get-grokbot-usage stub"

# 3. Sentry email fallback when cursor-account-profile is absent.
ALT_DIR="$TMP/alt-grokbot"
write_secrets "$ALT_DIR" "$ENC_TOKEN" ""
mkdir -p "$ALT_DIR/sentry"
printf '{"scope":{"user":{"email":"sentry@example.com"}}}\n' > "$ALT_DIR/sentry/scope_v3.json"
out="$(GROKBOT_CONFIG_DIR="$ALT_DIR" GROKBOT_MODE=ok run grokbot)"
[ "$(jq -r '.[0].usage.accountEmail' <<<"$out")" = "sentry@example.com" ] || fail "sentry email fallback"

# 4. Offline persistence snapshot fallback (active reset vs expired reset).
mkdir -p "$ALT_DIR/sand-client-persistence"
cat >"$ALT_DIR/sand-client-persistence/cache.blob" <<'EOF'
{
  "schemaVersion": 1,
  "value": {
    "kind": "weekly-usage",
    "reading": {
      "readAtMs": 1794000000000,
      "usage": {
        "percentUsed": 44.25,
        "nextResetMs": 4102444800000,
        "grokPlanLabel": "Grok Bot Plan",
        "unifiedPlanName": "Premium"
      }
    }
  }
}
EOF
out="$(GROKBOT_CONFIG_DIR="$ALT_DIR" GROKBOT_MODE=transport run grokbot)"
[ "$(jq -r '.[0].source' <<<"$out")" = "grokbot-offline-cache" ] || fail "offline cache source"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "44.25" ] || fail "offline cache percent"
[ "$(jq -r '.[0].usage.updatedAt' <<<"$out")" = "2026-11-06T21:20:00Z" ] || fail "offline cache preserved readAtMs"

# HTTP 401 must report auth expiry rather than masking it with offline cache.
out="$(GROKBOT_CONFIG_DIR="$ALT_DIR" GROKBOT_MODE=unauthorized run grokbot)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "401" ] || fail "401 reported even with offline cache"

# Expired cached window clamps to 0%.
cat >"$ALT_DIR/sand-client-persistence/cache.blob" <<'EOF'
{"schemaVersion":1,"value":{"reading":{"readAtMs":1700000000000,"usage":{"percentUsed":88,"nextResetMs":1700003600000,"grokPlanLabel":"Grok Bot Plan"}}}}
EOF
out="$(GROKBOT_CONFIG_DIR="$ALT_DIR" GROKBOT_MODE=down run grokbot)"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "0" ] || fail "expired offline window clamps to 0"
[ "$(jq -r '.[0].usage.primary.resetsAt' <<<"$out")" = "null" ] || fail "expired offline window clears resetsAt"

# 5. Structured errors without offline cache.
rm -rf "$ALT_DIR/sand-client-persistence"
out="$(GROKBOT_CONFIG_DIR="$ALT_DIR" GROKBOT_MODE=malformed run grokbot)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "1" ] || fail "malformed schema error"
out="$(GROKBOT_CONFIG_DIR="$ALT_DIR" GROKBOT_MODE=limited run grokbot)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "429" ] || fail "429 error"
out="$(GROKBOT_CONFIG_DIR="$ALT_DIR" GROKBOT_MODE=down run grokbot)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "503" ] || fail "503 runtime error"

# 6. Corrupt token and missing sign-in.
BAD_DIR="$TMP/bad-grokbot"
write_secrets "$BAD_DIR" "not-valid-base64" ""
out="$(GROKBOT_CONFIG_DIR="$BAD_DIR" GROKBOT_MODE=ok run grokbot)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "2" ] || fail "corrupt token error"
out="$(GROKBOT_CONFIG_DIR="$TMP/missing-grokbot" GROKBOT_MODE=ok run grokbot)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "2" ] || fail "missing sign-in error"

# 7. Provider health follows GROKBOT_CONFIG_DIR.
health="$(GROKBOT_CONFIG_DIR="$ALT_DIR" bash "$ROOT/providers/get-provider-health" grokbot)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "health ready"
health="$(GROKBOT_CONFIG_DIR="$TMP/missing-grokbot" bash "$ROOT/providers/get-provider-health" grok-bot)"
[ "$(jq -r '.[0].status' <<<"$health")" = "missing" ] || fail "health missing"

echo "OK: Grok Bot weekly quota, SafeStorage decryption, offline persistence fallback and health"
