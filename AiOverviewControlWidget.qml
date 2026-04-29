import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var providers: []
    property bool isLoading: false
    property bool hasError: false
    property string errorMessage: ""
    property string lastUpdated: ""
    property string rawJsonBuffer: ""
    property string rawStderrBuffer: ""
    property bool binaryReady: false
    property string resolvedBinaryPath: ""
    property int fetchTimeoutMs: 45000
    property bool usageDidTimeout: false
    property int usageRequestId: 0
    property int timedOutRequestId: -1
    property string providerSelection: (pluginData.providerSelection || "codex,claude,copilot").trim()
    property bool showErrorProviders: String(pluginData.showErrorProviders || "true") === "true"

    property int refreshIntervalMs: {
        const val = pluginData.refreshInterval;
        const parsed = val ? parseInt(val) : 120000;
        return Number.isFinite(parsed) ? parsed : 120000;
    }
    property string codexbarPath: (pluginData.codexbarPath || "").trim()
    property string sourceMode: pluginData.sourceMode || "cli"

    readonly property var selectedProviders: {
        const parts = providerSelection.split(",");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            const value = parts[i].trim().toLowerCase();
            if (value.length > 0 && result.indexOf(value) < 0) {
                result.push(value);
            }
        }
        return result.length > 0 ? result : ["codex"];
    }

    readonly property var successfulProviders: {
        const result = [];
        for (let i = 0; i < providers.length; i++) {
            const provider = providers[i];
            if (provider && provider.usage && !provider.error) {
                result.push(provider);
            }
        }
        return result;
    }

    readonly property var errorProviders: {
        const result = [];
        for (let i = 0; i < providers.length; i++) {
            const provider = providers[i];
            if (provider && provider.error) {
                result.push(provider);
            }
        }
        return result;
    }

    readonly property var providerData: {
        let bestProvider = null;
        let bestPercent = -1;
        for (let i = 0; i < successfulProviders.length; i++) {
            const provider = successfulProviders[i];
            const percent = Number(provider.usage && provider.usage.primary ? provider.usage.primary.usedPercent || 0 : 0);
            if (percent > bestPercent) {
                bestPercent = percent;
                bestProvider = provider;
            }
        }
        return bestProvider || (providers.length > 0 ? providers[0] : null);
    }
    readonly property bool hasProviderData: !!providerData && !!providerData.usage
    readonly property var usageData: hasProviderData ? providerData.usage : null
    readonly property var primaryWindow: usageData ? usageData.primary : null
    readonly property var secondaryWindow: usageData ? usageData.secondary : null
    readonly property var tertiaryWindow: usageData ? usageData.tertiary : null
    readonly property real primaryPercent: primaryWindow ? Number(primaryWindow.usedPercent || 0) : 0
    readonly property color heroAccent: getUsageColor(primaryPercent)

    readonly property string accountEmail: {
        if (!usageData) {
            return "";
        }
        if (usageData.identity && usageData.identity.accountEmail) {
            return usageData.identity.accountEmail;
        }
        return usageData.accountEmail || "";
    }

    readonly property string loginMethod: {
        if (!usageData) {
            return "";
        }
        if (usageData.identity && usageData.identity.loginMethod) {
            return usageData.identity.loginMethod;
        }
        return usageData.loginMethod || "";
    }

    readonly property var usageWindows: {
        const windows = [];
        if (primaryWindow) {
            windows.push({
                key: "primary",
                label: getWindowLabel(primaryWindow.windowMinutes),
                data: primaryWindow
            });
        }
        if (secondaryWindow) {
            windows.push({
                key: "secondary",
                label: getWindowLabel(secondaryWindow.windowMinutes),
                data: secondaryWindow
            });
        }
        if (tertiaryWindow) {
            windows.push({
                key: "tertiary",
                label: tertiaryWindow.resetDescription || "Tertiary",
                data: tertiaryWindow
            });
        }
        return windows;
    }

    readonly property string statusTitle: {
        if (isLoading && !hasProviderData) {
            return "Syncing usage";
        }
        if (hasError) {
            return "Needs attention";
        }
        if (!hasProviderData) {
            return "Waiting for data";
        }
        return "AI telemetry online";
    }

    readonly property string statusSubtitle: {
        if (isLoading && !hasProviderData) {
            return "Fetching usage windows from CodexBar.";
        }
        if (hasError) {
            return errorMessage;
        }
        if (!hasProviderData) {
            return "Run your configured AI CLIs and refresh to populate usage windows.";
        }
        const resetLabel = primaryWindow ? formatTimeUntil(primaryWindow.resetsAt) : "";
        if (!resetLabel) {
            return "Live session and weekly windows are available.";
        }
        return `Primary window resets in ${resetLabel}.`;
    }

    readonly property string barText: {
        if (hasError && !hasProviderData) {
            return "ERR";
        }
        if (isLoading && !hasProviderData) {
            return "...";
        }
        if (!hasProviderData) {
            return "N/A";
        }
        return `${Math.round(primaryPercent)}%`;
    }

    readonly property string resolvedPath: binaryReady && resolvedBinaryPath.length > 0 ? resolvedBinaryPath : "codexbar"

    function getUsageColor(percent) {
        if (percent >= 80) {
            return Theme.error;
        }
        if (percent >= 60) {
            return Theme.warning;
        }
        return Theme.success;
    }

    function capitalizeFirst(value) {
        if (!value) {
            return "";
        }
        return value.charAt(0).toUpperCase() + value.slice(1);
    }

    function getWindowLabel(windowMinutes) {
        if (!windowMinutes) {
            return "";
        }
        if (windowMinutes <= 300) {
            return "Session";
        }
        if (windowMinutes <= 10080) {
            return "Weekly";
        }
        return `${Math.floor(windowMinutes / 1440)}d`;
    }

    function formatTimeUntil(isoDate) {
        if (!isoDate) {
            return "";
        }
        const diff = new Date(isoDate).getTime() - Date.now();
        if (diff <= 0) {
            return "now";
        }
        const mins = Math.floor(diff / 60000);
        if (mins < 60) {
            return `${mins}m`;
        }
        const hours = Math.floor(mins / 60);
        if (hours < 24) {
            return `${hours}h ${mins % 60}m`;
        }
        const days = Math.floor(hours / 24);
        return `${days}d ${hours % 24}h`;
    }

    function formatUsageLine(windowData) {
        if (!windowData) {
            return "";
        }
        const percent = Math.round(Number(windowData.usedPercent || 0));
        const reset = formatTimeUntil(windowData.resetsAt);
        return reset.length > 0 ? `${percent}% · ${reset}` : `${percent}%`;
    }

    function formatUsageError(exitCode) {
        if (rawStderrBuffer.length > 0) {
            return rawStderrBuffer.trim();
        }
        if (sourceMode === "api") return "API mode needs provider API tokens in CodexBar configuration.";
        if (sourceMode === "oauth") return "OAuth mode requires provider authentication supported by CodexBar.";
        if (sourceMode === "web") return "Web mode currently depends on CodexBar web support and may be macOS-only.";
        return `codexbar exited with code ${exitCode}`;
    }

    function providerName(providerId) {
        const names = {
            codex: "Codex",
            claude: "Claude",
            copilot: "Copilot",
            cursor: "Cursor",
            gemini: "Gemini",
            openrouter: "OpenRouter",
            perplexity: "Perplexity",
            ollama: "Ollama",
            kilo: "Kilo",
            kiro: "Kiro",
            amp: "Amp",
            warp: "Warp"
        };
        return names[providerId] || capitalizeFirst(providerId || "provider");
    }

    function providerPercent(provider) {
        if (!provider || !provider.usage || !provider.usage.primary) {
            return 0;
        }
        return Number(provider.usage.primary.usedPercent || 0);
    }

    function providerErrorText(provider) {
        if (!provider || !provider.error) {
            return "";
        }
        return provider.error.message || provider.error.kind || "Provider returned an error.";
    }

    function detectBinary() {
        if (procDetect.running) {
            return;
        }
        resolvedBinaryPath = "";
        binaryReady = false;
        hasError = false;
        errorMessage = "";
        procDetect.running = true;
    }

    Component.onCompleted: detectBinary()

    Process {
        id: procDetect
        command: ["sh", "-c", "candidate=\"$1\"; if [ -n \"$candidate\" ] && [ -f \"$candidate\" ] && [ -x \"$candidate\" ]; then printf '%s\\n' \"$candidate\"; exit 0; fi; command -v codexbar 2>/dev/null || (test -x \"$HOME/.local/bin/codexbar\" && echo \"$HOME/.local/bin/codexbar\") || (test -x /usr/local/bin/codexbar && echo /usr/local/bin/codexbar) || true", "sh", root.codexbarPath]
        stdout: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (trimmed.length > 0) {
                    root.resolvedBinaryPath = trimmed;
                }
            }
        }
        onExited: code => {
            root.binaryReady = root.resolvedBinaryPath.length > 0;
            if (root.binaryReady) {
                root.refresh();
            } else {
                root.providers = [];
                root.hasError = true;
                root.errorMessage = root.codexbarPath.length > 0 ? "Configured codexbar path is invalid. Point to the executable file." : "codexbar not found. Install it or set its executable path in settings.";
            }
        }
    }

    Process {
        id: procUsage
        command: {
            const script = "set -u\n" +
                "bin=\"$1\"\n" +
                "providers_csv=\"$2\"\n" +
                "source_mode=\"$3\"\n" +
                "IFS=',' read -r -a providers <<< \"$providers_csv\"\n" +
                "first=1\n" +
                "printf '['\n" +
                "for provider in \"${providers[@]}\"; do\n" +
                "  provider=\"$(printf '%s' \"$provider\" | xargs)\"\n" +
                "  [ -z \"$provider\" ] && continue\n" +
                "  tmp_err=\"$(mktemp)\"\n" +
                "  cmd=(\"$bin\" usage --format json --provider \"$provider\")\n" +
                "  if [ -n \"$source_mode\" ]; then cmd+=(--source \"$source_mode\"); fi\n" +
                "  out=\"$(\"${cmd[@]}\" 2>\"$tmp_err\")\"\n" +
                "  status=$?\n" +
                "  if [ $first -eq 0 ]; then printf ','; fi\n" +
                "  first=0\n" +
                "  if [ $status -eq 0 ] && printf '%s' \"$out\" | node -e 'let s=\"\";process.stdin.on(\"data\",d=>s+=d);process.stdin.on(\"end\",()=>{JSON.parse(s);})' 2>/dev/null; then\n" +
                "    printf '%s' \"$out\" | node -e 'let s=\"\";process.stdin.on(\"data\",d=>s+=d);process.stdin.on(\"end\",()=>{const v=JSON.parse(s); const a=Array.isArray(v)?v:[v]; process.stdout.write(JSON.stringify(a.length===1?a[0]:a));})'\n" +
                "  else\n" +
                "    message=\"$(cat \"$tmp_err\")\"\n" +
                "    [ -z \"$message\" ] && message=\"$out\"\n" +
                "    [ -z \"$message\" ] && message=\"codexbar exited with status $status\"\n" +
                "    PROVIDER=\"$provider\" SOURCE=\"$source_mode\" STATUS=\"$status\" MESSAGE=\"$message\" node -e 'process.stdout.write(JSON.stringify({provider:process.env.PROVIDER,source:process.env.SOURCE,error:{code:Number(process.env.STATUS)||1,kind:\"runtime\",message:process.env.MESSAGE}}))'\n" +
                "  fi\n" +
                "  rm -f \"$tmp_err\"\n" +
                "done\n" +
                "printf ']'\n";
            return ["bash", "-lc", script, "bash", root.resolvedPath, root.selectedProviders.join(","), root.sourceMode];
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root.rawJsonBuffer += data
        }
        stderr: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (trimmed.length === 0) {
                    return;
                }
                if (root.rawStderrBuffer.length > 0) {
                    root.rawStderrBuffer += "\n";
                }
                root.rawStderrBuffer += trimmed;
            }
        }
        onExited: code => {
            const exitedRequestId = root.usageRequestId;
            usageTimeout.stop();
            root.isLoading = false;

            if (root.usageDidTimeout && root.timedOutRequestId === exitedRequestId) {
                root.usageDidTimeout = false;
                root.timedOutRequestId = -1;
                root.rawJsonBuffer = "";
                root.rawStderrBuffer = "";
                return;
            }

            if (code === 0 && root.rawJsonBuffer.length > 0) {
                try {
                    const payload = JSON.parse(root.rawJsonBuffer);
                    const list = Array.isArray(payload) ? payload : [payload];
                    const flattened = [];
                    for (let i = 0; i < list.length; i++) {
                        if (Array.isArray(list[i])) {
                            for (let j = 0; j < list[i].length; j++) {
                                flattened.push(list[i][j]);
                            }
                        } else {
                            flattened.push(list[i]);
                        }
                    }
                    root.providers = flattened;

                    if (root.successfulProviders.length === 0 && root.errorProviders.length > 0) {
                        root.hasError = true;
                        root.errorMessage = root.errorProviders[0].error.message || "Failed to fetch usage from providers.";
                    } else {
                        root.hasError = root.errorProviders.length > 0 && root.showErrorProviders;
                        root.errorMessage = root.errorProviders.length > 0 ? `${root.errorProviders.length} provider(s) need attention.` : "";
                    }
                    root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm:ss");
                } catch (error) {
                    root.hasError = true;
                    root.errorMessage = root.rawStderrBuffer.length > 0 ? root.rawStderrBuffer : "Failed to parse CodexBar output.";
                }
            } else if (code !== 0) {
                root.hasError = true;
                root.errorMessage = root.formatUsageError(code);
            }

            root.rawJsonBuffer = "";
            root.rawStderrBuffer = "";
        }
    }

    function refresh() {
        if (!binaryReady || procUsage.running || usageDidTimeout) {
            return;
        }
        hasError = false;
        isLoading = true;
        rawJsonBuffer = "";
        rawStderrBuffer = "";
        usageRequestId += 1;
        timedOutRequestId = -1;
        procUsage.running = true;
        usageTimeout.restart();
    }

    Timer {
        id: usageTimeout
        interval: root.fetchTimeoutMs
        repeat: false
        onTriggered: {
            if (procUsage.running) {
                root.timedOutRequestId = root.usageRequestId;
                root.usageDidTimeout = true;
                procUsage.running = false;
                root.isLoading = false;
                root.hasError = true;
                root.errorMessage = "codexbar timed out while fetching usage data.";
            }
        }
    }

    Timer {
        interval: root.refreshIntervalMs
        running: root.binaryReady
        repeat: true
        onTriggered: root.refresh()
    }

    component SurfaceButton: StyledRect {
        id: buttonRoot

        required property string iconName
        required property string label
        property string description: ""
        property bool compact: false
        property bool prominent: false
        property bool actionEnabled: true

        signal triggered

        implicitHeight: compact ? 42 : (description.length > 0 ? 58 : 48)
        radius: Theme.cornerRadius
        color: {
            if (!actionEnabled) {
                return Theme.surfaceContainer;
            }
            if (prominent) {
                return Theme.primaryContainer;
            }
            return buttonMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer;
        }
        border.width: 1
        border.color: {
            if (buttonRoot.activeFocus) {
                return Theme.primary;
            }
            if (prominent) {
                return Theme.withAlpha(Theme.primary, 0.38);
            }
            return buttonMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.18) : Theme.outlineVariant;
        }
        opacity: actionEnabled ? 1 : 0.54
        scale: actionEnabled && buttonMouse.containsMouse ? 1.01 : 1.0
        clip: true

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 140
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 140
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: compact ? Theme.spacingS : Theme.spacingM
            anchors.rightMargin: compact ? Theme.spacingS : Theme.spacingM
            anchors.topMargin: compact ? Theme.spacingS : Theme.spacingM
            anchors.bottomMargin: compact ? Theme.spacingS : Theme.spacingM
            spacing: compact ? Theme.spacingXS : Theme.spacingS

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: compact ? 24 : 28
                height: compact ? 24 : 28
                radius: width / 2
                color: buttonRoot.prominent ? Theme.withAlpha(Theme.primary, 0.18) : Theme.withAlpha(Theme.surfaceText, 0.08)

                DankIcon {
                    anchors.centerIn: parent
                    name: buttonRoot.iconName
                    size: compact ? 14 : 16
                    color: buttonRoot.prominent ? Theme.primary : Theme.surfaceText
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: description.length > 0 && !compact ? 2 : 0

                StyledText {
                    width: parent.width
                    text: buttonRoot.label
                    color: buttonRoot.prominent ? Theme.primary : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: !compact && buttonRoot.description.length > 0
                    width: parent.width
                    text: buttonRoot.description
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            enabled: buttonRoot.actionEnabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
            onClicked: buttonRoot.triggered()
        }
    }

    component SectionFrame: StyledRect {
        id: sectionRoot

        property string title: ""
        property string subtitle: ""
        property string aside: ""
        default property alias contentData: sectionBody.data

        width: parent ? parent.width : implicitWidth
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.surfaceText, 0.08)
        implicitHeight: sectionColumn.implicitHeight + Theme.spacingM * 2

        Column {
            id: sectionColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingS
                visible: sectionRoot.title.length > 0 || sectionRoot.subtitle.length > 0

                Column {
                    width: parent.width - (asideText.visible ? asideText.width + Theme.spacingS : 0)
                    spacing: 2

                    StyledText {
                        visible: sectionRoot.title.length > 0
                        width: parent.width
                        text: sectionRoot.title
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        visible: sectionRoot.subtitle.length > 0
                        width: parent.width
                        text: sectionRoot.subtitle
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }
                }

                StyledText {
                    id: asideText
                    visible: sectionRoot.aside.length > 0
                    text: sectionRoot.aside
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Column {
                id: sectionBody
                width: parent.width
                spacing: Theme.spacingS
            }
        }
    }

    component MetricTile: Rectangle {
        id: tile

        required property string label
        required property string value
        property color accentColor: Theme.primary

        implicitHeight: tileCol.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.withAlpha(accentColor, 0.08)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, 0.24)

        Column {
            id: tileCol
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: 3

            StyledText {
                width: parent.width
                text: tile.label
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: tile.value.length > 0 ? tile.value : "—"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            Rectangle {
                width: 26
                height: 26
                radius: 13
                color: Theme.withAlpha(root.heroAccent, 0.16)
                border.width: 1
                border.color: Theme.withAlpha(root.heroAccent, 0.28)

                DankIcon {
                    anchors.centerIn: parent
                    name: "monitoring"
                    size: 14
                    color: root.heroAccent
                }
            }

            StyledText {
                text: `${root.providerData ? root.providerName(root.providerData.provider) : "AI"} ${root.barText}`
                color: root.hasError ? Theme.error : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            Rectangle {
                width: 24
                height: 24
                radius: 12
                color: Theme.withAlpha(root.heroAccent, 0.16)
                border.width: 1
                border.color: Theme.withAlpha(root.heroAccent, 0.28)
                anchors.horizontalCenter: parent.horizontalCenter

                DankIcon {
                    anchors.centerIn: parent
                    name: "monitoring"
                    size: 13
                    color: root.heroAccent
                }
            }

            StyledText {
                text: root.barText
                color: root.hasError ? Theme.error : root.heroAccent
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 520
    popoutHeight: 760

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "AI Usage"
            detailsText: root.lastUpdated.length > 0 ? `Updated ${root.lastUpdated}` : "Live AI usage monitor"
            showCloseButton: true

            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: refreshArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                        DankIcon {
                            anchors.centerIn: parent
                            name: "refresh"
                            size: 16
                            color: Theme.surfaceText
                        }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                        }
                    }
                }
            }

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL

                Flickable {
                    id: contentFlick
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width - Theme.spacingM * 2
                    contentHeight: contentColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar {
                        anchors.right: parent.right
                        anchors.rightMargin: -Theme.spacingM
                    }

                    Column {
                        id: contentColumn
                        width: contentFlick.width
                        spacing: Theme.spacingM

                        StyledRect {
                            width: parent.width
                            radius: Theme.cornerRadius + 6
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.withAlpha(root.heroAccent, root.hasProviderData ? 0.34 : 0.18)
                            implicitHeight: heroColumn.implicitHeight + Theme.spacingL * 2
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: Theme.withAlpha(root.heroAccent, root.hasProviderData ? 0.16 : 0.07)
                                    }
                                    GradientStop {
                                        position: 0.56
                                        color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.08)
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: Theme.withAlpha(Theme.surfaceContainer, 0.02)
                                    }
                                }
                            }

                            Rectangle {
                                width: 170
                                height: 170
                                radius: 85
                                x: parent.width - width * 0.72
                                y: -height * 0.34
                                color: Theme.withAlpha(root.heroAccent, 0.09)
                            }

                            Column {
                                id: heroColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingL
                                spacing: Theme.spacingS

                                StyledText {
                                    width: parent.width
                                    text: "Quota telemetry"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    font.weight: Font.DemiBold
                                }

                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    Rectangle {
                                        implicitWidth: statusText.implicitWidth + Theme.spacingM * 2
                                        height: 28
                                        radius: 14
                                        color: Theme.withAlpha(root.hasError ? Theme.error : root.heroAccent, 0.16)
                                        border.width: 1
                                        border.color: Theme.withAlpha(root.hasError ? Theme.error : root.heroAccent, 0.3)

                                        StyledText {
                                            id: statusText
                                            anchors.centerIn: parent
                                            text: root.statusTitle
                                            color: root.hasError ? Theme.error : root.heroAccent
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Rectangle {
                                        implicitWidth: sourceText.implicitWidth + Theme.spacingM * 2
                                        height: 28
                                        radius: 14
                                        color: Theme.withAlpha(Theme.surfaceText, 0.08)
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.surfaceText, 0.12)

                                        StyledText {
                                            id: sourceText
                                            anchors.centerIn: parent
                                            text: `Source: ${root.sourceMode}`
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            font.weight: Font.Medium
                                        }
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    text: "AI usage monitor"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                    wrapMode: Text.WordWrap
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.statusSubtitle
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 54
                                        radius: Theme.cornerRadius
                                        color: Theme.withAlpha(root.heroAccent, 0.14)
                                        border.width: 1
                                        border.color: Theme.withAlpha(root.heroAccent, 0.3)

                                        Column {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.rightMargin: Theme.spacingM
                                            anchors.topMargin: Theme.spacingS
                                            anchors.bottomMargin: Theme.spacingS
                                            spacing: 1

                                            StyledText {
                                                width: parent.width
                                                text: "Current usage"
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall - 1
                                            }

                                            StyledText {
                                                width: parent.width
                                                text: root.hasProviderData ? `${Math.round(root.primaryPercent)}%` : "—"
                                                color: root.heroAccent
                                                font.pixelSize: Theme.fontSizeMedium + 1
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 54
                                        radius: Theme.cornerRadius
                                        color: Theme.withAlpha(Theme.surfaceText, 0.06)
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.surfaceText, 0.1)

                                        Column {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.rightMargin: Theme.spacingM
                                            anchors.topMargin: Theme.spacingS
                                            anchors.bottomMargin: Theme.spacingS
                                            spacing: 1

                                            StyledText {
                                                width: parent.width
                                                text: "Primary reset"
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall - 1
                                            }

                                            StyledText {
                                                width: parent.width
                                                text: root.primaryWindow ? root.formatTimeUntil(root.primaryWindow.resetsAt) : "—"
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    SurfaceButton {
                                        Layout.fillWidth: true
                                        iconName: "refresh"
                                        label: "Refresh now"
                                        description: "Fetch latest AI usage windows."
                                        prominent: true
                                        actionEnabled: root.binaryReady && !root.isLoading
                                        onTriggered: root.refresh()
                                    }

                                    SurfaceButton {
                                        Layout.fillWidth: true
                                        iconName: "terminal"
                                        label: "Recheck CLI"
                                        description: "Re-detect the CodexBar executable."
                                        actionEnabled: !procDetect.running
                                        onTriggered: root.detectBinary()
                                    }
                                }
                            }
                        }

                        SectionFrame {
                            visible: root.hasError
                            title: "Command feedback"
                            subtitle: "One or more providers returned an error."

                            Rectangle {
                                width: parent.width
                                implicitHeight: errText.implicitHeight + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.error, 0.11)
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.error, 0.3)

                                StyledText {
                                    id: errText
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingM
                                    text: root.errorMessage
                                    color: Theme.error
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        SectionFrame {
                            title: "Usage windows"
                            subtitle: "Live session and reset windows from the highest-usage provider."
                            aside: root.successfulProviders.length > 0 ? `${root.successfulProviders.length} active` : "No data"

                            StyledText {
                                visible: root.isLoading && !root.hasProviderData
                                width: parent.width
                                text: "Fetching usage data..."
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            StyledText {
                                visible: !root.isLoading && root.usageWindows.length === 0
                                width: parent.width
                                text: "No window data yet. Run the configured CLIs once, then refresh."
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: root.usageWindows

                                Rectangle {
                                    required property var modelData

                                    width: parent.width
                                    implicitHeight: winCol.implicitHeight + Theme.spacingM * 2
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainer
                                    border.width: 1
                                    border.color: Theme.withAlpha(root.getUsageColor(Number(modelData.data.usedPercent || 0)), 0.28)

                                    Column {
                                        id: winCol
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingM
                                        spacing: 6

                                        Row {
                                            width: parent.width
                                            spacing: Theme.spacingS

                                            StyledText {
                                                width: parent.width - valueText.implicitWidth - Theme.spacingS
                                                text: modelData.label
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                id: valueText
                                                text: root.formatUsageLine(modelData.data)
                                                color: root.getUsageColor(Number(modelData.data.usedPercent || 0))
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            height: 6
                                            radius: 3
                                            color: Theme.surfaceContainerHighest

                                            Rectangle {
                                                width: Math.min(1, Number(modelData.data.usedPercent || 0) / 100) * parent.width
                                                height: parent.height
                                                radius: parent.radius
                                                color: root.getUsageColor(Number(modelData.data.usedPercent || 0))

                                                Behavior on width {
                                                    NumberAnimation {
                                                        duration: 280
                                                        easing.type: Easing.OutCubic
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SectionFrame {
                            visible: root.successfulProviders.length > 1 || (root.showErrorProviders && root.errorProviders.length > 0)
                            title: "Providers"
                            subtitle: "Configured providers and their current state."
                            aside: `${root.selectedProviders.length} selected`

                            Repeater {
                                model: root.providers

                                Rectangle {
                                    required property var modelData

                                    width: parent.width
                                    implicitHeight: providerCol.implicitHeight + Theme.spacingM * 2
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainer
                                    border.width: 1
                                    border.color: modelData.error ? Theme.withAlpha(Theme.error, 0.28) : Theme.withAlpha(root.getUsageColor(root.providerPercent(modelData)), 0.28)

                                    Column {
                                        id: providerCol
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingM
                                        spacing: 6

                                        Row {
                                            width: parent.width
                                            spacing: Theme.spacingS

                                            StyledText {
                                                width: parent.width - providerValue.implicitWidth - Theme.spacingS
                                                text: root.providerName(modelData.provider)
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                id: providerValue
                                                text: modelData.error ? "Error" : `${Math.round(root.providerPercent(modelData))}%`
                                                color: modelData.error ? Theme.error : root.getUsageColor(root.providerPercent(modelData))
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: modelData.error ? root.providerErrorText(modelData) : `${modelData.source || root.sourceMode} · ${root.formatUsageLine(modelData.usage.primary)}`
                                            color: modelData.error ? Theme.error : Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 3
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        SectionFrame {
                            title: "Identity & runtime"
                            subtitle: "Account and command context used by this widget."

                            GridLayout {
                                width: parent.width
                                columns: 2
                                columnSpacing: Theme.spacingS
                                rowSpacing: Theme.spacingS

                                MetricTile {
                                    Layout.fillWidth: true
                                    label: "Account"
                                    value: root.accountEmail
                                    accentColor: root.heroAccent
                                }

                                MetricTile {
                                    Layout.fillWidth: true
                                    label: "Login method"
                                    value: root.loginMethod
                                    accentColor: root.heroAccent
                                }

                                MetricTile {
                                    Layout.fillWidth: true
                                    label: "CLI source"
                                    value: root.providerData ? `${root.providerName(root.providerData.provider)} · ${root.providerData.source || root.sourceMode}` : root.sourceMode
                                    accentColor: root.heroAccent
                                }

                                MetricTile {
                                    Layout.fillWidth: true
                                    label: "Last update"
                                    value: root.lastUpdated
                                    accentColor: root.heroAccent
                                }

                                MetricTile {
                                    Layout.fillWidth: true
                                    label: "Binary"
                                    value: root.resolvedBinaryPath
                                    accentColor: root.heroAccent
                                }

                                MetricTile {
                                    Layout.fillWidth: true
                                    label: "Credits"
                                    value: root.providerData && root.providerData.credits ? String(root.providerData.credits.remaining ?? "—") : "—"
                                    accentColor: root.heroAccent
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
