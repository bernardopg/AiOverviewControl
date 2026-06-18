import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "aiOverviewControl"

    readonly property string i18nLocale: AiOverviewControlI18n.normalizedLocale
    property var selectedIds: normalizeProviderSelection(loadValue("providerSelection", "codex,claude,copilot"))
    property var pinnedIds: normalizeCsvList(loadValue("pinnedProviders", ""))

    function normalizeCsvList(value) {
        const parts = String(value || "").split(",");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            const id = parts[i].trim().toLowerCase();
            if (id.length > 0 && result.indexOf(id) < 0) result.push(id);
        }
        return result;
    }

    function isPinned(id) { return pinnedIds.indexOf(id) >= 0; }

    function togglePinned(id) {
        const result = pinnedIds.slice();
        const index = result.indexOf(id);
        if (index >= 0) result.splice(index, 1);
        else result.push(id);
        pinnedIds = result;
        saveValue("pinnedProviders", result.join(","));
    }
    property var providerHealth: ({})
    property string healthBuffer: ""
    property string healthScript: ""

    readonly property int readyCount: {
        let n = 0;
        for (let i = 0; i < selectedIds.length; i++) {
            const health = providerHealth[selectedIds[i]];
            if (health && health.status === "ready") n++;
        }
        return n;
    }

    readonly property int missingCount: {
        let n = 0;
        for (let i = 0; i < selectedIds.length; i++) {
            const health = providerHealth[selectedIds[i]];
            if (health && health.status === "missing") n++;
        }
        return n;
    }

    readonly property var allProviders: [
        { id:"codex", name:"Codex", icon:"terminal", mode:"telemetry", requirement:"codex CLI", envVar:"", note:"Official app-server rate limits" },
        { id:"claude", name:"Claude", icon:"psychology", mode:"telemetry", requirement:"claude CLI or ~/.claude", envVar:"", note:"Local analytics and authenticated usage" },
        { id:"copilot", name:"Copilot", icon:"code", mode:"telemetry", requirement:"gh CLI or GitHub token", envVar:"COPILOT_GITHUB_TOKEN", note:"Authenticated Copilot quota from the GitHub session" },
        { id:"gemini", name:"Gemini", icon:"star", mode:"telemetry", requirement:"gemini CLI or API key", envVar:"GEMINI_API_KEY", note:"Authentication status; quota remains in AI Studio" },
        { id:"9router", name:"9Router", icon:"share", mode:"telemetry", requirement:"local 9Router database", envVar:"", note:"Local requests, tokens and cost" },
        { id:"openrouter", name:"OpenRouter", icon:"route", mode:"telemetry", requirement:"API key or 9Router data", envVar:"OPENROUTER_API_KEY", note:"Official key usage and limits" },
        { id:"deepseek", name:"DeepSeek", icon:"search", mode:"telemetry", requirement:"API key", envVar:"DEEPSEEK_API_KEY", note:"Official account balance" },
        { id:"kimi", name:"Kimi", icon:"language", mode:"telemetry", requirement:"API key", envVar:"MOONSHOT_API_KEY", note:"Official account balance (USD/CNY)" },
        { id:"minimax", name:"MiniMax", icon:"bar_chart", mode:"telemetry", requirement:"API key", envVar:"MINIMAX_API_KEY", note:"Official models API authentication check" },
        { id:"glm", name:"GLM", icon:"memory", mode:"telemetry", requirement:"API key", envVar:"GLM_API_KEY", note:"China (Zhipu) models API authentication check" },
        { id:"zai", name:"Z.ai", icon:"bubble_chart", mode:"telemetry", requirement:"API key", envVar:"ZAI_API_KEY", note:"Official /models auth check; GLM Coding Plan + PAYG" },
        { id:"mistral", name:"Mistral", icon:"wind_power", mode:"telemetry", requirement:"API key", envVar:"MISTRAL_API_KEY", note:"Official models API authentication check" },
        { id:"qwen", name:"Qwen", icon:"hub", mode:"telemetry", requirement:"API key", envVar:"DASHSCOPE_API_KEY", note:"DashScope models API authentication check" },
        { id:"nvidia", name:"NVIDIA NIM", icon:"developer_board", mode:"telemetry", requirement:"API key", envVar:"NVIDIA_API_KEY", note:"Official models API authentication check" },
        { id:"cloudflare", name:"Cloudflare AI", icon:"cloud", mode:"telemetry", requirement:"API token", envVar:"CLOUDFLARE_AI_TOKEN", note:"Token verify + Workers AI analytics" },
        { id:"vertexai", name:"Vertex AI", icon:"settings_remote", mode:"telemetry", requirement:"gcloud CLI", envVar:"GOOGLE_CLOUD_PROJECT", note:"Official gcloud authentication status" },
        { id:"byteplus", name:"BytePlus Ark", icon:"rocket_launch", mode:"telemetry", requirement:"API key", envVar:"BYTEPLUS_API_KEY", note:"Official models API authentication check" },
        { id:"ollama", name:"Ollama", icon:"dns", mode:"telemetry", requirement:"local Ollama server", envVar:"OLLAMA_HOST", note:"Official local tags and running-model APIs" },
        { id:"together", name:"Together AI", icon:"join_inner", mode:"telemetry", requirement:"API key", envVar:"TOGETHER_API_KEY", note:"Official credit balance" },
        { id:"groq", name:"Groq", icon:"fast_forward", mode:"telemetry", requirement:"API key", envVar:"GROQ_API_KEY", note:"Official models API authentication check" },
        { id:"cohere", name:"Cohere", icon:"waves", mode:"telemetry", requirement:"API key", envVar:"COHERE_API_KEY", note:"Official models API authentication check" },
        { id:"replicate", name:"Replicate", icon:"content_copy", mode:"telemetry", requirement:"API token", envVar:"REPLICATE_API_TOKEN", note:"Official account API authentication check" },
        { id:"fireworks", name:"Fireworks AI", icon:"local_fire_department", mode:"telemetry", requirement:"API key", envVar:"FIREWORKS_API_KEY", note:"Official inference models authentication check" },
        { id:"xai", name:"xAI (Grok)", icon:"bolt", mode:"telemetry", requirement:"API key", envVar:"XAI_API_KEY", note:"Official /v1/api-key authentication check" },
        { id:"kilo", name:"Kilo", icon:"straighten", mode:"telemetry", requirement:"API key", envVar:"KILO_API_KEY", note:"Gateway models API authentication check" },
        { id:"ai21", name:"AI21", icon:"looks_21", mode:"telemetry", requirement:"API key", envVar:"AI21_API_KEY", note:"Configured status; no documented read-only usage API" },
        { id:"perplexity", name:"Perplexity", icon:"auto_awesome", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"cursor", name:"Cursor", icon:"mouse", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"cline", name:"Cline", icon:"code_blocks", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"opencode", name:"OpenCode", icon:"open_in_new", mode:"informational", requirement:"none", envVar:"", note:"Usage belongs to configured upstream providers" },
        { id:"kiro", name:"Kiro", icon:"tune", mode:"informational", requirement:"none", envVar:"", note:"Subscription-only IDE; no public API" },
        { id:"warp", name:"Warp", icon:"speed", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"amp", name:"Amp", icon:"bolt", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" }
    ]

    readonly property var telemetryProviders: allProviders.filter(function(p) { return p.mode === "telemetry"; })
    readonly property var informationalProviders: allProviders.filter(function(p) { return p.mode === "informational"; })

    function t(key, fallback, params) {
        root.i18nLocale;
        return AiOverviewControlI18n.tr(key, fallback, params);
    }

    function normalizeProviderSelection(value) {
        const parts = String(value || "").split(",");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            const id = parts[i].trim().toLowerCase();
            if (id.length > 0 && result.indexOf(id) < 0) result.push(id);
        }
        return result.length > 0 ? result : ["codex"];
    }

    function isSelected(id) { return selectedIds.indexOf(id) >= 0; }

    function toggleProvider(id) {
        const result = selectedIds.slice();
        const index = result.indexOf(id);
        if (index >= 0 && result.length > 1) result.splice(index, 1);
        else if (index < 0) result.push(id);
        selectedIds = result;
        saveValue("providerSelection", result.join(","));
        runHealth();
    }

    function healthFor(id) {
        return providerHealth[id] || { status:"unknown", detail:t("settings.health.pending", "Not checked") };
    }

    function runHealth() {
        if (!healthScript || healthProcess.running) return;
        healthBuffer = "";
        healthProcess.command = ["bash", healthScript, selectedIds.join(",")];
        healthProcess.running = true;
    }

    Component.onCompleted: {
        const url = Qt.resolvedUrl("providers/get-provider-health").toString();
        healthScript = url.startsWith("file://") ? url.substring(7) : url;
        runHealth();
    }

    Process {
        id: healthProcess
        stdout: SplitParser { splitMarker: ""; onRead: data => root.healthBuffer += data }
        onExited: code => {
            if (code !== 0 || root.healthBuffer.length === 0) return;
            try {
                const items = JSON.parse(root.healthBuffer);
                const map = {};
                for (let i = 0; i < items.length; i++) map[items[i].provider] = items[i];
                root.providerHealth = map;
            } catch (error) {
                root.providerHealth = {};
            }
        }
    }

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius + 6
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.2)
        implicitHeight: hero.implicitHeight + Theme.spacingL * 2
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary, 0.1) }
                GradientStop { position: 1.0; color: Theme.withAlpha(Theme.primary, 0.0) }
            }
        }

        Rectangle {
            width: 150
            height: 150
            radius: 75
            anchors.right: parent.right
            anchors.rightMargin: -52
            anchors.top: parent.top
            anchors.topMargin: -62
            color: Theme.withAlpha(Theme.primary, 0.07)
        }

        Column {
            id: hero
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 44
                    height: 44
                    radius: 14
                    color: Theme.withAlpha(Theme.primary, 0.14)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.28)

                    DankIcon {
                        anchors.centerIn: parent
                        name: "monitoring"
                        size: 22
                        color: Theme.primary
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    Row {
                        spacing: Theme.spacingS

                        StyledText {
                            text: "AiOverviewControl"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            implicitWidth: versionLabel.implicitWidth + Theme.spacingS * 2
                            implicitHeight: 20
                            radius: 10
                            color: Theme.withAlpha(Theme.primary, 0.14)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.primary, 0.26)
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                id: versionLabel
                                anchors.centerIn: parent
                                text: "v1.4.4"
                                font.pixelSize: Theme.fontSizeSmall - 1
                                font.weight: Font.DemiBold
                                color: Theme.primary
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: t("settings.hero.self_managed", "Provider collection, health checks, refresh policy and rendering are managed by this plugin. No external aggregation tool is required.")
                        wrapMode: Text.WordWrap
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                DankActionButton {
                    Layout.alignment: Qt.AlignVCenter
                    iconName: "refresh"
                    iconColor: Theme.primary
                    backgroundColor: Theme.withAlpha(Theme.primary, 0.1)
                    buttonSize: 36
                    tooltipText: t("settings.health.recheck", "Re-check health")
                    onClicked: root.runHealth()
                }
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingXS

                HealthChip {
                    chipIcon: "playlist_add_check"
                    chipLabel: t("settings.active_count", "{count} active", { count: root.selectedIds.length })
                    chipAccent: Theme.primary
                }

                HealthChip {
                    visible: root.readyCount > 0
                    chipIcon: "check_circle"
                    chipLabel: t("settings.health.ready_count", "{count} ready", { count: root.readyCount })
                    chipAccent: Theme.success
                }

                HealthChip {
                    visible: root.missingCount > 0
                    chipIcon: "warning"
                    chipLabel: t("settings.health.missing_count", "{count} missing", { count: root.missingCount })
                    chipAccent: Theme.warning
                }
            }
        }
    }

    SectionHeader {
        width: parent.width
        headerTitle: t("settings.section.interface", "Interface")
        headerIcon: "tune"
    }

    DankDropdown {
        width: parent.width
        text: t("settings.language.label", "Language")
        description: t("settings.language.description", "UI language for this plugin. Auto follows system locale.")
        currentValue: loadValue("languageOverride", "auto")
        options: ["auto", "en_US", "pt_BR", "zh_CN", "es_ES", "de_DE"]
        optionIcons: ["language", "translate", "translate", "translate", "translate", "translate"]
        dropdownWidth: 220
        onValueChanged: function(value) { saveValue("languageOverride", value); }
    }

    DankDropdown {
        width: parent.width
        text: t("settings.density.label", "Dashboard density")
        description: t("settings.density.description", "Comfortable keeps full previews. Compact reduces card height and visual detail.")
        currentValue: loadValue("densityMode", "comfortable")
        options: ["comfortable", "compact"]
        optionIcons: ["view_agenda", "density_small"]
        dropdownWidth: 220
        onValueChanged: function(value) { saveValue("densityMode", value); }
    }

    DankDropdown {
        id: pillModeDropdown
        width: parent.width
        text: t("settings.pill_mode.label", "Pill mode")
        description: t("settings.pill_mode.description", "Auto shows providers with measurable usage. Custom uses the list below.")
        currentValue: loadValue("pillMode", "auto")
        options: ["auto", "custom", "top"]
        optionIcons: ["auto_awesome", "tune", "trending_up"]
        dropdownWidth: 180
        onValueChanged: function(value) { saveValue("pillMode", value); }
    }

    DankTextField {
        visible: pillModeDropdown.currentValue === "custom"
        width: parent.width
        placeholderText: "claude,codex,copilot"
        text: loadValue("pillProviders", "")
        onEditingFinished: saveValue("pillProviders", text.trim())
    }

    DankDropdown {
        width: parent.width
        text: t("settings.refresh_interval", "Refresh interval")
        description: t("settings.refresh_description", "How often the plugin queries selected local adapters and provider APIs.")
        currentValue: loadValue("refreshInterval", "120000")
        options: ["60000", "120000", "300000", "900000", "1800000"]
        optionIcons: ["timer", "timer", "timer_off", "timer_off", "timer_off"]
        dropdownWidth: 200
        onValueChanged: function(value) { saveValue("refreshInterval", value); }
    }

    DankToggle {
        width: parent.width
        text: t("settings.show_errors", "Show providers with errors")
        description: t("settings.show_errors_desc", "Keep authentication and configuration failures visible in the dashboard.")
        checked: loadValue("showErrorProviders", "true") === "true"
        onToggled: function(checked) { saveValue("showErrorProviders", checked ? "true" : "false"); }
    }

    DankToggle {
        width: parent.width
        text: t("settings.show_projects", "Show Claude projects")
        description: t("settings.show_projects_desc", "List the week's top projects inside the Claude card.")
        checked: loadValue("showClaudeProjects", "true") === "true"
        onToggled: function(checked) { saveValue("showClaudeProjects", checked ? "true" : "false"); }
    }

    DankToggle {
        id: notifyToggle
        width: parent.width
        text: t("settings.notify.label", "Quota notifications")
        description: t("settings.notify.description", "Send a desktop notification when a provider crosses the threshold.")
        checked: loadValue("quotaNotifications", "true") === "true"
        onToggled: function(checked) { saveValue("quotaNotifications", checked ? "true" : "false"); }
    }

    DankDropdown {
        visible: notifyToggle.checked
        width: parent.width
        text: t("settings.notify.threshold", "Notification threshold")
        description: t("settings.notify.threshold_desc", "Usage percent that triggers a notification.")
        currentValue: loadValue("notifyThreshold", "85")
        options: ["75", "85", "95"]
        optionIcons: ["notifications", "notifications_active", "notification_important"]
        dropdownWidth: 160
        onValueChanged: function(value) { saveValue("notifyThreshold", value); }
    }

    DankDropdown {
        visible: notifyToggle.checked
        width: parent.width
        text: t("settings.notify.cooldown", "Re-alert interval")
        description: t("settings.notify.cooldown_desc", "0 alerts once per quota window; other values repeat the alert after that many minutes while usage stays above the threshold.")
        currentValue: loadValue("notifyCooldownMinutes", "0")
        options: ["0", "60", "360", "1440"]
        optionIcons: ["notifications_off", "schedule", "schedule", "schedule"]
        dropdownWidth: 160
        onValueChanged: function(value) { saveValue("notifyCooldownMinutes", value); }
    }

    Column {
        visible: notifyToggle.checked
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            width: parent.width
            text: t("settings.notify.overrides", "Per-provider threshold overrides")
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
        }

        StyledText {
            width: parent.width
            text: t("settings.notify.overrides_desc", "Comma-separated provider:percent pairs that beat the global threshold.")
            wrapMode: Text.WordWrap
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall - 1
        }

        DankTextField {
            width: parent.width
            placeholderText: "claude:90,codex:75"
            text: loadValue("notifyThresholds", "")
            onEditingFinished: saveValue("notifyThresholds", text.trim())
        }
    }

    DankDropdown {
        width: parent.width
        text: t("settings.history_retention", "Usage history retention")
        description: t("settings.history_retention_desc", "Snapshots kept per trim of the local usage history (sparklines and trends).")
        currentValue: loadValue("historyRetention", "2000")
        options: ["500", "2000", "10000"]
        optionIcons: ["history", "history", "history"]
        dropdownWidth: 160
        onValueChanged: function(value) { saveValue("historyRetention", value); }
    }

    ProviderSection {
        width: parent.width
        title: t("settings.telemetry_providers", "Telemetry providers")
        description: t("settings.telemetry_providers_desc", "Adapters backed by official CLIs, documented APIs, or local usage stores.")
        providers: root.telemetryProviders
        sectionIcon: "monitoring"
    }

    ProviderSection {
        width: parent.width
        title: t("settings.informational_providers", "Informational providers")
        description: t("settings.informational_providers_desc", "These providers expose no public read-only quota API. Their cards link the user to the official usage surface.")
        providers: root.informationalProviders
        sectionIcon: "info"
    }

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.primary, 0.06)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.16)
        implicitHeight: selectionColumn.implicitHeight + Theme.spacingM * 2

        Column {
            id: selectionColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS
            StyledText { text:t("settings.current_selection", "Current selection"); color:Theme.primary; font.weight:Font.DemiBold; font.pixelSize:Theme.fontSizeSmall }
            StyledText { width:parent.width; text:root.selectedIds.join(", "); wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall }
            DankTextField {
                width: parent.width
                text: loadValue("providerSelection", "codex,claude,copilot")
                placeholderText: "codex,claude,copilot,openrouter"
                onEditingFinished: {
                    const normalized = root.normalizeProviderSelection(text);
                    root.selectedIds = normalized;
                    root.saveValue("providerSelection", normalized.join(","));
                    root.runHealth();
                }
            }
        }
    }

    CollapsibleSection {
        width: parent.width
        sectionTitle: t("settings.diagnostics", "Diagnostics and tests")
        sectionDesc: t("settings.diagnostics_desc", "Commands for validating the plugin-managed pipeline.")

        Column {
            width: parent.width
            spacing: Theme.spacingM
            Repeater {
                model: [
                    { label:t("settings.test_backend", "Test selected providers"), cmd:"PLUGIN=~/.config/DankMaterialShell/plugins/AiOverviewControl\n$PLUGIN/providers/get-provider-usage \"" + root.selectedIds.join(",") + "\" $PLUGIN/providers/get-copilot-usage | jq ." },
                    { label:t("settings.test_codex", "Test Codex app-server adapter"), cmd:"~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-codex-usage | jq ." },
                    { label:t("settings.test_health", "Check provider prerequisites"), cmd:"~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-provider-health \"" + root.selectedIds.join(",") + "\" | jq ." },
                    { label:t("settings.test_deps", "Check core dependencies"), cmd:"command -v bash jq curl codex claude gh gcloud ollama" },
                    { label:t("settings.test_qml", "Validate QML"), cmd:"qmllint ~/.config/DankMaterialShell/plugins/AiOverviewControl/AiOverviewControlWidget.qml ~/.config/DankMaterialShell/plugins/AiOverviewControl/AiOverviewControlSettings.qml" }
                ]
                delegate: Column {
                    id: diagRow
                    required property var modelData
                    property bool copied: false
                    width: parent.width
                    spacing: Theme.spacingXS

                    Timer {
                        id: copiedReset
                        interval: 1600
                        onTriggered: diagRow.copied = false
                    }

                    StyledText { width:parent.width; text:modelData.label; wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall; font.weight:Font.Medium }

                    StyledRect {
                        width: parent.width
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        implicitHeight: Math.max(commandText.implicitHeight, copyButton.height) + Theme.spacingS * 2

                        StyledText {
                            id: commandText
                            anchors.left: parent.left
                            anchors.right: copyButton.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingXS
                            text: diagRow.modelData.cmd
                            wrapMode: Text.WrapAnywhere
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.family: "monospace"
                        }

                        DankActionButton {
                            id: copyButton
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: 28
                            iconName: diagRow.copied ? "check" : "content_copy"
                            iconColor: diagRow.copied ? Theme.success : Theme.surfaceVariantText
                            backgroundColor: "transparent"
                            tooltipText: t("settings.copy_command", "Copy command")
                            onClicked: {
                                Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "_", diagRow.modelData.cmd]);
                                diagRow.copied = true;
                                copiedReset.restart();
                            }
                        }
                    }
                }
            }
        }
    }

    component HealthChip: Rectangle {
        id: healthChip

        required property string chipLabel
        property string chipIcon: ""
        property color chipAccent: Theme.primary

        implicitWidth: chipContent.implicitWidth + Theme.spacingM * 2
        implicitHeight: 26
        radius: 13
        color: Theme.withAlpha(chipAccent, 0.12)
        border.width: 1
        border.color: Theme.withAlpha(chipAccent, 0.24)

        Row {
            id: chipContent
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DankIcon {
                visible: healthChip.chipIcon.length > 0
                name: healthChip.chipIcon
                size: 13
                color: healthChip.chipAccent
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: healthChip.chipLabel
                color: healthChip.chipAccent
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    component SectionHeader: Column {
        id: sectionHeader

        required property string headerTitle
        property string headerIcon: ""

        width: parent ? parent.width : 0
        spacing: Theme.spacingXS

        Row {
            spacing: Theme.spacingS

            DankIcon {
                visible: sectionHeader.headerIcon.length > 0
                name: sectionHeader.headerIcon
                size: 15
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: sectionHeader.headerTitle.toUpperCase()
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
                font.letterSpacing: 1.0
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.withAlpha(Theme.surfaceText, 0.07)
        }
    }

    component ProviderSection: Column {
        id: providerSection
        required property string title
        required property string description
        required property var providers
        property string sectionIcon: ""
        spacing: Theme.spacingS

        Row {
            spacing: Theme.spacingS

            DankIcon {
                visible: providerSection.sectionIcon.length > 0
                name: providerSection.sectionIcon
                size: 16
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: providerSection.title
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        StyledText { width:parent.width; text:providerSection.description; wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.withAlpha(Theme.surfaceText, 0.06)
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingS
            Repeater {
                model: providerSection.providers
                delegate: Rectangle {
                    id: providerChip
                    required property var modelData
                    readonly property bool active: root.isSelected(modelData.id)
                    readonly property var health: root.healthFor(modelData.id)
                    width: chipRow.implicitWidth + Theme.spacingM * 2
                    height: 38
                    radius: 19
                    color: active ? Theme.withAlpha(Theme.primary, 0.17) : (chipMouse.containsMouse ? Theme.withAlpha(Theme.surfaceVariantText, 0.13) : Theme.withAlpha(Theme.surfaceVariantText, 0.07))
                    border.width: active ? 1 : 0
                    border.color: Theme.withAlpha(Theme.primary, activeFocus ? 0.9 : 0.45)
                    scale: chipMouse.containsMouse ? 1.04 : 1.0
                    activeFocusOnTab: true

                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: modelData.name
                    Accessible.checked: active
                    Keys.onReturnPressed: root.toggleProvider(modelData.id)
                    Keys.onSpacePressed: root.toggleProvider(modelData.id)

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS
                        DankIcon { name:providerChip.active ? "check" : modelData.icon; size:14; color:providerChip.active ? Theme.primary : Theme.surfaceVariantText }
                        StyledText { text:modelData.name; color:providerChip.active ? Theme.primary : Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall; font.weight:providerChip.active ? Font.Medium : Font.Normal }
                        Rectangle {
                            visible: providerChip.active
                            width: 7; height: 7; radius: 4
                            color: providerChip.health.status === "ready" ? Theme.success : (providerChip.health.status === "missing" ? Theme.warning : Theme.surfaceVariantText)
                        }
                    }
                    MouseArea { id:chipMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:root.toggleProvider(modelData.id) }
                }
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingXS
            Repeater {
                model: providerSection.providers.filter(function(p) { return root.isSelected(p.id); })
                delegate: StyledRect {
                    id: providerDetailRow
                    required property var modelData
                    readonly property var health: root.healthFor(modelData.id)
                    readonly property color healthColor: health.status === "ready" ? Theme.success : (health.status === "missing" ? Theme.warning : Theme.surfaceVariantText)
                    width: parent.width
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
                    border.width: 1
                    border.color: Theme.withAlpha(providerDetailRow.healthColor, 0.14)
                    implicitHeight: providerRow.implicitHeight + Theme.spacingS * 2

                    RowLayout {
                        id: providerRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingS

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 28
                            height: 28
                            radius: 9
                            color: Theme.withAlpha(Theme.primary, 0.1)

                            DankIcon {
                                anchors.centerIn: parent
                                name: providerDetailRow.modelData.icon
                                size: 14
                                color: Theme.primary
                            }
                        }

                        StyledText { Layout.preferredWidth:100; text:modelData.name; color:Theme.surfaceText; font.pixelSize:Theme.fontSizeSmall; font.weight:Font.Medium; elide:Text.ElideRight }
                        StyledText { Layout.fillWidth:true; text:modelData.note; wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall - 1 }

                        DankActionButton {
                            Layout.alignment: Qt.AlignVCenter
                            buttonSize: 26
                            iconName: root.isPinned(providerDetailRow.modelData.id) ? "star" : "star_border"
                            iconColor: root.isPinned(providerDetailRow.modelData.id) ? Theme.primary : Theme.surfaceVariantText
                            backgroundColor: "transparent"
                            tooltipText: t("settings.pin_provider", "Pin to top of dashboard")
                            onClicked: root.togglePinned(providerDetailRow.modelData.id)
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: healthLabel.implicitWidth + Theme.spacingS * 2
                            implicitHeight: 22
                            radius: 11
                            color: Theme.withAlpha(providerDetailRow.healthColor, 0.13)
                            border.width: 1
                            border.color: Theme.withAlpha(providerDetailRow.healthColor, 0.26)

                            StyledText {
                                id: healthLabel
                                anchors.centerIn: parent
                                text: providerDetailRow.health.status === "ready" ? t("settings.health.ready", "Ready") : providerDetailRow.health.detail
                                color: providerDetailRow.healthColor
                                font.pixelSize: Theme.fontSizeSmall - 1
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
        }
    }

    component CollapsibleSection: Item {
        id: section
        property string sectionTitle: ""
        property string sectionDesc: ""
        property bool expanded: false
        default property alias sectionContent: body.data
        width: parent ? parent.width : 0
        height: header.height + (expanded ? Theme.spacingS + body.implicitHeight : 0)

        Rectangle {
            id: header
            width: parent.width
            height: headerColumn.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, section.activeFocus ? 0.8 : 0.18)

            Column {
                id: headerColumn
                anchors.left: parent.left
                anchors.right: chevron.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.spacingM
                spacing: 2
                StyledText { width:parent.width; text:section.sectionTitle; color:Theme.surfaceText; font.pixelSize:Theme.fontSizeMedium; font.weight:Font.DemiBold }
                StyledText { visible:!section.expanded; width:parent.width; text:section.sectionDesc; wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall }
            }
            DankIcon { id:chevron; anchors.right:parent.right; anchors.rightMargin:Theme.spacingM; anchors.verticalCenter:parent.verticalCenter; name:"expand_more"; size:18; color:Theme.primary; rotation:section.expanded ? 180 : 0 }
            MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:section.expanded = !section.expanded }
        }

        Column {
            id: body
            visible: section.expanded
            anchors.top: header.bottom
            anchors.topMargin: Theme.spacingS
            width: parent.width
            spacing: Theme.spacingM
        }
    }
}
