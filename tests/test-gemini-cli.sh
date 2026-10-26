#!/usr/bin/env bash
# Gemini adapter — Gemini CLI quota through the Code Assist API, in-memory
# token renewal, ineligible accounts and the API-key fallback. Fixtures follow
# LoadCodeAssistResponse / RetrieveUserQuotaResponse in google-gemini/gemini-cli
# (packages/core/src/code_assist/types.ts); the ineligible reason is the live
# message Google returns for retired individual accounts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$TMP/bin" "$HOME/.gemini"
FIX="$ROOT/tests/fixtures"
REFRESH="1//fixture-refresh-token-0000"

# Fake curl routed by URL: token, loadCodeAssist, retrieveUserQuota, models.
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
case " $* " in *"$FAKE_REFRESH"*) : >"$FAKE_DIR/argv-leak" ;; esac
_cfg=(); while [ $# -gt 0 ]; do if [ "$1" = --config ] || [ "$1" = -K ]; then while IFS= read -r _l; do case "$_l" in 'header = "'*) _v="${_l#header = \"}"; _cfg+=(-H "${_v%\"}") ;; esac; done < "$2"; shift 2; else _cfg+=("$1"); shift; fi; done; set -- "${_cfg[@]}"
out=""; write_code=0; route=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    -H) printf 'H %s\n' "${args[$((i + 1))]}" >>"$FAKE_LOG" ;;
    --data) printf 'D %s\n' "${args[$((i + 1))]}" >>"$FAKE_LOG" ;;
    --data-urlencode)
      case "${args[$((i + 1))]}" in *@-) printf 'S %s\n' "$(cat)" >>"$FAKE_LOG" ;; esac ;;
    *oauth2.googleapis.com/token) route=TOKEN ;;
    *:loadCodeAssist) route=LOAD ;;
    *:retrieveUserQuota) route=QUOTA ;;
    *generativelanguage.googleapis.com*) route=MODELS ;;
  esac
done
printf 'R %s\n' "$route" >>"$FAKE_LOG"
body_var="FAKE_$route"; status_var="FAKE_STATUS_$route"
[ -z "$out" ] || cp "${!body_var:-/dev/null}" "$out"
[ "$write_code" -eq 0 ] || printf '%s' "${!status_var:-200}"
exit 0
STUB
chmod +x "$TMP/bin/curl"

printf '{"access_token":"renewedtoken","expires_in":3599,"token_type":"Bearer"}' >"$TMP/token.json"
printf '{"error":{"code":403,"message":"The caller does not have permission","status":"PERMISSION_DENIED"}}' >"$TMP/denied.json"
printf '{"models":[]}' >"$TMP/models.json"
printf '{"active":"dev@example.com","old":[]}' >"$HOME/.gemini/google_accounts.json"

fail() { echo "FAIL: $1" >&2; exit 1; }
check() { jq -e "$2" <<<"$3" >/dev/null || fail "$1: $3"; }
creds() { # creds <expiry_ms>
  jq -n --arg refresh "$REFRESH" --argjson expiry "$1" \
    '{access_token:"cachedtoken", refresh_token:$refresh, expiry_date:$expiry, token_type:"Bearer"}' \
    >"$HOME/.gemini/oauth_creds.json"
}
run() {
  : >"$TMP/log"; rm -f "$TMP/argv-leak"
  local out
  out="$(env -u GEMINI_API_KEY -u GOOGLE_API_KEY -u GOOGLE_GENERATIVE_AI_API_KEY \
    -u GOOGLE_CLOUD_PROJECT -u GOOGLE_CLOUD_PROJECT_ID \
    PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_LOG="$TMP/log" FAKE_REFRESH="$REFRESH" \
    FAKE_TOKEN="$TMP/token.json" FAKE_MODELS="$TMP/models.json" "$@" \
    "$ROOT/providers/get-provider-usage" gemini 2>/dev/null)"
  [ ! -e "$TMP/argv-leak" ] || fail "refresh token passed to curl on the command line"
  case "$out" in *"$REFRESH"*|*renewedtoken*|*cachedtoken*) fail "token leaked into output" ;; esac
  printf '%s' "$out"
}
future=$(( ($(date +%s) + 3600) * 1000 ))
past=$(( ($(date +%s) - 3600) * 1000 ))

