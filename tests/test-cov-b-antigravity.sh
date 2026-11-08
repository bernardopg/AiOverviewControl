#!/usr/bin/env bash
# Offline coverage for Antigravity fixture parsing and HTTP error mapping.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$HOME" "$XDG_CACHE_HOME"
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { bash "$ROOT/providers/get-provider-usage" antigravity ''; }

out="$(ANTIGRAVITY_RESPONSE_FILE="$ROOT/tests/fixtures/antigravity-valid.json" ANTIGRAVITY_ACCOUNT_EMAIL=fixture@example.invalid run)"
jq -e '.[0].provider=="antigravity" and .[0].error==null and .[0].usage.accountEmail=="fixture@example.invalid" and (.[0].accounts[0].windows|length)>0 and .[0].credits.remaining=="1 account"' <<<"$out" >/dev/null || fail "legacy groups fixture"

out="$(ANTIGRAVITY_RESPONSE_FILE="$ROOT/tests/fixtures/antigravity-models-valid.json" ANTIGRAVITY_INSTALL_LABEL=Fixture ANTIGRAVITY_ACCOUNT_EMAIL=models@example.invalid run)"
jq -e '.[0].error==null and .[0].accounts[0].install=="Fixture" and .[0].accounts[0].email=="models@example.invalid"' <<<"$out" >/dev/null || fail "models fixture"

out="$(ANTIGRAVITY_RESPONSE_FILE="$ROOT/tests/fixtures/antigravity-valid.json" bash "$ROOT/providers/get-antigravity-usage")"
jq -e '.[0].provider=="antigravity" and .[0].error==null' <<<"$out" >/dev/null || fail "public wrapper entrypoint"

for status in 401 403 429 500; do
  out="$(ANTIGRAVITY_RESPONSE_FILE="$ROOT/tests/fixtures/antigravity-valid.json" ANTIGRAVITY_HTTP_STATUS="$status" run)"
  jq -e --argjson s "$status" '.[0].error.code==$s and .[0].error.kind=="provider"' <<<"$out" >/dev/null || fail "HTTP $status mapping"
done

out="$(ANTIGRAVITY_RESPONSE_FILE="$TMP/no-such-file" run)"
jq -e '.[0].error.code==2 and .[0].error.kind=="runtime"' <<<"$out" >/dev/null || fail "unreadable fixture"
printf '{"unexpected":true}\n' > "$TMP/schema.json"
out="$(ANTIGRAVITY_RESPONSE_FILE="$TMP/schema.json" run)"
jq -e '.[0].error.code==1 and (.[0].error.message|contains("schema changed"))' <<<"$out" >/dev/null || fail "unknown schema"

# A failed OAuth token refresh is returned as an account provider error and
# never includes the refresh token in the response.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/sqlite3" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '1//fixture_refresh_token_12345678901234567890'
SH
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
while (($#)); do
  if [[ "$1" == -o ]]; then out="$2"; shift 2; else shift; fi
done
case "${ANTIGRAVITY_REFRESH_MODE:-rejected}" in
  transport) printf '000'; exit 7 ;;
  malformed) printf '%s' '{}' >"$out"; printf '200' ;;
  *) printf '%s' '{"error":{"message":"invalid_grant"}}' >"$out"; printf '400' ;;
esac
SH
chmod +x "$TMP/bin/sqlite3" "$TMP/bin/curl"
: >"$TMP/antigravity-state.vscdb"
out="$(PATH="$TMP/bin:$PATH" ANTIGRAVITY_STATE_DB="$TMP/antigravity-state.vscdb" \
  bash "$ROOT/providers/get-provider-usage" antigravity '')"
jq -e '.[0].error.code == 400 and .[0].error.kind == "provider" and (.[0].error.message | contains("invalid_grant"))' <<<"$out" >/dev/null \
  || fail "OAuth refresh failure was not reported"
if grep -q 'fixture_refresh_token_12345678901234567890' <<<"$out"; then
  fail "OAuth refresh token leaked into provider output"
fi
out="$(PATH="$TMP/bin:$PATH" ANTIGRAVITY_STATE_DB="$TMP/antigravity-state.vscdb" \
  ANTIGRAVITY_REFRESH_MODE=transport bash "$ROOT/providers/get-provider-usage" antigravity '')"
jq -e '.[0].error.code == 1 and .[0].error.kind == "provider" and (.[0].error.message | contains("could not reach Google"))' <<<"$out" >/dev/null \
  || fail "OAuth transport failure was not reported"
out="$(PATH="$TMP/bin:$PATH" ANTIGRAVITY_STATE_DB="$TMP/antigravity-state.vscdb" \
  ANTIGRAVITY_REFRESH_MODE=malformed bash "$ROOT/providers/get-provider-usage" antigravity '')"
