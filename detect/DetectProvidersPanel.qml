import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import ".."
import "ProviderDetect.js" as ProviderDetect

// "Detect providers": scans this computer for providers that are already set
// up and tracks the ones the user ticks. The dashboard opens it from the
// header's magnifier and the settings page embeds it in the Providers group,
// so both offer the same providers for the same reasons. The host owns the
// selection: the panel only emits applyRequested(ids).
//
// The scan is providers/get-provider-health over the whole catalog: it checks
// installed commands, sign-in files and variable *names*, reads nothing from
// a provider's API and never unlocks the desktop keyring.
Column {
    id: panel

    // providers/get-provider-health, as an absolute path.
    property string healthScript: ""
    // Providers to scan, as [{id, name}] in display order.
    property var catalog: []
    // Providers already tracked.
    property var trackedIds: []
    // The host's translator: function(key, fallback, params), and its locale,
    // so every text re-translates when the language changes.
    property var translate: null
    property string locale: ""
    property color logoColor: Theme.primary
    // The dashboard sheet scans as soon as it opens; the settings page waits
    // for the button so opening settings never runs a scan.
    property bool autoScan: false
    // The dashboard sheet has its own close action next to the title.
    property bool closable: false
    // Tallest the panel may grow; the results list scrolls past it. The
    // settings page leaves it unbounded.
    property real maxHeight: Infinity
    readonly property real maxResultsHeight: Math.max(160, maxHeight - titleRow.height - footer.height - spacing * 2)

    signal applyRequested(var ids)
    signal closeRequested

    // idle | scanning | results | applied | failed
    property string phase: "idle"
    property var result: ({found: [], possible: [], tracked: [], scanned: 0})
    property var picked: []
    property var appliedNames: []
    property bool _scanDone: false
    property bool _minimumElapsed: false
    property var _pendingResult: null

    readonly property int newCount: result.found.length + result.possible.length
    readonly property bool hasNew: newCount > 0

    spacing: Theme.spacingM

    function t(key, fallback, params) {
        panel.locale;
        if (translate)
            return translate(key, fallback, params);
        let text = String(fallback);
        for (const name in (params || {}))
            text = text.split("{" + name + "}").join(String(params[name]));
        return text;
    }

    function scan() {
        if (healthScript.length === 0 || scanProcess.running)
            return;
        const ids = (catalog || []).map(function(entry) { return entry.id; });
        if (ids.length === 0)
            return;
        phase = "scanning";
        _scanDone = false;
        _minimumElapsed = false;
        _pendingResult = null;
        scanProcess.command = ["bash", healthScript, ids.join(",")];
        scanProcess.running = true;
        minimumScan.restart();
    }

    function reset() {
        if (scanProcess.running)
            scanProcess.running = false;
        minimumScan.stop();
        phase = "idle";
        picked = [];
        appliedNames = [];
    }

    // Shows the result once the scan finished and the short minimum scan
    // time passed: a scan that answers in 80 ms would otherwise flash.
    function _settle() {
        if (!_scanDone || !_minimumElapsed)
            return;
        if (_pendingResult === null) {
            phase = "failed";
            return;
        }
        result = ProviderDetect.classify(_pendingResult, catalog, trackedIds);
        picked = ProviderDetect.defaultPicks(result);
        phase = "results";
    }

    function _finish(items) {
        if (phase !== "scanning")
            return;
        _pendingResult = items;
        _scanDone = true;
        _settle();
    }

    function isPicked(id) { return picked.indexOf(id) >= 0; }

    function toggle(id) { picked = ProviderDetect.toggled(picked, id); }

    function setAllPicked(on) {
        picked = on ? result.found.concat(result.possible).map(function(row) { return row.id; }) : [];
    }

    function apply() {
        if (picked.length === 0)
            return;
        const ids = picked.slice();
        const names = [];
        const rows = result.found.concat(result.possible);
        for (let i = 0; i < rows.length; i++) {
            if (ids.indexOf(rows[i].id) >= 0)
                names.push(rows[i].name);
        }
        appliedNames = names;
        phase = "applied";
        applyRequested(ids);
    }

    function evidenceText(row) {
        const label = row.label;
        switch (row.kind) {
        case "key":
            return t("detect.evidence.key", "{label} is set", {label: label});
        case "login":
            return t("detect.evidence.login", "Signed in · {label}", {label: label});
        case "local":
            return t("detect.evidence.local", "Local data · {label}", {label: label});
        case "vault":
            return t("detect.evidence.vault", "Keyring entry configured");
        case "cli":
            return t("detect.evidence.cli", "{label} installed · sign-in not verified", {label: label});
        case "keyring":
            return t("detect.evidence.keyring", "Desktop keyring available · sign-in not verified");
        }
        return t("detect.evidence.ready", "Ready");
    }

    function evidenceIcon(kind) {
        const icons = {key: "key", login: "verified_user", local: "folder_open", vault: "lock", cli: "terminal", keyring: "lock_open"};
        return icons[kind] || "check_circle";
    }

    Component.onCompleted: if (autoScan) Qt.callLater(scan)

    Process {
        id: scanProcess
        stdout: StdioCollector {
            onStreamFinished: {
                let items = null;
                try {
                    const parsed = JSON.parse(text);
                    items = Array.isArray(parsed) ? parsed : null;
                } catch (error) {
                    items = null;
                }
                panel._finish(items);
            }
        }
        onExited: code => {
            if (code !== 0)
                panel._finish(null);
        }
    }

    Timer {
        id: minimumScan
        interval: 650
        onTriggered: {
            panel._minimumElapsed = true;
            panel._settle();
        }
    }

    // ---- Title ----------------------------------------------------------
    RowLayout {
        id: titleRow
        width: parent.width
        spacing: Theme.spacingM

        Rectangle {
            Layout.alignment: Qt.AlignTop
            width: 40
            height: 40
            radius: 20
            color: Theme.withAlpha(panel.phase === "applied" ? Theme.success : Theme.primary, 0.14)
            border.width: 1
            border.color: Theme.withAlpha(panel.phase === "applied" ? Theme.success : Theme.primary, 0.3)

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }

            DIcon {
                id: titleIcon
                anchors.centerIn: parent
                name: panel.phase === "applied" ? "check_circle" : (panel.phase === "failed" ? "error" : "travel_explore")
                size: 20
                color: panel.phase === "applied" ? Theme.success : (panel.phase === "failed" ? Theme.error : Theme.primary)

                // A magnifier sweeping over the machine while the scan runs.
                SequentialAnimation on rotation {
                    running: panel.phase === "scanning"
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation {
                        from: 0
                        to: -18
                        duration: 260
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        from: -18
                        to: 18
                        duration: 520
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        from: 18
                        to: 0
                        duration: 260
                        easing.type: Easing.InQuad
                    }
                }
            }
        }

        Column {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            StyledText {
                width: parent.width
                text: panel.phase === "applied"
                    ? panel.t("detect.applied_title", "Now tracking {names}", {names: panel.appliedNames.join(", ")})
                    : panel.t("detect.title", "Detect providers")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
            }

            StyledText {
                objectName: "detect-status"
                width: parent.width
                color: panel.phase === "failed" ? Theme.error : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                text: {
                    if (panel.phase === "scanning")
                        return panel.t("detect.scanning", "Checking {count} providers on this computer…", {count: (panel.catalog || []).length});
                    if (panel.phase === "results")
                        return panel.t("detect.summary", "{found} ready to track · {count} providers checked", {found: panel.result.found.length, count: panel.result.scanned});
                    if (panel.phase === "applied")
                        return panel.t("detect.applied_body", "Added to the dashboard and the bar. Fetching their usage now.");
                    if (panel.phase === "failed")
                        return panel.t("detect.failed", "The check could not run. Try again.");
                    return panel.t("detect.intro", "Find AI tools, sign-ins and API keys already set up on this computer, then track them in one click.");
                }
            }
        }

        HeaderAction {
            visible: panel.closable
            Layout.alignment: Qt.AlignTop
            position: "single"
            iconName: "close"
            accent: Theme.error
            hoverRotation: 90
            label: panel.t("header.close", "Close")
            onTriggered: panel.closeRequested()
        }
    }

    // ---- Privacy note -------------------------------------------------------
    Row {
        visible: panel.phase === "idle" || panel.phase === "scanning"
        width: parent.width
        spacing: Theme.spacingS

        DIcon {
            name: "shield_lock"
            size: 14
            color: Theme.surfaceVariantText
        }

        StyledText {
            width: parent.width - 14 - Theme.spacingS
            text: panel.t("detect.privacy", "Only checks which tools are installed, which sign-in files exist and which variable names are set. Nothing leaves this computer, and the desktop keyring is never unlocked.")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall - 1
            wrapMode: Text.WordWrap
        }
    }

    // ---- Scanning -----------------------------------------------------------
    Row {
        visible: panel.phase === "scanning"
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spacingS
        height: 40

        DSpinner {
            anchors.verticalCenter: parent.verticalCenter
            size: 22
            running: panel.phase === "scanning"
        }
    }

    // ---- Results ------------------------------------------------------------
    // Scrolls on its own when the host caps the panel height (the dashboard
    // sheet), so the title and the actions below always stay in view.
    Flickable {
        id: resultsView
        objectName: "detect-results"
        visible: panel.phase === "results"
        width: parent.width
        height: Math.min(resultsColumn.implicitHeight, panel.maxResultsHeight)
        contentWidth: width
        contentHeight: resultsColumn.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ScrollBar.vertical: ScrollBar {
            policy: resultsView.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Column {
            id: resultsColumn
            width: resultsView.width - (resultsView.interactive ? Theme.spacingM : 0)
            spacing: Theme.spacingM

            Column {
                visible: panel.phase === "results" && panel.result.found.length > 0
                width: parent.width
                spacing: Theme.spacingXS

                SectionHeader {
                    width: parent.width
                    title: panel.t("detect.section.found", "Ready to track")
                    count: panel.result.found.length
                    accent: Theme.success
                }

                Repeater {
                    model: panel.phase === "results" ? panel.result.found : []

                    DetectRow {
                        width: parent.width
                    }
                }
            }

            Column {
                visible: panel.phase === "results" && panel.result.possible.length > 0
                width: parent.width
                spacing: Theme.spacingXS

                SectionHeader {
                    width: parent.width
                    title: panel.t("detect.section.possible", "Installed, sign-in not verified")
                    count: panel.result.possible.length
                    accent: Theme.warning
                }

                StyledText {
                    width: parent.width
                    text: panel.t("detect.section.possible_hint", "Tick one once you are signed in to its tool; otherwise its card shows a sign-in error.")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: panel.phase === "results" ? panel.result.possible : []

                    DetectRow {
                        width: parent.width
                    }
                }
            }

            // Nothing new: say why, and how to fix the most common cause.
            StyledRect {
                visible: panel.phase === "results" && !panel.hasNew
                width: parent.width
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceText, 0.04)
                border.width: 1
                border.color: Theme.withAlpha(Theme.surfaceText, 0.08)
                implicitHeight: emptyColumn.implicitHeight + Theme.spacingM * 2

                Column {
                    id: emptyColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width
                        text: panel.result.tracked.length > 0
                            ? panel.t("detect.none_tracked", "Everything set up here is already tracked")
                            : panel.t("detect.none_title", "No provider set up on this computer was found")
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StyledText {
                visible: panel.phase === "results" && panel.result.tracked.length > 0
                width: parent.width
                text: panel.t("detect.already_tracked", "Already tracked: {names}", {
                    names: panel.result.tracked.map(function(row) { return row.name; }).join(", ")
                })
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
                wrapMode: Text.WordWrap
            }

            // The shell does not read a terminal's exports, the most common reason a
            // provider with a key is not found.
            Row {
                visible: panel.phase === "results"
                width: parent.width
                spacing: Theme.spacingS

                DIcon {
                    name: "lightbulb"
                    size: 14
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    width: parent.width - 14 - Theme.spacingS
                    text: panel.t("detect.env_hint", "Missing one? API keys exported only in a terminal are not visible to the shell: put them in ~/.config/environment.d/ and log in again, or add the provider by hand.")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ---- Actions ------------------------------------------------------------
    // Secondary actions on one line, the primary one full width under them:
    // long translations never push it out of a narrow sheet.
    Column {
        id: footer
        width: parent.width
        spacing: Theme.spacingS

        Flow {
            width: parent.width
            spacing: Theme.spacingS

            DButton {
                objectName: "detect-scan"
                visible: panel.phase !== "scanning"
                // Filled while it is the only action, a text button next to the
                // results. Colours rather than DButton's newer `variant`, which
                // Dux Shell 2.1 lacks.
                readonly property bool filled: panel.phase === "idle" || panel.phase === "failed"
                backgroundColor: filled ? Theme.primary : "transparent"
                textColor: filled ? Theme.primaryText : Theme.primary
                iconName: panel.phase === "idle" ? "travel_explore" : "refresh"
                text: panel.phase === "idle"
                    ? panel.t("detect.scan", "Scan this computer")
                    : panel.t("detect.scan_again", "Scan again")
                onClicked: panel.scan()
            }

            DButton {
                objectName: "detect-select-all"
                visible: panel.phase === "results" && panel.newCount > 1
                backgroundColor: "transparent"
                textColor: Theme.primary
                iconName: panel.picked.length === panel.newCount ? "remove_done" : "done_all"
                text: panel.picked.length === panel.newCount
                    ? panel.t("detect.select_none", "Select none")
                    : panel.t("detect.select_all", "Select all")
                onClicked: panel.setAllPicked(panel.picked.length !== panel.newCount)
            }
        }

        DButton {
            objectName: "detect-apply"
            visible: panel.phase === "results" && panel.hasNew
            width: parent.width
            enabled: panel.picked.length > 0
            iconName: "playlist_add"
            text: panel.t("detect.track", "Track selected ({count})", {count: panel.picked.length})
            onClicked: panel.apply()
        }
    }

    // ---- Pieces -------------------------------------------------------------
    component SectionHeader: RowLayout {
        id: header

        property string title: ""
        property int count: 0
        property color accent: Theme.primary

        spacing: Theme.spacingS

        StyledText {
            text: header.title
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
        }

        Rectangle {
            implicitWidth: countLabel.implicitWidth + Theme.spacingS * 2
            implicitHeight: 18
            radius: 9
            color: Theme.withAlpha(header.accent, 0.14)

            StyledText {
                id: countLabel
                anchors.centerIn: parent
                text: header.count
                color: header.accent
                font.pixelSize: Theme.fontSizeSmall - 2
                font.weight: Font.Bold
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    // One provider: tick box, logo, name and what was found.
    component DetectRow: StyledRect {
        id: row

        required property var modelData
        readonly property bool checked: panel.isPicked(modelData.id)
        readonly property bool hovered: rowMouse.containsMouse

        objectName: "detect-row-" + modelData.id
        implicitHeight: 52
        radius: Theme.cornerRadius
        color: checked ? Theme.withAlpha(Theme.primary, hovered ? 0.14 : 0.1) : Theme.withAlpha(Theme.surfaceText, hovered ? 0.07 : 0.04)
        border.width: 1
        border.color: Theme.withAlpha(checked ? Theme.primary : Theme.surfaceText, checked ? 0.32 : 0.08)
        activeFocusOnTab: true

        Accessible.role: Accessible.CheckBox
        Accessible.name: modelData.name
        Accessible.description: panel.evidenceText(modelData)
        Accessible.checkable: true
        Accessible.checked: checked
        Keys.onSpacePressed: panel.toggle(modelData.id)

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingM

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 20
                height: 20
                radius: 6
                color: row.checked ? Theme.primary : "transparent"
                border.width: row.checked ? 0 : 2
                border.color: Theme.withAlpha(Theme.surfaceText, 0.4)

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                DIcon {
                    anchors.centerIn: parent
                    name: "check"
                    size: 15
                    color: Theme.primaryText
                    visible: row.checked
                    scale: row.checked ? 1 : 0.4

                    Behavior on scale {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutBack
                        }
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 32
                height: 32
                radius: 16
                color: Theme.withAlpha(panel.logoColor, 0.12)

                ProviderLogo {
                    anchors.centerIn: parent
                    providerId: row.modelData.id
                    logoSize: 17
                    tintColor: panel.logoColor
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    text: row.modelData.name
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingXS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: panel.evidenceIcon(row.modelData.kind)
                        size: 12
                        color: ProviderDetect.isStrong(row.modelData) ? Theme.success : Theme.warning
                    }

                    StyledText {
                        width: parent.width - 12 - Theme.spacingXS
                        text: panel.evidenceText(row.modelData)
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall - 1
                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                row.forceActiveFocus();
                panel.toggle(row.modelData.id);
            }
        }
    }
}