# 1. Valid token, Standard license: per-model daily buckets, most used first.
creds "$future"
out="$(run FAKE_LOAD="$FIX/gemini-load-standard.json" FAKE_QUOTA="$FIX/gemini-quota.json")"
check "quota" '.[0].provider == "gemini" and .[0].source == "gemini-cli"
  and .[0].usage.accountEmail == "dev@example.com · Gemini Code Assist" and .[0].usage.loginMethod == "oauth"
  and (.[0].usage.primary.usedPercent | round) == 60 and .[0].usage.primary.windowMinutes == 1440
  and .[0].usage.primary.resetDescription == "Daily · gemini-3.1-pro-preview"
  and .[0].usage.primary.resetsAt == "2026-10-27T07:00:00Z"
  and (.[0].usage.secondary.usedPercent | round) == 18
  and .[0].usage.secondary.resetDescription == "Daily · gemini-3.5-flash"
  and (.[0].usage.tertiary.usedPercent | round) == 1' "$out"
grep -qx 'H Authorization: Bearer cachedtoken' "$TMP/log" || fail "cached token not used"
grep -q '^R TOKEN' "$TMP/log" && fail "unexpired token was renewed"
grep -qx 'D {"project":"fixture-project-123"}' "$TMP/log" || fail "quota request lacks the project"

# 2. Expired token: renewed in memory over stdin, never written back.
creds "$past"
before="$(sha256sum "$HOME/.gemini/oauth_creds.json")"
out="$(run FAKE_LOAD="$FIX/gemini-load-standard.json" FAKE_QUOTA="$FIX/gemini-quota.json")"
check "renewed quota" '(.[0].usage.primary.usedPercent | round) == 60' "$out"
grep -qx "S $REFRESH" "$TMP/log" || fail "refresh token not sent on stdin"
grep -qx 'H Authorization: Bearer renewedtoken' "$TMP/log" || fail "renewed token not used"
[ "$before" = "$(sha256sum "$HOME/.gemini/oauth_creds.json")" ] || fail "credentials file was modified"

# 3. GOOGLE_CLOUD_PROJECT overrides the project from loadCodeAssist.
creds "$future"
out="$(run GOOGLE_CLOUD_PROJECT=my-gcp-project FAKE_LOAD="$FIX/gemini-load-standard.json" FAKE_QUOTA="$FIX/gemini-quota.json")"
grep -qx 'D {"project":"my-gcp-project"}' "$TMP/log" || fail "GOOGLE_CLOUD_PROJECT ignored"

# 4. Retired individual account: Google's reason, not a bare "authenticated".
out="$(run FAKE_LOAD="$FIX/gemini-load-ineligible.json")"
check "ineligible" '.[0].error.code == 403 and .[0].error.kind == "provider"
  and (.[0].error.message | contains("no longer supported"))' "$out"
grep -q '^R QUOTA' "$TMP/log" && fail "quota requested without a project"

# 5. ... but a configured API key still produces a card.
out="$(run GEMINI_API_KEY=fixture-key FAKE_LOAD="$FIX/gemini-load-ineligible.json")"
check "ineligible with key" '.[0].source == "gemini-api-key" and .[0].usage.primary.resetDescription == "Quota visible in AI Studio"' "$out"
grep -qx 'H x-goog-api-key: fixture-key' "$TMP/log" || fail "API key header"

# 6. Quota API refusal is reported with Google's message.
out="$(run FAKE_LOAD="$FIX/gemini-load-standard.json" FAKE_QUOTA="$TMP/denied.json" FAKE_STATUS_QUOTA=403)"
check "quota 403" '.[0].error.code == 403 and .[0].error.message == "The caller does not have permission"' "$out"

# 7. A failed renewal falls back to the sign-in note instead of an error.
creds "$past"
out="$(run FAKE_STATUS_TOKEN=400)"
check "renewal failure" '.[0].source == "gemini-cli" and .[0].usage.primary.resetDescription == "Gemini CLI authenticated"' "$out"
grep -q '^R LOAD' "$TMP/log" && fail "Code Assist called without a token"

# 8. Nothing configured.
rm -f "$HOME/.gemini/oauth_creds.json"
out="$(run)"
check "unconfigured" '.[0].error.code == 2 and .[0].source == "gemini-local"' "$out"

echo 'OK: Gemini CLI quota, token renewal, ineligible accounts and API-key fallback'
