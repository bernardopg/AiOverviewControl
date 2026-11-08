#!/usr/bin/env bash
# Provider keys read from the freedesktop keyring at the moment of use.
#
# A plugin started by the graphical session inherits the user manager's
# environment and never an interactive shell's exports, so a key exported in
# ~/.bashrc does not arrive. The adapter can read it from the keyring instead:
# the environment carries only the lookup spec, which is not a secret.
#
# Covered here: the key reaches curl from the keyring, an exported key still
# wins and skips the lookup, a readable auth.json with no key falls through to
# the keyring, an entry in a locked collection is skipped without a lookup (so
# no unlock prompt), a keyring that does not answer cannot stall the refresh, a
# spec is split without glob expansion and must hold attribute/value pairs, a
# missing secret-tool degrades to "no key", and readiness accepts a spec
# without a lookup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$TMP/bin" "$TMP/home" "$TMP/cache" "$TMP/data"
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
export XDG_DATA_HOME="$TMP/data"
export AIOC_NO_LITELLM=1 AIOC_NO_DOH_FALLBACK=1 AIOC_NO_FX=1
export VAULT_LOG="$TMP/vault.log" CFG_LOG="$TMP/config.log" ARGV_LOG="$TMP/argv.log"
: >"$VAULT_LOG"; : >"$CFG_LOG"; : >"$ARGV_LOG"
unset OPENROUTER_API_KEY ZAI_API_KEY GLM_API_KEY ZHIPU_API_KEY OPENCODE_API_KEY \
  AIOC_VAULT_OPENROUTER AIOC_VAULT_ZAI AIOC_VAULT_GLM AIOC_VAULT_OPENCODE \
  AIOC_VAULT_TIMEOUT OPENCODE_USAGE_SOURCE || true
export BUSCTL_LOG="$TMP/busctl.log"
: >"$BUSCTL_LOG"

OPENROUTER_SPEC="service openrouter username quota"
ZAI_SPEC="service zai username quota"
GLM_SPEC="service glm username quota"
OPENCODE_SPEC="service opencode username quota"

# Fake keyring: prints a key derived from the whole lookup and records it.
# AIOC_TEST_SLEEP models a locked keyring that waits for an answer.
cat >"$TMP/bin/secret-tool" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$VAULT_LOG"
[ -z "${AIOC_TEST_SLEEP:-}" ] || exec sleep "$AIOC_TEST_SLEEP"
printf 'vaultkey-%s' "$(printf '%s' "${*:2}" | tr ' ' '-')"
SH
chmod +x "$TMP/bin/secret-tool"

# Fake Secret Service: answers SearchItems the way `busctl --json=short`
# prints it, with the entry unlocked unless AIOC_TEST_ITEM says otherwise
# (locked, absent, or down for a bus that cannot be reached). It records its
# argv so the test can check the attribute pairs it was asked about.
cat >"$TMP/bin/busctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BUSCTL_LOG"
case "${AIOC_TEST_ITEM:-unlocked}" in
  unlocked) printf '{"type":"aoao","data":[["/org/freedesktop/secrets/collection/login/1"],[]]}\n' ;;
  locked)   printf '{"type":"aoao","data":[[],["/org/freedesktop/secrets/collection/login/1"]]}\n' ;;
  absent)   printf '{"type":"aoao","data":[[],[]]}\n' ;;
  *)        echo "Failed to connect to bus" >&2; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/busctl"

# Fake curl: records its argv and any --config contents, answers 401 so the
# adapter stops after the request.
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ARGV_LOG"
out=""; prev=""
for arg in "$@"; do
  [ "$prev" != -o ] || out="$arg"
  if [ "$prev" = --config ]; then cat "$arg" >>"$CFG_LOG"; fi
  prev="$arg"
done
[ -z "$out" ] || printf '{"error":{"message":"fake unauthorized"}}' >"$out"
printf 401
SH
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

usage() { bash "$ROOT/providers/get-provider-usage" "$1" "$ROOT/providers/get-copilot-usage" 2>/dev/null; }

# The fake keyring's answer for one spec, as curl receives it.
expected() { printf 'Authorization: Bearer vaultkey-%s' "$(printf '%s' "$1" | tr ' ' '-')"; }

