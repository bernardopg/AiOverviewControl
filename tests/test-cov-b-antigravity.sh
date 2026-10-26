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
echo 'OK: Antigravity fixture, transport, and token refresh coverage'
