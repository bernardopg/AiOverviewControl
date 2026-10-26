#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do case "${a[$i]}" in -o) out="${a[$((i+1))]}";; http*) url="${a[$i]}";; esac; done
case "$CASE:$url" in
  success:*credits) printf '%s' '{"windowLimits":{"fiveHour":{"used":4,"cap":2,"resetAt":1793000000000},"weekly":{"used":1,"cap":10}},"credits":{"monthlyCredits":20}}' >"$out"; printf 200;;
  success:*whoami) printf '%s' '{"user":{"name":"Ada","email":"ada@example.test"}}' >"$out";;
  success:*subscriptions) printf '%s' '{"data":{"planId":"individual-max-10x"}}' >"$out";;
  auth:*) printf '%s' '{}' >"$out"; printf 401;;
  fallback:*credits) printf '%s' '{broken' >"$out"; printf 200;;
  fallback:*) printf '%s' '{"data":[]}' >"$out"; printf 200;;
esac
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" COMMAND_CODE_API_KEY=sk-test "$ROOT/providers/get-provider-usage" cmd 2>/dev/null; }
out="$(run success)"; jq -e '.[0].usage.accountEmail == "Ada (ada@example.test)" and .[0].usage.primary.usedPercent == 100 and .[0].credits.remaining == "$20"' <<<"$out" >/dev/null || fail success
out="$(run auth)"; jq -e '.[0].error.code == 401' <<<"$out" >/dev/null || fail auth
out="$(run fallback)"; jq -e '.[0].source == "commandcode-models"' <<<"$out" >/dev/null || fail fallback
out="$(env -u COMMAND_CODE_API_KEY PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" commandcode 2>/dev/null)"; jq -e '.[0].error' <<<"$out" >/dev/null || fail missing-key
echo 'OK: test-cov-c2-commandcode'