# 1. The keyring supplies the key, and the key never reaches an argv.
export AIOC_VAULT_OPENROUTER="$OPENROUTER_SPEC"
: >"$CFG_LOG"; : >"$VAULT_LOG"; : >"$ARGV_LOG"
usage openrouter >/dev/null
grep -qF "$(expected "$OPENROUTER_SPEC")" "$CFG_LOG" \
  || fail "openrouter: keyring key did not reach the request"
grep -qF "lookup $OPENROUTER_SPEC" "$VAULT_LOG" \
  || fail "openrouter: lookup spec was not passed to secret-tool"
if grep -qF "vaultkey-${OPENROUTER_SPEC// /-}" "$ARGV_LOG"; then
  fail "openrouter: key reached a command line"
fi

# 1b. The Secret Service is asked about exactly the spec's attribute pairs.
grep -qF "SearchItems a{ss} 2 $OPENROUTER_SPEC" "$BUSCTL_LOG" \
  || fail "openrouter: SearchItems did not receive the spec's attribute pairs"

# 2. An exported key wins and skips the lookup entirely.
: >"$CFG_LOG"; : >"$VAULT_LOG"
export OPENROUTER_API_KEY=envkey-sentinel
usage openrouter >/dev/null
unset OPENROUTER_API_KEY
grep -qF 'Authorization: Bearer envkey-sentinel' "$CFG_LOG" || fail "openrouter: exported key was not preferred"
[ ! -s "$VAULT_LOG" ] || fail "openrouter: lookup ran although the key was exported"

# 3. Neither source: the existing missing-credential error, naming both.
unset AIOC_VAULT_OPENROUTER
out="$(usage openrouter)"
printf '%s' "$out" | jq -e '.[0].error.message | test("OPENROUTER_API_KEY") and test("AIOC_VAULT_OPENROUTER")' >/dev/null \
  || fail "openrouter: error must name the environment variable and the spec"

# 4. Z.ai and OpenCode Go take the same path. A readable auth.json that holds
#    no key must not swallow the keyring lookup.
export AIOC_VAULT_ZAI="$ZAI_SPEC"
: >"$CFG_LOG"
usage zai >/dev/null
grep -qF "$(expected "$ZAI_SPEC")" "$CFG_LOG" || fail "zai: keyring key did not reach the request"

mkdir -p "$TMP/data/opencode"
printf '%s\n' '{"opencode":{}}' >"$TMP/data/opencode/auth.json"
export AIOC_VAULT_OPENCODE="$OPENCODE_SPEC"
export OPENCODE_USAGE_SOURCE=api
: >"$CFG_LOG"
usage opencode >/dev/null
grep -qF "$(expected "$OPENCODE_SPEC")" "$CFG_LOG" || fail "opencode: keyring key did not reach the request"
unset OPENCODE_USAGE_SOURCE

# 4b. GLM reads its own spec, so one key per card stays possible.
export AIOC_VAULT_GLM="$GLM_SPEC"
: >"$CFG_LOG"
usage glm >/dev/null
grep -qF "$(expected "$GLM_SPEC")" "$CFG_LOG" || fail "glm: keyring key did not reach the request"
bash "$ROOT/providers/get-provider-health" glm | jq -e '.[0].status == "ready"' >/dev/null \
  || fail "health: a GLM keyring spec must count as ready"
unset AIOC_VAULT_GLM

# 4c. An entry that sits only in a locked collection is skipped: no lookup
#     runs, so a background refresh can never raise an unlock prompt. An
#     absent entry is skipped the same way.
export AIOC_VAULT_OPENROUTER="$OPENROUTER_SPEC"
for state in locked absent; do
  : >"$VAULT_LOG"; : >"$CFG_LOG"
  out="$(AIOC_TEST_ITEM="$state" usage openrouter)"
  [ ! -s "$VAULT_LOG" ] || fail "openrouter: a lookup ran for a $state entry"
  [ ! -s "$CFG_LOG" ] || fail "openrouter: a request was sent for a $state entry"
  printf '%s' "$out" | jq -e '.[0].error.message | test("unlocked keyring entry")' >/dev/null \
    || fail "openrouter: a $state entry must report the missing key"
done

