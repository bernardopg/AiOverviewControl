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
    property string focusedProviderId: ""
    property string pendingProviderId: availableProviderOptions[0] || "codex"
    property string claudeRawBuffer: ""
    property string claudeSubscriptionType: ""
    property string claudeRateLimitTier: ""
    property real claudeFiveHourUtil: 0
    property string claudeFiveHourReset: ""
    property real claudeSevenDayUtil: 0
    property string claudeSevenDayReset: ""
    property int claudeWeekMessages: 0
    property int claudeWeekSessions: 0
    property real claudeWeekTokens: 0
    property real claudeMonthTokens: 0
    property int claudeAlltimeSessions: 0
    property int claudeAlltimeMessages: 0
    property string claudeFirstSession: ""
    property real claudeTodayCost: 0
    property real claudeWeekCost: 0
    property real claudeMonthCost: 0
    property var claudeDailyTokens: [0, 0, 0, 0, 0, 0, 0]
    property var claudeDailyCosts: [0, 0, 0, 0, 0, 0, 0]
    property var dayLabels: [Qt.locale(root.i18nLocale).dayName(1, Locale.ShortFormat), Qt.locale(root.i18nLocale).dayName(2, Locale.ShortFormat), Qt.locale(root.i18nLocale).dayName(3, Locale.ShortFormat), Qt.locale(root.i18nLocale).dayName(4, Locale.ShortFormat), Qt.locale(root.i18nLocale).dayName(5, Locale.ShortFormat), Qt.locale(root.i18nLocale).dayName(6, Locale.ShortFormat), Qt.locale(root.i18nLocale).dayName(0, Locale.ShortFormat)]
    readonly property int currentWeekdayIndex: (new Date().getDay() + 6) % 7
    readonly property string i18nLocale: AiOverviewControlI18n.normalizedLocale

    function t(key, fallback, params) {
        root.i18nLocale;
        return AiOverviewControlI18n.tr(key, fallback, params);
    }

    property int refreshIntervalMs: {
        const val = pluginData.refreshInterval;
        const parsed = val ? parseInt(val) : 120000;
        return Number.isFinite(parsed) ? parsed : 120000;
    }
    property string codexbarPath: (pluginData.codexbarPath || "").trim()
    property string sourceMode: pluginData.sourceMode || "cli"
    readonly property string _pluginDir: (pluginService ? pluginService.getPluginPath(pluginId) : "") || (PluginService.pluginDirectory + "/aiOverviewControl")
    property string providerUsageScript: _pluginDir + "/providers/get-provider-usage"
    property string claudeUsageScript: _pluginDir + "/providers/get-claude-usage"
    property string copilotUsageScript: _pluginDir + "/providers/get-copilot-usage"
    readonly property var availableProviderOptions: [
        "codex",
        "claude",
        "copilot",
        "gemini",
        "9router",
        "openrouter",
        "deepseek",
        "kimi",
        "mistral",
        "glm",
        "minimax",
        "qwen",
        "nvidia",
        "cloudflare",
        "vertexai",
        "byteplus",
        "ollama",
        "perplexity",
        "cursor",
        "cline",
        "opencode",
        "kilo",
        "kiro",
        "warp",
        "amp"
    ]

    ListModel {
        id: claudeModelList
    }

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

    readonly property var displayProviders: {
        if (showErrorProviders) {
            return providers;
        }
        const result = [];
        for (let i = 0; i < providers.length; i++) {
            const provider = providers[i];
            if (provider && !provider.error) {
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
                label: tertiaryWindow.resetDescription || t("window.tertiary", "Tertiary"),
                data: tertiaryWindow
            });
        }
        return windows;
    }

    readonly property string statusTitle: {
        if (isLoading && !hasProviderData) {
            return t("status.syncing", "Syncing usage");
        }
        if (hasError) {
            return t("status.needs_attention", "Needs attention");
        }
        if (!hasProviderData) {
            return t("status.waiting", "Waiting for data");
        }
        return t("status.online", "AI telemetry online");
    }

    readonly property string statusSubtitle: {
        if (isLoading && !hasProviderData) {
            return t("status.fetching", "Fetching usage windows from local provider helpers.");
        }
        if (hasError) {
            return errorMessage;
        }
        if (!hasProviderData) {
            return t("status.no_data_hint", "Run your configured AI CLIs and refresh to populate usage windows.");
        }
        const resetLabel = primaryWindow ? formatTimeUntil(primaryWindow.resetsAt) : "";
        if (!resetLabel) {
            return t("status.windows_available", "Provider windows are available.");
        }
        return t("status.primary_resets", "Primary window resets in {time}.", { time: resetLabel });
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

    readonly property string resolvedPath: binaryReady ? resolvedBinaryPath : ""
    readonly property string providerEngineLabel: {
        if (!binaryReady) return "offline";
        if (resolvedBinaryPath.length > 0) return `local + ${resolvedBinaryPath.split("/").pop()}`;
        return t("status.local_helpers", "local helpers");
    }

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
            return t("window.session", "Session");
        }
        if (windowMinutes <= 10080) {
            return t("window.weekly", "Weekly");
        }
        if (windowMinutes <= 43200) {
            return t("window.monthly", "Monthly");
        }
        return `${Math.floor(windowMinutes / 1440)}d`;
    }

    function formatTimeUntil(isoDate) {
        if (!isoDate) {
            return "";
        }
        const diff = new Date(isoDate).getTime() - Date.now();
        if (diff <= 0) {
            return t("time.now", "now");
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
        if (windowData.displayValue && String(windowData.displayValue).length > 0) {
            return String(windowData.displayValue);
        }
        const percent = Math.round(Number(windowData.usedPercent || 0));
        const reset = formatTimeUntil(windowData.resetsAt);
        return reset.length > 0 ? `${percent}% · ${reset}` : `${percent}%`;
    }

    function formatUsageError(exitCode) {
        if (rawStderrBuffer.length > 0) {
            return rawStderrBuffer.trim();
        }
        if (sourceMode === "api") return t("error.api_mode", "API mode needs provider API tokens or native provider keys.");
        if (sourceMode === "oauth") return t("error.oauth_mode", "OAuth mode requires provider authentication supported by the selected provider.");
        if (sourceMode === "web") return t("error.web_mode", "Web mode depends on the optional fallback provider implementation.");
        return t("error.helper_exit", "provider helper exited with code {code}", { code: exitCode });
    }

    function providerName(providerId) {
        const names = {
            codex: "Codex",
            claude: "Claude",
            copilot: "Copilot",
            cursor: "Cursor",
            gemini: "Gemini",
            openrouter: "OpenRouter",
            "9router": "9Router",
            deepseek: "DeepSeek",
            kimi: "Kimi",
            moonshot: "Kimi",
            mistral: "Mistral",
            glm: "GLM",
            zhipu: "GLM",
            minimax: "MiniMax",
            qwen: "Qwen",
            dashscope: "Qwen",
            alibaba: "Qwen",
            nvidia: "NVIDIA NIM",
            nim: "NVIDIA NIM",
            cloudflare: "Cloudflare AI",
            vertexai: "Vertex AI",
            vertex: "Vertex AI",
            byteplus: "BytePlus Ark",
            ark: "BytePlus Ark",
            modelark: "BytePlus Ark",
            ollama: "Ollama",
            perplexity: "Perplexity",
            cline: "Cline",
            opencode: "OpenCode",
            kilo: "Kilo",
            kiro: "Kiro",
            amp: "Amp",
            warp: "Warp"
        };
        return names[providerId] || capitalizeFirst(providerId || "provider");
    }

    function normalizeProviderId(providerId) {
        return String(providerId || "").trim().toLowerCase();
    }

    function providersCsv(list) {
        const result = [];
        for (let i = 0; i < list.length; i++) {
            const provider = normalizeProviderId(list[i]);
            if (provider.length > 0 && result.indexOf(provider) < 0) {
                result.push(provider);
            }
        }
        return result.join(",");
    }

    function saveProviderSelection(csv) {
        const normalized = providersCsv(csv.split(","));
        if (normalized.length === 0) return;
        providerSelection = normalized;
        providers = [];
        PluginService.savePluginData("aiOverviewControl", "providerSelection", normalized);
        if (procUsage.running) {
            procUsage.running = false;
        }
        usageDidTimeout = false;
        timedOutRequestId = -1;
        refresh();
    }

    function addProvider(providerId) {
        const provider = normalizeProviderId(providerId);
        if (provider.length === 0) return;
        const next = selectedProviders.slice();
        if (next.indexOf(provider) < 0) {
            next.push(provider);
            saveProviderSelection(next.join(","));
            focusedProviderId = provider;
        }
    }

    function removeProvider(providerId) {
        const provider = normalizeProviderId(providerId);
        const next = [];
        for (let i = 0; i < selectedProviders.length; i++) {
            if (selectedProviders[i] !== provider) {
                next.push(selectedProviders[i]);
            }
        }
        if (next.length === 0) {
            next.push(availableProviderOptions[0] || "codex");
        }
        if (focusedProviderId === provider) {
            focusedProviderId = "";
        }
        saveProviderSelection(next.join(","));
    }

    function providerPercent(provider) {
        const windowData = primaryUsageWindow(provider);
        if (!windowData) {
            return 0;
        }
        return Number(windowData.usedPercent || 0);
    }

    function providerStatus(provider) {
        if (!provider) return "missing";
        if (provider.error) return "error";
        if (provider.usage) return "active";
        return "empty";
    }

    function providerStatusLabel(provider) {
        const status = root.providerStatus(provider);
        if (status === "error") return t("status.error", "Error");
        if (status === "active") return t("status.online", "Live");
        if (status === "empty") return t("status.waiting", "Waiting");
        return t("status.none", "(none)");
    }

    function providerSourceLabel(provider) {
        const source = provider && provider.source ? String(provider.source) : String(root.sourceMode || "cli");
        return source.length > 0 ? source : "cli";
    }

    function providerErrorText(provider) {
        if (!provider || !provider.error) {
            return "";
        }
        const rawMessage = provider.error.message || provider.error.kind || "Provider returned an error.";
        if (String(rawMessage).charAt(0) === "[") {
            try {
                const firstLine = String(rawMessage).split("\n")[0];
                const parsed = JSON.parse(firstLine);
                const list = Array.isArray(parsed) ? parsed : [parsed];
                for (let i = 0; i < list.length; i++) {
                    if (list[i] && list[i].provider === provider.provider && list[i].error) {
                        return list[i].error.message || list[i].error.kind || rawMessage;
                    }
                }
                if (list[0] && list[0].error) {
                    return list[0].error.message || list[0].error.kind || rawMessage;
                }
            } catch (error) {
                return rawMessage;
            }
        }
        return rawMessage;
    }

    function providerAccount(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage) return "—";
        if (usage.identity && usage.identity.accountEmail) return usage.identity.accountEmail;
        return usage.accountEmail || "—";
    }

    function providerLogin(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage) return "—";
        if (usage.identity && usage.identity.loginMethod) return usage.identity.loginMethod;
        return usage.loginMethod || "—";
    }

    function providerCredits(provider) {
        if (!provider || !provider.credits) return "—";
        return String(provider.credits.remaining ?? "—");
    }

    function compactPath(value) {
        const text = String(value || "");
        if (text.length === 0) return "none";
        const parts = text.split("/");
        if (parts.length <= 2) return text;
        return `…/${parts.slice(-2).join("/")}`;
    }

    function iconForProvider(providerId) {
        if (providerId === "codex") return "data_object";
        if (providerId === "claude") return "psychology";
        if (providerId === "copilot") return "hub";
        if (providerId === "gemini") return "auto_awesome";
        if (providerId === "openrouter") return "route";
        if (providerId === "9router") return "share";
        if (providerId === "deepseek") return "tsunami";
        if (providerId === "kimi" || providerId === "moonshot") return "dark_mode";
        if (providerId === "mistral") return "air";
        if (providerId === "glm" || providerId === "zhipu") return "bubble_chart";
        if (providerId === "minimax") return "grid_view";
        if (providerId === "qwen" || providerId === "dashscope" || providerId === "alibaba") return "cloud";
        if (providerId === "nvidia" || providerId === "nim") return "memory";
        if (providerId === "cloudflare") return "shield";
        if (providerId === "vertexai" || providerId === "vertex") return "hexagon";
        if (providerId === "byteplus" || providerId === "ark" || providerId === "modelark") return "bolt";
        if (providerId === "perplexity") return "travel_explore";
        if (providerId === "cursor") return "ads_click";
        if (providerId === "ollama") return "dns";
        if (providerId === "cline") return "terminal";
        if (providerId === "opencode") return "code";
        if (providerId === "warp") return "rocket_launch";
        if (providerId === "amp") return "electric_bolt";
        if (providerId === "kilo") return "speed";
        if (providerId === "kiro") return "tune";
        return "monitoring";
    }

    function providerAccent(providerId) {
        if (providerId === "claude") return Theme.warning;
        if (providerId === "codex") return Theme.success;
        if (providerId === "copilot") return Theme.primary;
        if (providerId === "gemini") return Theme.secondary;
        if (providerId === "openrouter") return Theme.primary;
        if (providerId === "9router") return Theme.secondary;
        if (providerId === "deepseek") return Theme.primary;
        if (providerId === "kimi" || providerId === "moonshot") return Theme.secondary;
        if (providerId === "mistral") return Theme.warning;
        if (providerId === "glm" || providerId === "zhipu") return Theme.primary;
        if (providerId === "minimax") return Theme.success;
        if (providerId === "qwen" || providerId === "dashscope" || providerId === "alibaba") return Theme.warning;
        if (providerId === "nvidia" || providerId === "nim") return Theme.success;
        if (providerId === "cloudflare") return Theme.warning;
        if (providerId === "vertexai" || providerId === "vertex") return Theme.primary;
        if (providerId === "byteplus" || providerId === "ark" || providerId === "modelark") return Theme.secondary;
        return Theme.secondary;
    }

    function windowsForProvider(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage) return [];
        const windows = [];
        if (usage.primary) windows.push({ key: "primary", label: usage.primary.resetDescription || getWindowLabel(usage.primary.windowMinutes), data: usage.primary });
        if (usage.secondary) windows.push({ key: "secondary", label: usage.secondary.resetDescription || getWindowLabel(usage.secondary.windowMinutes), data: usage.secondary });
        if (usage.tertiary) windows.push({ key: "tertiary", label: usage.tertiary.resetDescription || t("window.tertiary", "Tertiary"), data: usage.tertiary });
        return windows;
    }

    function primaryUsageWindow(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage) return null;
        return usage.primary || usage.secondary || usage.tertiary || null;
    }

    function weeklyUsageWindow(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage) return null;
        return usage.secondary || null;
    }

    function providerReset(provider) {
        const windowData = primaryUsageWindow(provider);
        if (!windowData) return "—";
        return formatTimeUntil(windowData.resetsAt);
    }

    function providerSubtitle(provider) {
        if (!provider) return t("status.provider_missing", "No provider data");
        if (provider.error) return root.providerErrorText(provider);
        const source = provider.source || root.sourceMode;
        const windowData = primaryUsageWindow(provider);
        if (windowData && windowData.displayValue && String(windowData.displayValue).length > 0) {
            const label = windowData.resetDescription || t("status.usage", "usage");
            return `${source} · ${label} · ${windowData.displayValue}`;
        }
        const reset = providerReset(provider);
        return reset !== "—" ? `${source} · ${t("status.reset", "reset")} ${reset}` : `${source} · ${t("status.no_reset", "no reset window")}`;
    }

    function formatTokens(n) {
        const value = Number(n || 0);
        if (value >= 1000000000) return `${(value / 1000000000).toFixed(1)}B`;
        if (value >= 1000000) return `${(value / 1000000).toFixed(1)}M`;
        if (value >= 1000) return `${(value / 1000).toFixed(1)}K`;
        return Math.round(value).toString();
    }

    function formatCost(usd) {
        const value = Number(usd || 0);
        if (value >= 1000) return `$${(value / 1000).toFixed(1)}K`;
        if (value >= 100) return `$${Math.round(value)}`;
        return `$${value.toFixed(2)}`;
    }

    function formatTier(tier) {
        if (!tier) return "—";
        if (tier.indexOf("max_20x") >= 0) return "Max 20x";
        if (tier.indexOf("max_5x") >= 0) return "Max 5x";
        if (tier.indexOf("pro") >= 0) return "Pro";
        if (tier.indexOf("free") >= 0) return "Free";
        return tier;
    }

    function parseNumberList(value) {
        const parts = value.split(",");
        const result = [];
        for (let i = 0; i < 7; i++) {
            result.push(i < parts.length ? Number(parts[i] || 0) : 0);
        }
        return result;
    }

    function parseClaudeLine(line) {
        const idx = line.indexOf("=");
        if (idx < 0) return;
        const key = line.substring(0, idx);
        const val = line.substring(idx + 1);
        if (key === "SUBSCRIPTION_TYPE") claudeSubscriptionType = val;
        else if (key === "RATE_LIMIT_TIER") claudeRateLimitTier = val;
        else if (key === "FIVE_HOUR_UTIL") claudeFiveHourUtil = Number(val || 0);
        else if (key === "FIVE_HOUR_RESET") claudeFiveHourReset = val;
        else if (key === "SEVEN_DAY_UTIL") claudeSevenDayUtil = Number(val || 0);
        else if (key === "SEVEN_DAY_RESET") claudeSevenDayReset = val;
        else if (key === "WEEK_MESSAGES") claudeWeekMessages = parseInt(val) || 0;
        else if (key === "WEEK_SESSIONS") claudeWeekSessions = parseInt(val) || 0;
        else if (key === "WEEK_TOKENS") claudeWeekTokens = Number(val || 0);
        else if (key === "MONTH_TOKENS") claudeMonthTokens = Number(val || 0);
        else if (key === "ALLTIME_SESSIONS") claudeAlltimeSessions = parseInt(val) || 0;
        else if (key === "ALLTIME_MESSAGES") claudeAlltimeMessages = parseInt(val) || 0;
        else if (key === "FIRST_SESSION") claudeFirstSession = val;
        else if (key === "TODAY_COST") claudeTodayCost = Number(val || 0);
        else if (key === "WEEK_COST") claudeWeekCost = Number(val || 0);
        else if (key === "MONTH_COST") claudeMonthCost = Number(val || 0);
        else if (key === "DAILY") claudeDailyTokens = parseNumberList(val);
        else if (key === "DAILY_COSTS") claudeDailyCosts = parseNumberList(val);
        else if (key === "WEEK_MODELS") {
            claudeModelList.clear();
            if (val.length > 0) {
                const pairs = val.split(",");
                for (let i = 0; i < pairs.length; i++) {
                    const kv = pairs[i].split(":");
                    if (kv.length === 2) {
                        claudeModelList.append({ modelName: capitalizeFirst(kv[0]), modelTokens: Number(kv[1] || 0) });
                    }
                }
            }
        }
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
        command: ["sh", "-c", "usage_script=\"$1\"; candidate=\"$2\"; [ -x \"$usage_script\" ] || exit 1; if [ -n \"$candidate\" ] && [ -f \"$candidate\" ] && [ -x \"$candidate\" ]; then printf '%s\\n' \"$candidate\"; exit 0; fi; command -v codexbar 2>/dev/null || (test -x \"$HOME/.local/bin/codexbar\" && echo \"$HOME/.local/bin/codexbar\") || (test -x /usr/local/bin/codexbar && echo /usr/local/bin/codexbar) || true", "sh", root.providerUsageScript, root.codexbarPath]
        stdout: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (trimmed.length > 0) {
                    root.resolvedBinaryPath = trimmed;
                }
            }
        }
        onExited: code => {
            root.binaryReady = code === 0;
            if (root.binaryReady) {
                root.refresh();
            } else {
                root.providers = [];
                root.hasError = true;
                root.errorMessage = t("error.helper_missing", "Local provider helper is missing or not executable: {path}", { path: root.providerUsageScript });
            }
        }
    }

    Process {
        id: procUsage
        command: ["bash", root.providerUsageScript, root.resolvedPath, root.selectedProviders.join(","), root.sourceMode, root.copilotUsageScript]
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
                        root.hasError = false;
                        root.errorMessage = root.errorProviders.length > 0 ? `${root.errorProviders.length} provider(s) need attention.` : "";
                    }
                    root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm:ss");
                } catch (error) {
                    root.hasError = true;
                    root.errorMessage = root.rawStderrBuffer.length > 0 ? root.rawStderrBuffer : "Failed to parse provider helper output.";
                }
            } else if (code !== 0) {
                root.hasError = true;
                root.errorMessage = root.formatUsageError(code);
            }

            root.rawJsonBuffer = "";
            root.rawStderrBuffer = "";
        }
    }

    Process {
        id: claudeStatsProcess
        command: ["bash", root.claudeUsageScript]
        stdout: SplitParser {
            onRead: data => {
                const lines = data.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    root.parseClaudeLine(lines[i]);
                }
            }
        }
        onExited: code => {
            if (code !== 0 && root.focusedProviderId === "claude") {
                root.errorMessage = "Claude Code usage details are unavailable. Check claude, jq, and curl.";
            }
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
        if (root.selectedProviders.indexOf("claude") >= 0 && !claudeStatsProcess.running) {
            claudeStatsProcess.running = true;
        }
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
                root.errorMessage = t("error.helper_timeout", "Provider helper timed out while fetching usage data.");
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

        implicitWidth: compact ? 104 : 176
        implicitHeight: compact ? 40 : (description.length > 0 ? 56 : 48)
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
            anchors.topMargin: compact ? Theme.spacingXS : Theme.spacingM
            anchors.bottomMargin: compact ? Theme.spacingXS : Theme.spacingM
            spacing: compact ? Theme.spacingXS : Theme.spacingS

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: compact ? 24 : 32
                height: compact ? 24 : 32
                radius: width / 2
                color: buttonRoot.prominent ? Theme.withAlpha(Theme.primary, 0.18) : Theme.withAlpha(Theme.surfaceText, 0.08)

                DankIcon {
                    anchors.centerIn: parent
                    name: buttonRoot.iconName
                    size: compact ? 14 : 18
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
                    font.pixelSize: compact ? Theme.fontSizeSmall : Theme.fontSizeMedium
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

    component BadgePill: StyledRect {
        id: pill

        required property string label
        property string iconName: "circle"
        property color accentColor: Theme.primary
        property bool emphasized: false

        implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
        implicitHeight: 28
        radius: 999
        color: emphasized ? Theme.withAlpha(accentColor, 0.16) : Theme.withAlpha(accentColor, 0.1)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, emphasized ? 0.3 : 0.18)

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DankIcon {
                visible: pill.iconName.length > 0
                name: pill.iconName
                size: 12
                color: pill.accentColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: pill.label
                color: pill.accentColor
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
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
        property bool multilineValue: false

        implicitHeight: multilineValue ? 68 : 58
        radius: Theme.cornerRadius
        color: Theme.withAlpha(accentColor, 0.055)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, 0.16)
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 3
            radius: 2
            color: Theme.withAlpha(accentColor, 0.78)
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: parent.width * 0.32
            height: parent.height
            opacity: 0.42
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(accentColor, 0.12) }
                GradientStop { position: 1.0; color: Theme.withAlpha(accentColor, 0.0) }
            }
        }

        Column {
            id: tileCol
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: 4

            StyledText {
                width: parent.width
                text: tile.label
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: tile.value.length > 0 ? tile.value : "—"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall + 1
                font.weight: Font.Bold
                maximumLineCount: tile.multilineValue ? 2 : 1
                wrapMode: tile.multilineValue ? Text.WrapAnywhere : Text.NoWrap
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

    component UsageBar: Column {
        id: usageBar
        required property string label
        required property real percent
        property string aside: ""
        property color accentColor: root.getUsageColor(percent)

        width: parent ? parent.width : implicitWidth
        spacing: 6

        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: parent.width - valueText.implicitWidth - Theme.spacingS
                text: usageBar.label
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall + 1
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            StyledText {
                id: valueText
                text: usageBar.aside.length > 0 ? usageBar.aside : `${Math.round(usageBar.percent)}%`
                color: usageBar.accentColor
                font.pixelSize: Theme.fontSizeSmall + 1
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            width: parent.width
            height: 8
            radius: 4
            color: Theme.withAlpha(Theme.surfaceText, 0.075)
            border.width: 1
            border.color: Theme.withAlpha(Theme.surfaceText, 0.045)
            clip: true

            Rectangle {
                width: Math.max(3, Math.min(1, usageBar.percent / 100) * parent.width)
                height: parent.height
                radius: parent.radius
                color: usageBar.accentColor

                Behavior on width {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    component ClaudeDailyBars: Row {
        id: dailyBars
        width: parent ? parent.width : implicitWidth
        spacing: Theme.spacingS

        property real maxDaily: Math.max.apply(null, root.claudeDailyTokens) || 1

        Repeater {
            model: 7

            Column {
                width: (dailyBars.width - Theme.spacingS * 6) / 7
                spacing: 7

                Rectangle {
                    width: parent.width
                    height: 66
                    radius: Theme.cornerRadius - 2
                    color: Theme.surfaceContainer
                    clip: true

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(3, (Number(root.claudeDailyTokens[index] || 0) / dailyBars.maxDaily) * parent.height)
                        color: index === root.currentWeekdayIndex ? Theme.warning : Theme.withAlpha(Theme.primary, 0.55)
                    }
                }

                StyledText {
                    width: parent.width
                    text: root.dayLabels[index]
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    component ProviderDashboardCard: StyledRect {
        id: card
        required property var provider
        property bool expanded: !!provider && provider.provider === root.focusedProviderId
        property bool hasUsage: !!provider && !!provider.usage && !provider.error
        property color accentColor: provider && provider.error ? Theme.error : root.providerAccent(provider ? provider.provider : "")
        property var windows: root.windowsForProvider(provider)
        property bool compact: width < 560
        property bool veryCompact: width < 430
        property bool hovered: cardMouse.containsMouse

        width: parent ? parent.width : implicitWidth
        radius: Theme.cornerRadius + 4
        color: expanded ? Theme.surfaceContainerHigh : (hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
        border.width: 1
        border.color: provider && provider.error ? Theme.withAlpha(Theme.error, expanded ? 0.34 : 0.16) : Theme.withAlpha(accentColor, expanded ? 0.42 : (hovered ? 0.26 : 0.12))
        implicitHeight: cardColumn.implicitHeight + (card.compact ? Theme.spacingM : Theme.spacingL) * 2
        clip: true
        scale: hovered ? 1.006 : 1.0

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            opacity: expanded || hovered ? 1 : 0.72
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(card.accentColor, expanded ? 0.12 : 0.055) }
                GradientStop { position: 0.52; color: Theme.withAlpha(card.accentColor, 0.025) }
                GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.0) }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: expanded ? 5 : 3
            color: Theme.withAlpha(card.accentColor, expanded ? 0.9 : 0.62)
        }

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Column {
            id: cardColumn
            z: 2
            anchors.fill: parent
            anchors.margins: card.compact ? Theme.spacingS : Theme.spacingM
            spacing: expanded ? Theme.spacingM : Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: card.compact ? Theme.spacingS : Theme.spacingL

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    visible: !card.veryCompact
                    width: card.compact ? 34 : 40
                    height: width
                    radius: width / 2
                    color: Theme.withAlpha(card.accentColor, 0.16)
                    border.width: 1
                    border.color: Theme.withAlpha(card.accentColor, 0.42)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: width / 2
                        color: Theme.withAlpha(card.accentColor, 0.08)
                    }

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.iconForProvider(card.provider.provider)
                        size: card.compact ? 18 : 21
                        color: card.accentColor
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6

                    StyledText {
                        width: parent.width
                        text: root.providerName(card.provider.provider)
                        color: Theme.surfaceText
                        font.pixelSize: card.compact ? Theme.fontSizeSmall + 1 : Theme.fontSizeMedium
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: root.providerSubtitle(card.provider)
                        color: card.provider.error ? Theme.withAlpha(Theme.error, 0.92) : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall - 1
                        maximumLineCount: card.provider.error ? (expanded ? 3 : 2) : (expanded ? 2 : 1)
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.spacingXS

                        BadgePill {
                            label: root.providerSourceLabel(card.provider)
                            iconName: "sync_alt"
                            accentColor: Theme.primary
                        }

                        BadgePill {
                            label: root.providerStatusLabel(card.provider)
                            iconName: card.provider && card.provider.error ? "warning" : "check_circle"
                            accentColor: card.provider && card.provider.error ? Theme.warning : root.providerAccent(card.provider.provider)
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: card.provider.error ? t("status.error", "Error") : `${Math.round(root.providerPercent(card.provider))}%`
                    color: card.provider.error ? Theme.error : root.getUsageColor(root.providerPercent(card.provider))
                    font.pixelSize: card.compact ? Theme.fontSizeMedium : Theme.fontSizeLarge
                    font.weight: Font.Bold
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.selectedProviders.length > 1
                    z: 2
                    width: card.compact ? 32 : 36
                    height: width
                    radius: width / 2
                    color: removeArea.containsMouse ? Theme.withAlpha(Theme.error, 0.14) : Theme.withAlpha(card.accentColor, 0.08)
                    border.width: 1
                    border.color: removeArea.containsMouse ? Theme.withAlpha(Theme.error, 0.32) : Theme.withAlpha(card.accentColor, 0.18)

                    DankIcon {
                        anchors.centerIn: parent
                        name: "close"
                        size: card.compact ? 16 : 18
                        color: removeArea.containsMouse ? Theme.error : Theme.surfaceVariantText
                    }

                    MouseArea {
                        id: removeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            mouse.accepted = true;
                            root.removeProvider(card.provider.provider);
                        }
                    }
                }

                DankIcon {
                    Layout.alignment: Qt.AlignVCenter
                    name: card.expanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
                    size: card.compact ? 24 : 28
                    color: Theme.surfaceVariantText
                }
            }

            UsageBar {
                visible: card.hasUsage && !card.expanded
                width: parent.width
                label: card.windows.length > 0 ? card.windows[0].label : t("status.usage", "Usage")
                percent: root.providerPercent(card.provider)
                aside: card.windows.length > 0 ? root.formatUsageLine(card.windows[0].data) : `${Math.round(root.providerPercent(card.provider))}%`
                accentColor: root.getUsageColor(root.providerPercent(card.provider))
            }

            Column {
                visible: card.expanded
                width: parent.width
                spacing: Theme.spacingL

                Repeater {
                    model: card.windows

                    UsageBar {
                        required property var modelData
                        width: parent.width
                        label: modelData.label
                        percent: Number(modelData.data.usedPercent || 0)
                        aside: root.formatUsageLine(modelData.data)
                        accentColor: root.getUsageColor(Number(modelData.data.usedPercent || 0))
                    }
                }

                GridLayout {
                    visible: card.hasUsage
                    width: parent.width
                    columns: card.width < 520 ? 1 : (card.width < 760 ? 2 : 3)
                    columnSpacing: Theme.spacingM
                    rowSpacing: Theme.spacingM

                    MetricTile {
                        Layout.fillWidth: true
                        label: t("card.account", "Account")
                        value: root.providerAccount(card.provider)
                        accentColor: card.accentColor
                        multilineValue: true
                    }

                    MetricTile {
                        Layout.fillWidth: true
                        label: t("card.login", "Login")
                        value: root.providerLogin(card.provider)
                        accentColor: card.accentColor
                    }

                    MetricTile {
                        Layout.fillWidth: true
                        label: t("card.credits", "Credits")
                        value: root.providerCredits(card.provider)
                        accentColor: card.accentColor
                    }
                }

                StyledRect {
                    visible: card.provider.provider === "claude"
                    width: parent.width
                    radius: Theme.cornerRadius + 2
                    color: Theme.withAlpha(Theme.warning, 0.08)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.warning, 0.22)
                    implicitHeight: claudeCol.implicitHeight + Theme.spacingL * 2

                    Column {
                        id: claudeCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingL

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: true
                                text: t("card.claude_details", "Claude Code details")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                            }

                            StyledText {
                                text: root.formatTier(root.claudeRateLimitTier)
                                color: Theme.warning
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }
                        }

                        UsageBar {
                            width: parent.width
                            label: t("card.week", "Week")
                            percent: root.claudeSevenDayUtil
                            aside: `${Math.round(root.claudeSevenDayUtil)}%`
                            accentColor: root.getUsageColor(root.claudeSevenDayUtil)
                        }

                        UsageBar {
                            width: parent.width
                            label: "5h"
                            percent: root.claudeFiveHourUtil
                            aside: `${Math.round(root.claudeFiveHourUtil)}%`
                            accentColor: root.getUsageColor(root.claudeFiveHourUtil)
                        }

                        GridLayout {
                            width: parent.width
                            columns: card.width < 520 ? 1 : 3
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            MetricTile { Layout.fillWidth: true; label: t("card.today", "Today"); value: `${root.formatTokens(root.claudeDailyTokens[root.currentWeekdayIndex] || 0)} · ${root.formatCost(root.claudeTodayCost)}`; accentColor: Theme.warning }
                            MetricTile { Layout.fillWidth: true; label: t("card.week", "Week"); value: `${root.formatTokens(root.claudeWeekTokens)} · ${root.formatCost(root.claudeWeekCost)}`; accentColor: Theme.warning }
                            MetricTile { Layout.fillWidth: true; label: t("card.month", "Month"); value: `${root.formatTokens(root.claudeMonthTokens)} · ${root.formatCost(root.claudeMonthCost)}`; accentColor: Theme.warning }
                        }

                        ClaudeDailyBars {
                            width: parent.width
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.models_week", "Models this week")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: claudeModelList

                                UsageBar {
                                    required property string modelName
                                    required property real modelTokens
                                    width: parent.width
                                    label: modelName
                                    percent: root.claudeWeekTokens > 0 ? (modelTokens / root.claudeWeekTokens) * 100 : 0
                                    aside: root.formatTokens(modelTokens)
                                    accentColor: Theme.warning
                                }
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: t("card.claude_since", "Since {date} · {sessions} sessions · {messages} messages", { date: root.claudeFirstSession || "—", sessions: root.claudeAlltimeSessions, messages: root.claudeAlltimeMessages })
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        MouseArea {
            z: 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: card.compact ? 76 : 82
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.focusedProviderId = card.expanded ? "" : card.provider.provider
        }
    }

    component ProviderManager: StyledRect {
        id: manager

        width: parent ? parent.width : implicitWidth
        radius: Theme.cornerRadius + 4
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.2)
        implicitHeight: managerColumn.implicitHeight + Theme.spacingL * 2

        Column {
            id: managerColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Flow {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width < 620 ? parent.width : Math.max(220, parent.width - 220 - 118 - Theme.spacingM * 2)
                    spacing: 4

                    StyledText {
                        width: parent.width
                        text: t("card.provider_control", "Provider control")
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }

                    StyledText {
                        width: parent.width
                        text: root.selectedProviders.join(", ")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                }

                DankDropdown {
                    id: addProviderDropdown
                    width: parent.width < 620 ? parent.width : 220
                    text: t("card.provider", "Provider")
                    description: t("card.provider_description", "Choose a provider supported by local helpers or fallback.")
                    currentValue: root.pendingProviderId
                    options: root.availableProviderOptions
                    dropdownWidth: 220
                    onValueChanged: function(value) {
                        root.pendingProviderId = value;
                    }
                }

                SurfaceButton {
                    id: addProviderButton
                    width: parent.width < 620 ? parent.width : implicitWidth
                    iconName: "add"
                    label: t("card.add_provider", "Add provider")
                    compact: true
                    prominent: true
                    actionEnabled: root.selectedProviders.indexOf(root.pendingProviderId) < 0
                    onTriggered: root.addProvider(root.pendingProviderId)
                }
            }
        }
    }

    popoutWidth: 860
    popoutHeight: 820

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: t("app.title", "AI Usage Control")
            detailsText: root.lastUpdated.length > 0 ? t("popout.details_updated", "Updated {time} · {source}", { time: root.lastUpdated, source: root.sourceMode }) : t("popout.provider_dashboard", "Provider dashboard")
            showCloseButton: true

            headerActions: Component {
                Row {
                    spacing: Theme.spacingS

                    SurfaceButton {
                        iconName: "terminal"
                        label: t("card.detect", "Detect")
                        compact: true
                        actionEnabled: !procDetect.running
                        onTriggered: root.detectBinary()
                    }

                    SurfaceButton {
                        iconName: "refresh"
                        label: t("card.refresh", "Refresh")
                        compact: true
                        prominent: true
                        actionEnabled: root.binaryReady && !root.isLoading
                        onTriggered: root.refresh()
                    }
                }
            }

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL

                Flickable {
                    id: contentFlick
                    anchors.fill: parent
                    anchors.leftMargin: popout.width < 620 ? Theme.spacingS : Theme.spacingL
                    anchors.rightMargin: popout.width < 620 ? Theme.spacingS : Theme.spacingL
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: contentColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar { anchors.right: parent.right; anchors.rightMargin: -Theme.spacingM }

                    Column {
                        id: contentColumn
                        width: contentFlick.width
                        spacing: Theme.spacingL

                        StyledRect {
                            width: parent.width
                            radius: Theme.cornerRadius + 8
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.withAlpha(root.heroAccent, 0.38)
                            implicitHeight: overviewCol.implicitHeight + (contentColumn.width < 560 ? Theme.spacingL : Theme.spacingXL) * 2
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Theme.withAlpha(root.heroAccent, 0.18) }
                                    GradientStop { position: 0.52; color: Theme.withAlpha(root.heroAccent, 0.055) }
                                    GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.02) }
                                }
                            }

                            Rectangle {
                                width: 180
                                height: 180
                                radius: 90
                                anchors.right: parent.right
                                anchors.rightMargin: -56
                                anchors.top: parent.top
                                anchors.topMargin: -68
                                color: Theme.withAlpha(root.heroAccent, 0.10)
                            }

                            Rectangle {
                                width: 92
                                height: 92
                                radius: 46
                                anchors.right: parent.right
                                anchors.rightMargin: 82
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: -42
                                color: Theme.withAlpha(Theme.primary, 0.07)
                            }

                            Column {
                                id: overviewCol
                                anchors.fill: parent
                                anchors.margins: contentColumn.width < 560 ? Theme.spacingL : Theme.spacingXL
                                spacing: Theme.spacingL

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingM

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        StyledText {
                                            width: parent.width
                                            text: t("app.title", "AI Usage Control")
                                            color: Theme.surfaceText
                                            font.pixelSize: contentColumn.width < 560 ? Theme.fontSizeLarge : Theme.fontSizeLarge + 4
                                            font.weight: Font.Bold
                                            wrapMode: Text.WordWrap
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: root.statusSubtitle
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeMedium
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                    }

                                    StyledRect {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: contentColumn.width >= 520
                                        width: 188
                                        height: 124
                                        radius: Theme.cornerRadius + 8
                                        color: Theme.withAlpha(root.heroAccent, 0.08)
                                        border.width: 1
                                        border.color: Theme.withAlpha(root.heroAccent, 0.24)

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingM
                                            spacing: Theme.spacingS

                                            BadgePill {
                                                label: root.providerData ? root.providerName(root.providerData.provider) : t("status.provider_missing", "No provider")
                                                iconName: root.providerData ? root.iconForProvider(root.providerData.provider) : "monitoring"
                                                accentColor: root.heroAccent
                                                emphasized: true
                                            }

                                            StyledText {
                                                width: parent.width
                                                text: root.barText
                                                color: root.heroAccent
                                                font.pixelSize: Theme.fontSizeLarge + 8
                                                font.weight: Font.Bold
                                            }

                                            StyledText {
                                                width: parent.width
                                                text: root.providerData ? root.providerSubtitle(root.providerData) : root.statusSubtitle
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                            }

                                            Row {
                                                width: parent.width
                                                spacing: Theme.spacingXS

                                                BadgePill {
                                                    label: root.providerData ? root.providerSourceLabel(root.providerData) : root.sourceMode
                                                    iconName: "sync_alt"
                                                    accentColor: Theme.primary
                                                }

                                                BadgePill {
                                                    label: root.hasError ? t("status.needs_attention", "Needs attention") : root.providerStatusLabel(root.providerData)
                                                    iconName: root.hasError ? "warning" : "check_circle"
                                                    accentColor: root.hasError ? Theme.warning : root.getUsageColor(root.primaryPercent)
                                                }
                                            }
                                        }
                                    }
                                }

                                GridLayout {
                                    width: parent.width
                                    columns: contentColumn.width < 520 ? 1 : (contentColumn.width < 760 ? 2 : 4)
                                    columnSpacing: Theme.spacingM
                                    rowSpacing: Theme.spacingM

                                    MetricTile { Layout.fillWidth: true; label: t("card.active", "Active"); value: String(root.successfulProviders.length); accentColor: Theme.success }
                                    MetricTile { Layout.fillWidth: true; label: t("card.attention", "Attention"); value: String(root.errorProviders.length); accentColor: root.errorProviders.length > 0 ? Theme.warning : Theme.success }
                                    MetricTile { Layout.fillWidth: true; label: t("card.engine", "Engine"); value: root.providerEngineLabel; accentColor: Theme.primary }
                                    MetricTile { Layout.fillWidth: true; label: t("card.fallback", "Fallback"); value: root.compactPath(root.resolvedBinaryPath); accentColor: Theme.primary; multilineValue: true }
                                }
                            }
                        }

                        RowLayout {
                            visible: root.providers.length > 0
                            width: parent.width
                            spacing: Theme.spacingM

                            StyledText {
                                Layout.fillWidth: true
                                text: t("card.providers", "Providers")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: providerCountLabel.implicitWidth + Theme.spacingM * 2
                                implicitHeight: 28
                                radius: 14
                                color: Theme.withAlpha(root.heroAccent, 0.12)
                                border.width: 1
                                border.color: Theme.withAlpha(root.heroAccent, 0.24)

                                StyledText {
                                    id: providerCountLabel
                                    anchors.centerIn: parent
                                    text: root.displayProviders.length === 1 ? t("status.displayed", "{count} displayed", { count: root.displayProviders.length }) : t("status.displayed_plural", "{count} displayed", { count: root.displayProviders.length })
                                    color: root.heroAccent
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        StyledText {
                            visible: root.isLoading && root.providers.length === 0
                            width: parent.width
                            text: t("status.loading_usage", "Fetching provider usage data...")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledRect {
                            visible: !root.isLoading && root.providers.length === 0
                            width: parent.width
                            radius: Theme.cornerRadius + 6
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.withAlpha(root.heroAccent, 0.18)
                            implicitHeight: emptyStateCol.implicitHeight + Theme.spacingL * 2

                            Column {
                                id: emptyStateCol
                                anchors.fill: parent
                                anchors.margins: Theme.spacingL
                                spacing: Theme.spacingM

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingM

                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        width: 36
                                        height: 36
                                        radius: 18
                                        color: Theme.withAlpha(root.heroAccent, 0.14)
                                        border.width: 1
                                        border.color: Theme.withAlpha(root.heroAccent, 0.28)

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "monitoring"
                                            size: 18
                                            color: root.heroAccent
                                        }
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        StyledText {
                                            width: parent.width
                                            text: t("status.no_provider_data", "No provider data available. Check credentials, local CLIs, or the optional fallback path.")
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.WordWrap
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: t("status.no_data_hint", "Run your configured AI CLIs and refresh to populate usage windows.")
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                Flow {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    BadgePill {
                                        label: t("card.refresh", "Refresh")
                                        iconName: "refresh"
                                        accentColor: Theme.primary
                                        emphasized: true
                                    }

                                    BadgePill {
                                        label: t("card.detect", "Detect")
                                        iconName: "terminal"
                                        accentColor: Theme.secondary
                                    }

                                    BadgePill {
                                        label: root.t("settings.active_count", "{count} active", { count: root.selectedProviders.length })
                                        iconName: "playlist_add_check"
                                        accentColor: Theme.surfaceVariantText
                                    }
                                }
                            }
                        }

                        ProviderManager {
                            width: parent.width
                        }

                        Repeater {
                            model: root.displayProviders

                            ProviderDashboardCard {
                                required property var modelData
                                provider: modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
