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
    property string pendingProviderId: "gemini"
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
    property var dayLabels: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    property int refreshIntervalMs: {
        const val = pluginData.refreshInterval;
        const parsed = val ? parseInt(val) : 120000;
        return Number.isFinite(parsed) ? parsed : 120000;
    }
    property string codexbarPath: (pluginData.codexbarPath || "").trim()
    property string sourceMode: pluginData.sourceMode || "cli"
    property string claudeUsageScript: PluginService.pluginDirectory + "/AiOverviewControl/get-claude-usage"
    readonly property var availableProviderOptions: [
        "codex",
        "claude",
        "copilot",
        "gemini",
        "openrouter",
        "perplexity",
        "cursor",
        "kilo",
        "kiro",
        "ollama",
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
            cursor: "Cursor",
            ollama: "Ollama",
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
        PluginService.savePluginData("aiOverviewControl", "providerSelection", normalized);
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
            next.push("codex");
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

    function iconForProvider(providerId) {
        if (providerId === "codex") return "data_object";
        if (providerId === "claude") return "psychology";
        if (providerId === "copilot") return "hub";
        if (providerId === "gemini") return "auto_awesome";
        if (providerId === "openrouter") return "route";
        if (providerId === "perplexity") return "travel_explore";
        if (providerId === "cursor") return "ads_click";
        if (providerId === "ollama") return "dns";
        return "monitoring";
    }

    function providerAccent(providerId) {
        if (providerId === "claude") return Theme.warning;
        if (providerId === "codex") return Theme.success;
        if (providerId === "copilot") return Theme.primary;
        if (providerId === "gemini") return Theme.secondary;
        return Theme.secondary;
    }

    function windowsForProvider(provider) {
        const usage = provider && provider.usage ? provider.usage : null;
        if (!usage) return [];
        const windows = [];
        if (usage.primary) windows.push({ key: "primary", label: getWindowLabel(usage.primary.windowMinutes), data: usage.primary });
        if (usage.secondary) windows.push({ key: "secondary", label: getWindowLabel(usage.secondary.windowMinutes), data: usage.secondary });
        if (usage.tertiary) windows.push({ key: "tertiary", label: usage.tertiary.resetDescription || "Tertiary", data: usage.tertiary });
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
        if (!provider) return "No provider data";
        if (provider.error) return root.providerErrorText(provider);
        const source = provider.source || root.sourceMode;
        const reset = providerReset(provider);
        return reset !== "—" ? `${source} · reset ${reset}` : `${source} · no reset window`;
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
                "  if printf '%s' \"$out\" | node -e 'let s=\"\";process.stdin.on(\"data\",d=>s+=d);process.stdin.on(\"end\",()=>{JSON.parse(s);})' 2>/dev/null; then\n" +
                "    printf '%s' \"$out\" | PROVIDER=\"$provider\" node -e 'let s=\"\";process.stdin.on(\"data\",d=>s+=d);process.stdin.on(\"end\",()=>{const v=JSON.parse(s); const a=Array.isArray(v)?v:[v]; const wanted=process.env.PROVIDER; const picked=a.find(x=>x&&x.provider===wanted)||a[0]||{provider:wanted}; if(!picked.provider) picked.provider=wanted; process.stdout.write(JSON.stringify(picked));})'\n" +
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
                        root.hasError = false;
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

        implicitWidth: compact ? 118 : 190
        implicitHeight: compact ? 46 : (description.length > 0 ? 62 : 52)
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
                width: compact ? 28 : 32
                height: compact ? 28 : 32
                radius: width / 2
                color: buttonRoot.prominent ? Theme.withAlpha(Theme.primary, 0.18) : Theme.withAlpha(Theme.surfaceText, 0.08)

                DankIcon {
                    anchors.centerIn: parent
                    name: buttonRoot.iconName
                    size: compact ? 16 : 18
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

        implicitHeight: 78
        radius: Theme.cornerRadius
        color: Theme.withAlpha(accentColor, 0.08)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, 0.24)

        Column {
            id: tileCol
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: 6

            StyledText {
                width: parent.width
                text: tile.label
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: tile.value.length > 0 ? tile.value : "—"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
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
        spacing: 8

        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: parent.width - valueText.implicitWidth - Theme.spacingS
                text: usageBar.label
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            StyledText {
                id: valueText
                text: usageBar.aside.length > 0 ? usageBar.aside : `${Math.round(usageBar.percent)}%`
                color: usageBar.accentColor
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            width: parent.width
            height: 10
            radius: 5
            color: Theme.surfaceContainerHighest

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
                        color: index === 2 ? Theme.warning : Theme.withAlpha(Theme.primary, 0.55)
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

        width: parent ? parent.width : implicitWidth
        radius: Theme.cornerRadius + 6
        color: expanded ? Theme.surfaceContainerHigh : Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(accentColor, expanded ? 0.48 : 0.28)
        implicitHeight: cardColumn.implicitHeight + Theme.spacingL * 2
        clip: true

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        Column {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: expanded ? Theme.spacingL : Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingL

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    width: 48
                    height: 48
                    radius: 24
                    color: Theme.withAlpha(card.accentColor, 0.14)
                    border.width: 1
                    border.color: Theme.withAlpha(card.accentColor, 0.34)

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.iconForProvider(card.provider.provider)
                        size: 24
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
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: root.providerSubtitle(card.provider)
                        color: card.provider.error ? Theme.error : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        maximumLineCount: expanded ? 2 : 1
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: card.provider.error ? "Error" : `${Math.round(root.providerPercent(card.provider))}%`
                    color: card.provider.error ? Theme.error : root.getUsageColor(root.providerPercent(card.provider))
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.selectedProviders.length > 1
                    z: 2
                    width: 36
                    height: 36
                    radius: 18
                    color: removeArea.containsMouse ? Theme.withAlpha(Theme.error, 0.14) : Theme.withAlpha(Theme.surfaceText, 0.06)
                    border.width: 1
                    border.color: removeArea.containsMouse ? Theme.withAlpha(Theme.error, 0.32) : Theme.withAlpha(Theme.surfaceText, 0.1)

                    DankIcon {
                        anchors.centerIn: parent
                        name: "close"
                        size: 18
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
                    size: 28
                    color: Theme.surfaceVariantText
                }
            }

            UsageBar {
                visible: card.hasUsage && !card.expanded
                width: parent.width
                label: card.windows.length > 0 ? card.windows[0].label : "Usage"
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
                    columns: 3
                    columnSpacing: Theme.spacingM
                    rowSpacing: Theme.spacingM

                    MetricTile {
                        Layout.fillWidth: true
                        label: "Account"
                        value: root.providerAccount(card.provider)
                        accentColor: card.accentColor
                    }

                    MetricTile {
                        Layout.fillWidth: true
                        label: "Login"
                        value: root.providerLogin(card.provider)
                        accentColor: card.accentColor
                    }

                    MetricTile {
                        Layout.fillWidth: true
                        label: "Credits"
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
                                text: "Claude Code details"
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
                            label: "Week"
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
                            columns: 3
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            MetricTile { Layout.fillWidth: true; label: "Today"; value: `${root.formatTokens(0)} · ${root.formatCost(root.claudeTodayCost)}`; accentColor: Theme.warning }
                            MetricTile { Layout.fillWidth: true; label: "Week"; value: `${root.formatTokens(root.claudeWeekTokens)} · ${root.formatCost(root.claudeWeekCost)}`; accentColor: Theme.warning }
                            MetricTile { Layout.fillWidth: true; label: "Month"; value: `${root.formatTokens(root.claudeMonthTokens)} · ${root.formatCost(root.claudeMonthCost)}`; accentColor: Theme.warning }
                        }

                        ClaudeDailyBars {
                            width: parent.width
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: "Models this week"
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
                            text: `Since ${root.claudeFirstSession || "—"} · ${root.claudeAlltimeSessions} sessions · ${root.claudeAlltimeMessages} messages`
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 82
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

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        width: parent.width
                        text: "Provider control"
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
                    Layout.preferredWidth: 220
                    text: "Provider"
                    description: "Choose a provider supported by CodexBar."
                    currentValue: root.pendingProviderId
                    options: root.availableProviderOptions
                    dropdownWidth: 220
                    onValueChanged: function(value) {
                        root.pendingProviderId = value;
                    }
                }

                SurfaceButton {
                    iconName: "add"
                    label: "Add provider"
                    compact: true
                    prominent: true
                    actionEnabled: root.selectedProviders.indexOf(root.pendingProviderId) < 0
                    onTriggered: root.addProvider(root.pendingProviderId)
                }
            }
        }
    }

    popoutWidth: 920
    popoutHeight: 900

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "AI Usage Control"
            detailsText: root.lastUpdated.length > 0 ? `Updated ${root.lastUpdated} · ${root.sourceMode}` : "Provider dashboard"
            showCloseButton: true

            headerActions: Component {
                Row {
                    spacing: Theme.spacingS

                    SurfaceButton {
                        iconName: "terminal"
                        label: "CLI"
                        compact: true
                        actionEnabled: !procDetect.running
                        onTriggered: root.detectBinary()
                    }

                    SurfaceButton {
                        iconName: "refresh"
                        label: "Refresh"
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
                    anchors.leftMargin: Theme.spacingL
                    anchors.rightMargin: Theme.spacingL
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width - Theme.spacingL * 2
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
                            border.color: Theme.withAlpha(root.heroAccent, 0.32)
                            implicitHeight: overviewCol.implicitHeight + Theme.spacingXL * 2
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Theme.withAlpha(root.heroAccent, 0.14) }
                                    GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.02) }
                                }
                            }

                            Column {
                                id: overviewCol
                                anchors.fill: parent
                                anchors.margins: Theme.spacingXL
                                spacing: Theme.spacingL

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingL

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        StyledText {
                                            width: parent.width
                                            text: "AI Usage Control"
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeLarge + 4
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

                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        width: 104
                                        height: 74
                                        radius: Theme.cornerRadius + 4
                                        color: Theme.withAlpha(root.heroAccent, 0.13)
                                        border.width: 1
                                        border.color: Theme.withAlpha(root.heroAccent, 0.32)

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: root.barText
                                            color: root.heroAccent
                                            font.pixelSize: Theme.fontSizeLarge + 3
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                GridLayout {
                                    width: parent.width
                                    columns: 4
                                    columnSpacing: Theme.spacingM
                                    rowSpacing: Theme.spacingM

                                    MetricTile { Layout.fillWidth: true; label: "Active"; value: String(root.successfulProviders.length); accentColor: Theme.success }
                                    MetricTile { Layout.fillWidth: true; label: "Attention"; value: String(root.errorProviders.length); accentColor: root.errorProviders.length > 0 ? Theme.warning : Theme.success }
                                    MetricTile { Layout.fillWidth: true; label: "Source"; value: root.sourceMode; accentColor: Theme.primary }
                                    MetricTile { Layout.fillWidth: true; label: "Binary"; value: root.resolvedBinaryPath; accentColor: Theme.primary }
                                }
                            }
                        }

                        StyledText {
                            visible: root.providers.length > 0
                            width: parent.width
                            text: "Providers"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                        }

                        StyledText {
                            visible: root.isLoading && root.providers.length === 0
                            width: parent.width
                            text: "Fetching provider usage..."
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            visible: !root.isLoading && root.providers.length === 0
                            width: parent.width
                            text: "No provider data yet. Check the CodexBar binary path and run your configured CLIs once."
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }

                        ProviderManager {
                            width: parent.width
                        }

                        Repeater {
                            model: root.providers

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
