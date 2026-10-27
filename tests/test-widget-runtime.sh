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
# DMS 2.0 keeps renamed widgets (DankToggle -> DToggle, …) as wrappers that
# log a deprecation when instantiated. Lazily loaded ones (tooltips, dialogs)
# may never instantiate here, so also reject any type whose DMS file is a
# deprecation wrapper.
deprecated=()
while IFS= read -r type; do
    for dir in Widgets Common Modules/Plugins Services DCommon/Widgets; do
        file="$IMPORTS/qs/$dir/$type.qml"
        if [[ -f "$file" ]] && grep -q 'Deprecation\.' "$file"; then
            deprecated+=("$type ($dir)")
        fi
    done
done < <(grep -ohE '\b[A-Z][A-Za-z0-9]+\b' "$ROOT"/*.qml | sort -u)
if (( ${#deprecated[@]} )); then
    printf 'FAIL: deprecated DMS types in plugin QML: %s\n' "${deprecated[*]}" >&2
    exit 1
fi
TMP="$(mktemp -d)"
pid=""
trap 'if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugin/providers" "$TMP/home" "$TMP/bin"
cp "$ROOT"/*.qml "$ROOT"/*.js "$ROOT/plugin.json" "$ROOT/qmldir" "$TMP/plugin/"
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
if [[ "${1:-}" == claude-work* ]]; then
    # The widget must transmit literal profile definitions and retention through
    # both refresh and retry processes, not only through direct adapter tests.
    jq -n --arg selection "$1" --arg retention "${AIOC_HISTORY_MAX:-}" \
        --argjson profiles "${AIOC_CLAUDE_PROFILES:-null}" '
      if $retention != "321" or $profiles["claude-work"].configDir != "/tmp/work account"
          or $profiles["claude-personal"].configDir != "/tmp/personal" then
        [{provider:"claude-work",error:{message:"Missing fixture environment"}}]
      else $selection | split(",") | map(. as $id | {
        provider:$id, source:"claude-local",
        usage:{identity:{providerID:$id},
          primary:{usedPercent:(if $id == "claude-work" then 73 else 12 end),windowMinutes:300},
          secondary:{usedPercent:(if $id == "claude-work" then 81 else 22 end),windowMinutes:10080}},
        analytics:(if $id == "claude-work" then
            {weekTokens:900,weekModels:"opus:900",weekProjects:"/work/app:900",rateLimitTier:"default_claude_max_20x"}
          else
            {weekTokens:100,weekModels:"sonnet:100",weekProjects:"/home/me:100",rateLimitTier:"default_claude_pro"}
          end) + {todayCost:1.25,dailyTokens:[0,0,0,0,0,0,0]}
      }) end'
    exit
fi
printf '[{"provider":"codex","name":"Codex","usage":{"provider":"codex","identity":{"providerID":"codex"},"primary":{"usedPercent":25,"windowMinutes":300},"secondary":{"usedPercent":15,"windowMinutes":10080}}}]\n'
SH
chmod +x "$TMP/plugin/providers/get-provider-usage"
# Stand-in for the consumable redemption: the real script is never run here.
cat > "$TMP/plugin/providers/reset-provider-limits" <<'SH'
#!/usr/bin/env bash
printf '{"provider":"%s","result":"reset","resetsLeft":1,"message":"fixture"}\n' "$1"
SH
chmod +x "$TMP/plugin/providers/reset-provider-limits"
# Ready for whichever provider is checked first, so the settings health status
# can be asserted after a selection change.
cat > "$TMP/plugin/providers/get-provider-health" <<'SH'
#!/usr/bin/env bash
printf '[{"provider":"%s","status":"ready","detail":"Ready"}]\n' "${1%%,*}"
SH
chmod +x "$TMP/plugin/providers/get-provider-health"
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
        Plugin.AiOverviewDashCard { id: dashCard; width: 300; height: 300 }
    }
    Plugin.AiOverviewSettingsWindow { visible: false }
    // DMS injects pluginService after the component is built; this instance
    // starts without it to mirror that first-load path.
    Plugin.AiOverviewControlSettings { id: lateSettings; visible: false }
    Component.onCompleted: {
        // DMS uses cache-busted file URLs, not the directory import above.
        // Compile the real entry point through that same public Qt interface.
        for (let attempt = 0; attempt < 3; attempt++) {
            const url = "file://" + Quickshell.env("AIOC_TEST_PLUGIN_DIR") + "/AiOverviewControlWidget.qml?t=" + attempt;
            const component = Qt.createComponent(url, Component.PreferSynchronous);
            if (component.status !== Component.Ready) {
                console.error("SMOKE FAIL: cache-busted widget: " + component.errorString());
                return;
            }
        }
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            if (root.step === 0) {
                // Empty-provider construction catches bindings that visibility cannot guard.
                // Real DMS injects a physical plugin path; qs directory imports use a VFS URL.
                widget._pluginDir = Quickshell.env("AIOC_TEST_PLUGIN_DIR");
                lateSettings.pluginService = service;
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
                const remaining = settings.content.find(item => item.text === settings.t("settings.show_remaining", "Show remaining quota"));
                if (!remaining || remaining.checked) { console.error("SMOKE FAIL: remaining quota default/control"); return; }
                remaining.toggled(true);
                widget.pluginData = service.data;
                if (service.data.showRemainingQuota !== "true" || widget.quotaDisplayPercent(25) !== 75
                    || widget.quotaDisplayPercent(0) !== 100 || widget.quotaDisplayPercent(100) !== 0
                    || widget.quotaDisplayPercent(150) !== 0 || widget.quotaDisplayPercent(-10) !== 100
                    || widget.pillPercentFor(widget.providers[0]) !== 25 || widget.providerPercent(widget.providers[0]) !== 25) {
                    console.error("SMOKE FAIL: remaining quota persistence or raw-consumption invariant"); return;
                }
                widget.focusProvider("codex");
                root.step = 3;
            } else if (root.step === 3) {
                const cardPercent = input.findChild(widget.dashboardView, "provider-percent-codex");
                const horizontal = input.findChild(hPill.item, "pill-entry-codex");
                if (!cardPercent || cardPercent.children.find(item => item.text === widget.quotaPercentText(25)) === undefined
                    || !horizontal || horizontal.children.find(item => item.text === "75%") === undefined
                    || widget.formatUsageLine({usedPercent: 25}).indexOf(widget.quotaPercentText(25)) !== 0
                    || widget.pillTooltipText().indexOf(widget.quotaPercentText(25)) < 0) {
                    console.error("SMOKE FAIL: remaining quota pill, dashboard or tooltip"); return;
                }
                settings.resetToDefaults();
                widget.pluginData = service.data;
                if (service.data.showRemainingQuota !== "false" || widget.quotaDisplayPercent(25) !== 25) {
                    console.error("SMOKE FAIL: remaining quota reset"); return;
                }
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
                // Changing the selection must re-run the readiness check even
                // though the initial check already completed (regression: the
                // status stuck on "Checking…" until a manual re-check).
                settings.selectedIds = ["claude"];
                root.step = 7;
            } else if (root.step === 7) {
                const health = settings.providerHealth["claude"];
                if (!health || health.status !== "ready")
                    console.error("SMOKE FAIL: selection change did not re-run health: " + JSON.stringify(settings.providerHealth));
                if (lateSettings.selectedIds.join(",") !== "codex" || !lateSettings.providerHealth["codex"])
                    console.error("SMOKE FAIL: late pluginService did not load selection and health: "
                        + JSON.stringify({ids: lateSettings.selectedIds, health: lateSettings.providerHealth}));
                for (const values of [["codex", "Bad", "/tmp/config"], ["claude-relative", "Bad", "relative"]]) {
                    if (settings.addClaudeProfile(values[0], values[1], values[2])) {
                        console.error("SMOKE FAIL: accepted invalid Claude profile"); return;
                    }
                }
                input.findChild(settings, "claude-profile-id").text = "claude-work";
                input.findChild(settings, "claude-profile-name").text = "Claude Work";
                input.findChild(settings, "claude-profile-dir").text = "/tmp/work account";
                input.findChild(settings, "claude-profile-add").clicked();
                widget.pluginData = service.data;
                if (!settings.isSelected("claude-work") || widget.providerName("claude-work") !== "Claude Work"
                    || widget.availableProviderOptions.indexOf("claude-work") < 0
                    || settings.allProviders.find(p => p.id === "claude-work") === undefined
                    || settings.addClaudeProfile("claude-work", "Duplicate", "/tmp/other")
                    || widget.notificationWindowKey("claude-work", {windowMinutes: 300}) === widget.notificationWindowKey("claude", {windowMinutes: 300})
                    || widget.providerConsoleUrl("claude-work", "") !== widget.providerConsoleUrl("claude", "")) {
                    console.error("SMOKE FAIL: Claude profile creation, identity or catalog"); return;
                }
                settings.addClaudeProfile("claude-personal", "Personal", "/tmp/personal");
                settings.content.find(item => item.text === settings.t("settings.show_remaining", "Show remaining quota")).toggled(true);
                settings.saveValue("historyRetention", "321");
                widget.pluginData = service.data;
                widget.providerSelection = "claude-work,claude-personal";
                widget.allExpanded = true;
                root.step = 8;
            } else if (root.step === 8 && !widget.isLoading) {
                // refresh() is dropped while an earlier fetch is in flight; on a
                // slow runner that fetch still carries the old selection.
                if (!widget.binaryReady) {
                    console.error("SMOKE FAIL: provider runtime unavailable (bash, jq or curl missing)"); return;
                }
                const requestId = widget.usageRequestId;
                widget.refresh();
                if (widget.usageRequestId === requestId) return;
                root.step = 9;
            } else if (root.step === 9 && !widget.isLoading) {
                if (widget.successfulProviders.length !== 2 || widget.errorProviders.length !== 0
                    || widget.providers[0].analytics.weekTokens !== 900 || widget.providers[1].analytics.weekTokens !== 100
                    || widget.pillPercentFor(widget.providers[0]) !== 73 || widget.quotaDisplayPercent(73) !== 27) {
                    console.error("SMOKE FAIL: simultaneous profile refresh, analytics or remaining quota: "
                        + JSON.stringify(widget.providers.map(p => p.provider))); return;
                }
                for (const pair of [["claude-work", 73], ["claude-personal", 12]]) {
                    const percent = input.findChild(widget.dashboardView, "provider-percent-" + pair[0]);
                    const pill = input.findChild(hPill.item, "pill-entry-" + pair[0]);
                    if (!percent || !percent.children.find(item => item.text === widget.quotaPercentText(pair[1]))
                        || !pill || !pill.children.find(item => item.text === (100 - pair[1]) + "%")) {
                        console.error("SMOKE FAIL: independent profile card/pill remaining display: " + pair[0]); return;
                    }
                }
                // Each profile renders its own details panel from its own item.
                for (const expected of [["claude-work", 900, "Opus"], ["claude-personal", 100, "Sonnet"]]) {
                    const panel = input.findChild(widget.dashboardView, "claude-details-" + expected[0]);
                    if (!panel || !panel.visible || !panel.details || panel.details.weekTokens !== expected[1]
                        || panel.details.models.length === 0 || panel.details.models[0].name !== expected[2]) {
                        console.error("SMOKE FAIL: per-profile Claude details panel: " + expected[0]); return;
                    }
                }
                const component = Qt.createComponent("file://" + Quickshell.env("AIOC_TEST_PLUGIN_DIR") + "/AiOverviewControlSettings.qml?t=reopen", Component.PreferSynchronous);
                const reopened = component.createObject(scene.contentItem, {visible: false, pluginService: service});
                if (!reopened || Object.keys(reopened.claudeProfiles).length !== 2 || !reopened.isSelected("claude-work")) {
                    console.error("SMOKE FAIL: persisted profiles do not survive settings reconstruction"); return;
                }
                reopened.destroy();
                widget.openProvider("claude-work");
                widget.retryProvider("claude-work");
                root.step = 10;
            } else if (root.step === 10 && widget.retryingProviderId === "") {
                if (!input.findChild(widget.dashboardView, "provider-header-claude-work") || widget.focusedProviderId !== "claude-work"
                    || widget.providers[0].error || widget.providers[0].usage.primary.usedPercent !== 73
                    || widget.providers[1].usage.primary.usedPercent !== 12) {
                    console.error("SMOKE FAIL: Claude profile retry isolation or focus"); return;
                }
                widget.barWindowOverrides = "claude-work:secondary";
                widget.pinnedProvidersCsv = "claude-work,claude-personal";
                root.step = 11;
            } else if (root.step === 11) {
                const pill = input.findChild(hPill.item, "pill-entry-claude-work");
                if (widget.pillPercentFor(widget.providers[0]) !== 81 || widget.providerPercent(widget.providers[0]) !== 73
                    || !pill.children.find(item => item.text === "19%")) {
                    console.error("SMOKE FAIL: remaining profile secondary window changed primary data"); return;
                }
                settings.selectedIds = ["claude-work"];
                settings.pinnedIds = ["claude-work"];
                settings.pillIds = ["claude-work"];
                settings.saveValue("barWindowOverrides", "claude-work:secondary");
                settings.saveValue("notifyThresholds", "claude-work:80");
                settings.removeClaudeProfile("claude-work");
                widget.pluginData = service.data;
                if (settings.claudeProfiles["claude-work"] || settings.isSelected("claude-work")
                    || settings.pinnedIds.length !== 0 || settings.pillIds.indexOf("claude-work") >= 0
                    || settings.loadValue("barWindowOverrides", "bad") !== "" || settings.loadValue("notifyThresholds", "bad") !== ""
                    || widget.availableProviderOptions.indexOf("claude-work") >= 0 || settings.selectedIds.length === 0) {
                    console.error("SMOKE FAIL: Claude profile removal/override cleanup"); return;
                }
                settings.resetToDefaults();
                if (Object.keys(settings.claudeProfiles).length !== 0 || settings.loadValue("showRemainingQuota", "true") !== "false") {
                    console.error("SMOKE FAIL: simultaneous profile/remaining reset"); return;
                }
                // Credits, extra usage and a consumable reset on two cards.
                widget.providers = [
                    {provider: "codex", usage: {primary: {usedPercent: 25}, secondary: {usedPercent: 10}},
                     billing: {credits: {hasCredits: true, unlimited: false, balance: 40}, spendControl: null},
                     limitResets: {supported: true, available: 2, usableNow: true, eligible: true,
                        items: [{id: "r1", title: "Full reset", resetsLeft: 1, usableNow: true, expiresAt: "2099-01-02T00:00:00Z"}]}},
                    {provider: "claude", usage: {primary: {usedPercent: 50}},
                     billing: {extraUsage: {enabled: true, used: 0.5, limit: 1, currency: "BRL", limitReached: false},
                        credits: {balance: 55, currency: "BRL", promo: 55, expiresAt: "2099-10-22T00:00:00Z"}},
                     limitResets: {supported: true, available: 0, usableNow: false, eligible: false, reason: "no_grant", items: []}}];
                widget.allExpanded = true;
                root.step = 12;
            } else if (root.step === 12) {
                const codexReset = input.findChild(widget.dashboardView, "provider-reset-codex");
                const claudeReset = input.findChild(widget.dashboardView, "provider-reset-claude");
                const extras = input.findChild(widget.dashboardView, "account-extras-claude");
                if (!codexReset || !codexReset.actionEnabled || !claudeReset || claudeReset.actionEnabled
                    || !extras || !extras.visible || !extras.showSpend || !extras.showCredits
                    || widget.formatMoney(55, "BRL").indexOf("R$") !== 0
                    || String(widget.freshUrl("DashboardContent.qml")).indexOf("DashboardContent.qml?v=" + widget._loadToken) < 0
                    || widget.resetBlockedText(widget.providerResets(widget.providers[1])).length === 0) {
                    console.error("SMOKE FAIL: credits panel or reset button state"); return;
                }
                codexReset.triggered();
                root.step = 13;
            } else if (root.step === 13) {
                const dialog = input.findChild(widget.dashboardView, "reset-confirm-dialog");
                const confirm = input.findChild(widget.dashboardView, "reset-confirm-button");
                if (widget.confirmResetProviderId !== "codex" || !dialog || !dialog.visible || !confirm || !confirm.actionEnabled) {
                    console.error("SMOKE FAIL: reset confirmation did not open"); return;
                }
                confirm.triggered();
                root.step = 14;
            } else if (root.step === 14 && widget.resettingProviderId === "" && dashCard.items.length > 0) {
                if (!widget.lastResetResult || widget.lastResetResult.result !== "reset"
                    || widget.resetResultText(widget.lastResetResult).length === 0) {
                    console.error("SMOKE FAIL: reset result " + JSON.stringify(widget.lastResetResult)); return;
                }
                // The bar widget publishes a snapshot that the DankDash card reads.
                if (dashCard.items.length === 0 || dashCard.items[0].id !== "claude" || dashCard.rows < 2) {
                    console.error("SMOKE FAIL: dash card did not read the widget snapshot " + JSON.stringify(dashCard.snapshot)); return;
                }
                // Shrink the card to the smallest height that still lists every
                // provider; the next tick checks the rows once they are laid out.
                const listed = dashCard.snapshot.items.length;
                let h = dashCard.height;
                while (h > 1 && dashCard.rows >= listed)
                    dashCard.height = --h;
                dashCard.height = h + 1;
                root.step = 15;
            } else if (root.step === 15) {
                // With the theme's bar height and spacing, every row still fits.
                // The offscreen window never polishes, so lay the columns out first.
                const layout = item => { for (const c of item.children) layout(c); if (typeof item.forceLayout === "function") item.forceLayout(); };
                layout(dashCard);
                // Content leaves (not the full-size card background) must keep the
                // same margin at the bottom as the card's padding at the top.
                const leaves = [];
                const collect = item => {
                    if (!item.visible) return;
                    const shown = Array.from(item.children).filter(c => c.visible);
                    if (shown.length === 0 && item.height > 0 && item.height < dashCard.height) leaves.push(item);
                    shown.forEach(collect);
                };
                collect(dashCard);
                const top = Math.min(...leaves.map(l => l.mapToItem(dashCard, 0, 0).y));
                const bottom = Math.max(...leaves.map(l => l.mapToItem(dashCard, 0, l.height).y));
                if (dashCard.items.length !== dashCard.snapshot.items.length || bottom > dashCard.height - top + 0.5) {
                    console.error("SMOKE FAIL: dash card rows overflow at height " + dashCard.height + ": " + bottom + " > " + (dashCard.height - top)); return;
                }
                dashCard.height = 300;
                widget.confirmResetProviderId = "";
                widget.allExpanded = false;
                widget.providers = [{provider: "codex", usage: {primary: {usedPercent: 25}}}];
                console.warn("FULL_UI_SMOKE_OK");
                root.step = 16;
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
    timeout 36 qs --no-color -p "$TMP/shell.qml" > "$TMP/log" 2>&1 &
pid=$!
for _ in {1..290}; do
    grep -q 'FULL_UI_SMOKE_OK' "$TMP/log" && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if ! grep -q 'FULL_UI_SMOKE_OK' "$TMP/log" || grep -Ei 'SMOKE FAIL|QtQuickTest::fail|TypeError|ReferenceError|binding loop|Failed to load configuration|Cannot assign|Unable to assign|Invalid property assignment|is not a type|i18n load failed|File name case mismatch|is deprecated and will be removed' "$TMP/log"; then
    printf '%s\n' "$(<"$TMP/log")" >&2
    exit 1
fi
# The same handler DMS exposes: `dms ipc call aiOverviewControl focus <id>`.
ipc() {
    # env -i also drops the locale; Qt warns on stdout for the resulting ASCII
    # locale, which would corrupt the exact IPC response asserted below.
    env -i HOME="$TMP/home" PATH="$PATH" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
        WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
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
