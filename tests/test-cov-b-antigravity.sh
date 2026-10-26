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

echo 'OK: Antigravity fixture and transport coverage'
