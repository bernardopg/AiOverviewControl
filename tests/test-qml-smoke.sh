#!/usr/bin/env bash
# Runtime smoke for the extracted fetch component, without a live DMS session.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v qs >/dev/null || { echo 'QML smoke requires Quickshell (qs)' >&2; exit 1; }
TMP="$(mktemp -d)"
pid=""
trap 'if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT
cp "$ROOT/LocalAnalyticsReader.qml" "$TMP/"
python3 - "$ROOT/AiOverviewControlWidget.qml" "$TMP/ProviderOrder.js" <<'PY'
import re, sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
function = re.search(r'    function reorderedPins\(.*?(?=\n    function )', source, re.S)
assert function, 'Pinned-order function missing'
Path(sys.argv[2]).write_text('.pragma library\n' + function.group(0) + '\n')
PY
printf 'LocalAnalyticsReader 1.0 LocalAnalyticsReader.qml\n' > "$TMP/qmldir"
cat > "$TMP/adapter" <<'SH'
case "$1" in
  success) printf '{"tokens":42}\n' ;;
  malformed) printf 'not json\n' ;;
  error) printf '{"error":"fixture"}\n' ;;
  failed) printf '{"tokens":42}\n'; exit 1 ;;
  hang) exec sleep 10 ;;
esac
SH
cat > "$TMP/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "ProviderOrder.js" as ProviderOrder
ShellRoot {
    id: root
    FloatingWindow { visible: true; implicitWidth: 1; implicitHeight: 1 }
    property int step: 0
    property var cases: ["success", "malformed", "error", "failed", "hang", "success"]
    LocalAnalyticsReader {
        id: reader
        providerId: "success"
        scriptPath: Qt.resolvedUrl("adapter").toString().replace("file://", "")
        timeoutMs: 250
        onCompleted: {
            const valid = root.cases[root.step] === "success";
            if ((valid && (!result || result.tokens !== 42)) || (!valid && result !== null)) {
                console.error("SMOKE FAIL: " + root.cases[root.step]);
                return;
            }
            root.step++;
            if (root.step === root.cases.length) {
                console.warn("QML_SMOKE_OK");
            } else {
                providerId = root.cases[root.step];
                next.start();
            }
        }
    }
    Timer { id: next; interval: 20; onTriggered: { reader.refresh(); reader.refresh(); } }
    Component.onCompleted: {
        const pins = ["codex", "claude", "kimi-code"];
        if (ProviderOrder.reorderedPins(pins, "kimi-code", "codex").join(",") !== "kimi-code,codex,claude"
            || ProviderOrder.reorderedPins(pins, "codex", "kimi-code").join(",") !== "claude,codex,kimi-code"
            || ProviderOrder.reorderedPins(pins, "unknown", "codex").join(",") !== pins.join(",")
            || ProviderOrder.reorderedPins(pins, "codex", "codex").join(",") !== pins.join(",")
            || pins.join(",") !== "codex,claude,kimi-code") {
            console.error("SMOKE FAIL: pinned order");
            return;
        }
        next.start();
    }
}
QML
env -u WAYLAND_DISPLAY -u QSG_USE_SIMPLE_ANIMATION_DRIVER -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen timeout 15 qs --no-color -p "$TMP/shell.qml" > "$TMP/log" 2>&1 &
pid=$!
for _ in {1..100}; do
    grep -q 'QML_SMOKE_OK' "$TMP/log" && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
grep -q 'QML_SMOKE_OK' "$TMP/log" || { printf '%s\n' "$(<"$TMP/log")" >&2; exit 1; }
if grep -Ei 'SMOKE FAIL|ReferenceError|TypeError|binding loop|Failed to load configuration' "$TMP/log"; then exit 1; fi
echo 'OK: QML runtime JSON parsing, errors, timeout, retry and refresh deduplication'
