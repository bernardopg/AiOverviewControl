#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_DATA_HOME="$TMP/data"; mkdir -p "$HOME" "$TMP/bin" "$TMP/data/opencode"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do case "${a[$i]}" in -o) out="${a[$((i+1))]}";; http*) url="${a[$i]}";; esac; done
if [[ "$url" == */models ]]; then printf '%s' '{"data":[]}' >"$out"; printf 200; exit; fi
case "$CASE" in ok) printf '%s' '{"rollingUsage":{"usagePercent":40,"resetInSec":1},"weeklyUsage":{"usagePercent":50,"resetInSec":2},"monthlyUsage":{"usagePercent":60,"resetInSec":3},"useBalance":true}' >"$out"; printf 200;; bad) printf '%s' '{}' >"$out"; printf 200;; auth) printf '%s' '{}' >"$out"; printf 403;; esac
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" OPENCODE_API_KEY=sk-test "$ROOT/providers/get-provider-usage" opencode 2>/dev/null; }
out="$(run ok)"; jq -e '.[0].usage.primary.usedPercent == 40 and (.[0].credits.remaining | contains("balance"))' <<<"$out" >/dev/null || fail usage
out="$(run bad)"; jq -e '.[0].source == "opencode-models"' <<<"$out" >/dev/null || fail fallback
out="$(run auth)"; jq -e '.[0].error.code == 403' <<<"$out" >/dev/null || fail auth
out="$(env -u OPENCODE_API_KEY PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" opencode 2>/dev/null)"; jq -e '.[0].error' <<<"$out" >/dev/null || fail missing-key
echo 'OK: test-cov-c2-opencode'
