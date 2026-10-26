#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME" "$XDG_CONFIG_HOME/cursor" "$TMP/bin"
jwt(){ printf 'e30.%s.sig' "$(printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '=')"; }
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do case "${a[$i]}" in -o) out="${a[$((i+1))]}";; http*) url="${a[$i]}";; esac; done
case "$CASE" in
  reject) printf '{}' >"$out"; printf 401;;
  rate) printf '{}' >"$out"; printf 429;;
  failure) printf '{}' >"$out"; printf 503;;
  unlimited) printf '%s' '{"individualUsage":{"plan":{"enabled":false}}}' >"$out"; printf 200;;
  legacy) if [[ "$url" == */usage-summary ]]; then printf '%s' '{"individualUsage":{"plan":{"enabled":false}}}' >"$out"; else printf '%s' '{"gpt-4":{"maxRequestUsage":100,"numRequests":25},"startOfMonth":1790812800000}' >"$out"; fi; printf 200;;
esac
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" cursor 2>/dev/null; }
jq -n --arg token "$(jwt '{"sub":"subject","exp":1999999999}')" '{accessToken:$token}' >"$XDG_CONFIG_HOME/cursor/auth.json"
for c in reject rate failure; do out="$(run "$c")"; jq -e '.[0].error' <<<"$out" >/dev/null || fail "$c"; done
out="$(run unlimited)"; jq -e '.[0].provider == "cursor"' <<<"$out" >/dev/null || fail unlimited
out="$(run legacy)"; jq -e '.[0].usage.primary.windowMinutes == 43200' <<<"$out" >/dev/null || fail legacy
echo 'OK: test-cov-c2-cursor'
