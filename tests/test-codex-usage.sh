#!/usr/bin/env bash
# Codex usage adapter backend-launch discipline — fake-codex unit test.
#
# Issue #25: every adapter invocation used to spawn a fresh `codex
# app-server`, and each such startup runs a marketplace refresh round whose
# leftover clones filled disks. Verifies the counters that keep backend
# launches to one per refresh window:
#   - daemon/proxy backend is preferred, with spawn fallback
#   - a fresh cache answers without launching any backend
#   - a refresh already in flight serves the cache instead of overlapping
#   - CODEX_APP_SERVER_MODE=spawn still works for non-standalone installs
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

if [ "${CODEX_STUB_NO_DAEMON:-0}" = "1" ] && [ "$2" = "daemon" ]; then
  echo "managed standalone Codex install not found" >&2
  exit 1
fi

if [ "$2" = "daemon" ]; then
  # `app-server daemon start` is idempotent and succeeds silently.
  exit 0
fi

if [ "$1" = "app-server" ]; then
  # Answer the initialize / account / rateLimits conversation like the real
  # app-server (or `app-server proxy`) would, then keep reading until stdin
  # closes — the real backend exits on EOF, not after its last response.
  while IFS= read -r line; do
    id="$(printf '%s' "$line" | jq -r '.id // empty')"
    case "$id" in
      0) printf '{"id":0,"result":{}}\n';;
      1) printf '{"id":1,"result":{"account":{"email":"t@example.com","planType":"plus"}}}\n';;
      2) printf '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1790000000},"secondary":{"usedPercent":5,"windowDurationMins":10080,"resetsAt":1790000000}},"planType":"plus"}}\n';;
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

# 1. Daemon/proxy backend preferred: `daemon start` is probed, the conversation
#    goes through `app-server proxy`, and no bare app-server is spawned.
out="$(run_adapter)"
grep -q '^app-server daemon start$' "$STUB_LOG" || fail "daemon start not attempted"
grep -q '^app-server proxy$' "$STUB_LOG" || fail "proxy backend not used"
[ "$(grep -c '^app-server$' "$STUB_LOG" || true)" -eq 0 ] || fail "bare app-server spawned despite daemon"
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

# 4. Non-standalone installs: daemon start fails, the adapter falls back to a
#    direct spawn and still returns valid usage.
rm -f "$STUB_LOG" "$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json"
out="$(CODEX_STUB_NO_DAEMON=1 run_adapter)"
grep -q '^app-server$' "$STUB_LOG" || fail "spawn fallback not used when daemon unavailable"
[ "$(jq -r '.usage.primary.usedPercent' <<<"$out")" = "10" ] || fail "spawn fallback usage invalid"

# 5. Explicit spawn mode skips the daemon probe entirely.
rm -f "$STUB_LOG" "$XDG_CACHE_HOME/AiOverviewControl/codex-usage.json"
out="$(CODEX_APP_SERVER_MODE=spawn run_adapter)"
grep -q 'daemon start' "$STUB_LOG" && fail "spawn mode probed the daemon"
grep -q '^app-server$' "$STUB_LOG" || fail "spawn mode did not spawn"
[ "$(jq -r '.usage.primary.usedPercent' <<<"$out")" = "10" ] || fail "spawn mode usage invalid"

echo "OK: codex usage backend-launch discipline"
