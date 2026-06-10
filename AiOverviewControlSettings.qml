import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "aiOverviewControl"

    readonly property string i18nLocale: AiOverviewControlI18n.normalizedLocale
    property var selectedIds: normalizeProviderSelection(loadValue("providerSelection", "codex,claude,copilot"))
    property var providerHealth: ({})
    property string healthBuffer: ""
    property string healthScript: ""

    readonly property var allProviders: [
        { id:"codex", name:"Codex", icon:"terminal", mode:"telemetry", requirement:"codex CLI", envVar:"", note:"Official app-server rate limits" },
        { id:"claude", name:"Claude", icon:"psychology", mode:"telemetry", requirement:"claude CLI or ~/.claude", envVar:"", note:"Local analytics and authenticated usage" },
        { id:"copilot", name:"Copilot", icon:"code", mode:"telemetry", requirement:"gh CLI or GitHub token", envVar:"COPILOT_GITHUB_TOKEN", note:"Authenticated Copilot quota from the GitHub session" },
        { id:"gemini", name:"Gemini", icon:"star", mode:"telemetry", requirement:"gemini CLI or API key", envVar:"GEMINI_API_KEY", note:"Authentication status; quota remains in AI Studio" },
        { id:"9router", name:"9Router", icon:"share", mode:"telemetry", requirement:"local 9Router database", envVar:"", note:"Local requests, tokens and cost" },
        { id:"openrouter", name:"OpenRouter", icon:"route", mode:"telemetry", requirement:"API key or 9Router data", envVar:"OPENROUTER_API_KEY", note:"Official key usage and limits" },
        { id:"deepseek", name:"DeepSeek", icon:"search", mode:"telemetry", requirement:"API key", envVar:"DEEPSEEK_API_KEY", note:"Official account balance" },
        { id:"kimi", name:"Kimi", icon:"language", mode:"telemetry", requirement:"API key", envVar:"MOONSHOT_API_KEY", note:"Official account balance" },
        { id:"minimax", name:"MiniMax", icon:"bar_chart", mode:"telemetry", requirement:"API key", envVar:"MINIMAX_API_KEY", note:"Configured status; no documented read-only quota API" },
        { id:"glm", name:"GLM", icon:"memory", mode:"telemetry", requirement:"API key", envVar:"GLM_API_KEY", note:"Configured status; no documented read-only quota API" },
        { id:"mistral", name:"Mistral", icon:"wind_power", mode:"telemetry", requirement:"API key", envVar:"MISTRAL_API_KEY", note:"Official API authentication check" },
        { id:"qwen", name:"Qwen", icon:"hub", mode:"telemetry", requirement:"API key", envVar:"DASHSCOPE_API_KEY", note:"Official models API authentication check" },
        { id:"nvidia", name:"NVIDIA NIM", icon:"developer_board", mode:"telemetry", requirement:"API key", envVar:"NVIDIA_API_KEY", note:"Official models API authentication check" },
        { id:"cloudflare", name:"Cloudflare AI", icon:"cloud", mode:"telemetry", requirement:"API token", envVar:"CLOUDFLARE_AI_TOKEN", note:"Official token verification; usage remains in analytics" },
        { id:"vertexai", name:"Vertex AI", icon:"settings_remote", mode:"telemetry", requirement:"gcloud CLI", envVar:"GOOGLE_CLOUD_PROJECT", note:"Official gcloud authentication status" },
        { id:"byteplus", name:"BytePlus Ark", icon:"rocket_launch", mode:"telemetry", requirement:"API key", envVar:"BYTEPLUS_API_KEY", note:"Official models API authentication check" },
        { id:"ollama", name:"Ollama", icon:"dns", mode:"telemetry", requirement:"local Ollama server", envVar:"OLLAMA_HOST", note:"Official local tags and running-model APIs" },
        { id:"together", name:"Together AI", icon:"join_inner", mode:"telemetry", requirement:"API key", envVar:"TOGETHER_API_KEY", note:"Official credit balance" },
        { id:"groq", name:"Groq", icon:"fast_forward", mode:"telemetry", requirement:"API key", envVar:"GROQ_API_KEY", note:"Official models API authentication check" },
        { id:"cohere", name:"Cohere", icon:"waves", mode:"telemetry", requirement:"API key", envVar:"COHERE_API_KEY", note:"Official models API authentication check" },
        { id:"replicate", name:"Replicate", icon:"content_copy", mode:"telemetry", requirement:"API token", envVar:"REPLICATE_API_TOKEN", note:"Official account API authentication check" },
        { id:"fireworks", name:"Fireworks AI", icon:"local_fire_department", mode:"telemetry", requirement:"API key", envVar:"FIREWORKS_API_KEY", note:"Official inference models authentication check" },
        { id:"ai21", name:"AI21", icon:"looks_21", mode:"telemetry", requirement:"API key", envVar:"AI21_API_KEY", note:"Configured status; no documented read-only usage API" },
        { id:"perplexity", name:"Perplexity", icon:"auto_awesome", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"cursor", name:"Cursor", icon:"mouse", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"cline", name:"Cline", icon:"code_blocks", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"opencode", name:"OpenCode", icon:"open_in_new", mode:"informational", requirement:"none", envVar:"", note:"Usage belongs to configured upstream providers" },
        { id:"kilo", name:"Kilo", icon:"straighten", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"kiro", name:"Kiro", icon:"tune", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
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
        radius: Theme.cornerRadius + 4
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.22)
        implicitHeight: hero.implicitHeight + Theme.spacingL * 2

        Column {
            id: hero
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                DankIcon { name:"monitoring"; size:22; color:Theme.primary }
                StyledText { Layout.fillWidth:true; text:"AiOverviewControl"; font.pixelSize:Theme.fontSizeLarge; font.weight:Font.Bold; color:Theme.surfaceText }
                StyledText { text:"v1.3.0"; font.pixelSize:Theme.fontSizeSmall; color:Theme.primary }
            }

            StyledText {
                width: parent.width
                text: t("settings.hero.self_managed", "Provider collection, health checks, refresh policy and rendering are managed by this plugin. No external aggregation tool is required.")
                wrapMode: Text.WordWrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            StyledText {
                text: t("settings.active_count", "{count} active", { count:selectedIds.length })
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
            }
        }
    }

    StyledText { width:parent.width; text:t("settings.section.interface", "Interface"); font.pixelSize:Theme.fontSizeSmall; font.weight:Font.DemiBold; color:Theme.surfaceVariantText }

    DankDropdown {
        width: parent.width
        text: t("settings.language.label", "Language")
        description: t("settings.language.description", "UI language for this plugin. Auto follows system locale.")
        currentValue: loadValue("languageOverride", "auto")
        options: ["auto", "en_US", "pt_BR", "zh_CN"]
        optionIcons: ["language", "translate", "translate", "translate"]
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
        options: ["auto", "custom"]
        optionIcons: ["auto_awesome", "tune"]
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

    ProviderSection {
        width: parent.width
        title: t("settings.telemetry_providers", "Telemetry providers")
        description: t("settings.telemetry_providers_desc", "Adapters backed by official CLIs, documented APIs, or local usage stores.")
        providers: root.telemetryProviders
    }

    ProviderSection {
        width: parent.width
        title: t("settings.informational_providers", "Informational providers")
        description: t("settings.informational_providers_desc", "These providers expose no public read-only quota API. Their cards link the user to the official usage surface.")
        providers: root.informationalProviders
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
                    required property var modelData
                    width: parent.width
                    spacing: Theme.spacingXS
                    StyledText { width:parent.width; text:modelData.label; wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall; font.weight:Font.Medium }
                    StyledRect {
                        width: parent.width
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        implicitHeight: commandText.implicitHeight + Theme.spacingS * 2
                        StyledText { id:commandText; anchors.fill:parent; anchors.margins:Theme.spacingS; text:modelData.cmd; wrapMode:Text.WrapAnywhere; color:Theme.primary; font.pixelSize:Theme.fontSizeSmall - 1 }
                    }
                }
            }
        }
    }

    component ProviderSection: Column {
        id: providerSection
        required property string title
        required property string description
        required property var providers
        spacing: Theme.spacingS

        StyledText { width:parent.width; text:providerSection.title; color:Theme.surfaceText; font.pixelSize:Theme.fontSizeMedium; font.weight:Font.DemiBold }
        StyledText { width:parent.width; text:providerSection.description; wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall }

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
                    color: active ? Theme.withAlpha(Theme.primary, 0.17) : Theme.withAlpha(Theme.surfaceVariantText, 0.07)
                    border.width: active ? 1 : 0
                    border.color: Theme.withAlpha(Theme.primary, activeFocus ? 0.9 : 0.45)
                    activeFocusOnTab: true
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
                    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:root.toggleProvider(modelData.id) }
                }
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingXS
            Repeater {
                model: providerSection.providers.filter(function(p) { return root.isSelected(p.id); })
                delegate: StyledRect {
                    required property var modelData
                    readonly property var health: root.healthFor(modelData.id)
                    width: parent.width
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
                    implicitHeight: providerRow.implicitHeight + Theme.spacingS * 2
                    RowLayout {
                        id: providerRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingS
                        StyledText { Layout.preferredWidth:110; text:modelData.name; color:Theme.surfaceText; font.pixelSize:Theme.fontSizeSmall; font.weight:Font.Medium }
                        StyledText { Layout.fillWidth:true; text:modelData.note; wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall - 1 }
                        StyledText {
                            text: health.status === "ready" ? t("settings.health.ready", "Ready") : health.detail
                            color: health.status === "ready" ? Theme.success : (health.status === "missing" ? Theme.warning : Theme.surfaceVariantText)
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.weight: Font.DemiBold
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
