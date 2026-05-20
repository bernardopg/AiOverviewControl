import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "aiOverviewControl"

    // ── helpers ──────────────────────────────────────────────────────────────

    readonly property var allProviders: [
        { id: "claude",      name: "Claude",        icon: "psychology",     auth: "native",    envVar: "" },
        { id: "copilot",     name: "Copilot",       icon: "code",           auth: "gh/token",  envVar: "COPILOT_GITHUB_TOKEN" },
        { id: "codex",       name: "Codex",         icon: "terminal",       auth: "codexbar",  envVar: "" },
        { id: "gemini",      name: "Gemini",        icon: "star",           auth: "key/oauth", envVar: "GEMINI_API_KEY" },
        { id: "9router",     name: "9Router",       icon: "share",          auth: "local db",  envVar: "" },
        { id: "openrouter",  name: "OpenRouter",    icon: "route",          auth: "key",       envVar: "OPENROUTER_API_KEY" },
        { id: "deepseek",    name: "DeepSeek",      icon: "search",         auth: "key",       envVar: "DEEPSEEK_API_KEY" },
        { id: "kimi",        name: "Kimi",          icon: "language",       auth: "key",       envVar: "MOONSHOT_API_KEY" },
        { id: "mistral",     name: "Mistral",       icon: "wind_power",     auth: "key",       envVar: "MISTRAL_API_KEY" },
        { id: "glm",         name: "GLM",           icon: "memory",         auth: "key",       envVar: "GLM_API_KEY" },
        { id: "minimax",     name: "MiniMax",       icon: "bar_chart",      auth: "key",       envVar: "MINIMAX_API_KEY" },
        { id: "qwen",        name: "Qwen",          icon: "hub",            auth: "key",       envVar: "DASHSCOPE_API_KEY" },
        { id: "nvidia",      name: "NVIDIA NIM",    icon: "developer_board",auth: "key",       envVar: "NVIDIA_API_KEY" },
        { id: "cloudflare",  name: "Cloudflare AI", icon: "cloud",          auth: "key+id",    envVar: "CLOUDFLARE_AI_TOKEN" },
        { id: "vertexai",    name: "Vertex AI",     icon: "settings_remote",auth: "gcloud",    envVar: "" },
        { id: "byteplus",    name: "BytePlus Ark",  icon: "rocket_launch",  auth: "key",       envVar: "BYTEPLUS_API_KEY" },
        { id: "ollama",      name: "Ollama",        icon: "dns",            auth: "local",     envVar: "" },
        { id: "perplexity",  name: "Perplexity",    icon: "auto_awesome",   auth: "codexbar",  envVar: "" },
        { id: "cursor",      name: "Cursor",        icon: "mouse",          auth: "codexbar",  envVar: "" },
        { id: "cline",       name: "Cline",         icon: "code_blocks",    auth: "codexbar",  envVar: "" },
        { id: "opencode",    name: "OpenCode",      icon: "open_in_new",    auth: "codexbar",  envVar: "" },
        { id: "kilo",        name: "Kilo",          icon: "straighten",     auth: "codexbar",  envVar: "" },
        { id: "kiro",        name: "Kiro",          icon: "tune",           auth: "codexbar",  envVar: "" },
        { id: "warp",        name: "Warp",          icon: "speed",          auth: "codexbar",  envVar: "" },
        { id: "amp",         name: "Amp",           icon: "bolt",           auth: "codexbar",  envVar: "" }
    ]

    readonly property var nativeProviders: allProviders.filter(function(p) {
        return p.auth !== "codexbar";
    })
    readonly property var codexbarProviders: allProviders.filter(function(p) {
        return p.auth === "codexbar";
    })

    // current selection as array (live, reflects text field edits)
    property var selectedIds: {
        const raw = root.loadValue("providerSelection", "codex,claude,copilot");
        const parts = raw.split(",");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            const v = parts[i].trim().toLowerCase();
            if (v.length > 0 && result.indexOf(v) < 0) result.push(v);
        }
        return result;
    }

    function isSelected(id) {
        return selectedIds.indexOf(id) >= 0;
    }

    function toggleProvider(id) {
        const current = root.loadValue("providerSelection", "codex,claude,copilot");
        const parts = current.split(",");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            const v = parts[i].trim().toLowerCase();
            if (v.length > 0 && result.indexOf(v) < 0) result.push(v);
        }
        const idx = result.indexOf(id);
        if (idx >= 0) {
            result.splice(idx, 1);
        } else {
            result.push(id);
        }
        const csv = result.length > 0 ? result.join(",") : id;
        root.saveValue("providerSelection", csv);
        selectedIds = result.length > 0 ? result : [id];
    }

    // ── Hero card ─────────────────────────────────────────────────────────────

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

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankIcon {
                    name: "monitoring"
                    size: 20
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "AiOverviewControl"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item { Layout.fillWidth: true; width: 1 }

                StyledText {
                    text: "v1.2.2"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.withAlpha(Theme.primary, 0.7)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                width: parent.width
                text: "Monitora quotas de uso de " + allProviders.length + " provedores de IA diretamente na DankBar. Provedores são consultados isoladamente — uma falha não afeta os demais."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            // summary chips
            Row {
                spacing: Theme.spacingS

                StyledRect {
                    radius: 99
                    color: Theme.withAlpha(Theme.primary, 0.15)
                    implicitWidth: summaryRow1.implicitWidth + Theme.spacingM * 2
                    implicitHeight: summaryRow1.implicitHeight + Theme.spacingXS * 2

                    Row {
                        id: summaryRow1
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon { name: "check_circle"; size: 14; color: Theme.primary }
                        StyledText {
                            text: selectedIds.length + " ativos"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.primary
                        }
                    }
                }

                StyledRect {
                    radius: 99
                    color: Theme.withAlpha(Theme.surfaceVariantText, 0.1)
                    implicitWidth: summaryRow2.implicitWidth + Theme.spacingM * 2
                    implicitHeight: summaryRow2.implicitHeight + Theme.spacingXS * 2

                    Row {
                        id: summaryRow2
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon { name: "database"; size: 14; color: Theme.surfaceVariantText }
                        StyledText {
                            text: allProviders.length + " disponíveis"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }
            }
        }
    }

    // ── Refresh ───────────────────────────────────────────────────────────────

    StyledText {
        width: parent.width
        text: "Atualização"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    DankDropdown {
        id: refreshDropdown
        width: parent.width
        text: "Intervalo de atualização"
        description: "Frequência com que os scripts locais buscam dados de cada provedor."
        currentValue: root.loadValue("refreshInterval", "120000")
        options: ["60000", "120000", "300000", "900000", "1800000"]
        optionIcons: ["timer", "timer", "timer_off", "timer_off", "timer_off"]
        dropdownWidth: 200
        onValueChanged: function(value) { root.saveValue("refreshInterval", value); }
    }

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceVariantText, 0.06)
        implicitHeight: refreshHintRow.implicitHeight + Theme.spacingS * 2

        Row {
            id: refreshHintRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingS

            DankIcon {
                name: "info"
                size: 14
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: parent.width - 14 - Theme.spacingS
                text: {
                    const v = refreshDropdown.currentValue;
                    const map = {
                        "60000":   "1 minuto — monitoramento ativo. Aumenta chamadas de API.",
                        "120000":  "2 minutos — padrão recomendado para uso normal.",
                        "300000":  "5 minutos — adequado para muitos provedores ou redes lentas.",
                        "900000":  "15 minutos — conservador, reduz rate-limit em APIs externas.",
                        "1800000": "30 minutos — mínimo, apenas para verificação ocasional."
                    };
                    return map[v] || "";
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── Providers: native ─────────────────────────────────────────────────────

    StyledText {
        width: parent.width
        text: "Provedores nativos"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    StyledText {
        width: parent.width
        text: "Estes provedores usam scripts locais ou APIs diretas — funcionam sem o codexbar. Clique para ativar/desativar."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Flow {
        width: parent.width
        spacing: Theme.spacingS

        Repeater {
            model: root.nativeProviders

            delegate: Rectangle {
                id: nativeChip
                required property var modelData

                readonly property bool active: root.isSelected(modelData.id)
                readonly property bool hasEnvVar: modelData.envVar.length > 0

                width: nativeChipRow.implicitWidth + Theme.spacingM * 2
                height: 36
                radius: 18
                color: active ? Theme.withAlpha(Theme.primary, 0.18) : Theme.withAlpha(Theme.surfaceVariantText, 0.08)
                border.width: active ? 1 : 0
                border.color: Theme.withAlpha(Theme.primary, 0.5)

                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    id: nativeChipRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: active ? "check" : modelData.icon
                        size: 14
                        color: active ? Theme.primary : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: modelData.name
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: active ? Font.Medium : Font.Normal
                        color: active ? Theme.primary : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // auth indicator dot
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.auth === "codexbar" || modelData.envVar.length > 0
                        color: modelData.auth === "local db" || modelData.auth === "local" || modelData.auth === "native" || modelData.auth === "gcloud"
                               ? Theme.withAlpha(Theme.secondary, 0.7)
                               : Theme.withAlpha(Theme.warning, 0.8)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.toggleProvider(modelData.id)
                }
            }
        }
    }

    // env var reference for active native providers that need keys
    Column {
        width: parent.width
        spacing: Theme.spacingXS
        visible: {
            for (let i = 0; i < root.nativeProviders.length; i++) {
                const p = root.nativeProviders[i];
                if (p.envVar.length > 0 && root.isSelected(p.id)) return true;
            }
            return false;
        }

        StyledText {
            width: parent.width
            text: "Variáveis de ambiente necessárias para provedores ativos:"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            topPadding: Theme.spacingXS
        }

        Repeater {
            model: root.nativeProviders.filter(function(p) {
                return p.envVar.length > 0 && root.isSelected(p.id);
            })

            delegate: StyledRect {
                required property var modelData
                width: parent.width
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.7)
                implicitHeight: envRow.implicitHeight + Theme.spacingS * 2

                Row {
                    id: envRow
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingM

                    StyledText {
                        text: modelData.name
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        width: 90
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: modelData.envVar
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: "monospace"
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item { width: 1; Layout.fillWidth: true }

                    // extra hint for cloudflare
                    StyledText {
                        visible: modelData.id === "cloudflare"
                        text: "+ CLOUDFLARE_ACCOUNT_ID"
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.withAlpha(Theme.warning, 0.8)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // ── Providers: codexbar-only ──────────────────────────────────────────────

    DankCollapsibleSection {
        id: codexbarProvidersSection
        width: parent.width
        title: "Provedores via codexbar"
        description: "Requerem o codexbar instalado. Sem ele, aparecem como erro."
        expanded: false

        Flow {
            width: parent.width
            spacing: Theme.spacingS

            Repeater {
                model: root.codexbarProviders

                delegate: Rectangle {
                    id: cbChip
                    required property var modelData

                    readonly property bool active: root.isSelected(modelData.id)

                    width: cbChipRow.implicitWidth + Theme.spacingM * 2
                    height: 36
                    radius: 18
                    color: active ? Theme.withAlpha(Theme.secondary, 0.18) : Theme.withAlpha(Theme.surfaceVariantText, 0.08)
                    border.width: active ? 1 : 0
                    border.color: Theme.withAlpha(Theme.secondary, 0.5)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        id: cbChipRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: active ? "check" : modelData.icon
                            size: 14
                            color: active ? Theme.secondary : Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: modelData.name
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: active ? Font.Medium : Font.Normal
                            color: active ? Theme.secondary : Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleProvider(modelData.id)
                    }
                }
            }
        }
    }

    // active list + manual field
    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.primary, 0.06)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.15)
        implicitHeight: activeProviderCol.implicitHeight + Theme.spacingM * 2

        Column {
            id: activeProviderCol
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankIcon { name: "playlist_add_check"; size: 16; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }

                StyledText {
                    text: "Seleção atual"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                width: parent.width
                text: selectedIds.length > 0 ? selectedIds.join(", ") : "(nenhum)"
                font.pixelSize: Theme.fontSizeSmall
                font.family: "monospace"
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: "Editar manualmente (separado por vírgula):"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            DankTextField {
                id: customField
                width: parent.width
                text: root.loadValue("providerSelection", "codex,claude,copilot")
                placeholderText: "claude,copilot,deepseek,ollama"
                onEditingFinished: {
                    const parts = text.split(",");
                    const result = [];
                    for (let i = 0; i < parts.length; i++) {
                        const v = parts[i].trim().toLowerCase();
                        if (v.length > 0 && result.indexOf(v) < 0) result.push(v);
                    }
                    if (result.length > 0) {
                        root.saveValue("providerSelection", result.join(","));
                        root.selectedIds = result;
                    }
                }
            }
        }
    }

    // ── codexbar path ─────────────────────────────────────────────────────────

    StyledText {
        width: parent.width
        text: "Fallback codexbar"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            width: parent.width
            text: "Caminho absoluto para o executável codexbar. Necessário apenas para provedores sem adaptador nativo. Deixe vazio para auto-detectar em PATH, ~/.local/bin e /usr/local/bin."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        DankTextField {
            id: codexbarField
            width: parent.width
            text: root.loadValue("codexbarPath", "")
            placeholderText: "/home/user/.local/bin/codexbar  (auto se vazio)"
            onEditingFinished: root.saveValue("codexbarPath", text)
        }

        // codexbar status hint based on field content
        Row {
            spacing: Theme.spacingXS
            visible: true

            DankIcon {
                name: codexbarField.text.trim().length > 0 ? "folder_open" : "search"
                size: 14
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: codexbarField.text.trim().length > 0
                      ? "Usando caminho customizado: " + codexbarField.text.trim()
                      : "Auto-detectando codexbar no PATH do sistema."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    // ── Source mode ───────────────────────────────────────────────────────────

    StyledText {
        width: parent.width
        text: "Modo de fonte (fallback)"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    DankDropdown {
        id: sourceDropdown
        width: parent.width
        text: "Modo de fonte"
        description: "Passado ao codexbar para provedores que o usam. Adaptadores nativos ignoram este valor."
        currentValue: root.loadValue("sourceMode", "cli")
        options: ["cli", "auto", "oauth", "api", "web"]
        optionIcons: ["terminal", "auto_awesome", "key", "api", "language"]
        dropdownWidth: 180
        onValueChanged: function(value) { root.saveValue("sourceMode", value); }
    }

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceVariantText, 0.06)
        implicitHeight: sourceModeHintCol.implicitHeight + Theme.spacingS * 2

        Column {
            id: sourceModeHintCol
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingXS

            Repeater {
                model: [
                    { mode: "cli",   icon: "check_circle", color: Theme.secondary,          text: "cli — melhor padrão no Linux. Telemetria local, zero chamadas de rede." },
                    { mode: "auto",  icon: "info",          color: Theme.surfaceVariantText, text: "auto — deixa o codexbar escolher a fonte por provedor." },
                    { mode: "oauth", icon: "key",           color: Theme.surfaceVariantText, text: "oauth — autentica via OAuth onde suportado pelo provedor." },
                    { mode: "api",   icon: "api",           color: Theme.surfaceVariantText, text: "api — usa tokens de API configurados no codexbar." },
                    { mode: "web",   icon: "warning",       color: Theme.warning,            text: "web — scraping de dashboards. Pode ser exclusivo do macOS para alguns provedores." }
                ]

                delegate: Row {
                    required property var modelData
                    visible: sourceDropdown.currentValue === modelData.mode
                    spacing: Theme.spacingS
                    width: parent.width

                    DankIcon {
                        name: modelData.icon
                        size: 14
                        color: modelData.color
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: modelData.text
                        font.pixelSize: Theme.fontSizeSmall
                        color: modelData.color
                        wrapMode: Text.WordWrap
                        width: parent.width - 14 - Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // ── Show errors toggle ────────────────────────────────────────────────────

    DankToggle {
        width: parent.width
        text: "Mostrar provedores com erro"
        description: "Mantém cartões de erro visíveis no painel. Recomendado ao configurar novos provedores para identificar falhas de autenticação."
        checked: root.loadValue("showErrorProviders", "true") === "true"
        onToggled: function(checked) {
            root.saveValue("showErrorProviders", checked ? "true" : "false");
        }
    }

    // ── Auth quick reference ──────────────────────────────────────────────────

    DankCollapsibleSection {
        id: authSection
        width: parent.width
        title: "Referência de autenticação"
        description: "Como cada tipo de provedor obtém credenciais."
        expanded: false

        Column {
            width: parent.width
            spacing: Theme.spacingM

            Repeater {
                model: [
                    {
                        title: "Nativos sem chave",
                        icon: "check_circle",
                        color: Theme.secondary,
                        items: ["claude — lê ~/.claude/ (JSONL + OAuth local)", "9router — lê ~/.9router/db/data.sqlite", "ollama — GET localhost:11434/api/tags", "vertexai — gcloud auth print-access-token"]
                    },
                    {
                        title: "Chave de API via env var",
                        icon: "key",
                        color: Theme.primary,
                        items: ["openrouter — OPENROUTER_API_KEY", "deepseek — DEEPSEEK_API_KEY", "kimi — MOONSHOT_API_KEY ou KIMI_API_KEY", "minimax — MINIMAX_API_KEY", "glm — GLM_API_KEY ou ZHIPU_API_KEY", "mistral — MISTRAL_API_KEY", "nvidia — NVIDIA_API_KEY", "cloudflare — CLOUDFLARE_AI_TOKEN + CLOUDFLARE_ACCOUNT_ID", "byteplus — BYTEPLUS_API_KEY ou ARK_API_KEY", "qwen — DASHSCOPE_API_KEY ou QWEN_API_KEY"]
                    },
                    {
                        title: "GitHub token (Copilot)",
                        icon: "code",
                        color: Theme.primary,
                        items: ["Prioridade: gh auth token → COPILOT_GITHUB_TOKEN → GH_TOKEN → GITHUB_TOKEN", "Execute: gh auth login"]
                    },
                    {
                        title: "Via codexbar (fallback)",
                        icon: "terminal",
                        color: Theme.surfaceVariantText,
                        items: ["codex, gemini, perplexity, cursor, cline, opencode, kilo, kiro, warp, amp", "Requer codexbar instalado e configurado com as credenciais do provedor"]
                    }
                ]

                delegate: Column {
                    required property var modelData
                    width: parent.width
                    spacing: Theme.spacingXS

                    Row {
                        spacing: Theme.spacingXS

                        DankIcon { name: modelData.icon; size: 14; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }

                        StyledText {
                            text: modelData.title
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Repeater {
                        model: modelData.items

                        StyledText {
                            required property string modelData
                            width: parent.width
                            text: "  · " + modelData
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            leftPadding: Theme.spacingS
                        }
                    }
                }
            }
        }
    }

    // ── Diagnóstico ───────────────────────────────────────────────────────────

    DankCollapsibleSection {
        id: diagSection
        width: parent.width
        title: "Diagnóstico e testes"
        description: "Comandos para validar a pipeline fora do widget."
        expanded: false

        Column {
            width: parent.width
            spacing: Theme.spacingM

            Repeater {
                model: [
                    {
                        label: "Testar backend completo (provedores selecionados)",
                        cmd: "PLUGIN=~/.config/DankMaterialShell/plugins/aiOverviewControl\n$PLUGIN/get-provider-usage \"$(command -v codexbar)\" \"" + root.selectedIds.join(",") + "\" cli $PLUGIN/get-copilot-usage | jq ."
                    },
                    {
                        label: "Testar Claude",
                        cmd: "~/.config/DankMaterialShell/plugins/aiOverviewControl/get-claude-usage"
                    },
                    {
                        label: "Testar Copilot",
                        cmd: "gh auth status\n~/.config/DankMaterialShell/plugins/aiOverviewControl/get-copilot-usage | jq ."
                    },
                    {
                        label: "Verificar dependências",
                        cmd: "command -v bash jq curl sqlite3 gh gcloud codexbar 2>&1 | cat"
                    },
                    {
                        label: "Validar QML",
                        cmd: "qmllint ~/.config/DankMaterialShell/plugins/aiOverviewControl/AiOverviewControlWidget.qml"
                    }
                ]

                delegate: Column {
                    required property var modelData
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceVariantText
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    StyledRect {
                        width: parent.width
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        implicitHeight: cmdText.implicitHeight + Theme.spacingS * 2

                        StyledText {
                            id: cmdText
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            text: modelData.cmd
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.family: "monospace"
                            color: Theme.primary
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }
        }
    }

    // ── Info footer ───────────────────────────────────────────────────────────

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceVariantText, 0.06)
        border.width: 1
        border.color: Theme.withAlpha(Theme.surfaceVariantText, 0.1)
        implicitHeight: footerRow.implicitHeight + Theme.spacingM * 2

        Row {
            id: footerRow
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            DankIcon { name: "info"; size: 16; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }

            StyledText {
                width: parent.width - 16 - Theme.spacingM
                text: "Adaptadores nativos (Claude, Copilot, DeepSeek, Kimi, GLM, MiniMax, Cloudflare, Ollama, Vertex AI) funcionam sem codexbar. Mistral, NVIDIA, Qwen e BytePlus validam a chave mas não têm endpoint de quota — exibem cartão informativo."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
