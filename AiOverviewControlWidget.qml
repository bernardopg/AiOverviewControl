import QtQuick
import QtQuick.Effects
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
    // Per-provider DankBar window selection (issue #17): "claude:secondary"
    // shows the 7-day window in the bar while the dashboard keeps every
    // window. Sorting, history, and cards keep the primary window. Since
    // 1.12.0 notifications follow this too by default, via the "displayed"
    // notifyWindowScope.
    property string barWindowOverrides: (pluginData.barWindowOverrides || "").trim()
    property string densityMode: pluginData.densityMode || "comfortable"
    property string providerFilter: ""
    property string providerStatusFilter: "all"
    property string focusedProviderId: ""
    property bool allExpanded: false
    property var usageHistory: ({})
    property string historyBuffer: ""
    property string retryBuffer: ""
    property string retryingProviderId: ""
    // In-process dispatch bookkeeping. The helper owns the durable state so
    // this remains only a cheap guard between refreshes in this instance.
    property var notifiedMap: ({})
    property color providerLogoColor: {
        const saved = String(pluginData.providerLogoColor || "").trim();
        return saved.length > 0 ? saved : Theme.primary;
    }
    property bool notifyEnabled: String(pluginData.quotaNotifications ?? "true") === "true"
    property int notifyThreshold: {
        const parsed = parseInt(pluginData.notifyThreshold || "85");
        return Number.isFinite(parsed) && parsed > 0 && parsed <= 100 ? parsed : 85;
    }
    // Hovering the DankBar pill spells out the window behind the number —
    // with barWindowOverrides the percentage is not necessarily the primary
    // window, so "31%" alone is ambiguous.
    property bool pillTooltipEnabled: String(pluginData.pillTooltip ?? "true") === "true"
    // Crowded bars (issue #33): hide names to keep logo + percentage, and
    // tighten the separator gap. Only the DankBar pill changes.
    property bool pillShowNames: String(pluginData.pillShowNames ?? "true") === "true"
    property bool pillCompact: String(pluginData.pillCompact ?? "false") === "true"
    property bool showClaudeProjects: String(pluginData.showClaudeProjects ?? "true") === "true"
    readonly property var moneyFormatter: currencyLoader.item
    readonly property string costCurrency: {
        const code = String(pluginData.costCurrency ?? "USD").toUpperCase();
        return ["USD", "EUR", "BRL", "GBP", "CAD", "CNY", "JPY", "AUD", "CHF"].indexOf(code) >= 0 ? code : "USD";
    }
    // Antigravity normally groups quotas exactly as its own Models screen:
    // Gemini and Claude/OpenAI. Per-model rows remain available for advanced
    // troubleshooting without making every account card noisy by default.
    property bool showAntigravityModelDetails: String(pluginData.showAntigravityModelDetails ?? "false") === "true"
    // Per-provider overrides: "claude:90,codex:75" beats the global threshold.
    readonly property var notifyThresholdOverrides: {
        const raw = String(pluginData.notifyThresholds || "").trim();
        const map = {};
        if (raw.length === 0)
            return map;
        const pairs = raw.split(",");
        for (let i = 0; i < pairs.length; i++) {
            const kv = pairs[i].split(":");
            if (kv.length !== 2)
                continue;
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
    // Which quota windows raise notifications.
    //   displayed — the window the DankBar shows (barWindowOverrides). Equal to
    //               "primary" until an override is set, so this is a safe default.
    //   all       — every window the provider reports (5h *and* 7d, ...).
    //   primary   — the pre-1.12 behaviour, primary window only.
    readonly property string notifyWindowScope: {
        const raw = String(pluginData.notifyWindowScope || "displayed").trim().toLowerCase();
        return (raw === "all" || raw === "primary") ? raw : "displayed";
    }
    // Minutes between repeats of the same alert; 0 = once per quota window.
    readonly property int notifyCooldownSecs: {
        const parsed = parseInt(pluginData.notifyCooldownMinutes || "0");
        if (!Number.isFinite(parsed) || parsed <= 0)
            return 999999999;
        return parsed * 60;
    }
    property string pinnedProvidersCsv: (pluginData.pinnedProviders || "").trim()
    readonly property var pinnedProviders: {
        const parts = pinnedProvidersCsv.split(",");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            const id = parts[i].trim().toLowerCase();
            if (id.length > 0 && result.indexOf(id) < 0)
                result.push(id);
        }
        return result;
    }
    property string pendingProviderId: availableProviderOptions[0] || "codex"
    property string claudeRateLimitTier: ""
    property real claudeFiveHourUtil: 0
    property string claudeFiveHourReset: ""
    property real claudeSevenDayUtil: 0
    property string claudeSevenDayReset: ""
    property real claudeScopedLimitUtil: 0
    property string claudeScopedLimitReset: ""
    property string claudeScopedLimitModel: ""
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
    // Version for the popout header pill; read from plugin.json so releases
    // only ever bump the manifest.
    property string pluginVersion: ""
    property string providerUsageScript: _pluginDir + "/providers/get-provider-usage"
    property string claudeUsageScript: _pluginDir + "/providers/get-claude-usage"
    property string copilotUsageScript: _pluginDir + "/providers/get-copilot-usage"
    property string usageHistoryScript: _pluginDir + "/providers/get-usage-history"
    property string notifyAlertScript: _pluginDir + "/providers/send-quota-alert"
    property string nineRouterAnalyticsScript: _pluginDir + "/providers/get-9router-analytics"
    readonly property var codexStats: codexReader.snapshot
    readonly property var opencodeStats: opencodeReader.snapshot
    readonly property var nineStats: nineReader.snapshot
    property string piAnalyticsScript: _pluginDir + "/providers/get-pi-analytics"
    readonly property var piStats: piReader.snapshot
    property string hermesAnalyticsScript: _pluginDir + "/providers/get-hermes-analytics"
    readonly property var hermesStats: hermesReader.snapshot
    // Hosted model providers first; the trailing group collects local and
    // non-provider tooling (self-hosted inference, gateways/routers, agent
    // harness analytics) so the picker keeps them visually separated.
    readonly property var availableProviderOptions: ["codex", "claude", "copilot", "antigravity", "gemini", "openrouter", "deepseek", "kimi", "kimi-code", "mistral", "glm", "zai", "minimax", "commandcode", "qwen", "nvidia", "cloudflare", "vertexai", "byteplus", "together", "groq", "cohere", "replicate", "fireworks", "ai21", "xai", "kilo", "perplexity", "cursor", "cline", "opencode", "kiro", "warp", "amp", "ollama", "9router", "pi", "hermes"]

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
            if (providerStatusFilter === "live" && (provider.error || !provider.usage))
                continue;
            if (providerStatusFilter === "issues" && !provider.error && !root.hasPartialAccountErrors(provider))
                continue;
            if (query.length > 0) {
                const haystack = `${providerName(provider.provider)} ${provider.provider} ${providerSourceLabel(provider)}`.toLowerCase();
                if (haystack.indexOf(query) < 0)
                    continue;
            }
            result.push(provider);
        }
        // Pinned first, then most-used so attention lands where quota is
        // burning; failed providers sink to the end without hiding.
        result.sort(function (a, b) {
            const aPin = pinnedProviders.indexOf(a.provider) >= 0 ? 0 : 1;
            const bPin = pinnedProviders.indexOf(b.provider) >= 0 ? 0 : 1;
            if (aPin !== bPin)
                return aPin - bPin;
            if (aPin === 0)
                return pinnedProviders.indexOf(a.provider) - pinnedProviders.indexOf(b.provider);
            const aErr = a.error ? 1 : 0;
            const bErr = b.error ? 1 : 0;
            if (aErr !== bErr)
                return aErr - bErr;
            return providerPercent(b) - providerPercent(a);
        });
        return result;
    }

    // Parsed "id:slot" pairs. IDs run through the same alias table as
    // notification thresholds (z.ai → zai, agy → antigravity, ...) so an
    // override survives however the user spelled the provider. Unknown or
    // empty slots are discarded so a typo can never blank the bar.
    readonly property var barWindowOverrideMap: {
        const raw = String(barWindowOverrides || "").trim();
        const map = {};
        if (raw.length === 0)
            return map;
        const pairs = raw.split(",");
        for (let i = 0; i < pairs.length; i++) {
            const kv = pairs[i].split(":");
            if (kv.length !== 2)
                continue;
            const id = notificationProviderId(kv[0].trim());
            const slot = kv[1].trim().toLowerCase();
            if (id.length === 0)
                continue;
            if (slot === "primary" || slot === "secondary" || slot === "tertiary" || slot === "highest") {
                map[id] = slot;
            }
        }
        return map;
    }

    readonly property var pillDisplayProviders: {
        if (pillMode === "top") {
            // Single most-critical provider: highest displayed usage wins.
            // pillPercentFor honors barWindowOverrides, so "top" ranks by the
            // exact number the user sees in the bar.
            let best = null;
            let bestPercent = -1;
            for (let i = 0; i < successfulProviders.length; i++) {
                const percent = pillPercentFor(successfulProviders[i]);
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
                if (id.length === 0)
                    continue;
                for (let j = 0; j < providers.length; j++) {
                    if (providers[j] && providers[j].provider === id && !providers[j].error) {
                        result.push(providers[j]);
                        break;
                    }
                }
            }
            // Custom mode is strict: never widen the pill by silently falling
            // back to every successful provider when the chosen subset has no
            // current data.
            return result;
        }
        // auto: show all with usedPercent > 0, else all successful
        const active = [];
        for (let i = 0; i < successfulProviders.length; i++) {
            if (pillPercentFor(successfulProviders[i]) > 0) {
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
        const out = {
            count: live.length,
            avg: 0,
            peak: 0,
            peakName: "",
            peakId: "",
            atRisk: 0,
            nextResetMs: 0
        };
        if (live.length === 0) {
            return out;
        }
        let sum = 0;
        let loadCount = 0;
        let nextMs = Infinity;
        for (let i = 0; i < live.length; i++) {
            const percent = providerPercent(live[i]);
            const win = primaryUsageWindow(live[i]);
            // Only timed quota windows contribute to the average load. Balance,
            // analytics, and informational cards report 0% by design — folding
            // them in would dilute the fleet average toward zero and misstate
            // real quota pressure. Peak / at-risk / reset still scan everyone.
            const isQuotaLoad = win && win.windowMinutes !== null && win.windowMinutes !== undefined;
            if (isQuotaLoad) {
                sum += percent;
                loadCount++;
            }
            if (percent > out.peak) {
                out.peak = percent;
                out.peakName = providerName(live[i].provider);
                out.peakId = live[i].provider;
            }
            if (percent >= 80) {
                out.atRisk++;
            }
            if (win && win.resetsAt) {
                const ms = new Date(win.resetsAt).getTime();
                if (!isNaN(ms) && ms > Date.now() && ms < nextMs) {
                    nextMs = ms;
                }
            }
        }
        out.avg = loadCount > 0 ? sum / loadCount : 0;
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
        return t("status.primary_resets", "Primary window resets in {time}.", {
            time: resetLabel
        });
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

    // Adapters emit English resetDescription strings ("5 hour", "Weekly",
    // "7 day · Opus"...). Standard ones are translated here, per " · " segment,
    // so every caller renders the same localized label; unknown text passes through.
    function windowLabel(windowData, fallback) {
        if (!windowData) return fallback || "";
        const raw = windowData.resetDescription;
        if (!raw) return getWindowLabel(windowData.windowMinutes) || fallback || "";
        return String(raw).split(" · ").map(part => translateWindowPart(part)).join(" · ");
    }

    // Every label an adapter can emit, in English, mapped to an i18n key.
    // Unknown text (model names, account labels) passes through untouched.
    function translateWindowPart(part) {
        const text = String(part).trim();
        const key = text.toLowerCase();
        const known = {
            "session": ["window.session", "Session"],
            "5 hour": ["window.session", "Session"],
            "5h": ["window.session", "Session"],
            "weekly": ["window.weekly", "Weekly"],
            "week": ["window.weekly", "Weekly"],
            "7 day": ["window.weekly", "Weekly"],
            "7 days": ["window.weekly", "Weekly"],
            "monthly": ["window.monthly", "Monthly"],
            "month": ["window.monthly", "Monthly"],
            "today": ["window.today", "Today"],
            "window": ["window.window", "Window"],
            "quota": ["window.quota", "Quota"],
            "credits": ["window.credits", "Credits"],
            "chat": ["window.chat", "Chat"],
            "completions": ["window.completions", "Completions"],
            "key limit": ["window.key_limit", "Key limit"],
            "spent today": ["window.spent_today", "Spent today"],
            "week and top models": ["window.week_top_models", "Week and top models"],
            "week and month spend": ["window.week_month_spend", "Week and month spend"],
            "tracked total": ["window.tracked_total", "Tracked total"],
            "tokens": ["window.tokens", "Tokens"],
            "total tokens": ["window.total_tokens", "Total tokens"],
            "tokens/5h": ["window.tokens_session", "Tokens / session"],
            "tokens/week": ["window.tokens_week", "Tokens / week"],
            "tokens/month": ["window.tokens_month", "Tokens / month"],
            "balance": ["window.balance", "Balance"],
            "granted credits": ["window.granted_credits", "Granted credits"],
            "paid balance": ["window.paid_balance", "Paid balance"],
            "voucher / cash": ["window.voucher_cash", "Voucher / Cash"],
            "running now": ["window.running_now", "Running now"],
            "prepaid credits": ["window.prepaid_credits", "Prepaid credits"],
            "account": ["window.account", "Account"],
            "premium requests": ["window.premium_requests", "Premium requests"],
            "ai credits": ["window.ai_credits", "AI credits"],
            "gemini models": ["window.gemini_models", "Gemini models"],
            "claude & openai models": ["window.claude_openai_models", "Claude & OpenAI models"],
            "other models": ["window.other_models", "Other models"],
            "1 hour": ["window.hourly", "Hourly"],
            "1 day": ["window.daily", "Daily"],
            "1 week": ["window.weekly", "Weekly"]
        };
        if (known[key]) return t(known[key][0], known[key][1]);
        let m = key.match(/^mcp (.+)$/);
        if (m) return "MCP " + translateWindowPart(text.substring(4));
        m = key.match(/^(\d+) (minute|hour|day|week)s?$/);
        if (m) {
            const unitKeys = { minute: ["window.n_minutes", "{count} minutes"], hour: ["window.n_hours", "{count} hours"], day: ["window.n_days", "{count} days"], week: ["window.n_weeks", "{count} weeks"] };
            return t(unitKeys[m[2]][0], unitKeys[m[2]][1], { count: m[1] });
        }
        m = text.match(/^Latest day (.+)$/);
        if (m) return t("window.latest_day", "Latest day {date}", { date: m[1] });
        m = text.match(/^local-routed, not (.+) quota$/);
        if (m) return t("window.local_routed", "local-routed, not {provider} quota", { provider: m[1] });
        m = text.match(/^Local — (\d+) model\(s\)$/);
        if (m) return t("window.local_models", "Local · {count} models", { count: m[1] });
        m = text.match(/^Available balance \((.+)\)$/);
        if (m) return t("window.available_balance", "Available balance ({currency})", { currency: m[1] });
        return text;
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
        return t("time.days", "{d}d", { d: Math.floor(windowMinutes / 1440) });
    }

    function formatTimeUntil(isoDate) {
        if (!isoDate) {
            return "";
        }
        const diff = new Date(isoDate).getTime() - Date.now();
        if (diff <= 0) {
            return t("time.now", "now");
        }
        return formatMinutes(Math.floor(diff / 60000));
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
        if (rawStderrBuffer.length > 0)
            return rawStderrBuffer.trim();
        return t("error.helper_exit", "provider helper exited with code {code}", {
            code: exitCode
        });
    }

    function providerName(providerId) {
        const names = {
            codex: "Codex",
            claude: "Claude",
            copilot: "Copilot",
            pi: "pi",
            hermes: "Hermes",
            antigravity: "Antigravity",
            cursor: "Cursor",
            gemini: "Gemini",
            openrouter: "OpenRouter",
            "9router": "9Router",
            deepseek: "DeepSeek",
            kimi: "Kimi",
            "kimi-code": "Kimi Code",
            moonshot: "Kimi",
            mistral: "Mistral",
            glm: "GLM",
            zhipu: "GLM",
            zai: "Z.ai",
            minimax: "MiniMax",
            commandcode: "Command Code",
            cmd: "Command Code",
            cmdcode: "Command Code",
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
            opencode: "OpenCode Go",
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

    function notificationProviderId(providerId) {
        const aliases = {
            agy: "antigravity",
            moonshot: "kimi",
            zhipu: "glm",
            "z.ai": "zai",
            dashscope: "qwen",
            alibaba: "qwen",
            nim: "nvidia",
            vertex: "vertexai",
            ark: "byteplus",
            modelark: "byteplus",
            grok: "xai"
        };
        const normalized = normalizeProviderId(providerId);
        return aliases[normalized] || normalized;
    }

    function notificationIconPath(providerId) {
        const canonicalId = notificationProviderId(providerId);
        if (canonicalId.length === 0 || _pluginDir.length === 0) {
            return "dialog-warning";
        }
        const extension = canonicalId === "byteplus" ? ".png" : ".svg";
        // DMS accepts a local path as the notification app icon, which lets
        // its popup use the same provider mark as the dashboard card.
        return _pluginDir + "/assets/provider-logos/" + canonicalId + extension;
    }

    function notificationWindowKey(providerId, windowData) {
        const canonicalId = notificationProviderId(providerId);
        const minutes = Math.max(0, Math.round(Number(windowData && windowData.windowMinutes || 0)));
        // Keep the identity independent of translated display text. Changing
        // the DMS/plugin locale must never re-arm a quota alert.
        let windowKind = "usage";
        if (minutes > 0 && minutes <= 300)
            windowKind = "session";
        else if (minutes > 0 && minutes <= 10080)
            windowKind = "weekly";
        else if (minutes > 0 && minutes <= 43200)
            windowKind = "monthly";
        else if (minutes > 0)
            windowKind = `${Math.floor(minutes / 1440)}d`;
        const resetMs = new Date(windowData && windowData.resetsAt || "").getTime();
        if (Number.isFinite(resetMs) && resetMs > 0) {
            // Some APIs recalculate a reset timestamp by a few seconds on
            // every poll. Bucket it by its quota duration so that drift does
            // not look like a brand-new quota window.
            const periodMs = minutes > 0 ? Math.max(60 * 60 * 1000, minutes * 60 * 1000) : 24 * 60 * 60 * 1000;
            return `${canonicalId}:${windowKind}:${minutes}:${Math.floor(resetMs / periodMs)}`;
        }
        return `${canonicalId}:${windowKind}:${minutes}:static`;
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
        if (normalized.length === 0)
            return;
        const tracked = normalized.split(",");
        const currentPillIds = providersCsv(pillProviders.split(",")).split(",");
        const nextPillIds = [];
        for (let i = 0; i < currentPillIds.length; i++) {
            if (tracked.indexOf(currentPillIds[i]) >= 0)
                nextPillIds.push(currentPillIds[i]);
        }
        if (nextPillIds.length === 0)
            nextPillIds.push(tracked[0]);
        pillProviders = nextPillIds.join(",");
        providerSelection = normalized;
        providers = [];
        PluginService.savePluginData("aiOverviewControl", "providerSelection", normalized);
        PluginService.savePluginData("aiOverviewControl", "pillProviders", pillProviders);
        if (procUsage.running) {
            procUsage.running = false;
        }
        usageDidTimeout = false;
        timedOutRequestId = -1;
        refresh();
    }

    function addProvider(providerId) {
        const provider = normalizeProviderId(providerId);
        if (provider.length === 0)
            return;
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
        if (!provider)
            return "missing";
        if (provider.error)
            return "error";
        if (hasPartialAccountErrors(provider))
            return "partial";
        if (provider.usage)
            return "active";
        return "empty";
    }

    function providerStatusLabel(provider) {
        const status = root.providerStatus(provider);
        if (status === "error")
            return t("status.error", "Error");
        if (status === "partial")
            return t("status.partial", "Partial");
        if (status === "active")
            return t("status.online", "Live");
        if (status === "empty")
            return t("status.waiting", "Waiting");
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
        if (!usage)
            return "—";
        const accounts = accountsForProvider(provider);
        if (provider.provider === "antigravity" && accounts.length >= 2) {
            return t("card.accounts_count", "{count} local accounts", {
                count: accounts.length
            });
        }
        if (usage.identity && usage.identity.accountEmail)
            return usage.identity.accountEmail;
        return usage.accountEmail || "—";
    }

    function providerLogin(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage)
            return "—";
        if (usage.identity && usage.identity.loginMethod)
            return usage.identity.loginMethod;
        return usage.loginMethod || "—";
    }

    function providerCredits(provider) {
        if (!provider || !provider.credits)
            return "—";
        return String(provider.credits.remaining ?? "—");
    }

    function providerUpdatedMs(provider) {
        const value = provider && provider.usage ? provider.usage.updatedAt : "";
        if (!value)
            return lastUpdatedMs;
        const parsed = new Date(value).getTime();
        return Number.isFinite(parsed) ? parsed : lastUpdatedMs;
    }

    function providerUpdatedLabel(provider) {
        const value = providerUpdatedMs(provider);
        return value > 0 ? Qt.formatDateTime(new Date(value), "hh:mm:ss") : lastUpdated;
    }

    function compactPath(value) {
        const text = String(value || "");
        if (text.length === 0)
            return "none";
        const parts = text.split("/");
        if (parts.length <= 2)
            return text;
        return `…/${parts.slice(-2).join("/")}`;
    }

    // Provider fallback icons live in ProviderLogo.defaultIcon (single source);
    // callers pass only providerId.

    function providerAccent(providerId) {
        if (providerId === "claude")
            return Theme.warning;
        if (providerId === "codex")
            return Theme.success;
        if (providerId === "copilot")
            return Theme.primary;
        if (providerId === "pi")
            return Theme.success;
        if (providerId === "hermes")
            return Theme.primary;
        if (providerId === "antigravity")
            return Theme.primary;
        if (providerId === "gemini")
            return Theme.secondary;
        if (providerId === "openrouter")
            return Theme.primary;
        if (providerId === "9router")
            return Theme.secondary;
        if (providerId === "deepseek")
            return Theme.primary;
        if (providerId === "kimi" || providerId === "kimi-code" || providerId === "moonshot")
            return Theme.secondary;
        if (providerId === "mistral")
            return Theme.warning;
        if (providerId === "glm" || providerId === "zhipu" || providerId === "zai")
            return Theme.primary;
        if (providerId === "minimax")
            return Theme.success;
        if (providerId === "commandcode" || providerId === "cmd" || providerId === "cmdcode")
            return Theme.primary;
        if (providerId === "opencode")
            return Theme.secondary;
        if (providerId === "qwen" || providerId === "dashscope" || providerId === "alibaba")
            return Theme.warning;
        if (providerId === "nvidia" || providerId === "nim")
            return Theme.success;
        if (providerId === "cloudflare")
            return Theme.warning;
        if (providerId === "vertexai" || providerId === "vertex")
            return Theme.primary;
        if (providerId === "byteplus" || providerId === "ark" || providerId === "modelark")
            return Theme.secondary;
        if (providerId === "together")
            return Theme.primary;
        if (providerId === "groq")
            return Theme.success;
        if (providerId === "cohere")
            return Theme.secondary;
        if (providerId === "replicate")
            return Theme.primary;
        if (providerId === "fireworks")
            return Theme.warning;
        if (providerId === "xai" || providerId === "grok")
            return Theme.primary;
        if (providerId === "ai21")
            return Theme.secondary;
        return Theme.secondary;
    }

    // Provider taxonomy for cards, hero and pickers. Most entries are plain
    // hosted model providers ("provider", the silent default). Local tooling
    // gets explicit kinds: "agent" for coding-agent harness analytics (pi —
    // no quota API of its own), "gateway" for routers that front other
    // providers (9Router), "local" for self-hosted inference (Ollama). A
    // Hermes-style entry that is both an agent manager and a provider can
    // combine roles ("agent,provider") and renders as "Agent · Provider".
    function providerKinds(providerId) {
        const kinds = {
            pi: "agent",
            hermes: "agent,provider",
            "9router": "gateway",
            ollama: "local"
        };
        const value = kinds[normalizeProviderId(providerId)];
        return value ? value.split(",") : ["provider"];
    }

    function isPlainProvider(providerId) {
        const kinds = providerKinds(providerId);
        return kinds.length === 1 && kinds[0] === "provider";
    }

    function providerKindLabel(kind) {
        if (kind === "agent")
            return t("kind.agent", "Agent");
        if (kind === "gateway")
            return t("kind.gateway", "Gateway");
        if (kind === "local")
            return t("kind.local", "Local");
        return t("kind.provider", "Provider");
    }

    function providerKindsLabel(providerId) {
        return providerKinds(providerId).map(providerKindLabel).join(" · ");
    }

    function providerKindIcon(kind) {
        if (kind === "agent")
            return "smart_toy";
        if (kind === "gateway")
            return "alt_route";
        if (kind === "local")
            return "dns";
        return "cloud";
    }

    function providerKindIconFor(providerId) {
        const kinds = providerKinds(providerId);
        for (let i = 0; i < kinds.length; i++) {
            if (kinds[i] !== "provider")
                return providerKindIcon(kinds[i]);
        }
        return providerKindIcon("provider");
    }

    function providerKindAccentFor(providerId) {
        const kinds = providerKinds(providerId);
        for (let i = 0; i < kinds.length; i++) {
            if (kinds[i] === "agent")
                return Theme.secondary;
            if (kinds[i] === "gateway")
                return Theme.primary;
            if (kinds[i] === "local")
                return Theme.success;
        }
        return Theme.surfaceVariantText;
    }

    function windowsForProvider(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage)
            return [];
        const accounts = accountsForProvider(provider);
        if (provider.provider === "antigravity" && showAntigravityModelDetails && accounts.length === 1 && accounts[0].modelWindows && accounts[0].modelWindows.length) {
            const modelWindows = accounts[0].modelWindows;
            const detailed = [];
            for (let i = 0; i < modelWindows.length; i++) {
                detailed.push({
                    key: `model-${i}`,
                    label: modelWindows[i].resetDescription || modelWindows[i].name || "",
                    data: modelWindows[i]
                });
            }
            return detailed;
        }
        if (provider.provider === "antigravity" && accounts.length === 1 && accounts[0].windows && accounts[0].windows.length) {
            const acctWindows = accounts[0].windows;
            const detailed = [];
            for (let i = 0; i < acctWindows.length; i++) {
                detailed.push({
                    key: `window-${i}`,
                    label: acctWindows[i].resetDescription || acctWindows[i].name || "",
                    data: acctWindows[i]
                });
            }
            return detailed;
        }
        const windows = [];
        if (usage.primary)
            windows.push({
                key: "primary",
                label: windowLabel(usage.primary),
                data: usage.primary
            });
        if (usage.secondary)
            windows.push({
                key: "secondary",
                label: windowLabel(usage.secondary),
                data: usage.secondary
            });
        if (usage.tertiary)
            windows.push({
                key: "tertiary",
                label: windowLabel(usage.tertiary, t("window.tertiary", "Tertiary")),
                data: usage.tertiary
            });
        return windows;
    }

    function primaryUsageWindow(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage)
            return null;
        return usage.primary || usage.secondary || usage.tertiary || null;
    }

    function barWindowChoiceFor(providerId) {
        const slot = barWindowOverrideMap[notificationProviderId(providerId)];
        return slot !== undefined ? slot : "primary";
    }

    // The window the DankBar shows for this provider: the configured
    // barWindowOverrides slot, or "highest" = the most-constrained window.
    // Payload shapes vary per account (e.g. Codex weekly-only has a null
    // secondary), so a chosen slot that is absent falls back to the primary
    // window — an override must never blank or zero the bar.
    function pillWindowFor(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage)
            return null;
        const slot = barWindowChoiceFor(provider.provider);
        if (slot === "highest") {
            let best = null;
            const candidates = [usage.primary, usage.secondary, usage.tertiary];
            for (let i = 0; i < candidates.length; i++) {
                const window = candidates[i];
                if (!window)
                    continue;
                if (!best || Number(window.usedPercent || 0) > Number(best.usedPercent || 0)) {
                    best = window;
                }
            }
            return best || primaryUsageWindow(provider);
        }
        if (slot !== "primary" && usage[slot])
            return usage[slot];
        return primaryUsageWindow(provider);
    }

    // Bar-display percent for a provider — the only percentage call the
    // DankBar pills should use. Cards, hero, fleet rollup, notifications and
    // history keep providerPercent()/primaryUsageWindow().
    function pillPercentFor(provider) {
        const windowData = pillWindowFor(provider);
        if (!windowData)
            return 0;
        return Number(windowData.usedPercent || 0);
    }

    // One line describing exactly what the DankBar is showing: provider,
    // which quota window the number came from, the percentage, and the reset.
    // DankTooltip renders a single elided line, so the reset is only appended
    // when the pill tracks one provider.
    function pillTooltipText() {
        const entries = [];
        const withReset = pillDisplayProviders.length === 1;
        for (let i = 0; i < pillDisplayProviders.length; i++) {
            const provider = pillDisplayProviders[i];
            const windowData = pillWindowFor(provider);
            if (!windowData)
                continue;
            const segment = [providerName(provider.provider)];
            const label = windowLabel(windowData);
            if (label && String(label).length > 0)
                segment.push(label);
            segment.push(`${Math.round(Number(windowData.usedPercent || 0))}%`);
            if (withReset) {
                const reset = formatTimeUntil(windowData.resetsAt);
                if (reset.length > 0)
                    segment.push(t("notify.resets_in", "resets in {time}", {
                        time: reset
                    }));
            }
            entries.push(segment.join(" · "));
        }
        return entries.join("   •   ");
    }

    // BasePill keeps its MouseArea at z:-1, below the plugin's pill content,
    // so reading its hover state is enough — no extra MouseArea that could
    // swallow the bar's own click, ripple, or hover highlight.
    function pillHostFor(item) {
        let node = item ? item.parent : null;
        for (let depth = 0; node && depth < 8; depth++) {
            if (node.isMouseHovered !== undefined)
                return node;
            node = node.parent;
        }
        return null;
    }

    function showPillTooltip(anchorItem) {
        if (!pillTooltipEnabled || !anchorItem)
            return;
        const text = pillTooltipText();
        if (text.length === 0)
            return;
        pillTooltipLoader.active = true;
        const tooltip = pillTooltipLoader.item;
        if (!tooltip)
            return;
        const currentScreen = parentScreen || Screen;
        if (!currentScreen)
            return;
        const edge = (axis && axis.edge) ? axis.edge : "top";
        const offset = barThickness + barSpacing + Theme.spacingXS;
        const center = anchorItem.mapToItem(null, anchorItem.width / 2, anchorItem.height / 2);
        if (edge === "left" || edge === "right") {
            const x = edge === "left" ? offset : (currentScreen.width - offset);
            tooltip.show(text, x, center.y, currentScreen, edge === "left", edge === "right");
            return;
        }
        // The tooltip is its own layer-shell window in screen coordinates, so
        // a bottom bar has to be measured from the bottom of the screen.
        tooltip.text = text;
        const y = edge === "bottom" ? Math.max(Theme.spacingS, currentScreen.height - offset - tooltip.implicitHeight) : offset;
        tooltip.show(text, center.x, y, currentScreen, false, false);
    }

    function hidePillTooltip() {
        if (pillTooltipLoader.item)
            pillTooltipLoader.item.hide();
        pillTooltipLoader.active = false;
    }

    // Quota windows checkNotifications() evaluates for one provider, per the
    // notifyWindowScope setting. Sorting, history, cards and the hero keep
    // using primaryUsageWindow() regardless.
    function notifyWindowsFor(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage)
            return [];
        if (notifyWindowScope === "all") {
            const every = [];
            const candidates = [usage.primary, usage.secondary, usage.tertiary];
            for (let i = 0; i < candidates.length; i++) {
                if (candidates[i])
                    every.push(candidates[i]);
            }
            return every;
        }
        const single = notifyWindowScope === "primary" ? primaryUsageWindow(provider) : pillWindowFor(provider);
        return single ? [single] : [];
    }

    // Providers exposing more than one signed-in account (Antigravity surfaces
    // every local IDE / Google session) carry an `accounts` array.
    function accountsForProvider(provider) {
        if (!provider || !provider.accounts || !provider.accounts.length)
            return [];
        return provider.accounts;
    }

    function accountErrorsForProvider(provider) {
        if (!provider || !provider.accountErrors || !provider.accountErrors.length)
            return [];
        return provider.accountErrors;
    }

    function hasPartialAccountErrors(provider) {
        return !!provider && !!provider.usage && !provider.error && accountErrorsForProvider(provider).length > 0;
    }

    function partialAccountErrorText(provider) {
        const errors = accountErrorsForProvider(provider);
        if (errors.length === 0)
            return "";
        const countLabel = t("card.account_errors_count", "{count} account(s) unavailable", {
            count: errors.length
        });
        const first = errors[0];
        const account = first.email || first.install || t("card.account", "Account");
        const message = first.message || t("status.error", "Error");
        return countLabel + " · " + account + ": " + message;
    }

    function hasMultipleAccounts(provider) {
        return accountsForProvider(provider).length >= 2 && !!provider && !provider.error;
    }

    function accountLabel(account) {
        return account && account.install ? account.install : t("card.account", "Account");
    }

    function accountEmailFor(account) {
        return account && account.email ? account.email : "";
    }

    function accountWorstPercent(account) {
        if (!account || !account.windows || !account.windows.length)
            return 0;
        let worst = 0;
        for (let i = 0; i < account.windows.length; i++) {
            const p = Number(account.windows[i].usedPercent || 0);
            if (p > worst)
                worst = p;
        }
        return worst;
    }

    function accountWindows(account) {
        if (!account)
            return [];
        if (showAntigravityModelDetails && account.modelWindows && account.modelWindows.length) {
            return account.modelWindows;
        }
        return account.windows || [];
    }

    function providerReset(provider) {
        const windowData = primaryUsageWindow(provider);
        if (!windowData)
            return "—";
        return formatTimeUntil(windowData.resetsAt);
    }

    function providerSubtitle(provider) {
        if (!provider)
            return t("status.provider_missing", "No provider data");
        if (provider.error)
            return root.providerErrorText(provider);
        const source = provider.source || "local";
        const windowData = primaryUsageWindow(provider);
        if (windowData && windowData.displayValue && String(windowData.displayValue).length > 0) {
            const label = windowData.resetDescription ? windowLabel(windowData) : t("status.usage", "usage");
            const reset = provider.provider === "antigravity" ? formatTimeUntil(windowData.resetsAt) : "";
            if (reset && reset !== "—") {
                return `${source} · ${label} · ${windowData.displayValue} · ${t("status.reset", "reset")} ${reset}`;
            }
            return `${source} · ${label} · ${windowData.displayValue}`;
        }
        const reset = providerReset(provider);
        return (reset && reset !== "—") ? `${source} · ${t("status.reset", "reset")} ${reset}` : `${source} · ${t("status.no_reset", "no reset window")}`;
    }

    function formatTokens(n) {
        const value = Number(n || 0);
        if (value >= 1000000000)
            return `${(value / 1000000000).toFixed(1)}B`;
        if (value >= 1000000)
            return `${(value / 1000000).toFixed(1)}M`;
        if (value >= 1000)
            return `${(value / 1000).toFixed(1)}K`;
        return Math.round(value).toString();
    }

    function formatCost(usd) {
        return currencyLoader.item ? currencyLoader.item.format(usd, root.i18nLocale) : "—";
    }

    // jq's strftime("%a") follows the shell locale of whichever adapter produced
    // the row, so adapters can disagree on the same weekday. Derive the label
    // from the ISO date instead, and fall back to the adapter string only when
    // the date is unusable.
    function weekdayLabel(dayData) {
        const raw = dayData && dayData.date ? String(dayData.date) : "";
        const parts = raw.split("-");
        if (parts.length === 3) {
            const parsed = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
            if (!isNaN(parsed.getTime()))
                return Qt.locale(root.i18nLocale).toString(parsed, "ddd");
        }
        return dayData && dayData.weekday ? String(dayData.weekday) : "";
    }

    function formatTier(tier) {
        if (!tier)
            return "—";
        if (tier.indexOf("max_20x") >= 0)
            return "Max 20x";
        if (tier.indexOf("max_5x") >= 0)
            return "Max 5x";
        if (tier.indexOf("pro") >= 0)
            return "Pro";
        if (tier.indexOf("free") >= 0)
            return t("tier.free", "Free");
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
        if (idx < 0)
            return;
        const key = line.substring(0, idx);
        const val = line.substring(idx + 1);
        if (key === "RATE_LIMIT_TIER")
            claudeRateLimitTier = val;
        else if (key === "FIVE_HOUR_UTIL")
            claudeFiveHourUtil = Number(val || 0);
        else if (key === "FIVE_HOUR_RESET")
            claudeFiveHourReset = val;
        else if (key === "SEVEN_DAY_UTIL")
            claudeSevenDayUtil = Number(val || 0);
        else if (key === "SEVEN_DAY_RESET")
            claudeSevenDayReset = val;
        else if (key === "SCOPED_LIMIT_UTIL")
            claudeScopedLimitUtil = Number(val || 0);
        else if (key === "SCOPED_LIMIT_RESET")
            claudeScopedLimitReset = val;
        else if (key === "SCOPED_LIMIT_MODEL")
            claudeScopedLimitModel = val;
        else if (key === "EXTRA_USAGE_ENABLED")
            claudeExtraUsageEnabled = (val === "true");
        else if (key === "WEEK_MESSAGES")
            claudeWeekMessages = parseInt(val) || 0;
        else if (key === "WEEK_SESSIONS")
            claudeWeekSessions = parseInt(val) || 0;
        else if (key === "WEEK_TOKENS")
            claudeWeekTokens = Number(val || 0);
        else if (key === "MONTH_TOKENS")
            claudeMonthTokens = Number(val || 0);
        else if (key === "ALLTIME_SESSIONS")
            claudeAlltimeSessions = parseInt(val) || 0;
        else if (key === "ALLTIME_MESSAGES")
            claudeAlltimeMessages = parseInt(val) || 0;
        else if (key === "FIRST_SESSION")
            claudeFirstSession = val;
        else if (key === "TODAY_COST")
            claudeTodayCost = Number(val || 0);
        else if (key === "WEEK_COST")
            claudeWeekCost = Number(val || 0);
        else if (key === "MONTH_COST")
            claudeMonthCost = Number(val || 0);
        else if (key === "DAILY")
            claudeDailyTokens = parseNumberList(val);
        else if (key === "DAILY_COSTS")
            claudeDailyCosts = parseNumberList(val);
        else if (key === "WEEK_MODELS") {
            claudeModelList.clear();
            if (val.length > 0) {
                const pairs = val.split(",");
                for (let i = 0; i < pairs.length; i++) {
                    const kv = pairs[i].split(":");
                    if (kv.length === 2) {
                        claudeModelList.append({
                            modelName: capitalizeFirst(kv[0]),
                            modelTokens: Number(kv[1] || 0),
                            modelCost: 0
                        });
                    }
                }
            }
        } else if (key === "WEEK_MODEL_COSTS") {
            // Arrives after WEEK_MODELS: enrich the already-built model rows.
            if (val.length > 0) {
                const pairs = val.split(",");
                for (let i = 0; i < pairs.length; i++) {
                    const kv = pairs[i].split(":");
                    if (kv.length !== 2)
                        continue;
                    const name = capitalizeFirst(kv[0]);
                    for (let j = 0; j < claudeModelList.count; j++) {
                        if (claudeModelList.get(j).modelName === name) {
                            claudeModelList.setProperty(j, "modelCost", Number(kv[1] || 0));
                            break;
                        }
                    }
                }
            }
        } else if (key === "WEEK_PROJECTS") {
            claudeProjectList.clear();
            if (val.length > 0) {
                const pairs = val.split(",");
                for (let i = 0; i < pairs.length; i++) {
                    const cut = pairs[i].lastIndexOf(":");
                    if (cut <= 0)
                        continue;
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
        if (value < 60)
            return t("time.minutes", "{m}m", { m: value });
        const hours = Math.floor(value / 60);
        if (hours < 24)
            return t("time.hours_minutes", "{h}h {m}m", { h: hours, m: value % 60 });
        return t("time.days_hours", "{d}d {h}h", { d: Math.floor(hours / 24), h: hours % 24 });
    }

    // Burn-rate forecast for a rolling window: utilization so far divided by
    // elapsed window time, extrapolated to 100%.
    function windowBurnForecast(util, resetIso, windowMinutes) {
        if (!resetIso || util <= 0)
            return null;
        const resetMs = new Date(resetIso).getTime();
        if (!Number.isFinite(resetMs))
            return null;
        const remainMin = Math.max(0, (resetMs - Date.now()) / 60000);
        if (remainMin <= 0 || remainMin >= windowMinutes)
            return null;
        const elapsedMin = Math.max(1, windowMinutes - remainMin);
        const rate = util / elapsedMin;
        if (rate <= 0)
            return null;
        const minTo100 = (100 - util) / rate;
        if (minTo100 <= remainMin) {
            return {
                exceed: true,
                text: t("claude.burn_pace_exceed", "At this pace: 100% in {time}", {
                    time: formatMinutes(minTo100)
                })
            };
        }
        return {
            exceed: false,
            text: t("claude.burn_pace_ok", "Usage on pace for this window")
        };
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
        if (dayOfMonth <= 0 || claudeMonthCost <= 0)
            return 0;
        const daysInMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
        return (claudeMonthCost / dayOfMonth) * daysInMonth;
    }

    function providerConsoleUrl(providerId, providerSource) {
        if ((providerId === "kimi" || providerId === "kimi-code" || providerId === "moonshot") && providerSource === "kimi-code") {
            return "https://www.kimi.com/code/console";
        }
        const urls = {
            claude: "https://claude.ai/settings/usage",
            codex: "https://chatgpt.com/codex/settings/usage",
            copilot: "https://github.com/settings/copilot/features",
            pi: "",
            hermes: "https://portal.nousresearch.com",
            antigravity: "",
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
            commandcode: "https://commandcode.ai/billing",
            cmd: "https://commandcode.ai/billing",
            cmdcode: "https://commandcode.ai/billing",
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
            groq: "https://console.groq.com/dashboard/usage",
            cohere: "https://dashboard.cohere.com/billing",
            replicate: "https://replicate.com/account/billing",
            fireworks: "https://app.fireworks.ai",
            ai21: "https://studio.ai21.com",
            xai: "https://console.x.ai/billing",
            grok: "https://console.x.ai/billing",
            perplexity: "https://www.perplexity.ai/settings",
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

    function openProviderConsole(providerId, providerSource) {
        const url = providerConsoleUrl(providerId, providerSource);
        if (url.length > 0)
            Quickshell.execDetached(["xdg-open", url]);
    }

    function isPinned(providerId) {
        return pinnedProviders.indexOf(normalizeProviderId(providerId)) >= 0;
    }

    function reorderedPins(pins, source, target) {
        const from = pins.indexOf(source);
        const to = pins.indexOf(target);
        if (from < 0 || to < 0 || source === target)
            return pins.slice();
        const next = pins.filter(id => id !== source);
        next.splice(next.indexOf(target), 0, source);
        return next;
    }

    function movePinnedBefore(source, target) {
        const next = reorderedPins(pinnedProviders, source, target);
        pinnedProvidersCsv = next.join(",");
        PluginService.savePluginData("aiOverviewControl", "pinnedProviders", pinnedProvidersCsv);
    }

    function togglePin(providerId) {
        const id = normalizeProviderId(providerId);
        const next = pinnedProviders.slice();
        const index = next.indexOf(id);
        if (index >= 0)
            next.splice(index, 1);
        else
            next.push(id);
        pinnedProvidersCsv = next.join(",");
        PluginService.savePluginData("aiOverviewControl", "pinnedProviders", pinnedProvidersCsv);
    }

    // Trend over the last two recorded snapshots: "up" | "down" | "flat" | "".
    function historyPercent(entry) {
        return Number(entry && entry.p !== undefined ? entry.p : entry) || 0;
    }

    function providerTrend(providerId) {
        const history = usageHistory[normalizeProviderId(providerId)];
        if (!history || history.length < 2)
            return "";
        const delta = historyPercent(history[history.length - 1]) - historyPercent(history[history.length - 2]);
        if (delta >= 1)
            return "up";
        if (delta <= -1)
            return "down";
        return "flat";
    }

    function retryProvider(providerId) {
        if (procRetry.running)
            return;
        retryingProviderId = normalizeProviderId(providerId);
        retryBuffer = "";
        procRetry.command = ["bash", providerUsageScript, retryingProviderId, copilotUsageScript];
        procRetry.running = true;
    }

    function checkNotifications() {
        if (!notifyEnabled)
            return;
        const seen = notifiedMap;
        const now = Date.now();
        for (let i = 0; i < successfulProviders.length; i++) {
            const provider = successfulProviders[i];
            const threshold = thresholdFor(provider.provider);
            const windows = notifyWindowsFor(provider);
            // notifyWindowScope "all" can hand back two windows that hash to
            // the same identity (e.g. both without windowMinutes or a reset
            // stamp). Alerting twice on one key would fight over the same
            // dedupe entry, so the first occurrence wins.
            const handled = {};
            for (let w = 0; w < windows.length; w++) {
                const windowData = windows[w];
                if (!windowData)
                    continue;
                const percent = Number(windowData.usedPercent || 0);
                // One stable key per provider quota window. In particular, do not
                // include the threshold or an unbucketed reset time: changing a
                // setting or a provider's timestamp jitter must not create a
                // fresh toast on every refresh.
                const dedupeKey = notificationWindowKey(provider.provider, windowData);
                if (handled[dedupeKey])
                    continue;
                handled[dedupeKey] = true;
                if (percent < threshold - 5) {
                    // Re-arm only after a meaningful fall. The hysteresis avoids
                    // a noisy alert/clear loop around the selected threshold and
                    // also makes static (no reset timestamp) windows usable.
                    delete seen[dedupeKey];
                    Quickshell.execDetached(["bash", notifyAlertScript, "--clear", dedupeKey]);
                    continue;
                }
                if (percent < threshold)
                    continue;

                const pct = Math.round(percent);
                const exhausted = percent >= 100;
                const severity = exhausted ? 2 : 1;
                const previous = seen[dedupeKey];
                const cooldownElapsed = previous && notifyCooldownSecs < 999999999 && now - previous.lastAttemptMs >= notifyCooldownSecs * 1000;
                // Dispatch on the crossing, when it becomes exhausted, or for an
                // explicitly requested reminder. The helper repeats this check
                // atomically across bars/reloads and updates, rather than stacks,
                // the DMS notification when an escalation is needed.
                if (previous && severity <= previous.severity && !cooldownElapsed)
                    continue;
                seen[dedupeKey] = {
                    severity: Math.max(severity, previous ? previous.severity : 0),
                    lastAttemptMs: now
                };

                const reset = formatTimeUntil(windowData.resetsAt);
                const windowLabel = root.windowLabel(windowData, t("status.usage", "usage"));

                const title = exhausted ? t("notify.title_exhausted", "{provider} quota reached", {
                    provider: providerName(provider.provider)
                }) : t("notify.title", "{provider} usage is high ({percent}%)", {
                    provider: providerName(provider.provider),
                    percent: pct
                });
                const bodyParts = [exhausted ? t("notify.body_exhausted", "No quota remains in the {window} window.", {
                        window: windowLabel
                    }) : t("notify.body", "{window} quota · {percent}% used", {
                        window: windowLabel,
                        percent: pct
                    })];
                if (reset.length > 0)
                    bodyParts.push(t("notify.resets_in", "resets in {time}", {
                        time: reset
                    }));

                // The helper persists state on disk (flock-guarded), so duplicate
                // widget instances, plugin reloads and shell restarts cannot
                // re-fire inside the cooldown window. At 100%, it replaces the
                // prior provider toast with a critical, branded update.
                Quickshell.execDetached(["bash", notifyAlertScript, dedupeKey, String(notifyCooldownSecs), exhausted ? "critical" : "normal", notificationIconPath(provider.provider), providerLogoColor.toString(), title, bodyParts.join(" · ")]);
            }
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
        // One-time, idempotent cleanup of the legacy state whose full reset
        // timestamp made jitter look like a new quota window every refresh.
        Quickshell.execDetached(["bash", notifyAlertScript, "--migrate"]);
        detectBinary();
    }

    // Manifest reader backing the popout version pill. The path binding
    // re-evaluates once _pluginDir is resolved above, so the pill appears as
    // soon as plugin.json has been read.
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
                // Manifest unreadable: the header simply hides the version pill.
            }
        }
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
                root.errorMessage = t("error.helper_missing", "Local provider helper is missing or not executable: {path}", {
                    path: root.providerUsageScript
                });
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
        environment: {
            "AIOC_HISTORY_MAX": root.historyRetention
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
                        const firstErr = root.errorProviders[0].error;
                        const firstErrMsg = (firstErr && typeof firstErr === "object") ? firstErr.message : (typeof firstErr === "string" ? firstErr : "");
                        root.errorMessage = firstErrMsg || t("error.fetch_failed", "Failed to fetch usage from providers.");
                    } else {
                        root.hasError = false;
                        root.errorMessage = root.errorProviders.length > 0 ? t("error.providers_need_attention", "{count} provider(s) need attention.", {
                            count: root.errorProviders.length
                        }) : "";
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
            claudeStatsProcess.running = true;
            claudeTimeout.restart();
        }
        if (root.selectedProviders.indexOf("9router") >= 0)
            nineReader.refresh();
        if (root.selectedProviders.indexOf("pi") >= 0)
            piReader.refresh();
        if (root.selectedProviders.indexOf("codex") >= 0)
            codexReader.refresh();
        if (root.selectedProviders.indexOf("opencode") >= 0)
            opencodeReader.refresh();
        if (root.selectedProviders.indexOf("hermes") >= 0)
            hermesReader.refresh();
    }

    // Load by URL: an already-running DMS engine can cache the old qmldir
    // before a plugin update adds a new exported type.
    component AnalyticsReaderHost: Item {
        id: host
        required property string providerId
        property string scriptPath: root._pluginDir + "/providers/get-local-analytics"
        property var commandArguments: [providerId]
        property bool retainOnFailure: false
        readonly property var snapshot: readerLoader.item ? readerLoader.item.result : null
        property bool refreshPending: false
        visible: false
        function refresh() {
            if (readerLoader.item) {
                readerLoader.item.scriptPath = host.scriptPath;
                readerLoader.item.commandArguments = host.commandArguments;
                readerLoader.item.retainOnFailure = host.retainOnFailure;
                readerLoader.item.refresh();
            } else {
                refreshPending = true;
            }
        }
        Loader {
            id: readerLoader
            Component.onCompleted: setSource(Qt.resolvedUrl("LocalAnalyticsReader.qml"), {
                providerId: host.providerId,
                scriptPath: host.scriptPath,
                timeoutMs: root.fetchTimeoutMs
            })
            onLoaded: {
                if (host.refreshPending) {
                    host.refreshPending = false;
                    host.refresh();
                }
            }
        }
    }
    // URL loading keeps new components compatible with an already-running DMS.
    Loader {
        id: currencyLoader
        visible: false
        Component.onCompleted: setSource(Qt.resolvedUrl("CurrencyFormatter.qml"), {
            scriptPath: root._pluginDir + "/providers/get-exchange-rates",
            currency: root.costCurrency
        })
    }
    Binding {
        target: currencyLoader.item
        property: "currency"
        value: root.costCurrency
        when: currencyLoader.item !== null
    }
    Binding {
        target: currencyLoader.item
        property: "scriptPath"
        value: root._pluginDir + "/providers/get-exchange-rates"
        when: currencyLoader.item !== null
    }

    AnalyticsReaderHost { id: codexReader; providerId: "codex" }
    AnalyticsReaderHost { id: opencodeReader; providerId: "opencode" }

    AnalyticsReaderHost {
        id: nineReader
        providerId: "9router"
        scriptPath: root.nineRouterAnalyticsScript
        commandArguments: []
        retainOnFailure: true
    }
    AnalyticsReaderHost {
        id: piReader
        providerId: "pi"
        scriptPath: root.piAnalyticsScript
        commandArguments: []
        retainOnFailure: true
    }
    AnalyticsReaderHost {
        id: hermesReader
        providerId: "hermes"
        scriptPath: root.hermesAnalyticsScript
        commandArguments: []
        retainOnFailure: true
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
    // animation settles before the view measures its position. View-local ids
    // and the scrolling animation remain owned by DashboardContent.qml.
    // Closed/unloaded dashboards are a safe no-op.
    property string pendingScrollProviderId: ""
    property var dashboardView: null

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
            if (root.dashboardView)
                root.dashboardView.scrollToProvider(id);
        }
    }
















    // Lazily built so a session that never hovers the bar never creates the
    // extra layer-shell surface.
    Loader {
        id: pillTooltipLoader
        active: false
        sourceComponent: DankTooltip {}
    }

    horizontalBarPill: Component {
        Row {
            id: horizontalPillContent
            spacing: Theme.spacingS

            readonly property var pillHost: root.pillHostFor(horizontalPillContent)
            readonly property bool pillHovered: pillHost ? pillHost.isMouseHovered : false
            onPillHoveredChanged: {
                if (pillHovered)
                    root.showPillTooltip(horizontalPillContent);
                else
                    root.hidePillTooltip();
            }
            Component.onDestruction: root.hidePillTooltip()

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                visible: !root.hasError || root.hasProviderData

                Repeater {
                    model: root.pillDisplayProviders

                    Row {
                        id: pillEntry
                        required property var modelData
                        required property int index
                        readonly property color usageColor: root.getUsageColor(root.pillPercentFor(modelData))
                        objectName: "pill-entry-" + modelData.provider
                        spacing: root.pillCompact ? 2 : 4

                        StyledText {
                            visible: pillEntry.index > 0
                            // Compact drops the padding spaces; leftPadding mirrors
                            // the entry spacing on the right of the dot.
                            text: root.pillCompact ? "·" : " · "
                            leftPadding: root.pillCompact ? 2 : 0
                            color: Theme.withAlpha(Theme.surfaceText, 0.3)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        ProviderLogo {
                            providerId: pillEntry.modelData.provider
                            logoSize: 14
                            tintColor: root.providerLogoColor
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            objectName: "pill-name-" + pillEntry.modelData.provider
                            visible: root.pillShowNames
                            text: root.providerName(pillEntry.modelData.provider)
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: `${Math.round(root.pillPercentFor(pillEntry.modelData))}%`
                            color: pillEntry.usageColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            StyledText {
                visible: root.pillDisplayProviders.length === 0
                text: root.isLoading ? "…" : (root.hasError ? root.t("pill.error", "ERR") : root.t("pill.no_data", "N/A"))
                color: root.isLoading ? Theme.surfaceVariantText : (root.hasError ? Theme.error : Theme.surfaceVariantText)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            id: verticalPillContent
            spacing: root.pillCompact ? 2 : Theme.spacingXS

            readonly property var pillHost: root.pillHostFor(verticalPillContent)
            readonly property bool pillHovered: pillHost ? pillHost.isMouseHovered : false
            onPillHoveredChanged: {
                if (pillHovered)
                    root.showPillTooltip(verticalPillContent);
                else
                    root.hidePillTooltip();
            }
            Component.onDestruction: root.hidePillTooltip()

            Repeater {
                model: root.pillDisplayProviders

                Column {
                    required property var modelData
                    spacing: 1
                    anchors.horizontalCenter: parent.horizontalCenter

                    ProviderLogo {
                        providerId: modelData.provider
                        logoSize: 13
                        tintColor: root.providerLogoColor
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: `${Math.round(root.pillPercentFor(modelData))}%`
                        color: root.getUsageColor(root.pillPercentFor(modelData))
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            StyledText {
                visible: root.pillDisplayProviders.length === 0
                text: root.isLoading ? "…" : (root.hasError ? root.t("pill.error", "ERR") : root.t("pill.no_data", "N/A"))
                color: root.hasError ? Theme.error : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }





    // Seven-column usage chart shared by every provider card. Each entry of
    // `bars` is { value, primary, secondary, label, today }: bar height comes
    // from value, hover lifts primary/secondary above the bar. Bars have a
    // square base and rounded top, and grow in staggered on first show.


    // One signed-in account (IDE / Google session) with its per-model quota,
    // rendered as a self-contained block inside a multi-account provider card.






    // Standalone settings window, created on first use. DMS Settings > Plugins
    // keeps loading the same AiOverviewControlSettings page directly.
    // Created from its URL rather than as an inline type, so a hot reload
    // picks the window up without a shell restart.
    property var _settingsWindow: null

    function openSettingsWindow() {
        if (!_settingsWindow) {
            const component = Qt.createComponent(Qt.resolvedUrl("AiOverviewSettingsWindow.qml"));
            if (component.status !== Component.Ready) {
                console.warn("AiOverviewControl: settings window failed:", component.errorString());
                PopoutService.openSettingsWithTab("plugins");
                return;
            }
            _settingsWindow = component.createObject(root, { pluginVersion: Qt.binding(() => root.pluginVersion) });
        }
        _settingsWindow.activate();
    }

    Component.onDestruction: if (_settingsWindow) _settingsWindow.destroy()

    // Returns string, not void: qmllint's parser rejects a `void` return
    // annotation even though the Quickshell runtime accepts it.
    IpcHandler {
        target: "aiOverviewControl"

        // Bindable to a compositor shortcut, e.g.
        // dms ipc call aiOverviewControl toggle
        function toggle(): string {
            root.triggerPopout();
            return "POPOUT_TOGGLED";
        }

        function settings(): string {
            root.openSettingsWindow();
            return "SETTINGS_OPENED";
        }

        function about(): string {
            root.openSettingsWindow();
            if (root._settingsWindow)
                root._settingsWindow.showAbout();
            return "ABOUT_OPENED";
        }
    }

    popoutWidth: densityMode === "compact" ? 800 : 860
    popoutHeight: 820

    popoutContent: Component {
        Loader {
            id: dashboardHost
            property var parentPopout: null
            property var closePopout: null
            onLoaded: root.dashboardView = item
            Component.onDestruction: {
                if (root.dashboardView === item)
                    root.dashboardView = null;
            }
            width: root.popoutWidth
            height: root.popoutHeight
            Component.onCompleted: setSource(Qt.resolvedUrl("DashboardContent.qml"), {
                controller: root,
                parentPopout: dashboardHost.parentPopout,
                closePopout: dashboardHost.closePopout
            })
            Binding {
                target: dashboardHost.item
                property: "parentPopout"
                value: dashboardHost.parentPopout
                when: dashboardHost.item !== null
            }
            Binding {
                target: dashboardHost.item
                property: "closePopout"
                value: dashboardHost.closePopout
                when: dashboardHost.item !== null
            }
        }
    }
}
