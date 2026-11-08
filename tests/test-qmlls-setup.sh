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

# Without an argument it finds the newest shell extraction under the runtime
# directory: a newer DMS 2.x tree wins over an older one and over a 1.x tree,
# and an extraction without PluginService.qml is never picked.
RUN="$TMP/runtime"
for extraction in dms-shell/old dms-shell/new danklinux-shell/legacy dms-shell/partial; do
  mkdir -p "$RUN/$extraction/Services"
done
cp "$TMP/shell/Services/PluginService.qml" "$RUN/dms-shell/old/Services/"
cp "$TMP/shell/Services/PluginService.qml" "$RUN/danklinux-shell/legacy/Services/"
cp "$TMP/shell/Services/PluginService.qml" "$RUN/dms-shell/new/Services/"
printf 'import QtQuick\nItem {}\n' > "$RUN/dms-shell/partial/Services/Other.qml"
touch -d '2026-01-01' "$RUN/dms-shell/old/Services/PluginService.qml"
touch -d '2025-01-01' "$RUN/danklinux-shell/legacy/Services/PluginService.qml"
touch -d '2026-06-01' "$RUN/dms-shell/new/Services/PluginService.qml"
printf 'marker\n' > "$RUN/dms-shell/new/marker.txt"
XDG_RUNTIME_DIR="$RUN" "$TMP/plugin/scripts/qmlls-setup" >/dev/null
[ -f "$tree/qs/marker.txt" ] || fail "the newest runtime extraction was not picked"

# No extraction at all is the same missing-dir error.
if XDG_RUNTIME_DIR="$TMP/empty-runtime" "$TMP/plugin/scripts/qmlls-setup" 2>"$TMP/err"; then fail "found a shell in an empty runtime dir"; fi
grep -q 'DMS shell dir not found' "$TMP/err" || fail "missing runtime extraction message"

echo 'OK: qmlls-setup builds the qs import tree'
