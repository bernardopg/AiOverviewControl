#!/usr/bin/env bash
# Exercise the DCO sign-off contract in an isolated Git repository.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q -b main
author() { git -C "$TMP" -c user.name="$1" -c user.email="$2" "${@:3}"; }
commit() { author "$1" "$2" commit -q --allow-empty "${@:3}"; }
check() { (cd "$TMP" && "$ROOT/scripts/check-dco" "$@"); }
reject() {
    local label="$1"; shift
    if check "$@" >"$TMP/output" 2>&1; then
        echo "FAIL: accepted $label" >&2; exit 1
    fi
    grep -q 'git commit -s' "$TMP/output" || { echo "FAIL: no fix hint for $label" >&2; exit 1; }
}

commit Base base@example.invalid -m baseline
BASE="$(git -C "$TMP" rev-parse HEAD)"

if check >/dev/null 2>&1; then echo "FAIL: accepted a call without BASE" >&2; exit 1; fi
check "$BASE" | grep -q '0 commit' || { echo "FAIL: empty range not accepted" >&2; exit 1; }

commit Ada ada@example.invalid -s -m 'feat: signed'
check "$BASE" >/dev/null

commit Ada ada@example.invalid -m 'fix: unsigned'
reject 'unsigned commit' "$BASE"
git -C "$TMP" reset -q --hard HEAD~1

commit Ada ada@example.invalid -m $'fix: wrong signer\n\nSigned-off-by: Eve <eve@example.invalid>'
reject 'sign-off from another email' "$BASE"
git -C "$TMP" reset -q --hard HEAD~1

commit Ada ada@example.invalid -m $'fix: sign-off in body only\n\nSee Signed-off-by: Ada <ada@example.invalid> above.\n\nRefs: #1'
reject 'sign-off that is not a trailer' "$BASE"
git -C "$TMP" reset -q --hard HEAD~1

commit 'dependabot[bot]' '49699333+dependabot[bot]@users.noreply.github.com' -m 'chore(deps): bump action'
check "$BASE" >/dev/null

git -C "$TMP" switch -q -c topic "$BASE"
commit Bo bo@example.invalid -s -m 'docs: topic'
git -C "$TMP" switch -q main
author Merger merger@example.invalid merge -q --no-ff --no-edit topic
check "$BASE" | grep -q '3 commit' || { echo "FAIL: merge commit not skipped" >&2; exit 1; }
check "$BASE" HEAD >/dev/null

echo "DCO tests OK"
