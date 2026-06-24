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
    property real lastUpdatedMs: 0
    property string rawJsonBuffer: ""
    property string rawStderrBuffer: ""
    property bool binaryReady: false
    property int fetchTimeoutMs: 45000
    property bool usageDidTimeout: false
    property int usageRequestId: 0
    property int timedOutRequestId: -1
    property string providerSelection: (pluginData.providerSelection || "codex,claude,copilot").trim()
    property bool showErrorProviders: String(pluginData.showErrorProviders ?? "true") === "true"
    property string pillMode: (pluginData.pillMode || "auto")
    property string pillProviders: (pluginData.pillProviders || providerSelection).trim()
    property string densityMode: pluginData.densityMode || "comfortable"
    property string providerFilter: ""
    property string providerStatusFilter: "all"
    property string focusedProviderId: ""
    property bool allExpanded: false
    property var usageHistory: ({})
    property string historyBuffer: ""
    property string retryBuffer: ""
    property string retryingProviderId: ""
    property var notifiedMap: ({})
    property bool notifyEnabled: String(pluginData.quotaNotifications ?? "true") === "true"
    property int notifyThreshold: {
        const parsed = parseInt(pluginData.notifyThreshold || "85");
        return Number.isFinite(parsed) && parsed > 0 && parsed <= 100 ? parsed : 85;
    }
    property bool showClaudeProjects: String(pluginData.showClaudeProjects ?? "true") === "true"
    // Per-provider overrides: "claude:90,codex:75" beats the global threshold.
    readonly property var notifyThresholdOverrides: {
        const raw = String(pluginData.notifyThresholds || "").trim();
        const map = {};
        if (raw.length === 0) return map;
        const pairs = raw.split(",");
        for (let i = 0; i < pairs.length; i++) {
            const kv = pairs[i].split(":");
            if (kv.length !== 2) continue;
            const id = kv[0].trim().toLowerCase();
            const value = parseInt(kv[1].trim());
            if (id.length > 0 && Number.isFinite(value) && value > 0 && value <= 100) {
                map[id] = value;
            }
        }
        return map;
    }

    function thresholdFor(providerId) {
        const override = notifyThresholdOverrides[normalizeProviderId(providerId)];
        return override !== undefined ? override : notifyThreshold;
    }
    // Minutes between repeats of the same alert; 0 = once per quota window.
    readonly property int notifyCooldownSecs: {
        const parsed = parseInt(pluginData.notifyCooldownMinutes || "0");
        if (!Number.isFinite(parsed) || parsed <= 0) return 999999999;
        return parsed * 60;
    }
    property string pinnedProvidersCsv: (pluginData.pinnedProviders || "").trim()
    readonly property var pinnedProviders: {
        const parts = pinnedProvidersCsv.split(",");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            const id = parts[i].trim().toLowerCase();
            if (id.length > 0 && result.indexOf(id) < 0) result.push(id);
        }
        return result;
    }
    property string pendingProviderId: availableProviderOptions[0] || "codex"
    property string claudeRawBuffer: ""
    property bool claudeStatsError: false
    property string claudeSubscriptionType: ""
    property string claudeRateLimitTier: ""
    property real claudeFiveHourUtil: 0
    property string claudeFiveHourReset: ""
    property real claudeSevenDayUtil: 0
    property string claudeSevenDayReset: ""
    property bool claudeExtraUsageEnabled: false
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
    // Resolved imperatively in Component.onCompleted — Qt.resolvedUrl is only reliable
    // when called from the file's own execution context, not from a declarative binding
    // that may be evaluated before the component URL context is established.
    property string _pluginDir: ""
    property string providerUsageScript: _pluginDir + "/providers/get-provider-usage"
    property string claudeUsageScript: _pluginDir + "/providers/get-claude-usage"
    property string copilotUsageScript: _pluginDir + "/providers/get-copilot-usage"
    property string usageHistoryScript: _pluginDir + "/providers/get-usage-history"
    property string notifyAlertScript: _pluginDir + "/providers/send-quota-alert"
    property string nineRouterAnalyticsScript: _pluginDir + "/providers/get-9router-analytics"
    property var nineStats: null
    property string nineStatsBuffer: ""
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
        "zai",
        "minimax",
        "qwen",
        "nvidia",
        "cloudflare",
        "vertexai",
        "byteplus",
        "ollama",
        "together",
        "groq",
        "cohere",
        "replicate",
        "fireworks",
        "ai21",
        "xai",
        "kilo",
        "perplexity",
        "cursor",
        "cline",
        "opencode",
        "kiro",
        "warp",
        "amp"
    ]

    ListModel {
        id: claudeModelList
    }

    ListModel {
        id: claudeProjectList
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

    readonly property var filteredDisplayProviders: {
        const query = providerFilter.trim().toLowerCase();
        const result = [];
        for (let i = 0; i < displayProviders.length; i++) {
            const provider = displayProviders[i];
            if (providerStatusFilter === "live" && (provider.error || !provider.usage)) continue;
            if (providerStatusFilter === "issues" && !provider.error) continue;
            if (query.length > 0) {
                const haystack = `${providerName(provider.provider)} ${provider.provider} ${providerSourceLabel(provider)}`.toLowerCase();
                if (haystack.indexOf(query) < 0) continue;
            }
            result.push(provider);
        }
        // Pinned first, then most-used so attention lands where quota is
        // burning; failed providers sink to the end without hiding.
        result.sort(function(a, b) {
            const aPin = pinnedProviders.indexOf(a.provider) >= 0 ? 0 : 1;
            const bPin = pinnedProviders.indexOf(b.provider) >= 0 ? 0 : 1;
            if (aPin !== bPin) return aPin - bPin;
            const aErr = a.error ? 1 : 0;
            const bErr = b.error ? 1 : 0;
            if (aErr !== bErr) return aErr - bErr;
            return providerPercent(b) - providerPercent(a);
        });
        return result;
    }

    readonly property var pillDisplayProviders: {
        if (pillMode === "top") {
            // Single most-critical provider: highest primary usage wins.
            let best = null;
            let bestPercent = -1;
            for (let i = 0; i < successfulProviders.length; i++) {
                const percent = providerPercent(successfulProviders[i]);
                if (percent > bestPercent) {
                    bestPercent = percent;
                    best = successfulProviders[i];
                }
            }
            return best ? [best] : [];
        }
        if (pillMode === "custom") {
            const ids = pillProviders.split(",");
            const result = [];
            for (let i = 0; i < ids.length; i++) {
                const id = ids[i].trim().toLowerCase();
                if (id.length === 0) continue;
                for (let j = 0; j < providers.length; j++) {
                    if (providers[j] && providers[j].provider === id && !providers[j].error) {
                        result.push(providers[j]);
                        break;
                    }
                }
            }
            return result.length > 0 ? result : successfulProviders;
        }
        // auto: show all with usedPercent > 0, else all successful
        const active = [];
        for (let i = 0; i < successfulProviders.length; i++) {
            if (providerPercent(successfulProviders[i]) > 0) {
                active.push(successfulProviders[i]);
            }
        }
        return active.length > 0 ? active : successfulProviders;
    }

    readonly property var providerData: {
        for (let i = 0; i < pinnedProviders.length; i++) {
            for (let j = 0; j < successfulProviders.length; j++) {
                if (successfulProviders[j].provider === pinnedProviders[i]) {
                    return successfulProviders[j];
                }
            }
        }
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

    // Cross-provider rollup: the fleet's quota pressure at a glance. Aggregates
    // the primary window of every live provider — average load, the hottest
    // provider, how many are near their cap, and the soonest reset. Percent is
    // the only unit comparable across heterogeneous providers, so we summarise
    // load rather than faking a cross-provider monetary total. staleTickMs is
    // touched so nextResetLabel re-evaluates on the same cadence as the hero.
    readonly property var fleetRollup: {
        const live = successfulProviders;
        const out = { count: live.length, avg: 0, peak: 0, peakName: "", peakId: "", atRisk: 0, nextResetMs: 0 };
        if (live.length === 0) {
            return out;
        }
        let sum = 0;
        let nextMs = Infinity;
        for (let i = 0; i < live.length; i++) {
            const percent = providerPercent(live[i]);
            sum += percent;
            if (percent > out.peak) {
                out.peak = percent;
                out.peakName = providerName(live[i].provider);
                out.peakId = live[i].provider;
            }
            if (percent >= 80) {
                out.atRisk++;
            }
            const win = primaryUsageWindow(live[i]);
            if (win && win.resetsAt) {
                const ms = new Date(win.resetsAt).getTime();
                if (!isNaN(ms) && ms > Date.now() && ms < nextMs) {
                    nextMs = ms;
                }
            }
        }
        out.avg = sum / live.length;
        if (nextMs !== Infinity) {
            out.nextResetMs = nextMs;
        }
        return out;
    }

    readonly property string fleetNextResetLabel: {
        staleTickMs;
        return fleetRollup.nextResetMs > 0 ? formatTimeUntil(fleetRollup.nextResetMs) : "—";
    }

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
                label: primaryWindow.resetDescription || getWindowLabel(primaryWindow.windowMinutes),
                data: primaryWindow
            });
        }
        if (secondaryWindow) {
            windows.push({
                key: "secondary",
                label: secondaryWindow.resetDescription || getWindowLabel(secondaryWindow.windowMinutes),
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

    readonly property bool isDataStale: {
        staleTickMs;
        return lastUpdatedMs > 0 && (Date.now() - lastUpdatedMs) > refreshIntervalMs * 2;
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
        if (rawStderrBuffer.length > 0) return rawStderrBuffer.trim();
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
            zai: "Z.ai",
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
            together: "Together AI",
            groq: "Groq",
            cohere: "Cohere",
            replicate: "Replicate",
            fireworks: "Fireworks AI",
            ai21: "AI21",
            xai: "xAI",
            grok: "xAI",
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
        const source = provider && provider.source ? String(provider.source) : "local";
        return source.length > 0 ? source : "local";
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

    function providerUpdatedMs(provider) {
        const value = provider && provider.usage ? provider.usage.updatedAt : "";
        if (!value) return lastUpdatedMs;
        const parsed = new Date(value).getTime();
        return Number.isFinite(parsed) ? parsed : lastUpdatedMs;
    }

    function providerUpdatedLabel(provider) {
        const value = providerUpdatedMs(provider);
        return value > 0 ? Qt.formatDateTime(new Date(value), "hh:mm:ss") : lastUpdated;
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
        if (providerId === "glm" || providerId === "zhipu" || providerId === "zai") return "bubble_chart";
        if (providerId === "minimax") return "grid_view";
        if (providerId === "qwen" || providerId === "dashscope" || providerId === "alibaba") return "cloud";
        if (providerId === "nvidia" || providerId === "nim") return "memory";
        if (providerId === "cloudflare") return "shield";
        if (providerId === "vertexai" || providerId === "vertex") return "hexagon";
        if (providerId === "byteplus" || providerId === "ark" || providerId === "modelark") return "bolt";
        if (providerId === "perplexity") return "travel_explore";
        if (providerId === "cursor") return "ads_click";
        if (providerId === "ollama") return "dns";
        if (providerId === "together") return "join_inner";
        if (providerId === "groq") return "fast_forward";
        if (providerId === "cohere") return "waves";
        if (providerId === "replicate") return "content_copy";
        if (providerId === "fireworks") return "local_fire_department";
        if (providerId === "xai" || providerId === "grok") return "bolt";
        if (providerId === "ai21") return "looks_21";
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
        if (providerId === "glm" || providerId === "zhipu" || providerId === "zai") return Theme.primary;
        if (providerId === "minimax") return Theme.success;
        if (providerId === "qwen" || providerId === "dashscope" || providerId === "alibaba") return Theme.warning;
        if (providerId === "nvidia" || providerId === "nim") return Theme.success;
        if (providerId === "cloudflare") return Theme.warning;
        if (providerId === "vertexai" || providerId === "vertex") return Theme.primary;
        if (providerId === "byteplus" || providerId === "ark" || providerId === "modelark") return Theme.secondary;
        if (providerId === "together") return Theme.primary;
        if (providerId === "groq") return Theme.success;
        if (providerId === "cohere") return Theme.secondary;
        if (providerId === "replicate") return Theme.primary;
        if (providerId === "fireworks") return Theme.warning;
        if (providerId === "xai" || providerId === "grok") return Theme.primary;
        if (providerId === "ai21") return Theme.secondary;
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
        const source = provider.source || "local";
        const windowData = primaryUsageWindow(provider);
        if (windowData && windowData.displayValue && String(windowData.displayValue).length > 0) {
            const label = windowData.resetDescription || t("status.usage", "usage");
            return `${source} · ${label} · ${windowData.displayValue}`;
        }
        const reset = providerReset(provider);
        return (reset && reset !== "—") ? `${source} · ${t("status.reset", "reset")} ${reset}` : `${source} · ${t("status.no_reset", "no reset window")}`;
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
        else if (key === "EXTRA_USAGE_ENABLED") claudeExtraUsageEnabled = (val === "true");
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
                        claudeModelList.append({ modelName: capitalizeFirst(kv[0]), modelTokens: Number(kv[1] || 0), modelCost: 0 });
                    }
                }
            }
        }
        else if (key === "WEEK_MODEL_COSTS") {
            // Arrives after WEEK_MODELS: enrich the already-built model rows.
            if (val.length > 0) {
                const pairs = val.split(",");
                for (let i = 0; i < pairs.length; i++) {
                    const kv = pairs[i].split(":");
                    if (kv.length !== 2) continue;
                    const name = capitalizeFirst(kv[0]);
                    for (let j = 0; j < claudeModelList.count; j++) {
                        if (claudeModelList.get(j).modelName === name) {
                            claudeModelList.setProperty(j, "modelCost", Number(kv[1] || 0));
                            break;
                        }
                    }
                }
            }
        }
        else if (key === "WEEK_PROJECTS") {
            claudeProjectList.clear();
            if (val.length > 0) {
                const pairs = val.split(",");
                for (let i = 0; i < pairs.length; i++) {
                    const cut = pairs[i].lastIndexOf(":");
                    if (cut <= 0) continue;
                    claudeProjectList.append({
                        projectPath: pairs[i].substring(0, cut),
                        projectTokens: Number(pairs[i].substring(cut + 1) || 0)
                    });
                }
            }
        }
    }

    function formatMinutes(mins) {
        const value = Math.max(0, Math.round(Number(mins) || 0));
        if (value < 60) return `${value}m`;
        const hours = Math.floor(value / 60);
        if (hours < 24) return `${hours}h ${value % 60}m`;
        return `${Math.floor(hours / 24)}d ${hours % 24}h`;
    }

    // Burn-rate forecast for a rolling window: utilization so far divided by
    // elapsed window time, extrapolated to 100%.
    function windowBurnForecast(util, resetIso, windowMinutes) {
        if (!resetIso || util <= 0) return null;
        const resetMs = new Date(resetIso).getTime();
        if (!Number.isFinite(resetMs)) return null;
        const remainMin = Math.max(0, (resetMs - Date.now()) / 60000);
        if (remainMin <= 0 || remainMin >= windowMinutes) return null;
        const elapsedMin = Math.max(1, windowMinutes - remainMin);
        const rate = util / elapsedMin;
        if (rate <= 0) return null;
        const minTo100 = (100 - util) / rate;
        if (minTo100 <= remainMin) {
            return { exceed: true, text: t("claude.burn_pace_exceed", "At this pace: 100% in {time}", { time: formatMinutes(minTo100) }) };
        }
        return { exceed: false, text: t("claude.burn_pace_ok", "Usage on pace for this window") };
    }

    readonly property var claudeBurnForecast: {
        staleTickMs;
        return windowBurnForecast(claudeFiveHourUtil, claudeFiveHourReset, 300);
    }

    readonly property var claudeWeekBurnForecast: {
        staleTickMs;
        return windowBurnForecast(claudeSevenDayUtil, claudeSevenDayReset, 10080);
    }

    readonly property real claudeMonthProjection: {
        const today = new Date();
        const dayOfMonth = today.getDate();
        if (dayOfMonth <= 0 || claudeMonthCost <= 0) return 0;
        const daysInMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
        return (claudeMonthCost / dayOfMonth) * daysInMonth;
    }

    function providerConsoleUrl(providerId) {
        const urls = {
            claude: "https://claude.ai/settings/usage",
            codex: "https://chatgpt.com/codex/settings/usage",
            copilot: "https://github.com/settings/copilot/features",
            gemini: "https://aistudio.google.com/usage",
            openrouter: "https://openrouter.ai/activity",
            deepseek: "https://platform.deepseek.com/usage",
            kimi: "https://platform.kimi.ai/console",
            moonshot: "https://platform.kimi.ai/console",
            mistral: "https://console.mistral.ai/usage",
            glm: "https://open.bigmodel.cn/usercenter/financial",
            zhipu: "https://open.bigmodel.cn/usercenter/financial",
            zai: "https://z.ai/manage-apikey/billing",
            minimax: "https://platform.minimax.io/user-center/payment/balance",
            qwen: "https://dashscope.console.aliyun.com",
            dashscope: "https://dashscope.console.aliyun.com",
            alibaba: "https://dashscope.console.aliyun.com",
            nvidia: "https://build.nvidia.com",
            nim: "https://build.nvidia.com",
            cloudflare: "https://dash.cloudflare.com",
            vertexai: "https://console.cloud.google.com/vertex-ai",
            vertex: "https://console.cloud.google.com/vertex-ai",
            byteplus: "https://console.volcengine.com",
            ark: "https://console.volcengine.com",
            modelark: "https://console.volcengine.com",
            together: "https://api.together.ai/settings/billing",
            groq: "https://console.groq.com/usage",
            cohere: "https://dashboard.cohere.com/billing",
            replicate: "https://replicate.com/account/billing",
            fireworks: "https://app.fireworks.ai",
            ai21: "https://studio.ai21.com",
            xai: "https://console.x.ai/billing",
            grok: "https://console.x.ai/billing",
            perplexity: "https://www.perplexity.ai/settings/billing",
            cursor: "https://cursor.com/settings",
            cline: "https://app.cline.bot",
            opencode: "https://opencode.ai",
            kilo: "https://app.kilo.ai/credits",
            kiro: "https://app.kiro.dev/settings/account",
            warp: "https://app.warp.dev",
            amp: "https://ampcode.com"
        };
        return urls[providerId] || "";
    }

    function openProviderConsole(providerId) {
        const url = providerConsoleUrl(providerId);
        if (url.length > 0) Quickshell.execDetached(["xdg-open", url]);
    }

    function isPinned(providerId) {
        return pinnedProviders.indexOf(normalizeProviderId(providerId)) >= 0;
    }

    function togglePin(providerId) {
        const id = normalizeProviderId(providerId);
        const next = pinnedProviders.slice();
        const index = next.indexOf(id);
        if (index >= 0) next.splice(index, 1);
        else next.push(id);
        pinnedProvidersCsv = next.join(",");
        PluginService.savePluginData("aiOverviewControl", "pinnedProviders", pinnedProvidersCsv);
    }

    // Trend over the last two recorded snapshots: "up" | "down" | "flat" | "".
    function historyPercent(entry) {
        return Number(entry && entry.p !== undefined ? entry.p : entry) || 0;
    }

    function providerTrend(providerId) {
        const history = usageHistory[normalizeProviderId(providerId)];
        if (!history || history.length < 2) return "";
        const delta = historyPercent(history[history.length - 1]) - historyPercent(history[history.length - 2]);
        if (delta >= 1) return "up";
        if (delta <= -1) return "down";
        return "flat";
    }

    function retryProvider(providerId) {
        if (procRetry.running) return;
        retryingProviderId = normalizeProviderId(providerId);
        retryBuffer = "";
        procRetry.command = ["bash", providerUsageScript, retryingProviderId, copilotUsageScript];
        procRetry.running = true;
    }

    function checkNotifications() {
        if (!notifyEnabled) return;
        const seen = notifiedMap;
        for (let i = 0; i < successfulProviders.length; i++) {
            const provider = successfulProviders[i];
            const windowData = primaryUsageWindow(provider);
            if (!windowData) continue;
            const percent = Number(windowData.usedPercent || 0);
            const threshold = thresholdFor(provider.provider);
            // Key includes the reset timestamp so a new window re-arms the alert.
            const dedupeKey = `${provider.provider}:${windowData.resetsAt || "static"}:${threshold}`;
            if (percent < threshold - 5) {
                // Usage dropped well below the threshold (window reset): clear
                // the persisted entry so the next crossing alerts again. The
                // 5pp hysteresis band avoids notify/clear flapping right at
                // the threshold. Matters mostly for "static" keys (null
                // resetsAt) that would otherwise never re-arm. Unconditional
                // because the on-disk entry may have been written by another
                // instance or before a reload; the helper exits early when
                // the key is absent.
                delete seen[dedupeKey];
                Quickshell.execDetached(["bash", notifyAlertScript, "--clear", dedupeKey]);
                continue;
            }
            if (percent < threshold || seen[dedupeKey]) continue;
            seen[dedupeKey] = true;

            const pct = Math.round(percent);
            const exhausted = pct >= 100;
            const reset = formatTimeUntil(windowData.resetsAt);
            const windowLabel = windowData.resetDescription || getWindowLabel(windowData.windowMinutes) || t("status.usage", "usage");
            const display = String(windowData.displayValue || "").trim();

            const title = exhausted
                ? t("notify.title_exhausted", "{provider} — quota exhausted", { provider: providerName(provider.provider) })
                : t("notify.title", "{provider} at {percent}%", { provider: providerName(provider.provider), percent: pct });
            const bodyParts = [windowLabel];
            if (display.length > 0 && display !== windowLabel) bodyParts.push(display);
            if (reset.length > 0) bodyParts.push(t("notify.resets_in", "resets in {time}", { time: reset }));

            // The helper persists state on disk (flock-guarded), so duplicate
            // widget instances, plugin reloads and shell restarts cannot
            // re-fire inside the cooldown window. `seen` stays as a cheap
            // in-process fast path only.
            Quickshell.execDetached([
                "bash", notifyAlertScript,
                dedupeKey,
                String(notifyCooldownSecs),
                exhausted ? "critical" : "normal",
                exhausted ? "dialog-error" : "dialog-warning",
                title,
                bodyParts.join(" · ")
            ]);
        }
        notifiedMap = seen;
    }

    function projectDisplayName(path) {
        const text = String(path || "");
        const parts = text.split("/");
        const tail = parts[parts.length - 1];
        return tail.length > 0 ? tail : text;
    }

    function detectBinary() {
        if (procDetect.running) {
            return;
        }
        binaryReady = false;
        hasError = false;
        errorMessage = "";
        procDetect.running = true;
    }

    Component.onCompleted: {
        // Re-read i18n bundles: the I18n singleton survives plugin hot-reloads,
        // so its cache can hold a stale bundle from when the shell first started.
        // Guarded because the singleton itself is frozen at process start — a
        // session whose singleton predates refresh() simply skips this (a full
        // shell restart already loads fresh bundles anyway).
        if (typeof AiOverviewControlI18n.refresh === "function") {
            AiOverviewControlI18n.refresh();
        }
        // Resolve plugin dir imperatively — only reliable from within the component's own context
        // 1. Try PluginService (authoritative, case-correct)
        if (pluginService && pluginId) {
            const fromService = pluginService.getPluginPath(pluginId);
            if (fromService && fromService.length > 0) {
                _pluginDir = fromService;
            }
        }
        // 2. Fallback: derive from this file's URL (Qt.resolvedUrl is reliable here)
        if (!_pluginDir) {
            const selfUrl = Qt.resolvedUrl("AiOverviewControlWidget.qml").toString();
            const withoutScheme = selfUrl.startsWith("file://") ? selfUrl.substring(7) : selfUrl;
            const lastSlash = withoutScheme.lastIndexOf("/");
            _pluginDir = lastSlash !== -1 ? withoutScheme.substring(0, lastSlash) : withoutScheme;
        }
        detectBinary();
    }

    Process {
        id: procDetect
        command: ["sh", "-c", "[ -x \"$1\" ] && command -v bash >/dev/null && command -v jq >/dev/null && command -v curl >/dev/null", "sh", root.providerUsageScript]
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

    // Snapshot of the argv for the in-flight fetch. Set imperatively in
    // refresh() instead of a reactive binding so a change to selectedProviders
    // while a request is in flight cannot mutate the running
    // process's command (Qt behaviour on command change while running is
    // undefined and would scramble the fetch).
    property var usageCommand: ["bash", root.providerUsageScript, root.selectedProviders.join(","), root.copilotUsageScript]

    property string historyRetention: {
        const parsed = parseInt(pluginData.historyRetention || "2000");
        return String(Number.isFinite(parsed) && parsed >= 50 ? parsed : 2000);
    }

    Process {
        id: procUsage
        command: root.usageCommand
        environment: { "AIOC_HISTORY_MAX": root.historyRetention }
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
                        const firstErr = root.errorProviders[0].error;
                        const firstErrMsg = (firstErr && typeof firstErr === "object") ? firstErr.message : (typeof firstErr === "string" ? firstErr : "");
                        root.errorMessage = firstErrMsg || t("error.fetch_failed", "Failed to fetch usage from providers.");
                    } else {
                        root.hasError = false;
                        root.errorMessage = root.errorProviders.length > 0 ? t("error.providers_need_attention", "{count} provider(s) need attention.", { count: root.errorProviders.length }) : "";
                    }
                    const nowMs = Date.now();
                    root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm:ss");
                    root.lastUpdatedMs = nowMs;
                    root.checkNotifications();
                    if (!procHistory.running) {
                        root.historyBuffer = "";
                        procHistory.running = true;
                    }
                } catch (error) {
                    root.hasError = true;
                    root.errorMessage = root.rawStderrBuffer.length > 0 ? root.rawStderrBuffer : t("error.parse_failed", "Failed to parse provider helper output.");
                }
            } else if (code === 0) {
                // Exited cleanly but produced no JSON — surface an explicit
                // empty state instead of silently keeping stale providers.
                root.providers = [];
                root.hasError = false;
                root.errorMessage = root.rawStderrBuffer.length > 0 ? root.rawStderrBuffer : "";
                root.lastUpdated = Qt.formatDateTime(new Date(), "hh:mm:ss");
                root.lastUpdatedMs = Date.now();
            } else {
                root.hasError = true;
                root.errorMessage = root.formatUsageError(code);
            }

            root.rawJsonBuffer = "";
            root.rawStderrBuffer = "";
        }
    }

    Process {
        id: procHistory
        command: ["bash", root.usageHistoryScript]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root.historyBuffer += data
        }
        onExited: code => {
            if (code !== 0 || root.historyBuffer.length === 0) {
                root.historyBuffer = "";
                return;
            }
            try {
                root.usageHistory = JSON.parse(root.historyBuffer);
            } catch (error) {
                // Corrupt history cache: ignore, sparklines simply stay hidden.
            }
            root.historyBuffer = "";
        }
    }

    Process {
        id: procRetry
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root.retryBuffer += data
        }
        onExited: code => {
            const targetId = root.retryingProviderId;
            root.retryingProviderId = "";
            if (code !== 0 || root.retryBuffer.length === 0) {
                root.retryBuffer = "";
                return;
            }
            try {
                const payload = JSON.parse(root.retryBuffer);
                const list = Array.isArray(payload) ? payload : [payload];
                if (list.length > 0 && list[0] && list[0].provider === targetId) {
                    const next = root.providers.slice();
                    for (let i = 0; i < next.length; i++) {
                        if (next[i] && next[i].provider === targetId) {
                            next[i] = list[0];
                            break;
                        }
                    }
                    root.providers = next;
                    root.checkNotifications();
                }
            } catch (error) {
                // Keep the previous card state on parse failure.
            }
            root.retryBuffer = "";
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
            claudeTimeout.stop();
            // Track the claude detail-fetch state independently of focus so a
            // failure is not silently swallowed when claude isn't focused.
            root.claudeStatsError = (code !== 0);
            if (code !== 0 && root.focusedProviderId === "claude") {
                root.errorMessage = t("error.claude_unavailable", "Claude Code usage details are unavailable. Check claude, jq, and curl.");
            }
        }
    }

    Timer {
        id: claudeTimeout
        interval: root.fetchTimeoutMs
        repeat: false
        onTriggered: {
            if (claudeStatsProcess.running) {
                claudeStatsProcess.running = false;
                root.claudeStatsError = true;
                if (root.focusedProviderId === "claude") {
                    root.errorMessage = t("error.claude_timeout", "Claude Code usage fetch timed out.");
                }
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
        // Snapshot argv now so an in-flight selection change cannot mutate the
        // running process command (see usageCommand declaration).
        usageCommand = ["bash", providerUsageScript, selectedProviders.join(","), copilotUsageScript];
        procUsage.running = true;
        usageTimeout.restart();
        if (root.selectedProviders.indexOf("claude") >= 0 && !claudeStatsProcess.running) {
            claudeStatsError = false;
            claudeStatsProcess.running = true;
            claudeTimeout.restart();
        }
        if (root.selectedProviders.indexOf("9router") >= 0 && !nineStatsProcess.running) {
            nineStatsBuffer = "";
            nineStatsProcess.running = true;
        }
    }

    Process {
        id: nineStatsProcess
        command: ["bash", root.nineRouterAnalyticsScript]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root.nineStatsBuffer += data
        }
        onExited: code => {
            if (code !== 0 || root.nineStatsBuffer.length === 0) {
                root.nineStatsBuffer = "";
                return;
            }
            try {
                const parsed = JSON.parse(root.nineStatsBuffer);
                root.nineStats = (parsed && !parsed.error) ? parsed : null;
            } catch (error) {
                // Keep the previous snapshot; the section simply stays as-is.
            }
            root.nineStatsBuffer = "";
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

    property int staleTickMs: 0
    Timer {
        id: staleClock
        interval: 10000
        running: root.binaryReady
        repeat: true
        onTriggered: root.staleTickMs = Date.now()
    }

    // ── In-popout navigation ──────────────────────────────────────────────────
    // focusProvider() expands a provider's dashboard card and scrolls the popout
    // to it, so the hero / fleet-rollup elements can act as jump links. The
    // scroll is deferred one tick (scrollFocusTimer) so the card's expand
    // animation settles before we measure its position. The id lookups
    // (contentFlick / providerCardsRepeater / contentColumn) resolve only when
    // the popout is instantiated — guarded because the bar pill can call nothing
    // here while the popout is closed.
    property string pendingScrollProviderId: ""

    function focusProvider(id) {
        if (!id || id.length === 0) {
            return;
        }
        root.focusedProviderId = id;
        root.providerStatusFilter = "all";
        root.providerFilter = "";
        root.pendingScrollProviderId = id;
        scrollFocusTimer.restart();
    }

    Timer {
        // Wait out the card's implicitHeight expand/collapse animation (220ms)
        // so positions are settled before we measure and scroll.
        id: scrollFocusTimer
        interval: 260
        repeat: false
        onTriggered: {
            const id = root.pendingScrollProviderId;
            if (!id || id.length === 0) {
                return;
            }
            if (typeof contentFlick === "undefined" || !contentFlick
                || typeof providerCardsRepeater === "undefined" || !providerCardsRepeater) {
                return;
            }
            for (let i = 0; i < providerCardsRepeater.count; i++) {
                const item = providerCardsRepeater.itemAt(i);
                if (item && item.provider && item.provider.provider === id) {
                    const y = item.mapToItem(contentColumn, 0, 0).y;
                    const maxY = Math.max(0, contentFlick.contentHeight - contentFlick.height);
                    const target = Math.min(Math.max(0, y - Theme.spacingM), maxY);
                    scrollFocusAnim.target = contentFlick;
                    scrollFocusAnim.from = contentFlick.contentY;
                    scrollFocusAnim.to = target;
                    scrollFocusAnim.restart();
                    break;
                }
            }
        }
    }

    NumberAnimation {
        id: scrollFocusAnim
        property: "contentY"
        duration: 360
        easing.type: Easing.OutCubic
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
        signal tapped

        implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
        implicitHeight: 28
        radius: 999
        color: emphasized ? Theme.withAlpha(accentColor, 0.16) : Theme.withAlpha(accentColor, 0.1)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, emphasized ? 0.3 : 0.18)

        TapHandler {
            onTapped: pill.tapped()
        }

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

    component InfoPill: StyledRect {
        id: ipill

        required property string label
        required property string value
        property color accentColor: Theme.primary
        property string iconName: ""

        implicitWidth: Math.min(ipillRow.implicitWidth + Theme.spacingM * 2, parent ? parent.width : 9999)
        implicitHeight: 26
        radius: 999
        color: Theme.withAlpha(accentColor, 0.08)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, 0.16)

        Row {
            id: ipillRow
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            DankIcon {
                visible: ipill.iconName.length > 0
                name: ipill.iconName
                size: 12
                color: ipill.accentColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: ipill.label
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: Math.min(implicitWidth, ipillRow.width - x)
                text: ipill.value.length > 0 ? ipill.value : "—"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
                elide: Text.ElideRight
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
            anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - Theme.spacingS * 2
            radius: width / 2
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

    component ProgressRing: Item {
        id: ring

        property real percent: 0
        property real thickness: 6
        property color accentColor: Theme.primary
        property color trackColor: Theme.withAlpha(Theme.surfaceText, 0.08)
        // Indirection so the arc sweeps smoothly instead of snapping when new
        // data lands.
        property real animatedPercent: percent

        Behavior on animatedPercent {
            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
        }

        onAnimatedPercentChanged: ringCanvas.requestPaint()
        onAccentColorChanged: ringCanvas.requestPaint()
        onTrackColorChanged: ringCanvas.requestPaint()
        onWidthChanged: ringCanvas.requestPaint()
        onHeightChanged: ringCanvas.requestPaint()

        Canvas {
            id: ringCanvas
            anchors.fill: parent
            antialiasing: true
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2;
                const cy = height / 2;
                const radius = Math.min(width, height) / 2 - ring.thickness / 2;
                if (radius <= 0) return;
                const start = -Math.PI / 2;
                const sweep = Math.max(0, Math.min(1, ring.animatedPercent / 100)) * Math.PI * 2;
                ctx.lineWidth = ring.thickness;
                ctx.lineCap = "round";
                ctx.strokeStyle = String(ring.trackColor);
                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, Math.PI * 2);
                ctx.stroke();
                if (sweep > 0.001) {
                    ctx.strokeStyle = String(ring.accentColor);
                    ctx.beginPath();
                    ctx.arc(cx, cy, radius, start, start + sweep);
                    ctx.stroke();
                }
            }
        }
    }

    component Sparkline: Item {
        id: spark

        // Points are {t: epochSeconds, p: percent} objects, oldest first.
        property var points: []
        property color lineColor: Theme.primary
        property int hoverIndex: -1

        readonly property real pad: 3
        readonly property real stepX: points && points.length > 1 ? (width - pad * 2) / (points.length - 1) : 0

        function pointPercent(index) {
            const entry = (points || [])[index];
            return Number(entry && entry.p !== undefined ? entry.p : entry) || 0;
        }

        function pointTime(index) {
            const entry = (points || [])[index];
            return entry && entry.t ? Number(entry.t) * 1000 : 0;
        }

        onPointsChanged: sparkCanvas.requestPaint()
        onLineColorChanged: sparkCanvas.requestPaint()
        onHoverIndexChanged: sparkCanvas.requestPaint()
        onWidthChanged: sparkCanvas.requestPaint()
        onHeightChanged: sparkCanvas.requestPaint()

        Canvas {
            id: sparkCanvas
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const pts = spark.points || [];
                if (pts.length < 2 || width <= 4 || height <= 4) return;
                const pad = spark.pad;
                const w = width - pad * 2;
                const h = height - pad * 2;
                let max = 10;
                for (let i = 0; i < pts.length; i++) max = Math.max(max, spark.pointPercent(i));
                const stepX = w / (pts.length - 1);
                const yFor = v => pad + h - (Math.max(0, Math.min(max, v)) / max) * h;

                ctx.beginPath();
                ctx.moveTo(pad, yFor(spark.pointPercent(0)));
                for (let i = 1; i < pts.length; i++) ctx.lineTo(pad + i * stepX, yFor(spark.pointPercent(i)));
                const line = String(spark.lineColor);
                ctx.strokeStyle = line;
                ctx.lineWidth = 2;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.stroke();

                // Soft area fill under the line
                ctx.lineTo(pad + w, pad + h);
                ctx.lineTo(pad, pad + h);
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(spark.lineColor.r, spark.lineColor.g, spark.lineColor.b, 0.12);
                ctx.fill();

                // Highlighted (hovered) or last point dot
                const dotIndex = spark.hoverIndex >= 0 && spark.hoverIndex < pts.length ? spark.hoverIndex : pts.length - 1;
                ctx.beginPath();
                ctx.arc(pad + dotIndex * stepX, yFor(spark.pointPercent(dotIndex)), spark.hoverIndex >= 0 ? 3.4 : 2.6, 0, Math.PI * 2);
                ctx.fillStyle = line;
                ctx.fill();
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: mouse => {
                if (spark.stepX <= 0) return;
                const index = Math.round((mouse.x - spark.pad) / spark.stepX);
                spark.hoverIndex = Math.max(0, Math.min((spark.points || []).length - 1, index));
            }
            onExited: spark.hoverIndex = -1
        }

        Rectangle {
            visible: spark.hoverIndex >= 0
            x: Math.max(0, Math.min(parent.width - width, spark.pad + spark.hoverIndex * spark.stepX - width / 2))
            y: -height - 2
            implicitWidth: hoverLabel.implicitWidth + Theme.spacingS * 2
            implicitHeight: 20
            radius: 10
            color: Theme.surfaceContainerHighest
            border.width: 1
            border.color: Theme.withAlpha(spark.lineColor, 0.4)

            StyledText {
                id: hoverLabel
                anchors.centerIn: parent
                text: spark.hoverIndex >= 0
                    ? `${Math.round(spark.pointPercent(spark.hoverIndex))}%${spark.pointTime(spark.hoverIndex) > 0 ? " · " + Qt.formatDateTime(new Date(spark.pointTime(spark.hoverIndex)), "hh:mm") : ""}`
                    : ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
            }
        }
    }

    component HeroStat: Row {
        id: heroStat

        required property string statIcon
        required property string statLabel
        required property string statValue
        property color statAccent: Theme.primary

        spacing: Theme.spacingS

        Rectangle {
            width: 34
            height: 34
            radius: 11
            color: Theme.withAlpha(heroStat.statAccent, 0.12)
            border.width: 1
            border.color: Theme.withAlpha(heroStat.statAccent, 0.2)
            anchors.verticalCenter: parent.verticalCenter

            DankIcon {
                anchors.centerIn: parent
                name: heroStat.statIcon
                size: 16
                color: heroStat.statAccent
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            StyledText {
                text: heroStat.statValue
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
            }

            StyledText {
                text: heroStat.statLabel
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
            }
        }
    }

    component PillProgressRing: Canvas {
        id: ring

        property real percent: 0
        property color accent: Theme.primary

        width: 20
        height: 20
        renderStrategy: Canvas.Cooperative
        onPercentChanged: requestPaint()
        onAccentChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2;
            const cy = height / 2;
            const r = 7.5;
            const lw = 2.5;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
            ctx.lineWidth = lw;
            ctx.strokeStyle = Theme.withAlpha(ring.accent, 0.2);
            ctx.stroke();
            const pct = percent / 100;
            if (pct > 0) {
                ctx.beginPath();
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1));
                ctx.lineWidth = lw;
                ctx.strokeStyle = ring.accent;
                ctx.lineCap = "round";
                ctx.stroke();
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
                anchors.verticalCenter: parent.verticalCenter

                PillProgressRing {
                    anchors.centerIn: parent
                    percent: root.primaryPercent
                    accent: root.heroAccent
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                visible: !root.hasError || root.hasProviderData

                Repeater {
                    model: root.pillDisplayProviders.length > 0 ? root.pillDisplayProviders : (root.hasProviderData ? [root.providerData] : [])

                    Row {
                        id: pillEntry
                        required property var modelData
                        required property int index
                        readonly property color usageColor: root.getUsageColor(root.providerPercent(modelData))
                        spacing: 4

                        StyledText {
                            visible: pillEntry.index > 0
                            text: " · "
                            color: Theme.withAlpha(Theme.surfaceText, 0.3)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            color: root.providerAccent(pillEntry.modelData.provider)
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        StyledText {
                            text: root.providerName(pillEntry.modelData.provider)
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: `${Math.round(root.providerPercent(pillEntry.modelData))}%`
                            color: pillEntry.usageColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            StyledText {
                visible: root.hasError && !root.hasProviderData
                text: root.isLoading ? "..." : "ERR"
                color: root.isLoading ? Theme.surfaceVariantText : Theme.error
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

                PillProgressRing {
                    anchors.centerIn: parent
                    percent: root.primaryPercent
                    accent: root.heroAccent
                }
            }

            Repeater {
                model: root.pillDisplayProviders.length > 0 ? root.pillDisplayProviders : (root.hasProviderData ? [root.providerData] : [])

                StyledText {
                    required property var modelData
                    text: `${Math.round(root.providerPercent(modelData))}%`
                    color: root.providerAccent(modelData.provider)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            StyledText {
                visible: (root.hasError && !root.hasProviderData) || (root.pillDisplayProviders.length === 0 && !root.hasProviderData)
                text: root.isLoading ? "..." : (root.hasError ? "ERR" : "N/A")
                color: root.hasError ? Theme.error : Theme.surfaceVariantText
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
                id: dayColumn
                width: (dailyBars.width - Theme.spacingS * 6) / 7
                spacing: 7

                Rectangle {
                    width: parent.width
                    height: 66
                    radius: Theme.cornerRadius - 2
                    color: Theme.surfaceContainer
                    border.width: dayHover.containsMouse ? 1 : 0
                    border.color: Theme.withAlpha(index === root.currentWeekdayIndex ? Theme.warning : Theme.primary, 0.5)
                    clip: true

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(3, (Number(root.claudeDailyTokens[index] || 0) / dailyBars.maxDaily) * parent.height)
                        color: index === root.currentWeekdayIndex ? Theme.warning : Theme.withAlpha(Theme.primary, dayHover.containsMouse ? 0.75 : 0.55)

                        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Rectangle {
                        visible: dayHover.containsMouse
                        anchors.fill: parent
                        radius: parent.radius
                        color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.93)

                        Column {
                            anchors.centerIn: parent
                            spacing: 1

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.formatTokens(root.claudeDailyTokens[index] || 0)
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.formatCost(root.claudeDailyCosts[index] || 0)
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall - 1
                            }
                        }
                    }

                    MouseArea {
                        id: dayHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }

                StyledText {
                    width: parent.width
                    text: root.dayLabels[index]
                    horizontalAlignment: Text.AlignHCenter
                    color: dayHover.containsMouse ? Theme.surfaceText : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    component ProviderDashboardCard: StyledRect {
        id: card
        required property var provider
        property bool expanded: root.allExpanded || (!!provider && provider.provider === root.focusedProviderId)
        property bool hasUsage: !!provider && !!provider.usage && !provider.error
        property color accentColor: provider && provider.error ? Theme.error : root.providerAccent(provider ? provider.provider : "")
        property var windows: root.windowsForProvider(provider)
        property bool compact: width < 560
        property bool veryCompact: width < 430
        property bool dense: root.densityMode === "compact"
        property bool hovered: cardMouse.containsMouse
        readonly property bool isStale: {
            root.staleTickMs;
            const updated = root.providerUpdatedMs(provider);
            return updated > 0 && (Date.now() - updated) > root.refreshIntervalMs * 2;
        }

        function toggleExpanded() {
            if (root.allExpanded) {
                root.allExpanded = false;
                root.focusedProviderId = card.provider.provider;
                return;
            }
            root.focusedProviderId = card.expanded ? "" : card.provider.provider;
        }

        width: parent ? parent.width : implicitWidth
        radius: Theme.cornerRadius + 4
        color: expanded ? Theme.surfaceContainerHigh : (hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
        border.width: 1
        border.color: {
            if (card.activeFocus) return Theme.primary;
            if (provider && provider.error) return Theme.withAlpha(Theme.error, expanded ? 0.34 : 0.16);
            return Theme.withAlpha(accentColor, expanded ? 0.42 : (hovered ? 0.26 : 0.07));
        }
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.providerName(provider ? provider.provider : "")
        Accessible.description: root.providerSubtitle(provider)
        Keys.onReturnPressed: toggleExpanded()
        Keys.onSpacePressed: toggleExpanded()
        Keys.onDeletePressed: {
            if (root.selectedProviders.length > 1) root.removeProvider(card.provider.provider);
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_P) {
                root.togglePin(card.provider.provider);
                event.accepted = true;
            } else if (event.key === Qt.Key_R && card.provider.error) {
                root.retryProvider(card.provider.provider);
                event.accepted = true;
            }
        }
        implicitHeight: cardColumn.implicitHeight + (card.dense ? Theme.spacingS : (card.compact ? Theme.spacingM : Theme.spacingL)) * 2
        clip: true
        scale: hovered ? 1.006 : 1.0

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            opacity: expanded || hovered ? 1 : 0.32
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(card.accentColor, expanded ? 0.12 : 0.055) }
                GradientStop { position: 0.52; color: Theme.withAlpha(card.accentColor, 0.025) }
                GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.0) }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: expanded ? parent.height - Theme.spacingM * 2 : parent.height * 0.34
            radius: width / 2
            visible: expanded || card.hovered || card.activeFocus
            color: Theme.withAlpha(card.accentColor, expanded ? 0.95 : 0.55)
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Column {
            id: cardColumn
            z: 2
            anchors.fill: parent
            anchors.margins: card.dense ? Theme.spacingS : (card.compact ? Theme.spacingS : Theme.spacingM)
            spacing: expanded ? (card.dense ? Theme.spacingS : Theme.spacingM) : Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: card.compact ? Theme.spacingS : Theme.spacingL

                Item {
                    Layout.alignment: Qt.AlignTop
                    visible: !card.veryCompact
                    width: card.dense ? 34 : (card.compact ? 38 : 46)
                    height: width

                    ProgressRing {
                        anchors.fill: parent
                        visible: card.hasUsage
                        percent: root.providerPercent(card.provider)
                        thickness: 2.5
                        accentColor: root.getUsageColor(root.providerPercent(card.provider))
                        trackColor: Theme.withAlpha(card.accentColor, 0.14)
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: width / 2
                        color: Theme.withAlpha(card.accentColor, 0.14)
                        border.width: card.hasUsage ? 0 : 1
                        border.color: Theme.withAlpha(card.accentColor, 0.4)

                        DankIcon {
                            anchors.centerIn: parent
                            name: root.iconForProvider(card.provider.provider)
                            size: card.dense ? 15 : (card.compact ? 17 : 20)
                            color: card.accentColor
                        }
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: card.dense ? 3 : 6

                    StyledText {
                        width: parent.width
                        text: root.providerName(card.provider.provider)
                        color: Theme.surfaceText
                        font.pixelSize: card.dense ? Theme.fontSizeSmall : (card.compact ? Theme.fontSizeSmall + 1 : Theme.fontSizeMedium)
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

                        BadgePill {
                            visible: card.isStale
                            label: root.t("status.stale", "Stale")
                            iconName: "schedule"
                            accentColor: Theme.warning
                            emphasized: true
                        }

                        BadgePill {
                            visible: !!card.provider.error
                            label: root.retryingProviderId === card.provider.provider ? "…" : root.t("card.retry", "Retry")
                            iconName: "refresh"
                            accentColor: Theme.error
                            emphasized: true
                            onTapped: root.retryProvider(card.provider.provider)
                        }
                    }
                }

                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3

                    DankIcon {
                        readonly property string trend: root.providerTrend(card.provider ? card.provider.provider : "")
                        visible: !card.provider.error && trend.length > 0 && trend !== "flat"
                        name: trend === "up" ? "trending_up" : "trending_down"
                        size: card.compact ? 15 : 17
                        color: trend === "up" ? Theme.warning : Theme.success
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: card.provider.error ? t("status.error", "Error") : `${Math.round(root.providerPercent(card.provider))}%`
                        color: card.provider.error ? Theme.error : root.getUsageColor(root.providerPercent(card.provider))
                        font.pixelSize: card.compact ? Theme.fontSizeMedium : Theme.fontSizeLarge
                        font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    z: 2
                    width: card.compact ? 30 : 34
                    height: width
                    radius: width / 2
                    color: pinArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.14) : (root.isPinned(card.provider.provider) ? Theme.withAlpha(Theme.primary, 0.1) : "transparent")
                    border.width: root.isPinned(card.provider.provider) ? 1 : 0
                    border.color: Theme.withAlpha(Theme.primary, 0.3)

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.isPinned(card.provider.provider) ? "star" : "star_border"
                        size: card.compact ? 15 : 17
                        color: root.isPinned(card.provider.provider) ? Theme.primary : Theme.surfaceVariantText
                    }

                    MouseArea {
                        id: pinArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            mouse.accepted = true;
                            root.togglePin(card.provider.provider);
                        }
                    }
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
                    name: "keyboard_arrow_down"
                    size: card.compact ? 24 : 28
                    color: card.expanded ? card.accentColor : Theme.surfaceVariantText
                    rotation: card.expanded ? 180 : 0

                    Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 160 } }
                }
            }

            UsageBar {
                visible: card.hasUsage && !card.expanded && !card.dense
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

                Column {
                    readonly property var historyPoints: root.usageHistory[card.provider.provider] || []
                    visible: card.hasUsage && historyPoints.length >= 2
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: t("card.history", "History")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall - 1
                        font.weight: Font.Medium
                    }

                    Sparkline {
                        width: parent.width
                        height: 38
                        points: parent.historyPoints
                        lineColor: root.getUsageColor(root.providerPercent(card.provider))
                    }
                }

                Flow {
                    visible: card.hasUsage
                    width: parent.width
                    spacing: Theme.spacingXS

                    InfoPill {
                        iconName: "person"
                        label: t("card.account", "Account")
                        value: root.providerAccount(card.provider)
                        accentColor: card.accentColor
                    }

                    InfoPill {
                        iconName: "vpn_key"
                        label: t("card.login", "Login")
                        value: root.providerLogin(card.provider)
                        accentColor: card.accentColor
                    }

                    InfoPill {
                        visible: root.providerCredits(card.provider) !== "—"
                        iconName: "toll"
                        label: t("card.credits", "Credits")
                        value: root.providerCredits(card.provider)
                        accentColor: card.accentColor
                    }
                }

                SurfaceButton {
                    visible: root.providerConsoleUrl(card.provider.provider).length > 0
                    iconName: "open_in_new"
                    label: t("card.open_console", "Open console")
                    compact: true
                    onTriggered: root.openProviderConsole(card.provider.provider)
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

                            BadgePill {
                                visible: root.claudeExtraUsageEnabled
                                label: t("card.extra_usage_on", "Extra usage on")
                                iconName: "add_circle"
                                accentColor: Theme.warning
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
                            aside: {
                                const reset = root.formatTimeUntil(root.claudeSevenDayReset);
                                return reset.length > 0 ? `${Math.round(root.claudeSevenDayUtil)}% · ${reset}` : `${Math.round(root.claudeSevenDayUtil)}%`;
                            }
                            accentColor: root.getUsageColor(root.claudeSevenDayUtil)
                        }

                        Row {
                            visible: !!root.claudeWeekBurnForecast && root.claudeWeekBurnForecast.exceed
                            spacing: Theme.spacingXS

                            DankIcon {
                                name: "local_fire_department"
                                size: 14
                                color: Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.claudeWeekBurnForecast ? root.claudeWeekBurnForecast.text : ""
                                color: Theme.error
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        UsageBar {
                            width: parent.width
                            label: "5h"
                            percent: root.claudeFiveHourUtil
                            aside: {
                                const reset = root.formatTimeUntil(root.claudeFiveHourReset);
                                return reset.length > 0 ? `${Math.round(root.claudeFiveHourUtil)}% · ${reset}` : `${Math.round(root.claudeFiveHourUtil)}%`;
                            }
                            accentColor: root.getUsageColor(root.claudeFiveHourUtil)
                        }

                        Row {
                            visible: !!root.claudeBurnForecast
                            spacing: Theme.spacingXS

                            DankIcon {
                                name: root.claudeBurnForecast && root.claudeBurnForecast.exceed ? "local_fire_department" : "check_circle"
                                size: 14
                                color: root.claudeBurnForecast && root.claudeBurnForecast.exceed ? Theme.error : Theme.success
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.claudeBurnForecast ? root.claudeBurnForecast.text : ""
                                color: root.claudeBurnForecast && root.claudeBurnForecast.exceed ? Theme.error : Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: root.claudeBurnForecast && root.claudeBurnForecast.exceed ? Font.DemiBold : Font.Normal
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        GridLayout {
                            width: parent.width
                            columns: card.width < 520 ? 1 : (card.width < 760 ? 2 : 4)
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            MetricTile { Layout.fillWidth: true; label: t("card.today_tokens", "Today tokens"); value: root.formatTokens(root.claudeDailyTokens[root.currentWeekdayIndex] || 0); accentColor: Theme.warning }
                            MetricTile { Layout.fillWidth: true; label: t("card.today_cost", "Today cost"); value: root.formatCost(root.claudeTodayCost); accentColor: Theme.warning }
                            MetricTile { Layout.fillWidth: true; label: t("card.week", "Week"); value: `${root.formatTokens(root.claudeWeekTokens)} · ${root.formatCost(root.claudeWeekCost)}`; accentColor: Theme.warning }
                            MetricTile { Layout.fillWidth: true; label: t("card.month", "Month"); value: `${root.formatTokens(root.claudeMonthTokens)} · ${root.formatCost(root.claudeMonthCost)}`; accentColor: Theme.warning }
                            MetricTile { Layout.fillWidth: true; visible: root.claudeMonthProjection > 0; label: t("card.projected_month", "Projected month"); value: `≈ ${root.formatCost(root.claudeMonthProjection)}`; accentColor: root.claudeMonthProjection > root.claudeMonthCost * 1.5 ? Theme.error : Theme.warning }
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
                                    required property real modelCost
                                    width: parent.width
                                    label: modelName
                                    percent: root.claudeWeekTokens > 0 ? (modelTokens / root.claudeWeekTokens) * 100 : 0
                                    aside: modelCost > 0 ? `${root.formatTokens(modelTokens)} · ${root.formatCost(modelCost)}` : root.formatTokens(modelTokens)
                                    accentColor: Theme.warning
                                }
                            }
                        }

                        Column {
                            visible: root.showClaudeProjects && claudeProjectList.count > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.top_projects", "Top projects this week")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: claudeProjectList

                                Column {
                                    required property string projectPath
                                    required property real projectTokens
                                    required property int index
                                    width: parent.width
                                    spacing: 3

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        StyledText {
                                            text: root.projectDisplayName(projectPath)
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.compactPath(projectPath)
                                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.7)
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                            elide: Text.ElideLeft
                                        }

                                        StyledText {
                                            text: root.formatTokens(projectTokens)
                                            color: Theme.warning
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 5
                                        radius: 2.5
                                        color: Theme.withAlpha(Theme.surfaceText, 0.06)

                                        Rectangle {
                                            readonly property real topTokens: claudeProjectList.count > 0 ? Math.max(1, claudeProjectList.get(0).projectTokens) : 1
                                            width: Math.max(3, (projectTokens / topTokens) * parent.width)
                                            height: parent.height
                                            radius: parent.radius
                                            color: Theme.withAlpha(Theme.warning, index === 0 ? 0.85 : 0.45)

                                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                        }
                                    }
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

                StyledRect {
                    visible: card.provider.provider === "9router" && root.nineStats !== null
                    width: parent.width
                    radius: Theme.cornerRadius + 2
                    color: Theme.withAlpha(Theme.secondary, 0.08)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.secondary, 0.22)
                    implicitHeight: nineCol.implicitHeight + Theme.spacingL * 2

                    Column {
                        id: nineCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingL

                        readonly property var stats: root.nineStats || ({})
                        readonly property var nineToday: stats.today || ({})
                        readonly property var nineWeek: stats.week || ({})
                        readonly property var nineMonth: stats.month || ({})
                        readonly property var nineDays: stats.days || []
                        readonly property var nineModels: stats.topModels || []
                        readonly property var nineProviders: stats.byProvider || []

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: true
                                text: t("card.nine_details", "9Router telemetry")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                            }

                            StyledText {
                                text: t("card.nine_month_total", "{cost} this month", { cost: root.formatCost(Number(nineCol.nineMonth.cost || 0)) })
                                color: Theme.secondary
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }
                        }

                        GridLayout {
                            width: parent.width
                            columns: card.width < 520 ? 1 : (card.width < 760 ? 2 : 4)
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.nine_today", "Today")
                                value: `${root.formatCost(Number(nineCol.nineToday.cost || 0))} · ${Number(nineCol.nineToday.requests || 0)} req`
                                accentColor: Theme.secondary
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.week", "Week")
                                value: `${root.formatCost(Number(nineCol.nineWeek.cost || 0))} · ${Number(nineCol.nineWeek.requests || 0)} req`
                                accentColor: Theme.secondary
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.month", "Month")
                                value: `${root.formatCost(Number(nineCol.nineMonth.cost || 0))} · ${Number(nineCol.nineMonth.requests || 0)} req`
                                accentColor: Theme.secondary
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.nine_week_tokens", "Week tokens")
                                value: `${root.formatTokens(Number(nineCol.nineWeek.promptTokens || 0))} in · ${root.formatTokens(Number(nineCol.nineWeek.completionTokens || 0))} out`
                                accentColor: Theme.secondary
                            }
                        }

                        // 7-day cost chart, calendar aligned (today is the last bar).
                        Row {
                            id: nineBars
                            width: parent.width
                            spacing: Theme.spacingS

                            readonly property real maxCost: {
                                let top = 0;
                                for (let i = 0; i < nineCol.nineDays.length; i++) {
                                    top = Math.max(top, Number(nineCol.nineDays[i].cost || 0));
                                }
                                return top > 0 ? top : 1;
                            }

                            Repeater {
                                model: nineCol.nineDays

                                Column {
                                    id: nineDayColumn
                                    required property var modelData
                                    required property int index
                                    width: (nineBars.width - Theme.spacingS * 6) / 7
                                    spacing: 7

                                    Rectangle {
                                        width: parent.width
                                        height: 66
                                        radius: Theme.cornerRadius - 2
                                        color: Theme.surfaceContainer
                                        border.width: nineDayHover.containsMouse ? 1 : 0
                                        border.color: Theme.withAlpha(index === 6 ? Theme.warning : Theme.secondary, 0.5)
                                        clip: true

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: Math.max(3, (Number(nineDayColumn.modelData.cost || 0) / nineBars.maxCost) * parent.height)
                                            color: index === 6 ? Theme.warning : Theme.withAlpha(Theme.secondary, nineDayHover.containsMouse ? 0.75 : 0.55)

                                            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }

                                        Rectangle {
                                            visible: nineDayHover.containsMouse
                                            anchors.fill: parent
                                            radius: parent.radius
                                            color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.93)

                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 1

                                                StyledText {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: root.formatCost(Number(nineDayColumn.modelData.cost || 0))
                                                    color: Theme.surfaceText
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: Font.Bold
                                                }

                                                StyledText {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: `${Number(nineDayColumn.modelData.requests || 0)} req`
                                                    color: Theme.surfaceVariantText
                                                    font.pixelSize: Theme.fontSizeSmall - 1
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: nineDayHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.NoButton
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: String(nineDayColumn.modelData.weekday || "")
                                        horizontalAlignment: Text.AlignHCenter
                                        color: nineDayHover.containsMouse ? Theme.surfaceText : Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }

                        Column {
                            visible: nineCol.nineModels.length > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.nine_models_week", "Top models (7 days)")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: nineCol.nineModels

                                UsageBar {
                                    required property var modelData
                                    width: parent.width
                                    label: modelData.provider ? `${modelData.model} · ${modelData.provider}` : String(modelData.model || "")
                                    percent: Number(nineCol.nineWeek.cost || 0) > 0 ? (Number(modelData.cost || 0) / Number(nineCol.nineWeek.cost)) * 100 : 0
                                    aside: `${root.formatCost(Number(modelData.cost || 0))} · ${Number(modelData.requests || 0)} req`
                                    accentColor: Theme.secondary
                                }
                            }
                        }

                        Column {
                            visible: nineCol.nineProviders.length > 1
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.nine_providers_week", "Routed providers (7 days)")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: nineCol.nineProviders

                                UsageBar {
                                    required property var modelData
                                    width: parent.width
                                    label: root.providerName(String(modelData.provider || ""))
                                    percent: Number(nineCol.nineWeek.cost || 0) > 0 ? (Number(modelData.cost || 0) / Number(nineCol.nineWeek.cost)) * 100 : 0
                                    aside: `${root.formatCost(Number(modelData.cost || 0))} · ${Number(modelData.requests || 0)} req`
                                    accentColor: Theme.secondary
                                }
                            }
                        }
                    }
                }
            }

            Row {
                visible: card.hasUsage && root.lastUpdated.length > 0
                width: parent.width
                spacing: Theme.spacingXS

                DankIcon {
                    name: card.isStale ? "schedule" : "check"
                    size: 12
                    color: card.isStale ? Theme.warning : Theme.withAlpha(Theme.surfaceVariantText, 0.6)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.t("card.updated_at", "Updated {time}", { time: root.providerUpdatedLabel(card.provider) })
                    color: card.isStale ? Theme.withAlpha(Theme.warning, 0.8) : Theme.withAlpha(Theme.surfaceVariantText, 0.6)
                    font.pixelSize: Theme.fontSizeSmall - 2
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        MouseArea {
            id: cardMouse
            z: 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: card.dense ? 64 : (card.compact ? 76 : 82)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                card.forceActiveFocus();
                card.toggleExpanded();
            }
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

            GridLayout {
                width: parent.width
                columns: width < 560 ? 1 : 3
                columnSpacing: Theme.spacingM
                rowSpacing: Theme.spacingM

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 34
                        height: 34
                        radius: 11
                        color: Theme.withAlpha(Theme.primary, 0.12)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.primary, 0.2)

                        DankIcon {
                            anchors.centerIn: parent
                            name: "playlist_add_check"
                            size: 16
                            color: Theme.primary
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        StyledText {
                            width: parent.width
                            text: t("card.provider_control", "Provider control")
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root.selectedProviders.join(", ")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                DankDropdown {
                    id: addProviderDropdown
                    Layout.preferredWidth: 220
                    Layout.fillWidth: managerColumn.width < 560
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
                    Layout.fillWidth: managerColumn.width < 560
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

    popoutWidth: densityMode === "compact" ? 800 : 860
    popoutHeight: 820

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: t("app.title", "AI Usage Control")
            detailsText: root.lastUpdated.length > 0 ? (root.isDataStale ? t("popout.details_stale", "Stale since {time} · local adapters", { time: root.lastUpdated }) : t("popout.details_updated", "Updated {time} · local adapters", { time: root.lastUpdated })) : t("popout.provider_dashboard", "Provider dashboard")
            showCloseButton: true

            headerActions: Component {
                Row {
                    spacing: Theme.spacingS

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
                    ScrollBar.vertical: ScrollBar {
                        id: contentScrollBar
                        policy: contentFlick.contentHeight > contentFlick.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 0
                        width: 10
                        padding: 2
                        // Thin, rounded handle that brightens on hover/drag and
                        // fades out when idle so it never competes with the cards.
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: width / 2
                            color: Theme.withAlpha(Theme.surfaceText,
                                contentScrollBar.pressed ? 0.5 : (contentScrollBar.hovered ? 0.34 : 0.2))
                            opacity: (contentScrollBar.active
                                || contentScrollBar.policy === ScrollBar.AlwaysOn
                                || contentScrollBar.hovered) ? 1 : 0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                        background: Rectangle {
                            implicitWidth: 6
                            radius: width / 2
                            color: Theme.withAlpha(Theme.surfaceText, 0.05)
                            opacity: contentScrollBar.hovered || contentScrollBar.pressed ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220 } }
                        }
                    }

                    Column {
                        id: contentColumn
                        // Reserve only the slim scrollbar plus a hair of gap, so the
                        // cards keep a symmetric inset instead of a wide right gutter.
                        width: contentFlick.width - contentScrollBar.width - 2
                        spacing: Theme.spacingL

                        Item {
                            width: parent.width
                            height: 3
                            visible: root.isLoading
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: 1.5
                                color: Theme.withAlpha(Theme.primary, 0.12)
                            }

                            Rectangle {
                                id: loadRunner
                                width: Math.max(48, parent.width * 0.24)
                                height: parent.height
                                radius: 1.5
                                color: Theme.primary

                                SequentialAnimation on x {
                                    running: root.isLoading
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: -loadRunner.width
                                        to: contentColumn.width
                                        duration: 1200
                                        easing.type: Easing.InOutCubic
                                    }
                                }
                            }
                        }

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
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: Theme.spacingS

                                        Row {
                                            spacing: Theme.spacingXS

                                            Rectangle {
                                                width: 8
                                                height: 8
                                                radius: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: root.hasError ? Theme.warning : (root.hasProviderData ? Theme.success : Theme.surfaceVariantText)

                                                SequentialAnimation on opacity {
                                                    running: root.isLoading
                                                    loops: Animation.Infinite
                                                    NumberAnimation { from: 1; to: 0.3; duration: 620; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { from: 0.3; to: 1; duration: 620; easing.type: Easing.InOutQuad }
                                                }
                                            }

                                            StyledText {
                                                text: root.statusTitle.toUpperCase()
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall - 2
                                                font.weight: Font.DemiBold
                                                font.letterSpacing: 1.2
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: root.providerData ? root.providerName(root.providerData.provider) : t("app.title", "AI Usage Control")
                                            color: Theme.surfaceText
                                            font.pixelSize: contentColumn.width < 560 ? Theme.fontSizeLarge + 2 : Theme.fontSizeLarge + 6
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

                                        Flow {
                                            width: parent.width
                                            spacing: Theme.spacingXS

                                            BadgePill {
                                                label: root.providerData ? root.providerSourceLabel(root.providerData) : t("status.local_helpers", "local adapters")
                                                iconName: "sync_alt"
                                                accentColor: Theme.primary
                                            }

                                            BadgePill {
                                                label: root.hasError && !root.hasProviderData
                                                    ? t("status.setup_required", "Setup required")
                                                    : root.hasError
                                                        ? t("status.needs_attention", "Needs attention")
                                                        : root.providerStatusLabel(root.providerData)
                                                iconName: root.hasError ? "warning" : "check_circle"
                                                accentColor: root.hasError ? Theme.warning : root.getUsageColor(root.primaryPercent)
                                            }

                                            BadgePill {
                                                visible: root.isDataStale
                                                label: t("status.stale", "Stale")
                                                iconName: "schedule"
                                                accentColor: Theme.warning
                                                emphasized: true
                                            }
                                        }
                                    }

                                    // Window bars double as a jump link to the focused provider's card.
                                    Item {
                                        visible: contentColumn.width >= 480 && root.hasProviderData && root.windowsForProvider(root.providerData).length > 0
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: Math.min(260, contentColumn.width * 0.44)
                                        implicitHeight: heroBarsCol.implicitHeight

                                        Column {
                                            id: heroBarsCol
                                            width: parent.width
                                            spacing: Theme.spacingM
                                            opacity: heroBarsJump.containsMouse ? 0.82 : 1
                                            Behavior on opacity { NumberAnimation { duration: 120 } }

                                            Repeater {
                                                model: root.windowsForProvider(root.providerData)

                                                UsageBar {
                                                    required property var modelData
                                                    width: parent.width
                                                    label: modelData.label
                                                    percent: Number(modelData.data.usedPercent || 0)
                                                    aside: root.formatUsageLine(modelData.data)
                                                    accentColor: root.getUsageColor(Number(modelData.data.usedPercent || 0))
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: heroBarsJump
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.focusProvider(root.providerData ? root.providerData.provider : "")
                                        }
                                    }

                                    // Guided hint that fills the window-bar slot when there is no
                                    // focused provider — covers loading, all-providers-errored, and
                                    // no-data-yet so the hero never reads as a blank panel.
                                    Row {
                                        visible: contentColumn.width >= 480 && !root.hasProviderData
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: Math.min(260, contentColumn.width * 0.44)
                                        spacing: Theme.spacingS

                                        readonly property color hintAccent: root.isLoading
                                            ? Theme.primary
                                            : (root.errorProviders.length > 0 ? Theme.warning : root.heroAccent)

                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.withAlpha(parent.hintAccent, 0.14)
                                            border.width: 1
                                            border.color: Theme.withAlpha(parent.hintAccent, 0.28)

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: root.isLoading
                                                    ? "hourglass_top"
                                                    : (root.errorProviders.length > 0 ? "warning" : "monitoring")
                                                size: 17
                                                color: parent.parent.hintAccent
                                            }
                                        }

                                        Column {
                                            width: parent.width - 34 - Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            StyledText {
                                                width: parent.width
                                                text: root.isLoading
                                                    ? t("status.syncing", "Syncing usage")
                                                    : (root.errorProviders.length > 0
                                                        ? t("hero.error_title", "All providers need attention")
                                                        : t("hero.empty_title", "No usage data yet"))
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.Bold
                                                wrapMode: Text.WordWrap
                                            }

                                            StyledText {
                                                width: parent.width
                                                text: root.isLoading
                                                    ? t("status.loading_usage", "Fetching provider usage data...")
                                                    : (root.errorProviders.length > 0
                                                        ? t("hero.error_body", "Check credentials and that the provider CLIs are installed.")
                                                        : t("status.no_data_hint", "Run your configured AI CLIs and refresh to populate usage windows."))
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }

                                StyledRect {
                                    width: parent.width
                                    visible: root.fleetRollup.count >= 2
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.surfaceText, 0.04)
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.surfaceText, 0.08)
                                    implicitHeight: fleetCol.implicitHeight + Theme.spacingM * 2

                                    Column {
                                        id: fleetCol
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingM
                                        spacing: Theme.spacingM

                                        RowLayout {
                                            width: parent.width
                                            spacing: Theme.spacingS

                                            DankIcon {
                                                Layout.alignment: Qt.AlignVCenter
                                                name: "dashboard"
                                                size: 15
                                                color: Theme.surfaceVariantText
                                            }

                                            StyledText {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: t("rollup.title", "Fleet overview").toUpperCase()
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall - 2
                                                font.weight: Font.DemiBold
                                                font.letterSpacing: 1.0
                                            }

                                            Item { Layout.fillWidth: true }

                                            BadgePill {
                                                Layout.alignment: Qt.AlignVCenter
                                                label: t("rollup.providers", "{count} live", { count: root.fleetRollup.count })
                                                iconName: "lan"
                                                accentColor: Theme.primary
                                            }
                                        }

                                        Flow {
                                            width: parent.width
                                            spacing: Theme.spacingXL

                                            Row {
                                                spacing: Theme.spacingS

                                                Item {
                                                    width: 40
                                                    height: 40
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    ProgressRing {
                                                        anchors.fill: parent
                                                        percent: root.fleetRollup.avg
                                                        thickness: 5
                                                        accentColor: root.getUsageColor(root.fleetRollup.avg)
                                                    }

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: `${Math.round(root.fleetRollup.avg)}%`
                                                        color: Theme.surfaceText
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        font.weight: Font.Bold
                                                    }
                                                }

                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 1

                                                    StyledText {
                                                        text: t("rollup.avg_load", "Avg load")
                                                        color: Theme.surfaceText
                                                        font.pixelSize: Theme.fontSizeMedium
                                                        font.weight: Font.Bold
                                                    }

                                                    StyledText {
                                                        text: t("rollup.across", "across {count}", { count: root.fleetRollup.count })
                                                        color: Theme.surfaceVariantText
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                    }
                                                }
                                            }

                                            // Peak provider is a jump link: click to expand + scroll to its card.
                                            MouseArea {
                                                id: peakJump
                                                implicitWidth: peakStat.implicitWidth
                                                implicitHeight: peakStat.implicitHeight
                                                enabled: root.fleetRollup.peakId.length > 0
                                                hoverEnabled: enabled
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: root.focusProvider(root.fleetRollup.peakId)

                                                HeroStat {
                                                    id: peakStat
                                                    opacity: peakJump.containsMouse ? 0.78 : 1
                                                    statIcon: "local_fire_department"
                                                    statLabel: root.fleetRollup.peakName.length > 0 ? root.fleetRollup.peakName : t("rollup.peak", "Peak")
                                                    statValue: `${Math.round(root.fleetRollup.peak)}%`
                                                    statAccent: root.getUsageColor(root.fleetRollup.peak)
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                }
                                            }

                                            HeroStat {
                                                statIcon: "warning"
                                                statLabel: t("rollup.at_risk", "At risk")
                                                statValue: String(root.fleetRollup.atRisk)
                                                statAccent: root.fleetRollup.atRisk > 0 ? Theme.error : Theme.success
                                            }

                                            HeroStat {
                                                visible: root.fleetRollup.nextResetMs > 0
                                                statIcon: "schedule"
                                                statLabel: t("rollup.next_reset", "Next reset")
                                                statValue: root.fleetNextResetLabel
                                                statAccent: root.heroAccent
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: Theme.withAlpha(Theme.surfaceText, 0.07)
                                }

                                Flow {
                                    width: parent.width
                                    spacing: Theme.spacingXL

                                    HeroStat {
                                        statIcon: "check_circle"
                                        statLabel: t("card.active", "Active")
                                        statValue: String(root.successfulProviders.length)
                                        statAccent: Theme.success
                                    }

                                    HeroStat {
                                        statIcon: "warning"
                                        statLabel: t("card.attention", "Attention")
                                        statValue: String(root.errorProviders.length)
                                        statAccent: root.errorProviders.length > 0 ? Theme.warning : Theme.success
                                    }

                                    HeroStat {
                                        visible: !!(root.primaryWindow && root.primaryWindow.resetsAt)
                                        statIcon: "schedule"
                                        statLabel: t("card.resets_in", "Resets in")
                                        statValue: root.primaryWindow ? root.formatTimeUntil(root.primaryWindow.resetsAt) : "—"
                                        statAccent: root.heroAccent
                                    }

                                    HeroStat {
                                        statIcon: "history"
                                        statLabel: t("popout.last_sync", "Last sync")
                                        statValue: root.lastUpdated.length > 0 ? root.lastUpdated : "—"
                                        statAccent: root.isDataStale ? Theme.warning : Theme.primary
                                    }
                                }
                            }
                        }

                        Column {
                            visible: root.providers.length > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            RowLayout {
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
                                        text: root.filteredDisplayProviders.length === 1 ? t("status.displayed", "{count} displayed", { count: root.filteredDisplayProviders.length }) : t("status.displayed_plural", "{count} displayed", { count: root.filteredDisplayProviders.length })
                                        color: root.heroAccent
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.DemiBold
                                    }
                                }

                                DankActionButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    iconName: root.allExpanded ? "unfold_less" : "unfold_more"
                                    iconColor: root.allExpanded ? Theme.primary : Theme.surfaceVariantText
                                    backgroundColor: Theme.withAlpha(Theme.primary, root.allExpanded ? 0.12 : 0.06)
                                    buttonSize: 30
                                    tooltipText: root.allExpanded ? t("card.collapse_all", "Collapse all") : t("card.expand_all", "Expand all")
                                    onClicked: {
                                        root.allExpanded = !root.allExpanded;
                                        if (root.allExpanded) root.focusedProviderId = "";
                                    }
                                }
                            }

                            DankFilterChips {
                                width: parent.width
                                showCounts: true
                                model: [
                                    { label: t("filter.all", "All"), count: root.displayProviders.length },
                                    { label: t("filter.live", "Live"), count: root.successfulProviders.length },
                                    { label: t("filter.issues", "Issues"), count: root.errorProviders.length }
                                ]
                                onSelectionChanged: index => root.providerStatusFilter = index === 1 ? "live" : (index === 2 ? "issues" : "all")
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
                                            text: t("status.no_provider_data", "No provider data available. Check credentials and local provider CLIs.")
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
                                        onTapped: root.refresh()
                                    }

                                    BadgePill {
                                        label: root.t("settings.configured_count", "{count} configured", { count: root.selectedProviders.length })
                                        iconName: "playlist_add_check"
                                        accentColor: Theme.surfaceVariantText
                                    }
                                }
                            }
                        }

                        ProviderManager {
                            width: parent.width
                        }

                        DankTextField {
                            visible: root.displayProviders.length > 5
                            width: parent.width
                            placeholderText: t("card.filter_providers", "Filter providers by name or source")
                            text: root.providerFilter
                            onTextChanged: root.providerFilter = text
                        }

                        Repeater {
                            id: providerCardsRepeater
                            model: root.filteredDisplayProviders

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
