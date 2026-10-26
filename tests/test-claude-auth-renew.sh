#!/usr/bin/env bash
# get-claude-usage renews an expired Claude OAuth access token through the
# installed CLI (`claude auth status`), never by itself:
#  - an expired token is renewed before the usage request
#  - a rejected (401) token gets one renewal and one retry
#  - a token the CLI cannot renew stays an authentication error, and a
#    cooldown stops one CLI process per poll
#  - an unexpired, accepted token never spawns the CLI
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CLAUDE_CONFIG_DIR="$TMP/claude" AIOC_NO_LITELLM=1 TZ=UTC
export AUTH_LOG="$TMP/auth.log" CURL_LOG="$TMP/curl.log"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/projects" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake CLI: `auth status` writes RENEW_TO as the new access token, as the real
# CLI does after a refresh; an empty RENEW_TO leaves the file untouched.
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  printf '%s\n' "$CLAUDE_CONFIG_DIR" >> "$AUTH_LOG"
  if [ -n "${RENEW_TO:-}" ]; then
    jq --arg t "$RENEW_TO" '.claudeAiOauth.accessToken = $t | .claudeAiOauth.expiresAt = (now * 1000 + 28800000 | floor)' \
      "$CLAUDE_CONFIG_DIR/.credentials.json" > "$CLAUDE_CONFIG_DIR/.credentials.new"
    mv "$CLAUDE_CONFIG_DIR/.credentials.new" "$CLAUDE_CONFIG_DIR/.credentials.json"
  fi
  exit 0
fi
printf '2.5.1 (fixture)\n'
SH
# Fake curl: accepts only the token named in VALID_TOKEN.
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; prev=""; auth=""
for arg in "$@"; do
  [ "$prev" != -o ] || out="$arg"
  case "$arg" in "Authorization: Bearer "*) auth="${arg#Authorization: Bearer }" ;; esac
  prev="$arg"
done
printf '%s\n' "$auth" >> "$CURL_LOG"
if [ "$auth" = "$VALID_TOKEN" ]; then
  printf '%s' '{"limits":[{"kind":"session","percent":42},{"kind":"weekly_all","percent":7}]}' > "$out"; printf 200
else
  printf '%s' '{"error":{"type":"authentication_error"}}' > "$out"; printf 401
fi
SH
chmod +x "$TMP/bin/claude" "$TMP/bin/curl"

creds() {  # creds TOKEN EXPIRES_AT_MS
  jq -n --arg t "$1" --argjson e "$2" \
    '{claudeAiOauth:{accessToken:$t,refreshToken:"fixture-refresh",expiresAt:$e,subscriptionType:"pro"}}' \
    > "$CLAUDE_CONFIG_DIR/.credentials.json"
}
reset() { rm -rf "$XDG_CACHE_HOME"; : > "$AUTH_LOG"; : > "$CURL_LOG"; }
run() { bash "$ROOT/providers/get-claude-usage"; }
now_ms="$(( $(date +%s) * 1000 ))"

# --- Expired token after a reboot: renewed before the request ---
reset; creds old-token $(( now_ms - 3600000 ))
out="$(VALID_TOKEN=new-token RENEW_TO=new-token run)"
grep -q '^FIVE_HOUR_UTIL=42$' <<<"$out" || fail "expired token was not renewed"
grep -q '^USAGE_ERROR_KIND=$' <<<"$out" || fail "renewed token still reported an error"
[ "$(wc -l < "$AUTH_LOG")" -eq 1 ] || fail "expected one CLI renewal"
[ "$(cat "$AUTH_LOG")" = "$CLAUDE_CONFIG_DIR" ] || fail "renewal ran for another config dir"
[ "$(cat "$CURL_LOG")" = "new-token" ] || fail "expired token was sent to the API"

# --- Token revoked before its expiry: one renewal and one retry ---
reset; creds old-token $(( now_ms + 3600000 ))
out="$(VALID_TOKEN=new-token RENEW_TO=new-token run)"
grep -q '^FIVE_HOUR_UTIL=42$' <<<"$out" || fail "rejected token was not renewed and retried"
[ "$(tr '\n' ' ' < "$CURL_LOG")" = "old-token new-token " ] || fail "wrong request sequence: $(cat "$CURL_LOG")"

# --- The CLI cannot renew: authentication error, then a cooldown ---
reset; creds old-token $(( now_ms - 3600000 ))
out="$(VALID_TOKEN=new-token RENEW_TO='' run)"
grep -q '^USAGE_ERROR_KIND=authentication$' <<<"$out" || fail "unrenewable token not reported as authentication"
out="$(VALID_TOKEN=new-token RENEW_TO='' run)"
grep -q '^USAGE_ERROR_KIND=authentication$' <<<"$out" || fail "second poll lost the authentication error"
[ "$(wc -l < "$AUTH_LOG")" -eq 1 ] || fail "cooldown did not stop repeated CLI renewals"
out="$(VALID_TOKEN=new-token RENEW_TO=new-token CLAUDE_AUTH_RENEW_COOLDOWN=0 run)"
grep -q '^FIVE_HOUR_UTIL=42$' <<<"$out" || fail "renewal after the cooldown failed"

# --- Valid token: the CLI is never spawned ---
reset; creds good-token $(( now_ms + 3600000 ))
out="$(VALID_TOKEN=good-token RENEW_TO=other run)"
grep -q '^FIVE_HOUR_UTIL=42$' <<<"$out" || fail "valid token request failed"
[ ! -s "$AUTH_LOG" ] || fail "CLI spawned for a valid token"

echo "OK: Claude OAuth renewal through the CLI"
