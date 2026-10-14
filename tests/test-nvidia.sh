#!/usr/bin/env bash
# NVIDIA key verification — fake-curl fixture test. The invalid-key fixture is
# the live NGC response to a bogus nvapi- key; the valid one follows the
# SakCallerInfoResponse schema of the official ngcsdk package.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin"

# Fake curl: logs argv and stdin so the test can prove the key travels only in
# the request body.
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; write_code=0; args=("$@")
printf 'ARGV %s\n' "$*" >>"$FAKE_LOG"
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
  esac
done
printf 'STDIN %s\n' "$(cat)" >>"$FAKE_LOG"
[ -z "$out" ] || cp "$FAKE_BODY" "$out"
[ "$write_code" -eq 0 ] || printf '%s' "$FAKE_STATUS"
exit 0
STUB
chmod +x "$TMP/bin/curl"

fail() { echo "FAIL: $1" >&2; exit 1; }
run() {
  : >"$TMP/log"
  PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_BODY="$1" FAKE_STATUS="$2" \
    NVIDIA_API_KEY="${3-nvapi-secret}" "$ROOT/providers/get-provider-usage" nvidia 2>/dev/null
}

# 1. Valid personal key: verified, owner shown.
out="$(run "$ROOT/tests/fixtures/nvidia-caller-info.json" 200)"
[ "$(jq -r '.[0].source' <<<"$out")" = "nvidia-ngc" ] || fail "source"
[ "$(jq -r '.[0].usage.accountEmail' <<<"$out")" = "dev@example.com" ] || fail "owner"
jq -e '.[0].usage.primary.resetDescription | startswith("Personal key verified")' <<<"$out" >/dev/null || fail "key type"
grep -q 'ARGV .*https://api.ngc.nvidia.com/v3/keys/get-caller-info' "$TMP/log" || fail "caller-info URL"
grep -qx 'STDIN nvapi-secret' "$TMP/log" || fail "key on stdin"
! grep -q 'ARGV .*nvapi-secret' "$TMP/log" || fail "key leaked into argv"

# 2. Invalid key is an error, not a green card.
out="$(run "$ROOT/tests/fixtures/nvidia-caller-info-invalid.json" 401)"
[ "$(jq -r '.[0].error.code' <<<"$out")" = "401" ] || fail "invalid key"

# 3. Key service down: degrade to an unverified note, not an error.
printf '%s\n' '<html>bad gateway</html>' >"$TMP/502.html"
out="$(run "$TMP/502.html" 502)"
[ "$(jq -r '.[0].source' <<<"$out")" = "nvidia-nim" ] || fail "fallback source"
[ "$(jq -r '.[0].error' <<<"$out")" = "null" ] || fail "fallback is not an error"

# 4. No key.
out="$(run "$TMP/502.html" 200 "")"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "missing key"

echo "OK: test-nvidia"