jq -e '.[0].error.code == 1 and .[0].error.kind == "provider" and (.[0].error.message | contains("schema changed"))' <<<"$out" >/dev/null \
  || fail "malformed OAuth response was not reported"

# Local language server: the running app answers retrieveUserQuotaSummary over
# loopback Connect-RPC, and that answer is used only for the account whose
# email GetUserStatus reports. Process 4242 is the app's server; 5151 is a
# shell whose command line merely mentions the path, which `pgrep -f` would
# have picked.
mkdir -p "$TMP/proc/4242" "$TMP/proc/5151"
printf '/opt/Antigravity/resources/bin/language_server\0--standalone\0--csrf_token\0csrf-fixture-secret\0--https_server_port\0000\0' \
  > "$TMP/proc/4242/cmdline"
ln -s /opt/Antigravity/resources/bin/language_server "$TMP/proc/4242/exe"
printf '/usr/bin/zsh\0-c\0echo /opt/Antigravity/resources/bin/language_server --csrf_token=shell-secret\0' \
  > "$TMP/proc/5151/cmdline"
ln -s /usr/bin/zsh "$TMP/proc/5151/exe"
cat >"$TMP/bin/pgrep" <<'SH'
#!/usr/bin/env bash
[ "$*" = "-x language_server" ] || exit 1
printf '5151\n4242\n'
SH
# Two loopback listeners (one does not speak Connect-RPC), one public one the
# adapter must never contact, and a listener of another process.
cat >"$TMP/bin/ss" <<'SH'
#!/usr/bin/env bash
printf 'LISTEN 0 128 127.0.0.1:44001 0.0.0.0:* users:(("language_server",pid=4242,fd=8))\n'
printf 'LISTEN 0 128 127.0.0.1:44123 0.0.0.0:* users:(("language_server",pid=4242,fd=9))\n'
printf 'LISTEN 0 128 0.0.0.0:44999 0.0.0.0:* users:(("language_server",pid=4242,fd=10))\n'
printf 'LISTEN 0 128 127.0.0.1:45555 0.0.0.0:* users:(("zsh",pid=5151,fd=3))\n'
SH
# The OAuth id_token names the account; the cloud endpoint answers with a
# Claude-only summary, the local server with the Gemini group as well.
idtoken="x.$(printf '%s' '{"email":"dev@example.com"}' | base64 -w0 | tr '+/' '-_' | tr -d '=').y"
export AG_TEST_IDTOKEN="$idtoken" AG_ARGV_LOG="$TMP/argv.log" AG_CFG_LOG="$TMP/cfg.log"
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$AG_ARGV_LOG"
out="" url="" prev=""
for arg in "$@"; do
  [ "$prev" != -o ] || out="$arg"
  [ "$prev" != --config ] || cat "$arg" >>"$AG_CFG_LOG"
  [[ "$arg" == http* ]] && url="$arg"
  prev="$arg"
done
case "$url" in
  *oauth2.googleapis.com/token*)
    printf '{"access_token":"tok","id_token":"%s"}' "$AG_TEST_IDTOKEN" >"$out"; printf '200' ;;
  *loadCodeAssist*)
    printf '{"cloudaicompanionProject":"proj-1"}' >"$out"; printf '200' ;;
  https://127.0.0.1:44001/*)
    exit 35 ;;
  https://127.0.0.1:44123/*GetUserStatus)
    printf '{"userStatus":{"email":"%s","name":"Dev"}}' "${AG_TEST_LOCAL_EMAIL:-Dev@Example.com}" >"$out"; printf '200' ;;
  https://127.0.0.1:44123/*RetrieveUserQuotaSummary)
    printf '%s' '{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.4,"resetTime":"2026-11-14T11:11:03Z"}]},{"displayName":"Gemini 4 Argon","buckets":[{"bucketId":"argon-5h","window":"5h","resetTime":"2026-11-08T20:00:00Z"}]},{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","window":"weekly","remaining":{"remainingFraction":0.75},"resetTime":"2026-11-14T11:11:03Z"}]}]}}' >"$out"
    printf '200' ;;
  https://127.0.0.1:*|https://0.0.0.0:*)
    echo "unexpected local port: $url" >&2; exit 7 ;;
  *retrieveUserQuotaSummary*)
    printf '%s' '{"groups":[{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","window":"weekly","remainingFraction":0.5,"resetTime":"2026-11-14T11:11:03Z"}]}]}' >"$out"
    printf '200' ;;
  *) printf '404' ;;
