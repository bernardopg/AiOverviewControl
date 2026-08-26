#!/usr/bin/env bash
# Command Code subscription quota tracking — fake-curl unit test.
# Verifies the alpha billing endpoint maps to 5h (primary) + weekly (secondary)
# + monthly USD credits, with graceful fallback to /provider/v1/models on alpha failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HDR_LOG="$TMP/headers.log"
mkdir -p "$TMP/bin"

# Fake curl that mimics real curl behavior:
#   -o file   → writes body to file, suppresses body on stdout
#   -w FORMAT → writes FORMAT to stdout (independent of -o)
# When both -o and -w are present, body goes to file and FORMAT goes to stdout —
# exactly like real curl.
#
# The stub MUST exit 0 in every branch — the parent script runs curls without
# -w for identity enrichment and treats a non-zero exit as a network error,
# overwriting the body file with an empty string. Forcing `exit 0` at the end
# keeps that error-handling path inert for our fixture-backed tests.
#
# The heredoc MUST be single-quoted ('STUB') so $@, ${args[@]}, etc. are written
# literally and expanded at stub-execution time, not heredoc-write time.
make_stub() {
  local pattern="$1"
  cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""
url=""
write_code=0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    -H) printf '%s\n' "${args[$((i + 1))]}" >> "${HDR_LOG:-/dev/null}" ;;
    http*) url="${args[$i]}" ;;
  esac
done
case "$url" in
__PATTERN__
esac
if [ "$write_code" -eq 1 ]; then printf '200'; fi
exit 0
STUB
  # Replace the __PATTERN__ placeholder with the actual case body for this test.
  python3 -c "
import sys
fn = '$TMP/bin/curl'
with open(fn) as f: s = f.read()
s = s.replace('__PATTERN__', '''$pattern''')
with open(fn, 'w') as f: f.write(s)
"
  chmod +x "$TMP/bin/curl"
}

# 1. Happy path — alpha billing returns quota + whoami + subscriptions.
# The literal $out / $ROOT in the case arms are the source of truth for the
# running stub (set at execution time, not heredoc-write time); shellcheck
# flags them as SC2016 because they sit inside a single-quoted shell fragment
# we deliberately only expand with help. The braces below keep SC2016 scoped
# to these three lines without disabling it for the whole file.
# shellcheck disable=SC2016
make_stub '  *alpha/billing/credits*)      [ -n "$out" ] && cp "'"$ROOT"'/tests/fixtures/commandcode-billing.json"      "$out" ;;
  *alpha/billing/subscriptions*)[ -n "$out" ] && cp "'"$ROOT"'/tests/fixtures/commandcode-subscriptions.json" "$out" ;;
  *alpha/whoami*)               [ -n "$out" ] && cp "'"$ROOT"'/tests/fixtures/commandcode-whoami.json"       "$out" ;;'

run() { PATH="$TMP/bin:$PATH" HDR_LOG="$HDR_LOG" "$@" "$ROOT/providers/get-provider-usage" commandcode 2>/dev/null; }
fail() { echo "FAIL: $1" >&2; exit 1; }

out="$(run env -u COMMAND_CODE_API_KEY COMMAND_CODE_API_KEY=user_test)"
[ "$(jq -r '.[0].source'                            <<<"$out")" = "commandcode-alpha" ]             || fail "source"
[ "$(jq -r '.[0].usage.primary.windowMinutes'       <<<"$out")" = "300" ]                          || fail "5h minutes"
[ "$(jq -r '.[0].usage.primary.resetDescription'    <<<"$out")" = "5h" ]                           || fail "5h label"
[ "$(jq -r '.[0].usage.primary.usedPercent|floor'   <<<"$out")" = "30" ]                           || fail "5h percent (4.20/14)"
[ "$(jq -r '.[0].usage.secondary.windowMinutes'     <<<"$out")" = "10080" ]                        || fail "weekly minutes"
[ "$(jq -r '.[0].usage.secondary.resetDescription'  <<<"$out")" = "weekly" ]                       || fail "weekly label"
# Literal $32.50 is a quoted string to compare against jq -r output.
# shellcheck disable=SC2016
[ "$(jq -r '.[0].credits.remaining'                 <<<"$out")" = '$32.50' ]                       || fail "monthly USD credits"
[ "$(jq -r '.[0].usage.identity.accountEmail'       <<<"$out")" = "Test User (test@example.com)" ] || fail "identity from whoami"
# The real API key must reach every endpoint — guards against placeholder
# headers (a literal "Bearer ***" once slipped through and 401'd every call).
[ "$(grep -c '^Authorization: Bearer user_test$' "$HDR_LOG")" -ge 3 ]                                || fail "auth header forwarded to alpha endpoints"

# 2. A `cmd login` credential is a safe fallback for graphical sessions, which
# normally do not source a user's shell startup file. It must also be reported
# as ready by the settings health helper.
CLI_HOME="$TMP/cli-home"
mkdir -p "$CLI_HOME/.commandcode"
printf '%s\n' '{"apiKey":"cli_test"}' > "$CLI_HOME/.commandcode/auth.json"
chmod 600 "$CLI_HOME/.commandcode/auth.json"
: > "$HDR_LOG"
out="$(run env -u COMMAND_CODE_API_KEY HOME="$CLI_HOME")"
[ "$(jq -r '.[0].source' <<<"$out")" = "commandcode-alpha" ] || fail "CLI auth source"
grep -q '^Authorization: Bearer cli_test$' "$HDR_LOG" || fail "CLI auth header"
health="$(env -u COMMAND_CODE_API_KEY HOME="$CLI_HOME" "$ROOT/providers/get-provider-health" commandcode 2>/dev/null)"
[ "$(jq -r '.[0].status' <<<"$health")" = "ready" ] || fail "CLI auth health"

# 3. No supported credential source.
EMPTY_HOME="$TMP/empty-home"
mkdir -p "$EMPTY_HOME"
out="$(run env -u COMMAND_CODE_API_KEY HOME="$EMPTY_HOME")"
[ "$(jq -r '.[0].error.kind' <<<"$out")" = "provider" ] || fail "no-key error kind"

# 4. Alpha billing 404 → fallback to /provider/v1/models.
# shellcheck disable=SC2016
make_stub '  *provider/v1/models*)         [ -n "$out" ] && cp "'"$ROOT"'/tests/fixtures/commandcode-models.json"       "$out" ;;'
: > "$HDR_LOG"
out="$(run env -u COMMAND_CODE_API_KEY COMMAND_CODE_API_KEY=user_test)"
[ "$(jq -r '.[0].source' <<<"$out")" = "commandcode-models" ] || fail "fallback source"
grep -q '^Authorization: Bearer user_test$' "$HDR_LOG" || fail "auth header forwarded to models fallback"

echo "OK: test-commandcode"
