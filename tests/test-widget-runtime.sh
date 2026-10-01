#!/usr/bin/env bash
# Full DMS types need a Wayland PanelWindow backend; offscreen reader CI is separate.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMPORTS="${AIOC_DMS_IMPORTS:-${XDG_CACHE_HOME:-$HOME/.cache}/dms-qmlls}"
if [[ -z "${WAYLAND_DISPLAY:-}" || ! -f "$IMPORTS/qs/Modules/Plugins/PluginComponent.qml" ]]; then
    echo 'SKIP: full widget runtime requires Wayland and DMS imports (scripts/qmlls-setup)'
    # CI provisions both; a missing prerequisite there is a failure, not a skip.
    [[ "${AIOC_REQUIRE_NATIVE_UI:-0}" == 1 ]] && exit 1
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
import QtTest
import "plugin" as Plugin
ShellRoot {
    id: root
    property int step: 0
    property bool pointerTest: Quickshell.env("AIOC_TEST_POINTER") === "1"
    property real dragScrollY: 0
    property real pillWidth: 0
    property real pillHeight: 0
    // Positioners lay out on polish, which never runs in the hidden scene.
    function pillSize() {
        const entries = input.findChild(hPill.item, "pill-entry-codex").parent;
        for (const entry of entries.children)
            if (entry.forceLayout) entry.forceLayout();
        entries.forceLayout();
        hPill.item.forceLayout();
        vPill.item.forceLayout();
        return {width: hPill.item.implicitWidth, height: vPill.item.implicitHeight};
    }
    QtObject { id: fakePopout; property bool shouldBeVisible: true }
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
    TestCase { id: input; when: false; parent: scene.contentItem }
    FloatingWindow {
        id: scene
        visible: false; implicitWidth: 1000; implicitHeight: 900
        // Stands in for DMS's PluginPopout so openProvider() sees an open
        // popout and never opens a real one.
        Loader {
            id: dashboard
            sourceComponent: widget.popoutContent; width: parent.width; height: parent.height
            onLoaded: item.parentPopout = fakePopout
        }
        Loader { id: hPill; sourceComponent: widget.horizontalBarPill }
        Loader { id: vPill; sourceComponent: widget.verticalBarPill }
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
                widget.focusedProviderId = "";
                widget.allExpanded = false;
                widget.pinnedProvidersCsv = "codex,opencode";
                widget.providers = ["codex", "opencode", "copilot", "claude", "deepseek", "groq", "nvidia"].map(id => ({
                    provider: id, name: id, usage: {provider: id, primary: {usedPercent: 25, windowMinutes: 300}}
                }));
                scene.visible = root.pointerTest;
                root.step = 4;
            } else if (root.step === 4) {
                const view = widget.dashboardView;
                const handle = input.findChild(view, "provider-drag-opencode");
                const target = input.findChild(view, "provider-drag-codex");
                if (!handle || !target) { console.error("SMOKE FAIL: reorder handles missing"); return; }
                const end = target.mapToItem(handle, target.width / 2, target.height / 2);
                const scroll = input.findChild(view, "provider-dashboard-scroll");
                if (root.pointerTest && (!scroll || scroll.contentHeight <= scroll.height)) {
                    console.error("SMOKE FAIL: drag fixture must have scrollable content"); return;
                }
                root.dragScrollY = scroll.contentY;
                if (root.pointerTest) {
                    root.step = -1;
                    input.mousePress(handle, handle.width / 2, handle.height / 2, Qt.LeftButton, Qt.NoModifier, 1);
                    input.mouseMove(handle, handle.width / 2, handle.height / 2 - 20, 1);
                    input.mouseMove(handle, end.x, end.y, 1);
                    input.mouseRelease(handle, end.x, end.y, Qt.LeftButton, Qt.NoModifier, 1);
                }
                root.step = 5;
            } else if (root.step === 5) {
                scene.visible = false;
                if (root.pointerTest && widget.pinnedProvidersCsv !== "opencode,codex")
                    console.error("SMOKE FAIL: dragging handle did not reorder pins: " + widget.pinnedProvidersCsv);
                const view = widget.dashboardView;
                const scroll = input.findChild(view, "provider-dashboard-scroll");
                if (root.pointerTest && Math.abs(scroll.contentY - root.dragScrollY) > 1)
                    console.error("SMOKE FAIL: reorder gesture scrolled the page");
                const header = input.findChild(view, "provider-header-codex");
                const center = header.mapToItem(view, 0, header.height / 2).y;
                for (const role of ["drag", "logo", "percent", "actions", "accent"]) {
                    const item = input.findChild(view, "provider-" + role + "-codex");
                    if (!item || Math.abs(item.mapToItem(view, 0, item.height / 2).y - center) > 1)
                        console.error("SMOKE FAIL: provider header misaligned: " + role);
                }
                // Issue #33: names on by default, then flip both pill toggles
                // through Settings so persistence and the widget binding run.
                const name = input.findChild(hPill.item, "pill-name-codex");
                if (!name || !name.visible) { console.error("SMOKE FAIL: pill name hidden by default"); return; }
                const before = root.pillSize();
                root.pillWidth = before.width;
                root.pillHeight = before.height;
                for (const key of ["settings.pill_show_names", "settings.pill_compact"]) {
                    const label = widget.t(key, "");
                    const toggle = settings.content.find(item => item.text === label && item.toggled);
                    if (!toggle) { console.error("SMOKE FAIL: missing toggle " + key); return; }
                    toggle.toggled(key === "settings.pill_compact");
                }
                if (service.data.pillShowNames !== "false" || service.data.pillCompact !== "true") {
                    console.error("SMOKE FAIL: pill toggles did not persist"); return;
                }
                widget.pluginData = service.data;
                root.step = 6;
            } else if (root.step === 6) {
                const name = input.findChild(hPill.item, "pill-name-codex");
                const entry = input.findChild(hPill.item, "pill-entry-codex");
                if (!name || name.visible) console.error("SMOKE FAIL: pillShowNames=false still renders the name");
                if (!entry || entry.spacing !== 2) console.error("SMOKE FAIL: pillCompact did not tighten entry spacing");
                const after = root.pillSize();
                if (!(after.width < root.pillWidth))
                    console.error(`SMOKE FAIL: compact pill not narrower (${after.width} >= ${root.pillWidth})`);
                if (!(after.height < root.pillHeight))
                    console.error("SMOKE FAIL: compact vertical pill not shorter");
                // Notification click target: unknown ids are rejected, a known
                // id expands its card on the already-open popout.
                widget.focusedProviderId = "";
                if (widget.openProvider("nope") !== "UNKNOWN_PROVIDER" || widget.focusedProviderId !== "")
                    console.error("SMOKE FAIL: openProvider accepted an unknown provider");
                if (widget.openProvider("claude") !== "PROVIDER_FOCUSED" || widget.focusedProviderId !== "claude")
                    console.error("SMOKE FAIL: openProvider did not focus the provider");
                if (!fakePopout.shouldBeVisible || widget.dashboardView.parentPopout !== fakePopout)
                    console.error("SMOKE FAIL: openProvider toggled an open popout");
                widget.focusedProviderId = "";
                console.warn("FULL_UI_SMOKE_OK");
                root.step = 7;
            }
        }
    }
}
QML
# No provider keys, real user settings, session bus or external HTTP in this fixture.
env -i HOME="$TMP/home" PATH="$TMP/bin:$PATH" LANG=en_US.UTF-8 AIOC_TEST_PLUGIN_DIR="$TMP/plugin" \
    AIOC_TEST_POINTER="${AIOC_TEST_POINTER:-0}" \
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
if ! grep -q 'FULL_UI_SMOKE_OK' "$TMP/log" || grep -Ei 'SMOKE FAIL|QtQuickTest::fail|TypeError|ReferenceError|binding loop|Failed to load configuration|Cannot assign|Unable to assign|Invalid property assignment|is not a type' "$TMP/log"; then
    printf '%s\n' "$(<"$TMP/log")" >&2
    exit 1
fi
# The same handler DMS exposes: `dms ipc call aiOverviewControl focus <id>`.
ipc() {
    env -i HOME="$TMP/home" PATH="$PATH" WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
        timeout 5 qs ipc -p "$TMP/shell.qml" call aiOverviewControl "$@" 2>&1
}
if [[ "$(ipc focus nope)" != UNKNOWN_PROVIDER || "$(ipc focus codex)" != PROVIDER_FOCUSED ]]; then
    printf 'IPC focus failed: %s / %s\n' "$(ipc focus nope)" "$(ipc focus codex)" >&2
    exit 1
fi
echo 'OK: full widget, pills (names/compact), dashboard alignment, settings/window and currency bindings'
echo 'OK: notification click IPC focuses a provider without toggling an open popout'
if [[ "${AIOC_TEST_POINTER:-0}" == 1 ]]; then
    echo 'OK: fast pointer drag reorders pinned cards without scrolling the page'
fi
