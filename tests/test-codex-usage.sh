#!/usr/bin/env bash
# Codex usage adapter backend-launch discipline — fake-codex unit test.
#
# Issue #25: each `codex app-server` startup runs a marketplace refresh.
# Cache and single-flight locking keep launches to one per refresh window.
# The daemon's control socket speaks WebSocket, not stdio JSONL, so never
# send JSONL through `codex app-server proxy`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin"

STUB_LOG="$TMP/stub-codex.log"
export STUB_LOG

cat > "$TMP/bin/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"

if [ "$1" = "app-server" ] && [ "$#" -eq 1 ]; then
  if [ "${CODEX_STUB_SILENT_ALL:-0}" = "1" ]; then
    while IFS= read -r _; do :; done
    exit 0
  fi
  # Answer the initialize / account / rateLimits conversation like the real
  # stdio app-server, then keep reading until stdin closes.
  while IFS= read -r line; do
    id="$(printf '%s' "$line" | jq -r '.id // empty')"
    case "$id" in
      0) printf '{"id":0,"result":{}}\n';;
      1) if [ "${CODEX_STUB_NO_ACCOUNT:-0}" = "1" ]; then printf '{"id":1,"result":{"account":null}}\n'; else printf '{"id":1,"result":{"account":{"email":"t@example.com","planType":"plus"}}}\n'; fi;;
      2) if [ "${CODEX_STUB_NO_ACCOUNT:-0}" = "1" ]; then printf '{"id":2,"result":{}}\n'; else printf '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1790000000},"secondary":{"usedPercent":5,"windowDurationMins":10080,"resetsAt":1790000000}},"planType":"plus"}}\n'; fi;;
    esac
  done
  exit 0
fi

exit 127
SH
chmod +x "$TMP/bin/codex"

run_adapter() { PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-codex-usage"; }
stub_calls() { wc -l <"$STUB_LOG" 2>/dev/null || printf '0'; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. The adapter speaks JSONL only to the stdio backend, never the WS proxy.
out="$(run_adapter)"
[ "$(stub_calls)" -eq 1 ] || fail "adapter attempted an unsupported daemon/proxy backend"
grep -q '^app-server$' "$STUB_LOG" || fail "stdio backend not used"
[ "$(jq -r '.usage.primary.usedPercent' <<<"$out")" = "10" ] || fail "primary window missing"
[ "$(jq -r '.usage.secondary.windowMinutes' <<<"$out")" = "10080" ] || fail "secondary window missing"

# 2. Freshness gate: an immediate second run serves the cache and launches
#    nothing at all.
calls_before="$(stub_calls)"
out="$(run_adapter)"
[ "$(jq -r '.source' <<<"$out")" = "codex-app-server-cache" ] || fail "fresh cache not served"
[ "$(stub_calls)" = "$calls_before" ] || fail "fresh cache run touched the backend"

# 3. A refresh already in flight: with the gate disabled and the lock held,
#    the stale cache is served rather than starting a second backend. Same
#    without any cache: bounded wait, then a structured error.
sleep 61 2>/dev/null || { jq -cn --argjson d "$(jq '.data' "$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json")" '{cached_at:(now|floor - 120),data:$d}' >"$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json"; }
flock "$TMP/cache/AiOverviewControl/codex-usage.lock" sleep 3 &
holder=$!
sleep 0.3
calls_before="$(stub_calls)"
out="$(CODEX_FRESH_TTL=0 CODEX_LOCK_WAIT=2 run_adapter)"
[ "$(jq -r '.source' <<<"$out")" = "codex-app-server-cache" ] || fail "in-flight refresh did not serve cache"
[ "$(stub_calls)" = "$calls_before" ] || fail "in-flight refresh spawned a second backend"

rm -f "$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json"
out="$(CODEX_FRESH_TTL=0 CODEX_LOCK_WAIT=1 run_adapter)"
[ "$(jq -r '.error.code' <<<"$out")" = "4" ] || fail "lock wait did not fail with code 4"
wait "$holder" 2>/dev/null || true

# 4. No response from stdio is a transport failure, not a logout.
rm -f "$STUB_LOG" "$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json"
out="$(CODEX_STUB_SILENT_ALL=1 run_adapter)"
[ "$(jq -r '.error.code' <<<"$out")" = "3" ] || fail "missing account response reported logout"

# 5. An explicit null account response still reports the real login failure.
out="$(CODEX_STUB_NO_ACCOUNT=1 run_adapter)"
[ "$(jq -r '.error.code' <<<"$out")" = "2" ] || fail "explicit unauthenticated account not reported"

echo "OK: codex usage backend-launch discipline"
