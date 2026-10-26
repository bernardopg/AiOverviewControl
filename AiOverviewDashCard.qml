import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash

// DankDash overview card: the providers closest to their limits. It reads the
// snapshot the bar widget writes after each refresh (dash-snapshot.json) and
// never polls a provider itself. Clicking it opens the full dashboard.
DashCardComponent {
    id: root

    readonly property var snapshot: {
        try {
            const parsed = JSON.parse(snapshotFile.text());
            return parsed && Array.isArray(parsed.items) ? parsed : null;
        } catch (error) {
            return null;
        }
    }
    readonly property bool wide: width >= DashMetrics.gridRowUnit * 2
    readonly property bool tall: height >= DashMetrics.gridRowUnit * 2
    // A square card shows one large number; larger cards list as many
    // providers as fit under the heading.
    readonly property bool compact: !wide && !tall
    readonly property real rowHeight: Theme.fontSizeSmall * 1.4 + Theme.spacingXS + Theme.spacingS + Theme.spacingS
    readonly property int rows: {
        if (compact)
            return 1;
        // The card pads its content, so fit rows into the content area.
        const fit = Math.max(1, Math.floor((heading.parent.height - heading.height) / rowHeight));
        const wanted = Number(options.count ?? 0);
        return wanted > 0 ? Math.min(wanted, fit) : fit;
    }
    readonly property var items: snapshot ? snapshot.items.slice(0, rows) : []
    readonly property bool remaining: snapshot ? snapshot.remaining === true : false

    tone: options.tone ?? ""
    clickable: true
    opensTab: false
    onClicked: Quickshell.execDetached(["dms", "ipc", "call", "aiOverviewControl", "toggle"])

    function t(key, fallback, params) {
        return AiOverviewControlI18n.tr(key, fallback, params);
    }

    function usageColor(percent) {
        if (percent >= 80)
            return Theme.error;
        if (percent >= 60)
            return Theme.warning;
        return Theme.success;
    }

    function shownPercent(item) {
        const used = Math.round(Number(item.percent) || 0);
        return remaining ? 100 - used : used;
    }

    function resetText(item) {
        const diff = item.resetsAt ? new Date(item.resetsAt).getTime() - Date.now() : NaN;
        if (!Number.isFinite(diff) || diff <= 0)
            return "";
        const minutes = Math.floor(diff / 60000);
        if (minutes < 60)
            return t("dash.reset_minutes", "resets in {count} min", {count: minutes});
        const hours = Math.floor(minutes / 60);
        if (hours < 48)
            return t("dash.reset_hours", "resets in {count} h", {count: hours});
        return t("dash.reset_days", "resets in {count} d", {count: Math.floor(hours / 24)});
    }

    FileView {
        id: snapshotFile
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/AiOverviewControl/dash-snapshot.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    // A file watch cannot start before the widget writes the first snapshot,
    // so look again until one exists, and while the dash is on screen.
    Timer {
        interval: 5000
        repeat: true
        running: root.snapshot === null || root.live
        onTriggered: snapshotFile.reload()
    }

    StyledText {
        id: heading
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        text: root.remaining ? t("dash.title_remaining", "AI quota left") : t("dash.title", "AI quota used")
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: root.mutedColor
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
    }

    StyledText {
        anchors.centerIn: parent
        width: parent.width
        visible: root.items.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: t("dash.empty", "Open the AiOverviewControl widget once to load providers.")
        font.pixelSize: Theme.fontSizeSmall
        color: root.mutedColor
    }

    // 1x1: the provider closest to its limit, as one large number.
    Column {
        visible: root.compact && root.items.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        NumericText {
            isMonospace: false
            text: root.items.length > 0 && !root.items[0].error ? root.shownPercent(root.items[0]) + "%" : "!"
            font.pixelSize: Theme.fontSizeXXLarge
            font.weight: Theme.fontWeightMedium
            color: root.items.length > 0 && !root.items[0].error ? root.usageColor(root.items[0].percent) : Theme.error
        }

        StyledText {
            width: parent.width
            text: root.items.length > 0 ? root.items[0].name : ""
            font.pixelSize: Theme.fontSizeSmall
            color: root.contentColor
            elide: Text.ElideRight
        }
    }

    // Wider or taller: one row per provider with a bar.
    Column {
        visible: !root.compact && root.items.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.topMargin: Theme.spacingS
        spacing: Theme.spacingS

        Repeater {
            model: root.compact ? [] : root.items

            Column {
                required property var modelData
                width: parent.width
                spacing: Theme.spacingXS

                Item {
                    width: parent.width
                    height: nameText.implicitHeight

                    StyledText {
                        id: nameText
                        wrapMode: Text.NoWrap
                        anchors.left: parent.left
                        anchors.right: valueText.left
                        anchors.rightMargin: Theme.spacingS
                        text: modelData.name
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: root.contentColor
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: valueText
                        anchors.right: parent.right
                        text: {
                            if (modelData.error)
                                return t("status.error", "Error");
                            const reset = root.width >= DashMetrics.gridRowUnit * 3 || root.tall ? root.resetText(modelData) : "";
                            const value = root.shownPercent(modelData) + "%";
                            return reset.length > 0 ? `${value} · ${reset}` : value;
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: modelData.error ? Theme.error : root.usageColor(modelData.percent)
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Theme.spacingS
                    radius: height / 2
                    color: root.chipColor

                    Rectangle {
                        width: modelData.error ? 0 : Math.max(height, parent.width * (Number(modelData.percent) || 0) / 100)
                        height: parent.height
                        radius: height / 2
                        color: root.usageColor(modelData.percent)
                    }
                }
            }
        }
    }
}
