#!/usr/bin/env bash
# Hot-upgrade contract (issue #92). A running shell caches each plugin
# directory's listing the first time the QML engine resolves a file in it, and
# DMS reuses that engine when it updates, reloads or enables a plugin. A QML or
# JavaScript file added later to an already listed directory then fails with
# "File name case mismatch" until `dms restart`, so the plugin cannot load.
#
# The runtime files of each directory are therefore frozen here. A new module
# goes into a new directory, which the engine lists fresh on first use; adding
# a file to a listed directory needs a release note that requires a restart,
# and this list updated with it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# The plugin root as of 2.2.0, the last release before the regression.
root_expected='AiOverviewControlI18n.qml
AiOverviewControlSettings.qml
AiOverviewControlWidget.qml
AiOverviewDashCard.qml
AiOverviewSettingsWindow.qml
ClaudeProfiles.js
CurrencyFormatter.qml
DashboardContent.qml
HeaderAction.qml
LocalAnalyticsReader.qml
ProviderLogo.qml
qmldir'
lib_expected='BarWindows.js'
# Provider detection (2.4.0) arrived as a new directory, listed fresh by a
# running shell on first use.
detect_expected='DetectProvidersPanel.qml
ProviderDetect.js'

list() { git -C "$ROOT" ls-files -- "$@" | sed 's|.*/||' | LC_ALL=C sort; }
root_actual="$(git -C "$ROOT" ls-files -- '*.qml' '*.js' qmldir | grep -v / | LC_ALL=C sort)"
[ "$root_actual" = "$(LC_ALL=C sort <<<"$root_expected")" ] \
  || fail "plugin root runtime files changed; a running shell cannot load a new one without a restart:
$(diff <(LC_ALL=C sort <<<"$root_expected") <(printf '%s\n' "$root_actual") || true)"
lib_actual="$(list 'lib/*')"
[ "$lib_actual" = "$lib_expected" ] \
  || fail "lib/ runtime files changed; put a new module in a new directory:
$(diff <(printf '%s\n' "$lib_expected") <(printf '%s\n' "$lib_actual") || true)"

detect_actual="$(list 'detect/*')"
[ "$detect_actual" = "$detect_expected" ] \
  || fail "detect/ runtime files changed; put a new module in a new directory:
$(diff <(printf '%s\n' "$detect_expected") <(printf '%s\n' "$detect_actual") || true)"

# Every QML/JavaScript directory the plugin loads from is one of those above.
dirs="$(git -C "$ROOT" ls-files -- '*.qml' '*.js' | grep -vE '^(tests|scripts|docs|\.github)/' \
  | sed -n 's|/[^/]*$||p' | LC_ALL=C sort -u)"
[ "$dirs" = "$(printf 'detect\nlib')" ] || fail "unexpected runtime directories: $dirs"

# Every relative import names a file that exists with that exact spelling.
while IFS= read -r line; do
  file="${line%%:*}"
  target="$(sed -E 's/^[^"]*"([^"]+)".*/\1/' <<<"${line#*:}")"
  [ -f "$ROOT/$(dirname "$file")/$target" ] || fail "$file imports missing $target"
done < <(cd "$ROOT" && grep -HE '^import "[^"]+\.(js|qml)"' -- *.qml lib/*.js detect/*.qml 2>/dev/null || true)
grep -q '^import "lib/BarWindows.js" as BarWindows$' "$ROOT/AiOverviewControlWidget.qml" \
  || fail "widget does not import lib/BarWindows.js"
grep -q '^import "lib/BarWindows.js" as BarWindows$' "$ROOT/AiOverviewControlSettings.qml" \
  || fail "settings do not import lib/BarWindows.js"
for host in DashboardContent.qml AiOverviewControlSettings.qml; do
  grep -q '^import "detect"$' "$ROOT/$host" || fail "$host does not import detect/"
done
echo 'OK: runtime files stay loadable by a running shell after an update'
