#!/usr/bin/env bash
# scripts/qmlls-setup copies a DMS shell tree, writes one qmldir per QML
# directory (singletons marked) and points .qmlls.ini at the copy. The script
# runs through a symlink so .qmlls.ini lands in a scratch tree, not the repo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/plugin/scripts" "$TMP/shell/Services" "$TMP/shell/Widgets/Empty"
ln -s "$ROOT/scripts/qmlls-setup" "$TMP/plugin/scripts/qmlls-setup"
printf 'pragma Singleton\nimport QtQuick\nQtObject {}\n' > "$TMP/shell/Services/PluginService.qml"
printf 'import QtQuick\nItem {}\n' > "$TMP/shell/Services/Helper.qml"
chmod -w "$TMP/shell/Services/Helper.qml"

out="$("$TMP/plugin/scripts/qmlls-setup" "$TMP/shell")"
tree="$XDG_CACHE_HOME/dms-qmlls"
[ "$out" = "qmlls import tree: $tree" ] || fail "output: $out"
[ "$(cat "$tree/qs/Services/qmldir")" = $'module qs.Services\nHelper 1.0 Helper.qml\nsingleton PluginService 1.0 PluginService.qml' ] \
  || fail "qmldir: $(cat "$tree/qs/Services/qmldir")"
[ ! -e "$tree/qs/Widgets/Empty/qmldir" ] || fail "qmldir written for a directory without QML"
[ -w "$tree/qs/Services/Helper.qml" ] || fail "copied tree is not writable"
grep -qx "importPaths=\"$tree\"" "$TMP/plugin/.qmlls.ini" || fail ".qmlls.ini: $(cat "$TMP/plugin/.qmlls.ini")"

# A shell tree that does not exist is an error.
if "$TMP/plugin/scripts/qmlls-setup" "$TMP/missing" 2>"$TMP/err"; then fail "accepted a missing shell dir"; fi
grep -q 'DMS shell dir not found' "$TMP/err" || fail "missing dir message"

echo 'OK: qmlls-setup builds the qs import tree'