esac
SH
chmod +x "$TMP/bin/pgrep" "$TMP/bin/ss" "$TMP/bin/curl"
local_run() {
  : >"$AG_ARGV_LOG"; : >"$AG_CFG_LOG"
  PATH="$TMP/bin:$PATH" ANTIGRAVITY_STATE_DB="$TMP/antigravity-state.vscdb" \
    ANTIGRAVITY_ALLOW_LOCAL_RPC=1 ANTIGRAVITY_PROC_DIR="$TMP/proc" "$@" \
    bash "$ROOT/providers/get-provider-usage" antigravity ''
}

# 1. Matching email (case-insensitive): the local answer, with every group,
#    a nested `remaining.remainingFraction`, and a bucket whose omitted
#    fraction (protobuf drops zero) reads as used up.
out="$(local_run env)"
jq -e '
  .[0].error == null
  and .[0].accounts[0].email == "dev@example.com"
  and .[0].accounts[0].loginMethod == "Antigravity app (local language server)"
  and ([.[0].accounts[0].windows[].group] == ["Gemini Models", "Claude & OpenAI Models", "Gemini 4 Argon"])
  and ([.[0].accounts[0].windows[] | select(.group == "Gemini Models")][0].usedPercent == 60)
  and ([.[0].accounts[0].windows[] | select(.group == "Claude & OpenAI Models")][0].usedPercent == 25)
  and ([.[0].accounts[0].windows[] | select(.group == "Gemini 4 Argon")][0].usedPercent == 100)
' <<<"$out" >/dev/null || fail "local language server summary was not used for its account: $out"
grep -q 'RetrieveUserQuotaSummary' "$AG_ARGV_LOG" || fail "local summary was not requested"
if grep -q 'retrieveUserQuotaSummary\|fetchAvailableModels' "$AG_ARGV_LOG"; then
  fail "cloud quota endpoint was called although the local server answered"
fi
grep -q '44999\|45555' "$AG_ARGV_LOG" && fail "a non-loopback or foreign port was contacted"
grep -q 'shell-secret' "$AG_CFG_LOG" && fail "the CSRF token was read from a process that is not the language server"
grep -q 'x-codeium-csrf-token: csrf-fixture-secret' "$AG_CFG_LOG" || fail "CSRF token did not reach the request"
grep -q 'csrf-fixture-secret' "$AG_ARGV_LOG" && fail "CSRF token reached a command line"
grep -q 'csrf-fixture-secret' <<<"$out" && fail "CSRF token leaked into output"

# 2. The local server is signed in to another account: this account keeps the
#    cloud answer, so one account's pools are never shown under another.
out="$(local_run env AG_TEST_LOCAL_EMAIL=other@example.com)"
jq -e '.[0].error == null and .[0].accounts[0].loginMethod == "IDE session OAuth (refreshed)"
  and ([.[0].accounts[0].windows[].group] == ["Claude & OpenAI Models"])
  and .[0].accounts[0].windows[0].usedPercent == 50' <<<"$out" >/dev/null \
  || fail "another account's local summary was attributed to this account: $out"

# 3. ANTIGRAVITY_NO_LOCAL_RPC=1 never contacts the local server.
out="$(local_run env ANTIGRAVITY_NO_LOCAL_RPC=1)"
grep -q '127.0.0.1' "$AG_ARGV_LOG" && fail "ANTIGRAVITY_NO_LOCAL_RPC did not disable the local server"
jq -e '.[0].accounts[0].loginMethod == "IDE session OAuth (refreshed)"' <<<"$out" >/dev/null || fail "opt-out did not fall back to the cloud"

# 4. A token given as --csrf_token=VALUE is read too.
printf '/opt/Antigravity/resources/bin/language_server\0--csrf_token=csrf-equals-secret\0' > "$TMP/proc/4242/cmdline"
out="$(local_run env)"
grep -q 'x-codeium-csrf-token: csrf-equals-secret' "$AG_CFG_LOG" || fail "--csrf_token=VALUE form was not read"
jq -e '.[0].accounts[0].loginMethod == "Antigravity app (local language server)"' <<<"$out" >/dev/null || fail "--csrf_token=VALUE summary"

# 5. A pinned state DB without the explicit opt-in never probes local servers,
#    so a developer machine's running app cannot leak into a fixture run.
: >"$AG_ARGV_LOG"
PATH="$TMP/bin:$PATH" ANTIGRAVITY_STATE_DB="$TMP/antigravity-state.vscdb" ANTIGRAVITY_PROC_DIR="$TMP/proc" \
  bash "$ROOT/providers/get-provider-usage" antigravity '' >/dev/null
grep -q '127.0.0.1' "$AG_ARGV_LOG" && fail "a pinned state DB probed the local server without opting in"
true
echo 'OK: Antigravity fixture, transport, and token refresh coverage'
