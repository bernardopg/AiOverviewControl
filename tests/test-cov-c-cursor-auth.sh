#!/usr/bin/env bash
# Cursor auth-file discovery, malformed tokens, and expired-session handling.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/cursor" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = -o ] && out="${args[$((i+1))]}"; done
printf '%s\n' '{"individualUsage":{"plan":{"enabled":true,"totalPercentUsed":18}}}' >"$out"
printf 200
STUB
chmod +x "$TMP/bin/curl"
fail() { echo "FAIL: $1" >&2; exit 1; }
jwt() { printf 'e30.%s.sig' "$(printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '=')"; }
run() { PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" cursor 2>/dev/null; }

# Auth-file token without exp, with identity from the sibling CLI config.
jq -n --arg token "$(jwt '{"sub":"user/one"}')" '{accessToken:$token}' >"$XDG_CONFIG_HOME/cursor/auth.json"
jq -n '{authInfo:{email:"cursor@example.com",displayName:"Cursor User"}}' >"$XDG_CONFIG_HOME/cursor/cli-config.json"
out="$(run)"
jq -e '.[0].usage.accountEmail == "cursor@example.com" and .[0].usage.primary.usedPercent == 18' <<<"$out" >/dev/null || fail "auth file / sibling identity"

# Invalid JWT payload and invalid JSON auth file resolve as no sign-in.
printf '%s\n' '{"accessToken":"not-a-jwt"}' >"$XDG_CONFIG_HOME/cursor/auth.json"
out="$(run)"
jq -e '.[0].error.message | contains("No Cursor sign-in")' <<<"$out" >/dev/null || fail "invalid token"
printf '%s\n' '{broken' >"$XDG_CONFIG_HOME/cursor/auth.json"
out="$(run)"
jq -e '.[0].error.message | contains("No Cursor sign-in")' <<<"$out" >/dev/null || fail "malformed auth JSON"

# Expired auth files are rejected before curl.
jq -n --arg token "$(jwt "{\"sub\":\"expired\",\"exp\":$(( $(date +%s) - 10 ))}")" '{accessToken:$token}' >"$XDG_CONFIG_HOME/cursor/auth.json"
out="$(run)"
jq -e '.[0].error.code == 401 and (.[0].error.message | contains("expired"))' <<<"$out" >/dev/null || fail "expired auth token"
echo "OK: test-cov-c-cursor-auth"
