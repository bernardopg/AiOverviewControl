#!/usr/bin/env bash
# Full DMS types need a Wayland PanelWindow backend; offscreen reader CI is separate.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMPORTS="${AIOC_DMS_IMPORTS:-${XDG_CACHE_HOME:-$HOME/.cache}/dms-qmlls}"
if [[ -z "${WAYLAND_DISPLAY:-}" || ! -f "$IMPORTS/qs/Modules/Plugins/PluginComponent.qml" ]]; then
    echo 'SKIP: full widget runtime requires Wayland and DMS imports (scripts/qmlls-setup)'
    exit 0
fi
TMP="$(mktemp -d)"
pid=""
trap 'if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugin/providers" "$TMP/home" "$TMP/bin"
cp "$ROOT"/*.qml "$ROOT/plugin.json" "$ROOT/qmldir" "$TMP/plugin/"
cp -r "$ROOT/i18n" "$ROOT/assets" "$TMP/plugin/"
for name in get-provider-usage get-provider-health get-local-analytics get-claude-usage get-9router-analytics get-pi-analytics get-hermes-analytics get-usage-history get-history-stats get-exchange-rates record-usage-history; do
    printf '#!/bin/bash\nprintf '\''{"providers":[],"error":"fixture"}\\n'\''\n' > "$TMP/plugin/providers/$name"
    chmod +x "$TMP/plugin/providers/$name"
done
cat > "$TMP/plugin/providers/get-exchange-rates" <<'SH'
#!/usr/bin/env bash
printf '{"base":"USD","currency":"%s","rate":5,"date":"2026-09-29","stale":false}\n' "$1"
SH
cat > "$TMP/plugin/providers/get-provider-usage" <<'SH'
#!/usr/bin/env bash
printf '[{"provider":"codex","name":"Codex","usage":{"provider":"codex","identity":{"providerID":"codex"},"primary":{"usedPercent":25,"windowMinutes":300},"secondary":{"usedPercent":15,"windowMinutes":10080}}}]\n'
SH
chmod +x "$TMP/plugin/providers/get-provider-usage"
printf '#!/bin/bash\nexit 1\n' > "$TMP/bin/curl"
chmod +x "$TMP/bin/curl" "$TMP/plugin/providers/get-exchange-rates"
cat > "$TMP/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugin" as Plugin
ShellRoot {
    id: root
    property int step: 0
    QtObject {
        id: service
        property var data: ({providerSelection: "codex", costCurrency: "USD"})
        property var availablePlugins: ({})
        signal pluginDataChanged(string pluginId)
        function getPluginPath(id) { return Quickshell.env("AIOC_TEST_PLUGIN_DIR"); }
        function getPluginVariants(id) { return []; }
        function loadPluginData(id, key, fallback) { return data[key] === undefined ? fallback : data[key]; }
        function savePluginData(id, key, value) { const next = Object.assign({}, data); next[key] = value; data = next; }
    }
    Plugin.AiOverviewControlWidget { id: widget; pluginId: "fixture"; pluginService: service }
    // Real DMS controls and all visual components, but no visible desktop windows.
    FloatingWindow {
        visible: false; implicitWidth: 1000; implicitHeight: 900
        Loader { sourceComponent: widget.popoutContent; width: parent.width; height: parent.height }
        Loader { sourceComponent: widget.horizontalBarPill }
        Loader { sourceComponent: widget.verticalBarPill }
        Plugin.AiOverviewControlSettings { id: settings; visible: false; pluginService: service }
    }
    Plugin.AiOverviewSettingsWindow { visible: false }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            if (root.step === 0) {
                // Empty-provider construction catches bindings that visibility cannot guard.
                // Real DMS injects a physical plugin path; qs directory imports use a VFS URL.
                widget._pluginDir = Quickshell.env("AIOC_TEST_PLUGIN_DIR");
                const choice = settings.content.find(item => item.values && item.values.indexOf("BRL") >= 0);
                if (!choice) { console.error("SMOKE FAIL: missing currency control"); return; }
                choice.picked("BRL");
                if (settings.loadValue("costCurrency", "USD") !== "BRL") {
                    console.error("SMOKE FAIL: currency setting did not persist"); return;
                }
                widget.pluginData = service.data;
                widget.providers = [];
                root.step = 1;
            } else if (root.step === 1 && widget.formatCost(2).indexOf("BRL 10") === 0) {
                widget.providers = [{provider: "codex", name: "Codex", usage: {
                    provider: "codex",
                    identity: {providerID: "codex"},
                    primary: {usedPercent: 25, windowMinutes: 300},
                    secondary: {usedPercent: 15, windowMinutes: 10080}
                }}];
                settings.resetToDefaults();
                if (settings.loadValue("costCurrency", "BRL") !== "USD") {
                    console.error("SMOKE FAIL: reset did not restore USD"); return;
                }
                widget.pluginData = service.data;
                root.step = 2;
            } else if (root.step === 2 && widget.formatCost(2).indexOf("$2") === 0) {
                if (!widget.dashboardView) { console.error("SMOKE FAIL: view not attached"); return; }
                widget.focusProvider("codex");
                root.step = 3;
            } else if (root.step === 3) {
                console.warn("FULL_UI_SMOKE_OK");
                root.step = 4;
            }
        }
    }
}
QML
# No provider keys, real user settings, session bus or external HTTP in this fixture.
env -i HOME="$TMP/home" PATH="$TMP/bin:$PATH" LANG=en_US.UTF-8 AIOC_TEST_PLUGIN_DIR="$TMP/plugin" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
    WAYLAND_DISPLAY="$WAYLAND_DISPLAY" QT_QPA_PLATFORM=wayland \
    QML_XHR_ALLOW_FILE_READ=1 QML_IMPORT_PATH="$IMPORTS" \
    timeout 15 qs --no-color -p "$TMP/shell.qml" > "$TMP/log" 2>&1 &
pid=$!
for _ in {1..120}; do
    grep -q 'FULL_UI_SMOKE_OK' "$TMP/log" && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if ! grep -q 'FULL_UI_SMOKE_OK' "$TMP/log" || grep -Ei 'SMOKE FAIL|TypeError|ReferenceError|binding loop|Failed to load configuration|Cannot assign|Unable to assign|Invalid property assignment|is not a type' "$TMP/log"; then
    printf '%s\n' "$(<"$TMP/log")" >&2
    exit 1
fi
echo 'OK: full widget, horizontal/vertical pills, dashboard, settings/window and live currency bindings'
