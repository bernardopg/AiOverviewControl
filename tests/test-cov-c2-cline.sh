#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do case "${a[$i]}" in -o) out="${a[$((i+1))]}";; http*) url="${a[$i]}";; esac; done
case "$CASE:$url" in
  reject:*) printf '%s' '{"message":"denied"}' >"$out"; printf 403;;
  error:*) printf '%s' '{}' >"$out"; printf 502;;
  *:*/users/me) printf '%s' '{"success":true,"data":{"id":"u1","email":"x@example.test","balance":0,"organizations":[],"plan":null}}' >"$out"; printf 200;;
  *:*/balance) printf '%s' '{"balance":0}' >"$out"; printf 200;;
  *:*/plan) printf '%s' '{}' >"$out";;
  *:*/usages*) printf '%s' '{"items":[]}' >"$out"; printf 200;;
esac
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" CLINE_API_KEY=sk-test "$ROOT/providers/get-provider-usage" cline 2>/dev/null; }
out="$(run reject)"; jq -e '.[0].error.code == 403 and (.[0].error.message | contains("rejected"))' <<<"$out" >/dev/null || fail reject
out="$(run error)"; jq -e '.[0].error.code == 502' <<<"$out" >/dev/null || fail server-error
out="$(run ok)"; jq -e '.[0].usage.primary.usedPercent == 100' <<<"$out" >/dev/null || fail empty-balance
out="$(env -u CLINE_API_KEY PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" cline 2>/dev/null)"; jq -e '.[0].error' <<<"$out" >/dev/null || fail missing
echo 'OK: test-cov-c2-cline'
