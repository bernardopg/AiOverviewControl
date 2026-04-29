import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "aiOverviewControl"

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius + 4
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.2)
        implicitHeight: heroColumn.implicitHeight + Theme.spacingL * 2
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary, 0.16) }
                GradientStop { position: 0.56; color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.08) }
                GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.02) }
            }
        }

        Column {
            id: heroColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: "AI usage telemetry"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
            }

            StyledText {
                width: parent.width
                text: "AiOverviewControl Settings"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: "Configure CodexBar-powered usage telemetry for Codex, Claude, Copilot, and other AI providers."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Runtime"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    DankDropdown {
        id: refreshDropdown
        text: "Refresh Interval"
        description: "How often usage telemetry is fetched from CodexBar."
        currentValue: root.loadValue("refreshInterval", "120000")
        options: ["60000", "120000", "300000", "900000", "1800000"]
        dropdownWidth: 180
        onValueChanged: function(value) {
            root.saveValue("refreshInterval", value);
        }
    }

    StyledText {
        width: parent.width
        leftPadding: Theme.spacingM
        text: {
            const value = refreshDropdown.currentValue;
            if (value === "60000") return "Refreshes every 1 minute";
            if (value === "120000") return "Refreshes every 2 minutes";
            if (value === "300000") return "Refreshes every 5 minutes";
            if (value === "900000") return "Refreshes every 15 minutes";
            if (value === "1800000") return "Refreshes every 30 minutes";
            return "";
        }
        font.pixelSize: Theme.fontSizeSmall
        font.italic: true
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Binary"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            width: parent.width
            text: "Path to the codexbar executable. Leave empty to auto-detect PATH, ~/.local/bin, and /usr/local/bin."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        DankTextField {
            width: parent.width
            text: root.loadValue("codexbarPath", "")
            placeholderText: "/home/user/.local/bin/codexbar"
            onEditingFinished: root.saveValue("codexbarPath", text)
        }
    }

    StyledText {
        width: parent.width
        text: "Providers"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    DankDropdown {
        id: providerDropdown
        text: "Provider Set"
        description: "Providers are queried one by one, so partial failures do not hide working accounts."
        currentValue: root.loadValue("providerSelection", "codex,claude,copilot")
        options: [
            "codex",
            "claude",
            "copilot",
            "codex,claude",
            "codex,claude,copilot",
            "codex,claude,copilot,gemini,openrouter,perplexity"
        ]
        dropdownWidth: 330
        onValueChanged: function(value) {
            root.saveValue("providerSelection", value);
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            width: parent.width
            text: "Custom provider list"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        DankTextField {
            width: parent.width
            text: root.loadValue("providerSelection", "codex,claude,copilot")
            placeholderText: "codex,claude,copilot,gemini"
            onEditingFinished: {
                const parts = text.split(",");
                const result = [];
                for (let i = 0; i < parts.length; i++) {
                    const provider = parts[i].trim().toLowerCase();
                    if (provider.length > 0 && result.indexOf(provider) < 0) {
                        result.push(provider);
                    }
                }
                if (result.length > 0) {
                    root.saveValue("providerSelection", result.join(","));
                }
            }
        }
    }

    StyledText {
        width: parent.width
        leftPadding: Theme.spacingM
        text: {
            const value = providerDropdown.currentValue;
            if (value === "codex,claude,copilot") return "Recommended overview: Codex/ChatGPT, Claude, and Copilot when supported by the installed CodexBar build.";
            if (value.indexOf(",") >= 0) return "Multiple providers are fetched separately and merged in the widget.";
            return "Single-provider mode keeps the bar focused on one account.";
        }
        font.pixelSize: Theme.fontSizeSmall
        font.italic: true
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Source mode"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    DankDropdown {
        id: sourceDropdown
        text: "Source Mode"
        description: "CLI is the most reliable default on Linux. API requires CodexBar token config."
        currentValue: root.loadValue("sourceMode", "cli")
        options: ["cli", "auto", "oauth", "api", "web"]
        dropdownWidth: 180
        onValueChanged: function(value) {
            root.saveValue("sourceMode", value);
        }
    }

    StyledText {
        width: parent.width
        leftPadding: Theme.spacingM
        text: {
            const value = sourceDropdown.currentValue;
            if (value === "cli") return "CLI: Works for your current Codex and Claude subscription telemetry on Linux.";
            if (value === "auto") return "Auto: Lets CodexBar choose; it may choose web paths that are macOS-only.";
            if (value === "oauth") return "OAuth: Uses supported provider OAuth/session auth when available.";
            if (value === "api") return "API: Uses provider API tokens configured in CodexBar; subscriptions do not always expose API usage.";
            if (value === "web") return "Web: Uses provider web dashboards; CodexBar reports this as macOS-only for some providers.";
            return "";
        }
        font.pixelSize: Theme.fontSizeSmall
        font.italic: true
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    DankDropdown {
        id: errorDropdown
        text: "Show Provider Errors"
        description: "Keep enabled while adding Copilot/API providers so unsupported sources are visible."
        currentValue: root.loadValue("showErrorProviders", "true")
        options: ["true", "false"]
        dropdownWidth: 140
        onValueChanged: function(value) {
            root.saveValue("showErrorProviders", value);
        }
    }

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.warning, 0.1)
        border.width: 1
        border.color: Theme.withAlpha(Theme.warning, 0.26)
        implicitHeight: cautionText.implicitHeight + Theme.spacingM * 2

        StyledText {
            id: cautionText
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            text: "On Linux, CodexBar currently reports web dashboard fetching as macOS-only. Use CLI for subscription telemetry, or API only when you have provider API tokens configured."
            color: Theme.warning
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }
    }

    StyledText {
        width: parent.width
        text: "Quick setup"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.surfaceText, 0.08)
        implicitHeight: checklistColumn.implicitHeight + Theme.spacingM * 2

        Column {
            id: checklistColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingXS

            Repeater {
                model: [
                    "1. Install CodexBar CLI",
                    "2. Test: codexbar usage --format json --provider codex --source cli",
                    "3. Add Claude, Copilot, or API providers as CodexBar supports them"
                ]

                StyledText {
                    required property string modelData
                    width: parent.width
                    text: modelData
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
