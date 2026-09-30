import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "aiOverviewControl"
    // The standalone settings window draws its own brand header, so it hides
    // the mascot + title here to avoid showing them twice.
    property bool showBrand: true

    readonly property string i18nLocale: AiOverviewControlI18n.normalizedLocale
    property var selectedIds: normalizeProviderSelection(loadValue("providerSelection", "codex,claude,copilot"))
    property var pinnedIds: normalizeCsvList(loadValue("pinnedProviders", ""))
    property var pillIds: normalizePillSelection(loadValue("pillProviders", selectedIds.join(",")))
    // Stored empty means "follow the theme accent" — the same contract the
    // widget uses, so an empty value must never reach the color property.
    property color providerLogoColor: {
        root.settingsEpoch;
        const saved = String(loadValue("providerLogoColor", "") || "").trim();
        return saved.length > 0 ? saved : Theme.primary;
    }

    function normalizeCsvList(value) {
        const parts = String(value || "").split(",");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            const id = parts[i].trim().toLowerCase();
            if (id.length > 0 && result.indexOf(id) < 0) result.push(id);
        }
        return result;
    }

    function normalizePillSelection(value) {
        const parts = normalizeCsvList(value);
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            if (selectedIds.indexOf(parts[i]) >= 0) result.push(parts[i]);
        }
        return result.length > 0 ? result : [selectedIds[0]];
    }

    function isPillSelected(id) { return pillIds.indexOf(id) >= 0; }

    function togglePillProvider(id) {
        if (!isSelected(id)) return;
        const result = pillIds.slice();
        const index = result.indexOf(id);
        if (index >= 0 && result.length > 1) result.splice(index, 1);
        else if (index < 0) result.push(id);
        pillIds = result;
        saveValue("pillProviders", result.join(","));
    }

    function isPinned(id) { return pinnedIds.indexOf(id) >= 0; }

    function openProviderLogoColorPicker() {
        const modal = PopoutService.colorPickerModal;
        if (!modal) return;
        modal.selectedColor = root.providerLogoColor;
        modal.pickerTitle = t("settings.logo_color", "Provider logo color");
        modal.onColorSelectedCallback = function(selectedColor) {
            root.providerLogoColor = selectedColor;
            saveValue("providerLogoColor", selectedColor.toString());
        };
        modal.show();
    }

    function togglePinned(id) {
        const result = pinnedIds.slice();
        const index = result.indexOf(id);
        if (index >= 0) result.splice(index, 1);
        else result.push(id);
        pinnedIds = result;
        saveValue("pinnedProviders", result.join(","));
    }

    // Per-provider DankBar window overrides (issue #17). Mirrors the widget's
    // barWindowOverrideMap parsing: same slot vocabulary. Only entries that
    // differ from "primary" are persisted, so restoring the default removes
    // the pair and the CSV stays small.
    function barWindowOverrideMap() {
        const map = {};
        const raw = String(loadValue("barWindowOverrides", "") || "").trim();
        if (raw.length === 0) return map;
        const pairs = raw.split(",");
        for (let i = 0; i < pairs.length; i++) {
            const kv = pairs[i].split(":");
            if (kv.length !== 2) continue;
            const id = kv[0].trim().toLowerCase();
            const slot = kv[1].trim().toLowerCase();
            if (id.length === 0) continue;
            if (slot === "primary" || slot === "secondary" || slot === "tertiary" || slot === "highest") {
                map[id] = slot;
            }
        }
        return map;
    }

    function barChoiceFor(id) {
        const slot = barWindowOverrideMap()[id];
        return slot !== undefined ? slot : "primary";
    }

    function setBarChoice(id, slot) {
        if (!isSelected(id)) return;
        const map = barWindowOverrideMap();
        if (slot === "primary") delete map[id];
        else map[id] = slot;
        const pairs = [];
        for (const key in map) pairs.push(key + ":" + map[key]);
        saveValue("barWindowOverrides", pairs.join(","));
    }

    function providerDisplayName(id) {
        for (let i = 0; i < allProviders.length; i++) {
            if (allProviders[i].id === id) return allProviders[i].name;
        }
        return id;
    }

    // Same alias table the widget applies before looking up a threshold, so
    // validation accepts every spelling the runtime accepts.
    readonly property var providerAliases: ({
        agy: "antigravity", moonshot: "kimi", zhipu: "glm",
        "z.ai": "zai", dashscope: "qwen", alibaba: "qwen", nim: "nvidia",
        vertex: "vertexai", ark: "byteplus", modelark: "byteplus",
        grok: "xai"
    })

    // Inline validation for the per-provider threshold CSV. The widget's
    // parser drops malformed pairs silently, so without this the only symptom
    // of a typo is a notification that never arrives.
    function notifyThresholdIssues(value) {
        const raw = String(value || "").trim();
        if (raw.length === 0) return [];
        const known = {};
        for (let i = 0; i < allProviders.length; i++) known[allProviders[i].id] = true;
        const issues = [];
        const seen = {};
        const pairs = raw.split(",");
        for (let i = 0; i < pairs.length; i++) {
            const entry = pairs[i].trim();
            if (entry.length === 0) {
                issues.push(t("settings.notify.overrides_error_empty", "Empty entry — remove the stray comma."));
                continue;
            }
            const kv = entry.split(":");
            if (kv.length !== 2 || kv[0].trim().length === 0 || kv[1].trim().length === 0) {
                issues.push(t("settings.notify.overrides_error_pair", "“{entry}” is not a provider:percent pair.", { entry: entry }));
                continue;
            }
            const spelled = kv[0].trim().toLowerCase();
            const id = providerAliases[spelled] || spelled;
            const percentText = kv[1].trim();
            const percent = parseInt(percentText);
            if (!known[id]) {
                issues.push(t("settings.notify.overrides_error_provider", "Unknown provider “{id}”.", { id: kv[0].trim() }));
            } else if (seen[id]) {
                issues.push(t("settings.notify.overrides_error_duplicate", "“{id}” is listed more than once — the last value wins.", { id: id }));
            } else {
                seen[id] = true;
                if (!isSelected(id)) {
                    issues.push(t("settings.notify.overrides_error_untracked", "“{id}” is not a tracked provider, so it never alerts.", { id: id }));
                }
            }
            if (!/^[0-9]+$/.test(percentText) || !Number.isFinite(percent) || percent < 1 || percent > 100) {
                issues.push(t("settings.notify.overrides_error_percent", "“{value}” is not a whole percentage between 1 and 100.", { value: percentText }));
            }
        }
        return issues;
    }

    // Bumped by resetToDefaults() so every control re-reads its stored value.
    // Settings widgets evaluate loadValue() once at construction, so without
    // this the panel would keep showing the pre-reset state until reopened.
    property int settingsEpoch: 0

    // Every key this plugin persists, with the same default the widget assumes
    // when the key is absent. Keep in sync with the widget's pluginData reads.
    readonly property var settingDefaults: ({
        providerSelection: "codex,claude,copilot",
        pinnedProviders: "",
        pillProviders: "codex,claude,copilot",
        pillMode: "auto",
        barWindowOverrides: "",
        densityMode: "comfortable",
        languageOverride: "auto",
        refreshInterval: "120000",
        showErrorProviders: "true",
        showClaudeProjects: "true",
        costCurrency: "USD",
        showAntigravityModelDetails: "false",
        pillTooltip: "true",
        pillShowNames: "true",
        pillCompact: "false",
        quotaNotifications: "true",
        notifyThreshold: "85",
        notifyCooldownMinutes: "0",
        notifyThresholds: "",
        notifyWindowScope: "displayed",
        historyRetention: "2000",
        providerLogoColor: ""
    })

    function resetToDefaults() {
        for (const key in settingDefaults) {
            saveValue(key, settingDefaults[key]);
        }
        selectedIds = normalizeProviderSelection(settingDefaults.providerSelection);
        pinnedIds = [];
        pillIds = selectedIds.slice();
        providerLogoColor = Theme.primary.toString();
        // providerLogoColor defaults to "", which the widget reads as "follow
        // the theme accent"; the local property mirrors that for the swatch.
        settingsEpoch++;
        runHealth();
    }
    // Resolved imperatively in Component.onCompleted — Qt.resolvedUrl is only reliable
    // when called from the file's own execution context, not from a declarative binding.
    // Store installs place the plugin under its manifest id (e.g. "aiOverviewControl"),
    // which is not necessarily the display-name casing used by manual checkouts, so
    // this must never be a hardcoded literal.
    property string _pluginDir: ""
    // Version pill in the hero; read from plugin.json so releases only bump
    // the manifest.
    property string pluginVersion: ""
    property var providerHealth: ({})
    property string healthBuffer: ""
    property string healthScript: ""
    property bool healthRefreshPending: false

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

    readonly property int informationalCount: {
        let n = 0;
        for (let i = 0; i < selectedIds.length; i++) {
            const health = providerHealth[selectedIds[i]];
            if (health && health.status === "info") n++;
        }
        return n;
    }

    readonly property var allProviders: [
        { id:"codex", name:"Codex", icon:"terminal", mode:"telemetry", requirement:"codex CLI", envVar:"", note:"Official app-server rate limits" },
        { id:"claude", name:"Claude", icon:"psychology", mode:"telemetry", requirement:"claude CLI or ~/.claude", envVar:"", note:"Local analytics and authenticated usage" },
        { id:"copilot", name:"Copilot", icon:"code", mode:"telemetry", requirement:"gh CLI or GitHub token", envVar:"COPILOT_GITHUB_TOKEN", note:"Authenticated Copilot quota from the GitHub session" },
        { id:"pi", name:"pi", icon:"smart_toy", mode:"telemetry", requirement:"pi CLI or ~/.pi/agent/sessions", envVar:"", note:"Local session cost/token analytics — no quota API" },
        { id:"hermes", name:"Hermes", icon:"hub", mode:"telemetry", requirement:"hermes CLI or ~/.hermes/state.db", envVar:"", note:"Dual-nature: agent harness telemetry (sessions, tokens, models, projects) from the local state database; provider side routes through Nous Portal / OpenRouter — expand the card for details" },
        { id:"antigravity", name:"Antigravity", icon:"rocket_launch", mode:"telemetry", requirement:"Antigravity CLI keyring or IDE session", envVar:"", note:"Per-model quota and reset times, one block per signed-in account / IDE — expand the card to compare accounts" },
        { id:"gemini", name:"Gemini", icon:"star", mode:"telemetry", requirement:"gemini CLI or API key", envVar:"GEMINI_API_KEY", note:"Authentication status; quota remains in AI Studio" },
        { id:"9router", name:"9Router", icon:"share", mode:"telemetry", requirement:"local 9Router database", envVar:"", note:"Local requests, tokens and cost" },
        { id:"openrouter", name:"OpenRouter", icon:"route", mode:"telemetry", requirement:"API key or 9Router data", envVar:"OPENROUTER_API_KEY", note:"Official key usage and limits" },
        { id:"deepseek", name:"DeepSeek", icon:"search", mode:"telemetry", requirement:"API key", envVar:"DEEPSEEK_API_KEY", note:"Official account balance" },
        { id:"kimi", name:"Kimi", icon:"language", mode:"telemetry", requirement:"API key", envVar:"MOONSHOT_API_KEY", note:"Account balance (USD/CNY), or Kimi Code subscription quota with a sk-kimi- key / KIMI_CODING_API_KEY" },
        { id:"kimi-code", name:"Kimi Code", icon:"language", mode:"telemetry", requirement:"API key", envVar:"KIMI_CODING_API_KEY", note:"Independent Kimi Code subscription quota" },
        { id:"minimax", name:"MiniMax", icon:"bar_chart", mode:"telemetry", requirement:"API key or Token Plan key", envVar:"MINIMAX_API_KEY", note:"Token Plan quota (5h + weekly) via MINIMAX_TOKEN_PLAN_KEY or sk-cp MINIMAX_API_KEY; pay-as-you-go keys use models API authentication" },
        { id:"commandcode", name:"Command Code", icon:"terminal", mode:"telemetry", requirement:"API key or cmd login", envVar:"COMMAND_CODE_API_KEY", note:"Uses COMMAND_CODE_API_KEY or the credential saved by cmd login. Reads /alpha/billing/credits for 5h/weekly/monthly quota; falls back to /provider/v1/models on alpha failure." },
        { id:"glm", name:"GLM", icon:"memory", mode:"telemetry", requirement:"API key", envVar:"GLM_API_KEY", note:"China (Zhipu) quota windows and plan; falls back to models authentication" },
        { id:"zai", name:"Z.ai", icon:"bubble_chart", mode:"telemetry", requirement:"API key", envVar:"ZAI_API_KEY", note:"Official quota windows and plan; falls back to models authentication" },
        { id:"mistral", name:"Mistral", icon:"wind_power", mode:"telemetry", requirement:"API key", envVar:"MISTRAL_API_KEY", note:"Official models API authentication check" },
        { id:"qwen", name:"Qwen", icon:"hub", mode:"telemetry", requirement:"API key", envVar:"DASHSCOPE_API_KEY", note:"DashScope models API authentication check" },
        { id:"nvidia", name:"NVIDIA NIM", icon:"developer_board", mode:"telemetry", requirement:"API key", envVar:"NVIDIA_API_KEY", note:"Configured-key status; the public models catalog cannot validate the key" },
        { id:"cloudflare", name:"Cloudflare AI", icon:"cloud", mode:"telemetry", requirement:"API token", envVar:"CLOUDFLARE_AI_TOKEN", note:"Token verify + Workers AI analytics" },
        { id:"vertexai", name:"Vertex AI", icon:"settings_remote", mode:"telemetry", requirement:"gcloud CLI", envVar:"GOOGLE_CLOUD_PROJECT", note:"Official gcloud authentication status" },
        { id:"byteplus", name:"BytePlus Ark", icon:"rocket_launch", mode:"telemetry", requirement:"API key", envVar:"BYTEPLUS_API_KEY", note:"Official models API authentication check" },
        { id:"ollama", name:"Ollama", icon:"dns", mode:"telemetry", requirement:"local Ollama server", envVar:"OLLAMA_HOST", note:"Official local tags and running-model APIs" },
        { id:"together", name:"Together AI", icon:"join_inner", mode:"telemetry", requirement:"API key", envVar:"TOGETHER_API_KEY", note:"Read-only API-key validation; usage and billing remain in the console" },
        { id:"groq", name:"Groq", icon:"fast_forward", mode:"telemetry", requirement:"API key", envVar:"GROQ_API_KEY", note:"Official models API authentication check" },
        { id:"cohere", name:"Cohere", icon:"waves", mode:"telemetry", requirement:"API key", envVar:"COHERE_API_KEY", note:"Official models API authentication check" },
        { id:"replicate", name:"Replicate", icon:"content_copy", mode:"telemetry", requirement:"API token", envVar:"REPLICATE_API_TOKEN", note:"Official account API authentication check" },
        { id:"fireworks", name:"Fireworks AI", icon:"local_fire_department", mode:"telemetry", requirement:"API key", envVar:"FIREWORKS_API_KEY", note:"API-key validation; FIREWORKS_ACCOUNT_ID enables account quotas" },
        { id:"xai", name:"xAI (Grok)", icon:"bolt", mode:"telemetry", requirement:"grok login or API key", envVar:"XAI_API_KEY", note:"Prefers grok login (~/.grok/auth.json) for SuperGrok weekly usage. XAI_API_KEY validates inference keys. Prepaid API credits need XAI_MANAGEMENT_KEY and XAI_TEAM_ID." },
        { id:"kilo", name:"Kilo", icon:"straighten", mode:"telemetry", requirement:"API key", envVar:"KILO_API_KEY", note:"Configured-key status; the no-auth models endpoint is only a best-effort probe" },
        { id:"ai21", name:"AI21", icon:"looks_21", mode:"telemetry", requirement:"API key", envVar:"AI21_API_KEY", note:"Configured status; no documented read-only usage API" },
        { id:"perplexity", name:"Perplexity", icon:"auto_awesome", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"cursor", name:"Cursor", icon:"mouse", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"cline", name:"Cline", icon:"code_blocks", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"opencode", name:"OpenCode Go", icon:"open_in_new", mode:"telemetry", requirement:"API key or CLI login", envVar:"OPENCODE_API_KEY", note:"Uses OPENCODE_API_KEY or the credential saved by `opencode auth login` to ~/.local/share/opencode/auth.json. Reads OpenCode Zen's /zen/go/v1/usage for live 5h/weekly/monthly quota; shows when balance fallback is enabled; falls back to /zen/go/v1/models on failure." },
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
        if (index >= 0 && result.length > 1) {
            result.splice(index, 1);
            const nextPillIds = pillIds.filter(function(providerId) { return providerId !== id; });
            if (nextPillIds.length === 0) nextPillIds.push(result[0]);
            pillIds = nextPillIds;
            saveValue("pillProviders", nextPillIds.join(","));
        }
        else if (index < 0) result.push(id);
        selectedIds = result;
        saveValue("providerSelection", result.join(","));
        runHealth();
    }

    function healthFor(id) {
        return providerHealth[id] || { status:"checking", detail:t("settings.health.checking", "Checking…") };
    }

    function healthColor(status) {
        if (status === "ready") return Theme.success;
        if (status === "missing") return Theme.warning;
        if (status === "info") return Theme.primary;
        return Theme.surfaceVariantText;
    }

    // Mirrors the widget's taxonomy: local tooling is tagged so pi (agent
    // analytics) and 9Router (gateway) never read as plain cloud providers.
    // Dual-nature entries (e.g. a future Hermes "agent,provider") render as
    // "Agent · Provider".
    function providerKind(providerId) {
        const kinds = {
            pi: "agent",
            hermes: "agent,provider",
            "9router": "gateway",
            ollama: "local"
        };
        return kinds[String(providerId || "").trim().toLowerCase()] || "";
    }

    function providerKindLabel(providerId) {
        const kinds = providerKind(providerId).split(",").filter(function(kind) { return kind.length > 0; });
        const labels = [];
        for (let i = 0; i < kinds.length; i++) {
            const kind = kinds[i];
            if (kind === "agent") labels.push(t("kind.agent", "Agent"));
            else if (kind === "gateway") labels.push(t("kind.gateway", "Gateway"));
            else if (kind === "local") labels.push(t("kind.local", "Local"));
            else labels.push(t("kind.provider", "Provider"));
        }
        return labels.join(" · ");
    }

    function runHealth() {
        if (!healthScript) return;
        if (healthProcess.running) {
            healthRefreshPending = true;
            return;
        }
        healthRefreshPending = false;
        healthBuffer = "";
        healthProcess.command = ["bash", healthScript, selectedIds.join(",")];
        healthProcess.running = true;
    }

    Component.onCompleted: {
        // 1. Try PluginService (authoritative, case-correct)
        if (pluginService && pluginId) {
            const fromService = pluginService.getPluginPath(pluginId);
            if (fromService && fromService.length > 0) {
                _pluginDir = fromService;
            }
        }
        // 2. Fallback: derive from this file's URL (Qt.resolvedUrl is reliable here)
        if (!_pluginDir) {
            const selfUrl = Qt.resolvedUrl("AiOverviewControlSettings.qml").toString();
            const withoutScheme = selfUrl.startsWith("file://") ? selfUrl.substring(7) : selfUrl;
            const lastSlash = withoutScheme.lastIndexOf("/");
            _pluginDir = lastSlash !== -1 ? withoutScheme.substring(0, lastSlash) : withoutScheme;
        }
        const url = Qt.resolvedUrl("providers/get-provider-health").toString();
        healthScript = url.startsWith("file://") ? url.substring(7) : url;
        const exportUrl = Qt.resolvedUrl("providers/export-usage-history").toString();
        exportScript = exportUrl.startsWith("file://") ? exportUrl.substring(7) : exportUrl;
        runHealth();
    }

    // Manifest reader for the hero version pill; loads once _pluginDir is set.
    FileView {
        id: pluginManifestView
        path: root._pluginDir.length > 0 ? root._pluginDir + "/plugin.json" : ""
        printErrors: false
        // Follow the manifest on disk, so an in-place update shows the new
        // version without a shell restart.
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const manifest = JSON.parse(text());
                if (manifest && manifest.version) {
                    root.pluginVersion = String(manifest.version);
                }
            } catch (error) {
                // Manifest unreadable: the hero simply hides the version pill.
            }
        }
    }

    // Usage-history export. The script prints the file it wrote on stdout and
    // a short reason on stderr, so both outcomes have something to show.
    property int historySnapshotCount: 0
    property int historyLastTrimmed: 0
    Process {
        id: historyStatsProcess
        command: ["bash", decodeURIComponent(Qt.resolvedUrl("providers/get-history-stats").toString().replace("file://", ""))]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.historySnapshotCount = result.count || 0;
                    root.historyLastTrimmed = result.trimmed || 0;
                } catch (error) {}
            }
        }
    }
    Timer {
        interval: 5000
        running: root.visible
        repeat: true
        onTriggered: { if (!historyStatsProcess.running) historyStatsProcess.running = true; }
    }

    property string exportScript: ""
    property string exportBuffer: ""
    property string exportErrorBuffer: ""
    property string exportResultPath: ""
    property string exportErrorText: ""

    function exportHistory(format) {
        if (exportProcess.running || exportScript.length === 0) return;
        exportBuffer = "";
        exportErrorBuffer = "";
        exportResultPath = "";
        exportErrorText = "";
        exportProcess.command = ["bash", exportScript, format];
        exportProcess.running = true;
    }

    Process {
        id: exportProcess
        running: false
        stdout: SplitParser { splitMarker: ""; onRead: data => root.exportBuffer += data }
        stderr: SplitParser { splitMarker: ""; onRead: data => root.exportErrorBuffer += data }
        onExited: code => {
            if (code === 0) {
                root.exportResultPath = root.exportBuffer.trim();
                root.exportErrorText = "";
            } else {
                root.exportResultPath = "";
                const reason = root.exportErrorBuffer.trim();
                root.exportErrorText = reason.length > 0
                    ? reason
                    : t("settings.history_export_failed", "Export failed.");
            }
        }
    }

    Process {
        id: healthProcess
        stdout: SplitParser { splitMarker: ""; onRead: data => root.healthBuffer += data }
        onExited: code => {
            if (code === 0 && root.healthBuffer.length > 0) {
                try {
                    const items = JSON.parse(root.healthBuffer);
                    const map = {};
                    for (let i = 0; i < items.length; i++) map[items[i].provider] = items[i];
                    root.providerHealth = map;
                } catch (error) {
                    const failedMap = {};
                    for (let i = 0; i < root.selectedIds.length; i++) {
                        failedMap[root.selectedIds[i]] = { status:"unknown", detail:t("settings.health.failed", "Check failed") };
                    }
                    root.providerHealth = failedMap;
                }
            } else {
                const failedMap = {};
                for (let i = 0; i < root.selectedIds.length; i++) {
                    failedMap[root.selectedIds[i]] = { status:"unknown", detail:t("settings.health.failed", "Check failed") };
                }
                root.providerHealth = failedMap;
            }
            if (root.healthRefreshPending) Qt.callLater(root.runHealth);
        }
    }

    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius + 4
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.14)
        implicitHeight: hero.implicitHeight + Theme.spacingL * 2
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary, 0.12) }
                GradientStop { position: 0.6; color: Theme.withAlpha(Theme.primary, 0.02) }
            }
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
                    visible: root.showBrand
                    width: 44
                    height: 44
                    radius: width / 2
                    color: Theme.withAlpha(Theme.primary, 0.16)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.28)

                    // Same tinted mascot as the popout and settings window.
                    Image {
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        source: Qt.resolvedUrl("assets/logo.png")
                        sourceSize: Qt.size(60, 60)
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: Theme.primary
                        }
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    Row {
                        visible: root.showBrand
                        spacing: Theme.spacingS

                        StyledText {
                            text: t("app.title", "AI Usage Control")
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            visible: root.pluginVersion.length > 0
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
                                text: "v" + root.pluginVersion
                                font.pixelSize: Theme.fontSizeSmall - 2
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

                HealthChip {
                    visible: root.informationalCount > 0
                    chipIcon: "info"
                    chipLabel: t("settings.health.info_count", "{count} informational", { count: root.informationalCount })
                    chipAccent: Theme.primary
                }
            }
        }
    }

    SectionHeader {
        width: parent.width
        headerTitle: t("settings.section.interface", "Interface")
        headerIcon: "tune"
    }

    ValueDropdown {
        width: parent.width
        text: t("settings.language.label", "Language")
        description: t("settings.language.description", "UI language for this plugin. Auto follows system locale.")
        selected: { root.settingsEpoch; return loadValue("languageOverride", "auto"); }
        values: ["auto", "en_US", "pt_BR", "zh_CN", "es_ES", "de_DE"]
        // Language names stay in their own language so anyone can find theirs.
        labels: [t("settings.option.auto", "Auto"), "English", "Português (Brasil)", "简体中文", "Español", "Deutsch"]
        optionIcons: ["language", "translate", "translate", "translate", "translate", "translate"]
        dropdownWidth: 220
        onPicked: function(value) { saveValue("languageOverride", value); }
    }

    ValueDropdown {
        width: parent.width
        text: t("settings.density.label", "Dashboard density")
        description: t("settings.density.description", "Comfortable keeps full previews. Compact reduces card height and visual detail.")
        selected: { root.settingsEpoch; return loadValue("densityMode", "comfortable"); }
        values: ["comfortable", "compact"]
        labels: [t("settings.option.comfortable", "Comfortable"), t("settings.option.compact", "Compact")]
        optionIcons: ["view_agenda", "density_small"]
        dropdownWidth: 220
        onPicked: function(value) { saveValue("densityMode", value); }
    }

    ValueDropdown {
        id: pillModeDropdown
        width: parent.width
        text: t("settings.pill_mode.label", "Pill mode")
        description: t("settings.pill_mode.description", "Auto shows providers with measurable usage. Custom uses the list below.")
        selected: { root.settingsEpoch; return loadValue("pillMode", "auto"); }
        values: ["auto", "custom", "top"]
        labels: [t("settings.option.auto", "Auto"), t("settings.option.custom", "Custom"), t("settings.option.top", "Top usage")]
        optionIcons: ["auto_awesome", "tune", "trending_up"]
        dropdownWidth: 180
        onPicked: function(value) { saveValue("pillMode", value); }
    }

    StyledRect {
        visible: pillModeDropdown.selected === "custom"
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.18)
        implicitHeight: pillProviderColumn.implicitHeight + Theme.spacingM * 2

        Column {
            id: pillProviderColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                text: t("settings.pill_providers.label", "Providers shown in DankBar")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
            }

            StyledText {
                width: parent.width
                text: t("settings.pill_providers.description", "Choose a compact subset of tracked providers. This only changes the DankBar pill; tracking and dashboard cards remain unchanged.")
                wrapMode: Text.WordWrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.allProviders.filter(function(provider) { return root.isSelected(provider.id); })

                    Rectangle {
                        id: pillProviderChip
                        required property var modelData
                        readonly property bool active: root.isPillSelected(modelData.id)
                        width: pillProviderRow.implicitWidth + Theme.spacingM * 2
                        height: 36
                        radius: 18
                        color: active
                            ? Theme.withAlpha(Theme.primary, 0.17)
                            : Theme.withAlpha(Theme.surfaceVariantText, pillProviderMouse.containsMouse ? 0.13 : 0.07)
                        border.width: active ? 1 : 0
                        border.color: Theme.withAlpha(Theme.primary, 0.48)
                        activeFocusOnTab: true
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: modelData.name
                        Accessible.checked: active
                        Keys.onReturnPressed: root.togglePillProvider(modelData.id)
                        Keys.onSpacePressed: root.togglePillProvider(modelData.id)

                        Row {
                            id: pillProviderRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            ProviderLogo {
                                providerId: pillProviderChip.modelData.id
                                logoSize: 16
                                tintColor: root.providerLogoColor
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: pillProviderChip.modelData.name
                                color: pillProviderChip.active ? Theme.primary : Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: pillProviderChip.active ? Font.Medium : Font.Normal
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            DankIcon {
                                visible: pillProviderChip.active
                                name: "check"
                                size: 13
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: pillProviderMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.togglePillProvider(pillProviderChip.modelData.id)
                        }
                    }
                }
            }
        }
    }

    DankToggle {
        // DankToggle insets its text by spacingM; bleed out to align with the other rows.
        x: -Theme.spacingM
        width: parent.width + Theme.spacingM * 2
        text: t("settings.pill_tooltip", "DankBar pill tooltip")
        description: t("settings.pill_tooltip_desc", "Hovering the bar pill spells out the provider, which quota window the percentage came from, and when it resets.")
        checked: { root.settingsEpoch; return loadValue("pillTooltip", "true") === "true"; }
        onToggled: function(checked) { saveValue("pillTooltip", checked ? "true" : "false"); }
    }

    // Pill footprint controls (issue #33): logo + percentage only, and a
    // tighter gap around the separator dot for crowded bars.
    DankToggle {
        x: -Theme.spacingM
        width: parent.width + Theme.spacingM * 2
        text: t("settings.pill_show_names", "Provider names in pill")
        description: t("settings.pill_show_names_desc", "Turn off to keep only each provider's logo and percentage. The tooltip still names them.")
        checked: { root.settingsEpoch; return loadValue("pillShowNames", "true") === "true"; }
        onToggled: function(checked) { saveValue("pillShowNames", checked ? "true" : "false"); }
    }

    DankToggle {
        x: -Theme.spacingM
        width: parent.width + Theme.spacingM * 2
        text: t("settings.pill_compact", "Compact pill spacing")
        description: t("settings.pill_compact_desc", "Tightens the gap around the dot between providers and inside each entry.")
        checked: { root.settingsEpoch; return loadValue("pillCompact", "false") === "true"; }
        onToggled: function(checked) { saveValue("pillCompact", checked ? "true" : "false"); }
    }

    // Per-provider DankBar window selection (issue #17). The tracked-provider
    // list is never empty (normalizeProviderSelection guarantees one entry),
    // so the block is always rendered.
    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.18)
        implicitHeight: barWindowColumn.implicitHeight + Theme.spacingM * 2

        Column {
            id: barWindowColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                text: t("settings.bar_window.label", "DankBar usage window")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
            }

            StyledText {
                width: parent.width
                text: t("settings.bar_window.description", "Providers with more than one quota window (e.g. Claude's 5 hour and 7 day) always show the primary window in the DankBar. Choose a different window per provider — the dashboard keeps showing every window. \"Highest\" follows the most-constrained window; providers without the chosen window fall back to the primary.")
                wrapMode: Text.WordWrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: root.selectedIds

                ValueDropdown {
                    required property string modelData
                    width: parent.width
                    text: root.providerDisplayName(modelData)
                    selected: { root.settingsEpoch; return root.barChoiceFor(modelData); }
                    values: ["primary", "secondary", "tertiary", "highest"]
                    labels: [t("settings.option.primary", "Primary"), t("settings.option.secondary", "Secondary"), t("settings.option.tertiary", "Tertiary"), t("settings.option.highest", "Highest")]
                    optionIcons: ["looks_one", "looks_two", "looks_3", "trending_up"]
                    dropdownWidth: 200
                    onPicked: function(value) { root.setBarChoice(modelData, value); }
                }
            }
        }
    }

    ValueDropdown {
        width: parent.width
        text: t("settings.refresh_interval", "Refresh interval")
        description: t("settings.refresh_description", "How often the plugin queries selected local adapters and provider APIs.")
        selected: { root.settingsEpoch; return loadValue("refreshInterval", "120000"); }
        values: ["60000", "120000", "300000", "900000", "1800000"]
        labels: [1, 2, 5, 15, 30].map(n => t("settings.option.minutes", "{count} min", { count: n }))
        optionIcons: ["timer", "timer", "timer_off", "timer_off", "timer_off"]
        dropdownWidth: 200
        onPicked: function(value) { saveValue("refreshInterval", value); }
    }

    DankToggle {
        // DankToggle insets its text by spacingM; bleed out to align with the other rows.
        x: -Theme.spacingM
        width: parent.width + Theme.spacingM * 2
        text: t("settings.show_errors", "Show providers with errors")
        description: t("settings.show_errors_desc", "Keep authentication and configuration failures visible in the dashboard.")
        checked: { root.settingsEpoch; return loadValue("showErrorProviders", "true") === "true"; }
        onToggled: function(checked) { saveValue("showErrorProviders", checked ? "true" : "false"); }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            width: parent.width
            text: t("settings.logo_color", "Provider logo color")
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
        }

        StyledText {
            width: parent.width
            text: t("settings.logo_color_desc", "One monochrome color for every provider logo in the dashboard and desktop notifications.")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall - 1
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            height: 46
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingM

                Rectangle {
                    width: 28
                    height: 28
                    radius: width / 2
                    color: root.providerLogoColor
                    border.color: Theme.outline
                    border.width: 1
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.providerLogoColor.toString()
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item { width: 1; height: 1; Layout.fillWidth: true }

                DankIcon {
                    name: "edit"
                    size: Theme.iconSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StateLayer {
                stateColor: Theme.surfaceText
                onClicked: root.openProviderLogoColorPicker()
            }
        }
    }

    ValueDropdown {
        width: parent.width
        text: t("settings.cost_currency", "Estimated cost currency")
        description: t("settings.cost_currency_desc", "Convert USD analytics for display using daily exchange rates. Balances and stored amounts stay unchanged; unavailable rates fall back to USD.")
        selected: { root.settingsEpoch; return loadValue("costCurrency", "USD"); }
        values: ["USD", "EUR", "BRL", "GBP", "CAD", "CNY", "JPY", "AUD", "CHF"]
        labels: values
        onPicked: function(value) { saveValue("costCurrency", value); }
    }

    DankToggle {
        // DankToggle insets its text by spacingM; bleed out to align with the other rows.
        x: -Theme.spacingM
        width: parent.width + Theme.spacingM * 2
        text: t("settings.show_projects", "Show Claude projects")
        description: t("settings.show_projects_desc", "List the week's top projects inside the Claude card.")
        checked: { root.settingsEpoch; return loadValue("showClaudeProjects", "true") === "true"; }
        onToggled: function(checked) { saveValue("showClaudeProjects", checked ? "true" : "false"); }
    }

    DankToggle {
        // DankToggle insets its text by spacingM; bleed out to align with the other rows.
        x: -Theme.spacingM
        width: parent.width + Theme.spacingM * 2
        text: t("settings.antigravity_model_details", "Show individual Antigravity models")
        description: t("settings.antigravity_model_details_desc", "By default Antigravity shows the same Gemini and Claude/OpenAI quota families as its Models screen. Enable this only for per-model troubleshooting.")
        checked: { root.settingsEpoch; return loadValue("showAntigravityModelDetails", "false") === "true"; }
        onToggled: function(checked) { saveValue("showAntigravityModelDetails", checked ? "true" : "false"); }
    }

    DankToggle {
        id: notifyToggle
        // DankToggle insets its text by spacingM; bleed out to align with the other rows.
        x: -Theme.spacingM
        width: parent.width + Theme.spacingM * 2
        text: t("settings.notify.label", "Quota notifications")
        description: t("settings.notify.description", "Alert once when a provider crosses the threshold, then update the same notification if its quota is exhausted.")
        checked: { root.settingsEpoch; return loadValue("quotaNotifications", "true") === "true"; }
        onToggled: function(checked) { saveValue("quotaNotifications", checked ? "true" : "false"); }
    }

    ValueDropdown {
        visible: notifyToggle.checked
        width: parent.width
        text: t("settings.notify.threshold", "Notification threshold")
        description: t("settings.notify.threshold_desc", "Usage percent that triggers a notification.")
        selected: { root.settingsEpoch; return loadValue("notifyThreshold", "85"); }
        values: ["75", "85", "95"]
        labels: ["75%", "85%", "95%"]
        optionIcons: ["notifications", "notifications_active", "notification_important"]
        dropdownWidth: 160
        onPicked: function(value) { saveValue("notifyThreshold", value); }
    }

    ValueDropdown {
        visible: notifyToggle.checked
        width: parent.width
        text: t("settings.notify.window_scope", "Windows that raise alerts")
        description: t("settings.notify.window_scope_desc", "“displayed” alerts on whatever window the DankBar shows for each provider — identical to “primary” until you override a provider above. “all” also alerts on Claude's 7 day, Codex's weekly, and every other secondary window.")
        selected: { root.settingsEpoch; return loadValue("notifyWindowScope", "displayed"); }
        values: ["displayed", "all", "primary"]
        labels: [t("settings.option.displayed", "Displayed"), t("settings.option.all", "All windows"), t("settings.option.primary", "Primary")]
        optionIcons: ["align_horizontal_left", "select_all", "looks_one"]
        dropdownWidth: 200
        onPicked: function(value) { saveValue("notifyWindowScope", value); }
    }

    ValueDropdown {
        visible: notifyToggle.checked
        width: parent.width
        text: t("settings.notify.cooldown", "Re-alert interval")
        description: t("settings.notify.cooldown_desc", "0 alerts once per quota window. Other values update the same notification after that many minutes while usage stays high.")
        selected: { root.settingsEpoch; return loadValue("notifyCooldownMinutes", "0"); }
        values: ["0", "60", "360", "1440"]
        labels: [t("settings.option.once", "Once per window")].concat([1, 6, 24].map(n => t("settings.option.hours", "{count} h", { count: n })))
        optionIcons: ["notifications_off", "schedule", "schedule", "schedule"]
        dropdownWidth: 160
        onPicked: function(value) { saveValue("notifyCooldownMinutes", value); }
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
            id: thresholdOverridesField
            width: parent.width
            placeholderText: "claude:90,codex:75"
            text: { root.settingsEpoch; return loadValue("notifyThresholds", ""); }
            onEditingFinished: saveValue("notifyThresholds", text.trim())
        }

        // Live — bound to the field rather than to the saved value, so a typo
        // is flagged while typing instead of after the entry is dropped.
        Repeater {
            model: root.notifyThresholdIssues(thresholdOverridesField.text)

            Row {
                required property string modelData
                width: parent.width
                spacing: Theme.spacingXS

                DankIcon {
                    name: "error_outline"
                    size: 14
                    color: Theme.error
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    width: parent.width - 14 - Theme.spacingXS
                    text: parent.modelData
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall - 1
                }
            }
        }
    }

    ValueDropdown {
        width: parent.width
        text: t("settings.history_retention", "Usage history retention")
        description: t("settings.history_retention_desc", "Snapshots kept per trim of the local usage history (sparklines and trends).") + "\n" + t("settings.history_count", "{count} snapshots stored · last trim removed {trimmed}", { count: root.historySnapshotCount, trimmed: root.historyLastTrimmed })
        selected: { root.settingsEpoch; return loadValue("historyRetention", "2000"); }
        values: ["500", "2000", "10000"]
        labels: [500, 2000, 10000].map(n => t("settings.option.snapshots", "{count} snapshots", { count: n.toLocaleString(Qt.locale(root.i18nLocale), "f", 0) }))
        optionIcons: ["history", "history", "history"]
        dropdownWidth: 160
        onPicked: function(value) { saveValue("historyRetention", value); }
    }

    // Usage history export. The store is an append-only JSONL cache the plugin
    // trims on its own, so a copy is the only way to keep long-term data.
    StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.18)
        implicitHeight: exportColumn.implicitHeight + Theme.spacingM * 2

        Column {
            id: exportColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                text: t("settings.history_export", "Export usage history")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
            }

            StyledText {
                width: parent.width
                text: t("settings.history_export_desc", "Writes every recorded snapshot to your downloads folder. CSV opens in a spreadsheet; JSONL is the raw store.")
                wrapMode: Text.WordWrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                spacing: Theme.spacingS

                DankButton {
                    text: "CSV"
                    iconName: "table_view"
                    enabled: !exportProcess.running
                    onClicked: root.exportHistory("csv")
                }

                DankButton {
                    text: "JSONL"
                    iconName: "data_object"
                    backgroundColor: Theme.surfaceContainerHighest
                    textColor: Theme.surfaceText
                    enabled: !exportProcess.running
                    onClicked: root.exportHistory("jsonl")
                }
            }

            StyledText {
                width: parent.width
                visible: root.exportResultPath.length > 0
                text: t("settings.history_export_done", "Saved to {path}", { path: root.exportResultPath })
                wrapMode: Text.WrapAnywhere
                color: Theme.success
                font.pixelSize: Theme.fontSizeSmall - 1
            }

            StyledText {
                width: parent.width
                visible: root.exportErrorText.length > 0
                text: root.exportErrorText
                wrapMode: Text.WordWrap
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall - 1
            }
        }
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
                text: { root.settingsEpoch; return loadValue("providerSelection", "codex,claude,copilot"); }
                placeholderText: "codex,claude,copilot,openrouter"
                onEditingFinished: {
                    const normalized = root.normalizeProviderSelection(text);
                    root.selectedIds = normalized;
                    const nextPillIds = root.pillIds.filter(function(providerId) {
                        return normalized.indexOf(providerId) >= 0;
                    });
                    if (nextPillIds.length === 0) nextPillIds.push(normalized[0]);
                    root.pillIds = nextPillIds;
                    root.saveValue("providerSelection", normalized.join(","));
                    root.saveValue("pillProviders", nextPillIds.join(","));
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
                    { label:t("settings.test_backend", "Test selected providers"), cmd:root._pluginDir + "/providers/get-provider-usage \"" + root.selectedIds.join(",") + "\" " + root._pluginDir + "/providers/get-copilot-usage | jq ." },
                    { label:t("settings.test_codex", "Test Codex app-server adapter"), cmd:root._pluginDir + "/providers/get-codex-usage | jq ." },
                    { label:t("settings.test_pi", "Test pi session analytics adapter"), cmd:root._pluginDir + "/providers/get-pi-analytics | jq ." },
                    { label:t("settings.test_hermes", "Test Hermes telemetry adapter"), cmd:root._pluginDir + "/providers/get-hermes-analytics | jq ." },
                    { label:t("settings.test_health", "Check provider prerequisites"), cmd:root._pluginDir + "/providers/get-provider-health \"" + root.selectedIds.join(",") + "\" | jq ." },
                    { label:t("settings.test_export", "Export usage history to CSV"), cmd:root._pluginDir + "/providers/export-usage-history csv" },
                    { label:t("settings.test_deps", "Check core dependencies"), cmd:"command -v bash jq curl codex claude pi gh gcloud ollama" },
                    { label:t("settings.test_qml", "Validate QML"), cmd:"qmllint " + root._pluginDir + "/AiOverviewControlWidget.qml " + root._pluginDir + "/AiOverviewControlSettings.qml" }
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

    // Reset-to-defaults. Two-step rather than modal: PluginSettings has no
    // confirmation dialog of its own, and this wipes provider selection,
    // pins, thresholds, and bar overrides in one click.
    StyledRect {
        id: resetCard
        property bool armed: false

        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.error, resetCard.armed ? 0.1 : 0.05)
        border.width: 1
        border.color: Theme.withAlpha(Theme.error, resetCard.armed ? 0.36 : 0.16)
        implicitHeight: resetColumn.implicitHeight + Theme.spacingM * 2

        Timer {
            id: resetDisarm
            interval: 5000
            onTriggered: resetCard.armed = false
        }

        Column {
            id: resetColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                text: t("settings.reset", "Reset plugin settings")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
            }

            StyledText {
                width: parent.width
                text: resetCard.armed
                    ? t("settings.reset_confirm_desc", "This restores every option on this page, including tracked providers, pins, notification thresholds, and DankBar overrides. Recorded usage history is kept.")
                    : t("settings.reset_desc", "Restore every option on this page to its default. Recorded usage history is kept.")
                wrapMode: Text.WordWrap
                color: resetCard.armed ? Theme.error : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                spacing: Theme.spacingS

                DankButton {
                    text: resetCard.armed
                        ? t("settings.reset_confirm", "Confirm reset")
                        : t("settings.reset_action", "Reset to defaults")
                    iconName: resetCard.armed ? "restart_alt" : "settings_backup_restore"
                    backgroundColor: resetCard.armed ? Theme.error : Theme.surfaceContainerHighest
                    textColor: resetCard.armed ? Theme.background : Theme.surfaceText
                    onClicked: {
                        if (!resetCard.armed) {
                            resetCard.armed = true;
                            resetDisarm.restart();
                            return;
                        }
                        resetDisarm.stop();
                        resetCard.armed = false;
                        root.resetToDefaults();
                    }
                }

                DankButton {
                    visible: resetCard.armed
                    text: t("settings.reset_cancel", "Cancel")
                    backgroundColor: Theme.surfaceContainerHighest
                    textColor: Theme.surfaceText
                    onClicked: {
                        resetDisarm.stop();
                        resetCard.armed = false;
                    }
                }
            }
        }
    }

    // DankDropdown shows its raw option strings, so stored values ("compact",
    // "primary", "120000") would leak into the UI untranslated. This keeps the
    // stored value and the translated label apart: `values` are persisted,
    // `labels` are what the user reads.
    component ValueDropdown: DankDropdown {
        id: valueDropdown
        property var values: []
        property var labels: []
        property string selected: ""
        signal picked(string value)

        options: labels
        currentValue: {
            const i = values.indexOf(selected);
            return i >= 0 && i < labels.length ? labels[i] : selected;
        }
        onValueChanged: function(label) {
            const i = labels.indexOf(label);
            const picked = i >= 0 ? values[i] : label;
            valueDropdown.selected = picked;
            valueDropdown.picked(picked);
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

        // Uniform grid: every provider gets the same cell, so the list scans
        // in columns instead of a ragged run of different-width pills.
        Grid {
            id: providerGrid
            width: parent.width
            columns: Math.max(2, Math.floor((width + spacing) / (168 + spacing)))
            spacing: Theme.spacingS
            readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

            Repeater {
                model: providerSection.providers
                delegate: Rectangle {
                    id: providerChip
                    required property var modelData
                    readonly property bool active: root.isSelected(modelData.id)
                    readonly property var health: root.healthFor(modelData.id)
                    width: providerGrid.cellWidth
                    height: 44
                    radius: Theme.cornerRadius
                    color: active ? Theme.withAlpha(Theme.primary, chipMouse.containsMouse ? 0.22 : 0.15) : (chipMouse.containsMouse ? Theme.withAlpha(Theme.surfaceVariantText, 0.13) : Theme.withAlpha(Theme.surfaceVariantText, 0.06))
                    border.width: 1
                    border.color: active ? Theme.withAlpha(Theme.primary, activeFocus ? 0.9 : 0.4) : Theme.withAlpha(Theme.surfaceText, activeFocus ? 0.5 : 0.06)
                    scale: chipMouse.pressed ? 0.97 : 1.0
                    activeFocusOnTab: true

                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: modelData.name
                    Accessible.checked: active
                    Keys.onReturnPressed: root.toggleProvider(modelData.id)
                    Keys.onSpacePressed: root.toggleProvider(modelData.id)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: Theme.withAlpha(providerChip.active ? Theme.primary : Theme.surfaceText, providerChip.active ? 0.16 : 0.06)

                            ProviderLogo {
                                anchors.centerIn: parent
                                providerId: providerChip.modelData.id
                                logoSize: 16
                                tintColor: providerChip.active ? root.providerLogoColor : Theme.surfaceVariantText
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: providerChip.modelData.name
                                color: providerChip.active ? Theme.surfaceText : Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: providerChip.active ? Font.DemiBold : Font.Normal
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.providerKind(providerChip.modelData.id).length > 0
                                text: root.providerKindLabel(providerChip.modelData.id)
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall - 3
                                font.weight: Font.DemiBold
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }

                        // Selected: health-coloured check; otherwise an empty ring.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 18
                            height: 18
                            radius: 9
                            color: providerChip.active ? root.healthColor(providerChip.health.status) : "transparent"
                            border.width: providerChip.active ? 0 : 1.5
                            border.color: Theme.withAlpha(Theme.surfaceText, chipMouse.containsMouse ? 0.4 : 0.2)
                            Behavior on color { ColorAnimation { duration: 160 } }

                            DankIcon {
                                anchors.centerIn: parent
                                visible: providerChip.active
                                name: "check"
                                size: 13
                                color: Theme.surfaceContainer
                            }
                        }
                    }

                    MouseArea { id:chipMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:root.toggleProvider(providerChip.modelData.id) }
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
                    readonly property color healthColor: root.healthColor(health.status)
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

                            ProviderLogo {
                                anchors.centerIn: parent
                                providerId: providerDetailRow.modelData.id
                                logoSize: 16
                                tintColor: root.providerLogoColor
                            }
                        }

                        StyledText { Layout.preferredWidth:100; text:modelData.name; color:Theme.surfaceText; font.pixelSize:Theme.fontSizeSmall; font.weight:Font.Medium; elide:Text.ElideRight }
                        StyledText { Layout.fillWidth:true; text:root.t("provider.note." + modelData.id, modelData.note); wrapMode:Text.WordWrap; color:Theme.surfaceVariantText; font.pixelSize:Theme.fontSizeSmall - 1 }

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
