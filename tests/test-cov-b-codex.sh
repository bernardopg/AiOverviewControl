#!/usr/bin/env bash
# Offline coverage for Codex refresh retries, stale cache, and native forwarding.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" CALLS="$TMP/calls"
mkdir -p "$HOME" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/codex" <<'SH'
#!/usr/bin/env bash
[ "$#" = 1 ] && [ "$1" = app-server ] || exit 9
n=0; [ ! -f "$CALLS" ] || n="$(cat "$CALLS")"; n=$((n + 1)); printf '%s' "$n" > "$CALLS"
while IFS= read -r line; do
  id="$(jq -r '.id // empty' <<<"$line")"
  case "$id" in
    0) printf '{"id":0,"result":{}}\n' ;;
    1) printf '{"id":1,"result":{"account":{"email":"cov@example.invalid","planType":"pro"}}}\n' ;;
    2)
      if [ "${CODEX_MODE:-success}" = retry ] && [ "$n" = 1 ]; then printf '{"id":2,"result":{}}\n'
      elif [ "${CODEX_MODE:-success}" = reject ]; then printf '{"id":2,"error":{"message":"limits unavailable"}}\n'
      else printf '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":125,"resetsAt":1790000000},"individualLimit":12},"rateLimitResetCredits":{"availableCount":"0"}}}\n'; fi ;;
  esac
done
SH
chmod +x "$TMP/bin/codex"
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { CODEX_FRESH_TTL=0 bash "$ROOT/providers/get-codex-usage"; }

# Retry after an account response with incomplete limits; verify all fallback fields.
out="$(CODEX_MODE=retry run)"
[ "$(cat "$CALLS")" = 2 ] || fail "incomplete response did not retry once"
jq -e '.provider == "codex" and .usage.identity.accountEmail == "cov@example.invalid" and .usage.loginMethod == "pro" and .usage.primary.usedPercent == 125 and .usage.primary.windowMinutes == null and .usage.secondary == null and .credits.balance == 0 and .credits.remaining == "0"' <<<"$out" >/dev/null || fail "Codex successful result mapping"

# Stale-but-usable cache wins over a provider failure, then expires after 15 minutes.
CACHE="$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json"
jq -cn --argjson d "$out" '{cached_at:(now|floor - 120),data:$d}' > "$CACHE"
: > "$CALLS"
out="$(CODEX_MODE=reject run)"
jq -e '.source == "codex-app-server-cache"' <<<"$out" >/dev/null || fail "stale cache fallback"

jq -cn --argjson d "$out" '{cached_at:(now|floor - 901),data:$d}' > "$CACHE"
: > "$CALLS"
out="$(CODEX_MODE=reject run)"
jq -e '.error.code == 3 and .error.message == "limits unavailable"' <<<"$out" >/dev/null || fail "expired cache should report backend error"

# Native adapter reports a missing executable, then forwards the helper exactly.
json_error() { jq -cn --arg p "$1" --arg s "$2" --argjson c "$3" --arg k "$4" --arg m "$5" '{provider:$p,source:$s,error:{code:$c,kind:$k,message:$m}}'; }
source "$ROOT/providers/native/codex.bash"
CODEX_SCRIPT="$TMP/missing"
out="$(fetch_codex_native)"
jq -e '.error.code == 127 and .provider == "codex"' <<<"$out" >/dev/null || fail "missing Codex helper"
cat > "$TMP/helper" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"provider":"codex","source":"fixture"}'
SH
chmod +x "$TMP/helper"
export CODEX_SCRIPT="$TMP/helper"
out="$(fetch_codex_native)"
jq -e '.provider == "codex" and .source == "fixture"' <<<"$out" >/dev/null || fail "Codex native forwarding"

echo 'OK: Codex refresh, cache, and native coverage'