# 4d. A bus that cannot be asked falls back to the bounded lookup.
: >"$VAULT_LOG"; : >"$CFG_LOG"
AIOC_TEST_ITEM=down usage openrouter >/dev/null
grep -qF "$(expected "$OPENROUTER_SPEC")" "$CFG_LOG" || fail "openrouter: an unreachable bus must still allow the lookup"

# 4e. The spec is split on whitespace but never glob-expanded, and a spec
#     that is not attribute/value pairs is ignored without a lookup.
mkdir -p "$TMP/globdir"
: >"$TMP/globdir/should-not-appear"
: >"$VAULT_LOG"
( cd "$TMP/globdir" && AIOC_VAULT_OPENROUTER="service * username quota" \
    bash "$ROOT/providers/get-provider-usage" openrouter "$ROOT/providers/get-copilot-usage" >/dev/null 2>&1 )
grep -qxF "lookup service * username quota" "$VAULT_LOG" || fail "spec was glob-expanded"
: >"$VAULT_LOG"
AIOC_VAULT_OPENROUTER="service openrouter username" usage openrouter >/dev/null
[ ! -s "$VAULT_LOG" ] || fail "an odd-length spec must not reach secret-tool"
AIOC_VAULT_OPENROUTER="service openrouter username" bash "$ROOT/providers/get-provider-health" openrouter \
  | jq -e '.[0].status == "missing"' >/dev/null || fail "health: an odd-length spec must not count as ready"

# 4f. A malformed timeout falls back to the default instead of disabling the
#     lookup.
: >"$CFG_LOG"
AIOC_VAULT_TIMEOUT=soon usage openrouter >/dev/null
grep -qF "$(expected "$OPENROUTER_SPEC")" "$CFG_LOG" || fail "a malformed AIOC_VAULT_TIMEOUT must use the default"
unset AIOC_VAULT_OPENROUTER

# 5. A keyring that does not answer is bounded: the refresh continues without
#    a key instead of waiting for a prompt nobody will answer.
#    The entry is reported unlocked, so the lookup really runs and is cut off.
export AIOC_VAULT_OPENROUTER="$OPENROUTER_SPEC" AIOC_VAULT_TIMEOUT=1 AIOC_TEST_SLEEP=5
: >"$VAULT_LOG"
started=$SECONDS
out="$(usage openrouter)"
elapsed=$((SECONDS - started))
unset AIOC_VAULT_OPENROUTER AIOC_VAULT_TIMEOUT AIOC_TEST_SLEEP
grep -qF "lookup $OPENROUTER_SPEC" "$VAULT_LOG" || fail "the bounded case never reached secret-tool"
[ "$elapsed" -le 3 ] || fail "lookup was not bounded (${elapsed}s)"
printf '%s' "$out" | jq -e '.[0].error.message | test("OPENROUTER_API_KEY")' >/dev/null \
  || fail "a bounded lookup must report the missing key"

# 6. Without secret-tool the spec is inert: no key, and not ready.
mkdir -p "$TMP/nosecret"
ln -s "$(command -v tr)" "$TMP/nosecret/tr"
env PATH="$TMP/nosecret" AIOC_VAULT_OPENROUTER="$OPENROUTER_SPEC" \
  "$BASH" -c '. "$1/providers/vault-common"
    [ -z "$(vault_key openrouter)" ] || exit 1
    if has_vault_spec openrouter; then exit 1; fi
    exit 0' _ "$ROOT" \
  || fail "a missing secret-tool must degrade to no key"

# 7. Readiness accepts the spec without touching the keyring.
export AIOC_VAULT_OPENROUTER="$OPENROUTER_SPEC"
: >"$VAULT_LOG"
bash "$ROOT/providers/get-provider-health" openrouter | jq -e '.[0].status == "ready"' >/dev/null \
  || fail "health: a keyring spec must count as ready"
[ ! -s "$VAULT_LOG" ] || fail "health: readiness must not perform a lookup"
unset AIOC_VAULT_OPENROUTER
bash "$ROOT/providers/get-provider-health" openrouter | jq -e '.[0].status == "missing"' >/dev/null \
  || fail "health: missing without an exported key or a spec"

echo "OK: keyring keys, exported-key precedence, keyless auth.json, locked entries, glob-safe specs, bounded lookup, readiness"
