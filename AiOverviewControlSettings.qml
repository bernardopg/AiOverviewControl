import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "lib/BarWindows.js" as BarWindows
import "ClaudeProfiles.js" as ClaudeProfiles
import "detect"
import "detect/ProviderDetect.js" as ProviderDetect

PluginSettings {
    id: root
    pluginId: "aiOverviewControl"
    // The standalone settings window draws its own brand header, so it hides
    // the mascot + title here to avoid showing them twice.
    property bool showBrand: true

    readonly property string i18nLocale: AiOverviewControlI18n.normalizedLocale
    readonly property var claudeProfiles: {
        root.settingsEpoch;
        return ClaudeProfiles.parse(loadValue("claudeProfiles", "{}"));
    }
    property string claudeProfileError: ""
    onClaudeProfilesChanged: runHealth()
    property var selectedIds: normalizeProviderSelection(loadValue("providerSelection", "codex,claude,copilot"))
    // pluginService (and with it the saved selection) arrives after this
    // component is constructed, so the runHealth() in Component.onCompleted
    // can check the default provider set instead of the user's. Re-run the
    // check whenever the effective selection changes; runHealth() queues an
    // overlapping call rather than dropping it.
    onSelectedIdsChanged: runHealth()
    property var pinnedIds: normalizeCsvList(loadValue("pinnedProviders", ""))
    property var pillIds: normalizePillSelection(loadValue("pillProviders", selectedIds.join(",")))
    // DMS sets pluginService from Loader.onLoaded, after this component is
    // built, so the loadValue() bindings above capture the defaults. Re-read
    // the saved selection once the service arrives, then check its health.
    Connections {
        target: root
        function onPluginServiceChanged() {
            selectedIds = normalizeProviderSelection(loadValue("providerSelection", "codex,claude,copilot"));
            pinnedIds = normalizeCsvList(loadValue("pinnedProviders", ""));
            pillIds = normalizePillSelection(loadValue("pillProviders", selectedIds.join(",")));
            // Assigning selectedIds triggers onSelectedIdsChanged -> runHealth().
        }
    }
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

    // Per-provider DankBar window overrides (issues #17 and #86). lib/BarWindows.js
    // is the widget's parser too, so both read the same slot vocabulary. The
    // default ("auto": the primary window, or a later one once it is used up)
    // is the absence of a pair, so restoring it removes the pair and the CSV
    // stays small; an explicit "primary" is stored and keeps the primary
    // window even when another one is exhausted.
    function barWindowOverrideMap() {
        return BarWindows.parseOverrides(loadValue("barWindowOverrides", ""));
    }

    function barChoiceFor(id) {
        const slot = barWindowOverrideMap()[id];
        return slot !== undefined ? slot : "auto";
    }

    function setBarChoice(id, slot) {
        if (!isSelected(id)) return;
        const map = barWindowOverrideMap();
        const canonical = BarWindows.normalizeSlot(slot);
        if (canonical === "") delete map[id];
        else map[id] = canonical;
        const pairs = [];
        for (const key in map) pairs.push(key + ":" + map[key]);
        saveValue("barWindowOverrides", pairs.join(","));
    }

    // providers/get-provider-health reports what a provider is missing in
    // English. Prose details are localized through health.detail.<slug>
    // (tests/test-i18n.sh keeps every one of them in the bundles); a bare
    // variable name such as DEEPSEEK_API_KEY has no key and shows as is.
    function healthDetailText(detail) {
        const raw = String(detail || "");
        const slug = raw.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 60).replace(/_+$/, "");
        return slug.length > 0 ? t("health.detail." + slug, raw) : raw;
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
        grok: "xai", "grok-bot": "grokbot"
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
        claudeProfiles: "{}",
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
        showRemainingQuota: "false",
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

    readonly property var allProviders: baseProviders.concat(Object.keys(claudeProfiles).map(function(id) {
        const profile = root.claudeProfiles[id];
        return {id: id, name: profile.name, icon: "psychology", mode: "telemetry", requirement: profile.configDir, envVar: "", note: ""};
    }))
    readonly property var baseProviders: [
        { id:"codex", name:"Codex", icon:"terminal", mode:"telemetry", requirement:"codex CLI", envVar:"", note:"Official app-server rate limits" },
        { id:"claude", name:"Claude", icon:"psychology", mode:"telemetry", requirement:"claude CLI or ~/.claude", envVar:"", note:"Local analytics and authenticated usage" },
        { id:"copilot", name:"Copilot", icon:"code", mode:"telemetry", requirement:"gh CLI or GitHub token", envVar:"COPILOT_GITHUB_TOKEN", note:"Authenticated Copilot quota from the GitHub session" },
        { id:"pi", name:"pi", icon:"smart_toy", mode:"telemetry", requirement:"pi CLI or ~/.pi/agent/sessions", envVar:"", note:"Local session cost/token analytics — no quota API" },
        { id:"hermes", name:"Hermes", icon:"hub", mode:"telemetry", requirement:"hermes CLI or ~/.hermes/state.db", envVar:"", note:"Dual-nature: agent harness telemetry (sessions, tokens, models, projects) from the local state database; provider side routes through Nous Portal / OpenRouter — expand the card for details" },
        { id:"antigravity", name:"Antigravity", icon:"rocket_launch", mode:"telemetry", requirement:"Antigravity CLI keyring or IDE session", envVar:"", note:"Per-model quota and reset times, one block per signed-in account / IDE — expand the card to compare accounts" },
        { id:"gemini", name:"Gemini", icon:"star", mode:"telemetry", requirement:"gemini CLI or API key", envVar:"GEMINI_API_KEY", note:"Gemini CLI quota per model from the Code Assist API, or API-key authentication; explains when Google no longer offers Code Assist to the CLI account" },
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
        { id:"nvidia", name:"NVIDIA NIM", icon:"developer_board", mode:"telemetry", requirement:"API key", envVar:"NVIDIA_API_KEY", note:"Verifies the nvapi- key with NGC; credits and rate limits stay on build.nvidia.com" },
        { id:"anthropic", name:"Anthropic API", icon:"psychology", mode:"telemetry", requirement:"Admin API key", envVar:"ANTHROPIC_ADMIN_KEY", note:"Admin API cost report: month-to-date and today's spend; ANTHROPIC_MONTHLY_BUDGET_USD adds a percentage" },
        { id:"openai", name:"OpenAI API", icon:"data_object", mode:"telemetry", requirement:"Admin API key", envVar:"OPENAI_ADMIN_KEY", note:"Admin API organization costs: month-to-date and today's spend; OPENAI_MONTHLY_BUDGET_USD adds a percentage" },
        { id:"vercel", name:"Vercel AI Gateway", icon:"change_history", mode:"telemetry", requirement:"AI Gateway API key", envVar:"AI_GATEWAY_API_KEY", note:"Official AI Gateway credits API: remaining balance and total spend" },
        { id:"neuralwatt", name:"Neuralwatt", icon:"energy_savings_leaf", mode:"telemetry", requirement:"API key", envVar:"NEURALWATT_API_KEY", note:"Official quota API: subscription kWh allowance, prepaid USD balance and per-key spending limit" },
        { id:"cloudflare", name:"Cloudflare AI", icon:"cloud", mode:"telemetry", requirement:"API token", envVar:"CLOUDFLARE_AI_TOKEN", note:"Token verify + Workers AI analytics" },
        { id:"vertexai", name:"Vertex AI", icon:"settings_remote", mode:"telemetry", requirement:"gcloud CLI", envVar:"GOOGLE_CLOUD_PROJECT", note:"Official gcloud authentication status" },
        { id:"byteplus", name:"BytePlus Ark", icon:"rocket_launch", mode:"telemetry", requirement:"API key", envVar:"BYTEPLUS_API_KEY", note:"Official models API authentication check" },
        { id:"ollama-cloud", name:"Ollama Cloud", icon:"cloud_queue", mode:"telemetry", requirement:"API key", envVar:"OLLAMA_API_KEY", note:"Official balance API: included monthly credits (or legacy session and weekly limits) and purchased credits" },
        { id:"ollama", name:"Ollama", icon:"dns", mode:"telemetry", requirement:"local Ollama server", envVar:"OLLAMA_HOST", note:"Official local tags and running-model APIs" },
        { id:"together", name:"Together AI", icon:"join_inner", mode:"telemetry", requirement:"API key", envVar:"TOGETHER_API_KEY", note:"Read-only API-key validation; usage and billing remain in the console" },
        { id:"groq", name:"Groq", icon:"fast_forward", mode:"telemetry", requirement:"API key", envVar:"GROQ_API_KEY", note:"API-key check; set GROQ_QUOTA_MODEL to read requests/day and tokens/minute from one 1-token request every 30 minutes" },
        { id:"cohere", name:"Cohere", icon:"waves", mode:"telemetry", requirement:"API key", envVar:"COHERE_API_KEY", note:"Official models API authentication check" },
        { id:"replicate", name:"Replicate", icon:"content_copy", mode:"telemetry", requirement:"API token", envVar:"REPLICATE_API_TOKEN", note:"Official account API authentication check" },
        { id:"fireworks", name:"Fireworks AI", icon:"local_fire_department", mode:"telemetry", requirement:"API key", envVar:"FIREWORKS_API_KEY", note:"API-key validation; FIREWORKS_ACCOUNT_ID enables account quotas" },
        { id:"xai", name:"xAI (Grok)", icon:"bolt", mode:"telemetry", requirement:"grok login or API key", envVar:"XAI_API_KEY", note:"Prefers grok login (~/.grok/auth.json) for SuperGrok weekly usage. XAI_API_KEY validates inference keys. Prepaid API credits need XAI_MANAGEMENT_KEY and XAI_TEAM_ID." },
        { id:"kilo", name:"Kilo", icon:"straighten", mode:"telemetry", requirement:"API key", envVar:"KILO_API_KEY", note:"Configured-key status; the no-auth models endpoint is only a best-effort probe" },
        { id:"ai21", name:"AI21", icon:"looks_21", mode:"telemetry", requirement:"API key", envVar:"AI21_API_KEY", note:"Configured status; no documented read-only usage API" },
        { id:"cursor", name:"Cursor", icon:"mouse", mode:"telemetry", requirement:"Cursor IDE session or cursor-agent login", envVar:"", note:"Cursor Models and Other Models from the signed-in Cursor session" },
        { id:"grokbot", name:"Grok Bot", icon:"smart_toy", mode:"telemetry", requirement:"Grok Bot desktop app sign-in", envVar:"", note:"Weekly Grok Bot Plan quota from the signed-in Grok Bot desktop app" },
        { id:"perplexity", name:"Perplexity", icon:"auto_awesome", mode:"informational", requirement:"none", envVar:"", note:"No public read-only quota API" },
        { id:"cline", name:"Cline", icon:"code_blocks", mode:"telemetry", requirement:"API key or Cline CLI login", envVar:"CLINE_API_KEY", note:"Cline credit balance (personal or active organization), today's requests and tokens including free models, and ClinePass plan; uses CLINE_API_KEY or a valid Cline CLI sign-in" },
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
    }

    // Tracks the providers picked in "Detect providers" in one save.
    function addProviders(ids) {
        const result = ProviderDetect.merge(selectedIds, ids);
        if (result.length === selectedIds.length) return;
        selectedIds = result;
        saveValue("providerSelection", result.join(","));
    }

    // Detection scans the built-in catalog; Claude profiles need a directory
    // and are added below instead.
    readonly property var detectCatalog: baseProviders.map(function(provider) {
        return { id: provider.id, name: provider.name };
    })

    function addClaudeProfile(id, name, configDir) {
        id = String(id).trim().toLowerCase();
        const candidate = {};
        candidate[id] = {name: String(name).trim(), configDir: String(configDir).trim()};
        const profiles = Object.assign({}, claudeProfiles);
        if (Object.keys(profiles).length >= 16 || profiles[id] || !ClaudeProfiles.parse(candidate)[id]) {
            claudeProfileError = t("settings.claude_profiles_invalid", "Use a unique claude- ID, a name (1–80 characters) and an absolute directory. Maximum: 16 profiles.");
            return false;
        }
        profiles[id] = candidate[id];
        saveValue("claudeProfiles", JSON.stringify(profiles));
        settingsEpoch++;
        if (!isSelected(id)) toggleProvider(id);
        claudeProfileError = "";
        return true;
    }

    function removeClaudeProfile(id) {
        const profiles = Object.assign({}, claudeProfiles);
        delete profiles[id];
        saveValue("claudeProfiles", JSON.stringify(profiles));
        selectedIds = selectedIds.filter(function(value) { return value !== id; });
        if (selectedIds.length === 0) selectedIds = ["claude"];
        pinnedIds = pinnedIds.filter(function(value) { return value !== id; });
        pillIds = pillIds.filter(function(value) { return value !== id; });
        if (pillIds.length === 0) pillIds = [selectedIds[0]];
        saveValue("providerSelection", selectedIds.join(","));
        saveValue("pinnedProviders", pinnedIds.join(","));
        saveValue("pillProviders", pillIds.join(","));
        for (const key of ["barWindowOverrides", "notifyThresholds"]) {
            const pairs = String(loadValue(key, "")).split(",").filter(function(pair) { return pair.split(":")[0].trim() !== id; });
            saveValue(key, pairs.join(","));
        }
        settingsEpoch++;
        claudeProfileError = "";
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
        healthProcess.environment = {"AIOC_CLAUDE_PROFILES": JSON.stringify(claudeProfiles)};
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

    // ---- Page layout ---------------------------------------------------
    // The page is a stack of foldable groups. Which ones are open lives in
    // memory only: the page reopens with the bar group open, next to the
    // live preview, instead of persisting UI state as a plugin setting.
    readonly property var groupIds: ["general", "bar", "dashboard", "notifications", "providers", "profiles", "data", "diagnostics"]
    property var expandedGroups: ({ bar: true })
    readonly property bool allGroupsExpanded: groupIds.every(function(id) { return expandedGroups[id] === true; })

    function isGroupExpanded(id) { return expandedGroups[id] === true; }

    function setGroupExpanded(id, open) {
        const next = Object.assign({}, expandedGroups);
        next[id] = open;
        expandedGroups = next;
    }

    function setAllGroupsExpanded(open) {
        const next = {};
        for (let i = 0; i < groupIds.length; i++) next[groupIds[i]] = open;
        expandedGroups = next;
    }

    // saveValue() changes the stored data but no binding of this page; the
    // preview and the group summaries read through live() so they follow
    // every change at once.
    property int previewEpoch: 0
    onSettingChanged: previewEpoch++

    function live(key, fallback) {
        root.previewEpoch;
        root.settingsEpoch;
        const value = loadValue(key, fallback);
        return value === undefined || value === null ? fallback : String(value);
    }

    // The label a dropdown shows for a stored value.
    function optionLabel(values, labels, value) {
        const index = values.indexOf(value);
        return index >= 0 && index < labels.length ? labels[index] : String(value);
    }

    readonly property var languageValues: ["auto", "en_US", "pt_BR", "zh_CN", "es_ES", "de_DE"]
    // Language names stay in their own language so anyone can find theirs.
    readonly property var languageLabels: [t("settings.option.auto", "Auto"), "English", "Português (Brasil)", "简体中文", "Español", "Deutsch"]
    readonly property var refreshValues: ["60000", "120000", "300000", "900000", "1800000"]
    readonly property var refreshLabels: [1, 2, 5, 15, 30].map(n => t("settings.option.minutes", "{count} min", { count: n }))
    readonly property var pillModeValues: ["auto", "custom", "top"]
    readonly property var pillModeLabels: [t("settings.option.auto", "Auto"), t("settings.option.custom", "Custom"), t("settings.option.top", "Top usage")]
    readonly property var densityValues: ["comfortable", "compact"]
    readonly property var densityLabels: [t("settings.option.comfortable", "Comfortable"), t("settings.option.compact", "Compact")]
    readonly property var historyValues: ["500", "2000", "10000"]
    readonly property var historyLabels: [500, 2000, 10000].map(n => t("settings.option.snapshots", "{count} snapshots", { count: n.toLocaleString(Qt.locale(root.i18nLocale), "f", 0) }))
    readonly property var scopeValues: ["displayed", "all", "primary"]
    readonly property var scopeLabels: [t("settings.option.displayed", "Displayed"), t("settings.option.all", "All windows"), t("settings.option.primary", "Primary")]

    // One line per group, shown under its title while it is folded.
    function groupSummary(id) {
        const parts = [];
        if (id === "general") {
            parts.push(optionLabel(languageValues, languageLabels, live("languageOverride", "auto")));
            parts.push(t("settings.summary.every", "every {interval}", { interval: optionLabel(refreshValues, refreshLabels, live("refreshInterval", "120000")) }));
        } else if (id === "bar") {
            parts.push(optionLabel(pillModeValues, pillModeLabels, live("pillMode", "auto")));
            parts.push(t("settings.summary.in_bar", "{count} in the bar", { count: previewProviders().length }));
            if (live("showRemainingQuota", "false") === "true") parts.push(t("settings.summary.remaining", "remaining quota"));
        } else if (id === "dashboard") {
            parts.push(optionLabel(densityValues, densityLabels, live("densityMode", "comfortable")));
            parts.push(live("costCurrency", "USD"));
        } else if (id === "notifications") {
            if (live("quotaNotifications", "true") !== "true") return t("settings.summary.off", "Off");
            parts.push(t("settings.summary.at_percent", "At {percent}%", { percent: live("notifyThreshold", "85") }));
            parts.push(optionLabel(scopeValues, scopeLabels, live("notifyWindowScope", "displayed")));
        } else if (id === "providers") {
            parts.push(t("settings.active_count", "{count} active", { count: selectedIds.length }));
            if (readyCount > 0) parts.push(t("settings.health.ready_count", "{count} ready", { count: readyCount }));
            if (missingCount > 0) parts.push(t("settings.health.missing_count", "{count} missing", { count: missingCount }));
        } else if (id === "profiles") {
            const count = Object.keys(claudeProfiles).length;
            return count === 0 ? t("settings.summary.no_profiles", "No extra profiles") : t("settings.summary.profiles", "Profiles: {count}", { count: count });
        } else if (id === "data") {
            parts.push(optionLabel(historyValues, historyLabels, live("historyRetention", "2000")));
        } else if (id === "diagnostics") {
            return t("settings.diagnostics_desc", "Commands for validating the plugin-managed pipeline.");
        }
        return parts.join(" · ");
    }

    // ---- Provider filter -------------------------------------------------
    property string providerQuery: ""

    function providerMatches(provider) {
        const query = providerQuery.trim().toLowerCase();
        if (query.length === 0) return true;
        return String(provider.name).toLowerCase().indexOf(query) >= 0
            || String(provider.id).toLowerCase().indexOf(query) >= 0;
    }

    // ---- Live bar preview ------------------------------------------------
    // The preview renders the bar pill the way the widget does, from the
    // same settings and lib/BarWindows.js, but with sample numbers: fixed per
    // provider so it never flickers, and never a provider's real usage, which
    // this page does not read.
    readonly property var previewSamples: ({
        codex: [42, 18], claude: [67, 81], copilot: [23], openrouter: [35], antigravity: [12, 55],
        gemini: [8], "kimi-code": [51, 30], zai: [74, 20], glm: [74, 20], minimax: [28, 61],
        cursor: [58], grokbot: [46], opencode: [33, 12, 9], commandcode: [19, 40], xai: [27]
    })
    readonly property var previewBalances: ({ deepseek: "¥9.34", kimi: "¥42.00", vercel: "$95.50", cline: "$13.74" })

    function previewUsage(id) {
        if (previewBalances[id] !== undefined)
            return { primary: { usedPercent: 0, isBalance: true, windowMinutes: null, displayValue: previewBalances[id], resetDescription: "Balance" } };
        let sample = previewSamples[id];
        if (!sample) {
            let hash = 0;
            for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) % 997;
            sample = [15 + hash % 70];
        }
        const minutes = [300, 10080, 43200];
        const usage = {};
        const slots = ["primary", "secondary", "tertiary"];
        for (let i = 0; i < sample.length && i < 3; i++)
            usage[slots[i]] = { usedPercent: sample[i], windowMinutes: minutes[i] };
        return usage;
    }

    function previewSlot(id) {
        root.previewEpoch;
        const slot = BarWindows.parseOverrides(live("barWindowOverrides", ""))[id];
        return slot === undefined ? "" : slot;
    }

    function previewWindows(id) { return BarWindows.windowsFor(previewUsage(id), previewSlot(id)); }

    function previewPercent(id) { return BarWindows.maxPercent(previewWindows(id)); }

    // The providers the bar would show, in the widget's pill-mode rules.
    function previewProviders() {
        const mode = live("pillMode", "auto");
        if (mode === "custom") return pillIds.filter(function(id) { return isSelected(id); });
        if (mode === "top") {
            let best = null;
            for (let i = 0; i < selectedIds.length; i++) {
                if (!best || previewPercent(selectedIds[i]) > previewPercent(best)) best = selectedIds[i];
            }
            return best ? [best] : [];
        }
        return selectedIds.slice();
    }

    function previewIsBalance(windowData) {
        return !!windowData && windowData.isBalance === true && String(windowData.displayValue || "").length > 0;
    }

    function previewNumber(windowData) {
        if (previewIsBalance(windowData)) return String(windowData.displayValue);
        const used = Math.max(0, Math.min(100, Number(windowData.usedPercent) || 0));
        return Math.round(live("showRemainingQuota", "false") === "true" ? 100 - used : used) + "%";
    }

    // The widget's usage scale.
    function previewColor(percent) {
        if (percent >= 80) return Theme.error;
        if (percent >= 60) return Theme.warning;
        return Theme.success;
    }

    function previewWindowTag(windowData) {
        const minutes = Number(windowData && windowData.windowMinutes) || 0;
        if (minutes > 0 && minutes % 1440 === 0) return t("time.days", "{d}d", { d: minutes / 1440 });
        if (minutes > 0 && minutes % 60 === 0) return t("time.hours", "{h}h", { h: minutes / 60 });
        if (minutes > 0) return t("time.minutes", "{m}m", { m: minutes });
        return "";
    }

    function previewWindowLabel(windowData) {
        const minutes = Number(windowData && windowData.windowMinutes) || 0;
        if (previewIsBalance(windowData)) return t("window.balance", "Balance");
        if (minutes > 0 && minutes <= 300) return t("window.session", "Session");
        if (minutes > 0 && minutes <= 10080) return t("window.weekly", "Weekly");
        if (minutes > 0) return t("window.monthly", "Monthly");
        return "";
    }

    // The tooltip line the widget builds: provider, window and number per
    // displayed window.
    function previewTooltipText() {
        const remaining = live("showRemainingQuota", "false") === "true";
        const entries = previewProviders().map(function(id) {
            const segment = [providerDisplayName(id)];
            const windows = previewWindows(id);
            for (let i = 0; i < windows.length; i++) {
                const label = previewWindowLabel(windows[i]);
                if (label.length > 0) segment.push(label);
                segment.push(previewIsBalance(windows[i]) || !remaining
                    ? previewNumber(windows[i])
                    : t("quota.remaining", "{percent}% left", { percent: parseInt(previewNumber(windows[i]), 10) }));
            }
            return segment.join(" · ");
        });
        return entries.join("   •   ");
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
                            text: t("app.title", "AiOverviewControl")
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

                DActionButton {
                    objectName: "settings-expand-all"
                    Layout.alignment: Qt.AlignVCenter
                    iconName: root.allGroupsExpanded ? "unfold_less" : "unfold_more"
                    iconColor: Theme.primary
                    backgroundColor: Theme.withAlpha(Theme.primary, 0.1)
                    buttonSize: 36
                    tooltipText: root.allGroupsExpanded ? t("settings.collapse_all", "Collapse all sections") : t("settings.expand_all", "Expand all sections")
                    onClicked: root.setAllGroupsExpanded(!root.allGroupsExpanded)
                }

                DActionButton {
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


    // Live preview of the bar pill: every change below shows up here before
    // the bar picks it up on its next refresh.
    PillPreview {
        objectName: "settings-preview"
        width: parent.width
    }

    SettingsGroup {
        groupId: "general"
        groupTitle: t("settings.group.general", "General")
        groupIcon: "tune"

        ValueDropdown {
            objectName: "setting-languageOverride"
            width: parent.width
            text: t("settings.language.label", "Language")
            description: t("settings.language.description", "UI language for this plugin. Auto follows system locale.")
            selected: { root.settingsEpoch; return loadValue("languageOverride", "auto"); }
            values: root.languageValues
            labels: root.languageLabels
            optionIcons: ["language", "translate", "translate", "translate", "translate", "translate"]
            dropdownWidth: 230
            onPicked: function(value) { saveValue("languageOverride", value); }
        }

        ValueDropdown {
            objectName: "setting-refreshInterval"
            width: parent.width
            text: t("settings.refresh_interval", "Refresh interval")
            description: t("settings.refresh_description", "How often the plugin queries selected local adapters and provider APIs.")
            selected: { root.settingsEpoch; return loadValue("refreshInterval", "120000"); }
            values: root.refreshValues
            labels: root.refreshLabels
            optionIcons: ["timer", "timer", "timer", "timer", "timer"]
            dropdownWidth: 230
            onPicked: function(value) { saveValue("refreshInterval", value); }
        }
    }

    SettingsGroup {
        groupId: "bar"
        groupTitle: t("settings.group.bar", "Bar pill")
        groupIcon: "view_week"

        ValueDropdown {
            id: pillModeDropdown
            objectName: "setting-pillMode"
            width: parent.width
            text: t("settings.pill_mode.label", "Pill mode")
            description: t("settings.pill_mode.description", "Auto shows providers with measurable usage. Custom uses the list below.")
            selected: { root.settingsEpoch; return loadValue("pillMode", "auto"); }
            values: root.pillModeValues
            labels: root.pillModeLabels
            optionIcons: ["auto_awesome", "tune", "trending_up"]
            dropdownWidth: 230
            onPicked: function(value) { saveValue("pillMode", value); }
        }

        SubPanel {
            visible: pillModeDropdown.selected === "custom"
            panelTitle: t("settings.pill_providers.label", "Providers shown in the bar")
            panelDescription: t("settings.pill_providers.description", "Choose a compact subset of tracked providers. This only changes the bar pill; tracking and dashboard cards remain unchanged.")

            Flow {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.allProviders.filter(function(provider) { return root.isSelected(provider.id); })

                    Rectangle {
                        id: pillProviderChip
                        required property var modelData
                        readonly property bool active: root.isPillSelected(modelData.id)
                        objectName: "pill-provider-" + modelData.id
                        width: pillProviderRow.implicitWidth + Theme.spacingM * 2
                        height: 36
                        radius: 18
                        color: active
                            ? Theme.withAlpha(Theme.primary, 0.17)
                            : Theme.withAlpha(Theme.surfaceVariantText, pillProviderMouse.containsMouse ? 0.13 : 0.07)
                        border.width: active || activeFocus ? 1 : 0
                        border.color: Theme.withAlpha(Theme.primary, activeFocus ? 0.9 : 0.48)
                        activeFocusOnTab: true
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: modelData.name
                        Accessible.checked: active
                        Keys.onReturnPressed: root.togglePillProvider(modelData.id)
                        Keys.onSpacePressed: root.togglePillProvider(modelData.id)
                        Behavior on color { ColorAnimation { duration: 140 } }

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

                            DIcon {
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

        // Pill footprint controls (issue #33): logo + percentage only, and a
        // tighter gap around the separator dot for crowded bars.
        SettingToggle {
            settingKey: "pillShowNames"
            defaultValue: true
            text: t("settings.pill_show_names", "Provider names in pill")
            description: t("settings.pill_show_names_desc", "Turn off to keep only each provider's logo and percentage. The tooltip still names them.")
        }

        SettingToggle {
            settingKey: "pillCompact"
            defaultValue: false
            text: t("settings.pill_compact", "Compact pill spacing")
            description: t("settings.pill_compact_desc", "Tightens the gap around the dot between providers and inside each entry.")
        }

        SettingToggle {
            settingKey: "showRemainingQuota"
            defaultValue: false
            text: t("settings.show_remaining", "Show remaining quota")
            description: t("settings.show_remaining_desc", "Show available quota instead of consumed quota in the pill and dashboard. Alert thresholds still use consumption.")
        }

        SettingToggle {
            settingKey: "pillTooltip"
            defaultValue: true
            text: t("settings.pill_tooltip", "Bar pill tooltip")
            description: t("settings.pill_tooltip_desc", "Hovering the bar pill spells out the provider, which quota window the percentage came from, and when it resets.")
        }

        // Per-provider DankBar window selection (issues #17 and #86). The
        // tracked-provider list is never empty (normalizeProviderSelection
        // guarantees one entry), so the panel always has a row.
        SubPanel {
            objectName: "setting-barWindowOverrides"
            panelTitle: t("settings.bar_window.label", "Bar usage window")
            panelDescription: t("settings.bar_window.short", "Which quota window each provider shows in the bar. The dashboard keeps showing every window.")

            InlineHelp {
                helpText: t("settings.bar_window.description", "Providers with more than one quota window (e.g. Claude's 5 hour and 7 day) show the primary window in the bar by default, or a later window once it is used up, so an account blocked by its weekly limit reads 100% instead of an idle 5 hour window. Pick Primary to always keep the primary window. Choose another window per provider, or several at once: each is then tagged with its length, as in 5h 45% / 7d 80%. The dashboard keeps showing every window. \"Highest\" follows the most-constrained window; providers without the chosen window fall back to the primary.")
            }

            Repeater {
                model: root.selectedIds

                RowLayout {
                    id: barWindowRow
                    required property string modelData
                    width: parent.width
                    spacing: Theme.spacingS

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.withAlpha(Theme.primary, 0.1)

                        ProviderLogo {
                            anchors.centerIn: parent
                            providerId: barWindowRow.modelData
                            logoSize: 15
                            tintColor: root.providerLogoColor
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.providerDisplayName(barWindowRow.modelData)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    ValueDropdown {
                        objectName: "bar-window-" + barWindowRow.modelData
                        Layout.preferredWidth: 230
                        selected: { root.settingsEpoch; return root.barChoiceFor(barWindowRow.modelData); }
                        values: ["auto", "primary", "secondary", "tertiary", "highest", "primary+secondary", "all"]
                        labels: [t("settings.option.auto_window", "Automatic"), t("settings.option.primary", "Primary"), t("settings.option.secondary", "Secondary"), t("settings.option.tertiary", "Tertiary"), t("settings.option.highest", "Highest"), t("settings.option.primary_secondary", "Primary + secondary"), t("settings.option.all_windows", "All windows")]
                        optionIcons: ["auto_mode", "looks_one", "looks_two", "looks_3", "trending_up", "view_agenda", "view_list"]
                        dropdownWidth: 230
                        onPicked: function(value) { root.setBarChoice(barWindowRow.modelData, value); root.previewEpoch++; }
                    }
                }
            }
        }
    }

    SettingsGroup {
        groupId: "dashboard"
        groupTitle: t("settings.group.dashboard", "Dashboard")
        groupIcon: "dashboard"

        ValueDropdown {
            objectName: "setting-densityMode"
            width: parent.width
            text: t("settings.density.label", "Dashboard density")
            description: t("settings.density.description", "Comfortable keeps full previews. Compact reduces card height and visual detail.")
            selected: { root.settingsEpoch; return loadValue("densityMode", "comfortable"); }
            values: root.densityValues
            labels: root.densityLabels
            optionIcons: ["view_agenda", "density_small"]
            dropdownWidth: 230
            onPicked: function(value) { saveValue("densityMode", value); }
        }

        ValueDropdown {
            objectName: "setting-costCurrency"
            width: parent.width
            text: t("settings.cost_currency", "Estimated cost currency")
            description: t("settings.cost_currency_desc", "Convert USD analytics for display using daily exchange rates. Balances and stored amounts stay unchanged; unavailable rates fall back to USD.")
            selected: { root.settingsEpoch; return loadValue("costCurrency", "USD"); }
            values: ["USD", "EUR", "BRL", "GBP", "CAD", "CNY", "JPY", "AUD", "CHF"]
            labels: values
            optionIcons: ["attach_money", "euro", "payments", "currency_pound", "payments", "currency_yuan", "currency_yen", "payments", "currency_franc"]
            dropdownWidth: 230
            onPicked: function(value) { saveValue("costCurrency", value); }
        }

        // One monochrome tint for every provider logo. Stored empty means
        // "follow the theme accent", the same contract the widget uses.
        RowLayout {
            objectName: "setting-providerLogoColor"
            width: parent.width
            spacing: Theme.spacingM

            Column {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    width: parent.width
                    text: t("settings.logo_color", "Provider logo color")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                }

                StyledText {
                    width: parent.width
                    text: t("settings.logo_color_desc", "One monochrome color for every provider logo in the dashboard and desktop notifications.")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }

            DActionButton {
                objectName: "logo-color-theme"
                Layout.alignment: Qt.AlignVCenter
                visible: { root.previewEpoch; return String(loadValue("providerLogoColor", "") || "").length > 0; }
                buttonSize: 32
                iconName: "format_color_reset"
                iconColor: Theme.surfaceVariantText
                backgroundColor: "transparent"
                tooltipText: t("settings.logo_color_theme", "Follow the theme accent")
                onClicked: {
                    saveValue("providerLogoColor", "");
                    root.providerLogoColor = Theme.primary;
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: swatchRow.implicitWidth + Theme.spacingM * 2
                implicitHeight: 40
                radius: 20
                color: swatchMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.4)
                Behavior on color { ColorAnimation { duration: 140 } }

                Row {
                    id: swatchRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 22
                        height: 22
                        radius: 11
                        color: root.providerLogoColor
                        border.color: Theme.withAlpha(Theme.surfaceText, 0.3)
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    ProviderLogo {
                        providerId: "claude"
                        logoSize: 16
                        tintColor: root.providerLogoColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DIcon {
                        name: "colorize"
                        size: 15
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: swatchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openProviderLogoColorPicker()
                }
            }
        }

        SettingToggle {
            settingKey: "showErrorProviders"
            defaultValue: true
            text: t("settings.show_errors", "Show providers with errors")
            description: t("settings.show_errors_desc", "Keep authentication and configuration failures visible in the dashboard.")
        }

        SettingToggle {
            settingKey: "showClaudeProjects"
            defaultValue: true
            text: t("settings.show_projects", "Show Claude projects")
            description: t("settings.show_projects_desc", "List the week's top projects inside the Claude card.")
        }

        SettingToggle {
            settingKey: "showAntigravityModelDetails"
            defaultValue: false
            text: t("settings.antigravity_model_details", "Show individual Antigravity models")
            description: t("settings.antigravity_model_details_desc", "By default Antigravity shows the same Gemini and Claude/OpenAI quota families as its Models screen. Enable this only for per-model troubleshooting.")
        }
    }

    SettingsGroup {
        groupId: "notifications"
        groupTitle: t("settings.group.notifications", "Notifications")
        groupIcon: "notifications"

        SettingToggle {
            id: notifyToggle
            settingKey: "quotaNotifications"
            defaultValue: true
            text: t("settings.notify.label", "Quota notifications")
            description: t("settings.notify.description", "Alert once when a provider crosses the threshold, then update the same notification if its quota is exhausted.")
        }

        // Everything below only applies while alerts are on, so it folds
        // under the switch instead of sitting greyed out.
        SubPanel {
            visible: notifyToggle.checked

            ValueDropdown {
                objectName: "setting-notifyThreshold"
                width: parent.width
                text: t("settings.notify.threshold", "Notification threshold")
                description: t("settings.notify.threshold_desc", "Usage percent that triggers a notification.")
                selected: { root.settingsEpoch; return loadValue("notifyThreshold", "85"); }
                values: ["75", "85", "95"]
                labels: ["75%", "85%", "95%"]
                optionIcons: ["notifications", "notifications_active", "notification_important"]
                dropdownWidth: 230
                onPicked: function(value) { saveValue("notifyThreshold", value); }
            }

            ValueDropdown {
                objectName: "setting-notifyWindowScope"
                width: parent.width
                text: t("settings.notify.window_scope", "Windows that raise alerts")
                description: t("settings.notify.window_scope_desc", "“Displayed” alerts on whatever windows the bar shows for each provider — identical to “Primary” until you override a provider above. “All windows” also alerts on Claude's 7 day, Codex's weekly, and every other secondary window.")
                selected: { root.settingsEpoch; return loadValue("notifyWindowScope", "displayed"); }
                values: root.scopeValues
                labels: root.scopeLabels
                optionIcons: ["align_horizontal_left", "select_all", "looks_one"]
                dropdownWidth: 230
                onPicked: function(value) { saveValue("notifyWindowScope", value); }
            }

            ValueDropdown {
                objectName: "setting-notifyCooldownMinutes"
                width: parent.width
                text: t("settings.notify.cooldown", "Re-alert interval")
                description: t("settings.notify.cooldown_desc", "0 alerts once per quota window. Other values update the same notification after that many minutes while usage stays high.")
                selected: { root.settingsEpoch; return loadValue("notifyCooldownMinutes", "0"); }
                values: ["0", "60", "360", "1440"]
                labels: [t("settings.option.once", "Once per window")].concat([1, 6, 24].map(n => t("settings.option.hours", "{count} h", { count: n })))
                optionIcons: ["notifications_off", "schedule", "schedule", "schedule"]
                dropdownWidth: 230
                onPicked: function(value) { saveValue("notifyCooldownMinutes", value); }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingXS

                StyledText {
                    width: parent.width
                    text: t("settings.notify.overrides", "Per-provider threshold overrides")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                }

                StyledText {
                    width: parent.width
                    text: t("settings.notify.overrides_desc", "Comma-separated provider:percent pairs that beat the global threshold.")
                    wrapMode: Text.WordWrap
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                DTextField {
                    id: thresholdOverridesField
                    objectName: "setting-notifyThresholds"
                    width: parent.width
                    placeholderText: "claude:90,codex:75"
                    isError: root.notifyThresholdIssues(text).length > 0
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

                        DIcon {
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
        }
    }

    SettingsGroup {
        groupId: "providers"
        groupTitle: t("settings.group.providers", "Providers")
        groupIcon: "hub"

        StyledRect {
            objectName: "settings-detect-providers"
            width: parent.width
            radius: Theme.cornerRadius + 2
            color: Theme.withAlpha(Theme.primary, 0.06)
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, 0.18)
            implicitHeight: settingsDetectPanel.implicitHeight + Theme.spacingM * 2

            DetectProvidersPanel {
                id: settingsDetectPanel
                objectName: "settings-detect-panel"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                healthScript: root.healthScript
                catalog: root.detectCatalog
                trackedIds: root.selectedIds
                translate: root.t
                locale: root.i18nLocale
                logoColor: root.providerLogoColor
                onApplyRequested: ids => root.addProviders(ids)
            }
        }

        DSearchField {
            id: providerSearch
            objectName: "provider-search"
            width: parent.width
            placeholderText: t("settings.providers.search", "Search providers")
            text: root.providerQuery
            onTextChanged: root.providerQuery = text
        }

        StyledText {
            width: parent.width
            visible: root.providerQuery.trim().length > 0
                && root.allProviders.filter(function(provider) { return root.providerMatches(provider); }).length === 0
            text: t("settings.providers.no_match", "No provider matches “{query}”.", { query: root.providerQuery.trim() })
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
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

        // The same selection as a comma-separated list, for pasting a set of
        // providers in one go.
        InlineHelp {
            helpLabel: t("settings.providers.edit_text", "Edit the list as text")
            helpIcon: "edit_note"

            DTextField {
                objectName: "setting-providerSelection"
                width: parent.width
                text: { root.settingsEpoch; return root.selectedIds.join(","); }
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

    SettingsGroup {
        groupId: "profiles"
        groupTitle: t("settings.claude_profiles", "Claude profiles")
        groupIcon: "manage_accounts"

        StyledText {
            width: parent.width
            text: t("settings.claude_profiles_desc", "Track separate Claude accounts. Each profile reads only its own CLAUDE_CONFIG_DIR; sign in with Claude before adding it.")
            wrapMode: Text.WordWrap
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        Repeater {
            model: Object.keys(root.claudeProfiles)

            StyledRect {
                id: profileCard
                required property string modelData
                width: parent.width
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.72)
                border.width: 1
                border.color: Theme.withAlpha(Theme.primary, 0.14)
                implicitHeight: profileRow.implicitHeight + Theme.spacingS * 2

                RowLayout {
                    id: profileRow
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 32
                        height: 32
                        radius: 16
                        color: Theme.withAlpha(Theme.primary, 0.12)

                        ProviderLogo {
                            anchors.centerIn: parent
                            providerId: "claude"
                            logoSize: 17
                            tintColor: root.providerLogoColor
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            width: parent.width
                            text: root.claudeProfiles[profileCard.modelData].name + "  ·  " + profileCard.modelData
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root.claudeProfiles[profileCard.modelData].configDir
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.family: "monospace"
                            elide: Text.ElideMiddle
                        }
                    }

                    DActionButton {
                        objectName: "claude-profile-remove-" + profileCard.modelData
                        Layout.alignment: Qt.AlignVCenter
                        buttonSize: 30
                        iconName: "delete"
                        iconColor: Theme.error
                        backgroundColor: "transparent"
                        tooltipText: t("settings.claude_profile_remove", "Remove")
                        onClicked: root.removeClaudeProfile(profileCard.modelData)
                    }
                }
            }
        }

        SubPanel {
            panelTitle: t("settings.claude_profile_new", "Add a profile")

            GridLayout {
                width: parent.width
                columns: width > 560 ? 2 : 1
                columnSpacing: Theme.spacingS
                rowSpacing: Theme.spacingS

                DTextField {
                    id: claudeProfileId
                    objectName: "claude-profile-id"
                    Layout.fillWidth: true
                    placeholderText: t("settings.claude_profile_id", "Provider ID, e.g. claude-work")
                }

                DTextField {
                    id: claudeProfileName
                    objectName: "claude-profile-name"
                    Layout.fillWidth: true
                    placeholderText: t("settings.claude_profile_name", "Display name, e.g. Claude Work")
                }

                DTextField {
                    id: claudeProfileDir
                    objectName: "claude-profile-dir"
                    Layout.fillWidth: true
                    Layout.columnSpan: parent.columns
                    placeholderText: t("settings.claude_profile_dir", "Absolute CLAUDE_CONFIG_DIR path")
                }
            }

            DButton {
                objectName: "claude-profile-add"
                text: t("settings.claude_profile_add", "Add Claude profile")
                iconName: "person_add"
                onClicked: {
                    if (root.addClaudeProfile(claudeProfileId.text, claudeProfileName.text, claudeProfileDir.text)) {
                        claudeProfileId.text = "";
                        claudeProfileName.text = "";
                        claudeProfileDir.text = "";
                    }
                }
            }

            StyledText {
                width: parent.width
                visible: root.claudeProfileError.length > 0
                text: root.claudeProfileError
                wrapMode: Text.WordWrap
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    SettingsGroup {
        groupId: "data"
        groupTitle: t("settings.group.data", "History and data")
        groupIcon: "history"

        ValueDropdown {
            objectName: "setting-historyRetention"
            width: parent.width
            text: t("settings.history_retention", "Usage history retention")
            description: t("settings.history_retention_desc", "Snapshots kept per trim of the local usage history (sparklines and trends).") + "\n" + t("settings.history_count", "{count} snapshots stored · last trim removed {trimmed}", { count: root.historySnapshotCount, trimmed: root.historyLastTrimmed })
            selected: { root.settingsEpoch; return loadValue("historyRetention", "2000"); }
            values: root.historyValues
            labels: root.historyLabels
            optionIcons: ["history", "history", "history"]
            dropdownWidth: 230
            onPicked: function(value) { saveValue("historyRetention", value); }
        }

        // Usage history export. The store is an append-only JSONL cache the plugin
        // trims on its own, so a copy is the only way to keep long-term data.
        SubPanel {
            panelTitle: t("settings.history_export", "Export usage history")
            panelDescription: t("settings.history_export_desc", "Writes every recorded snapshot to your downloads folder. CSV opens in a spreadsheet; JSONL is the raw store.")

            Row {
                spacing: Theme.spacingS

                DButton {
                    text: "CSV"
                    iconName: "table_view"
                    enabled: !exportProcess.running
                    onClicked: root.exportHistory("csv")
                }

                DButton {
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

    SettingsGroup {
        groupId: "diagnostics"
        groupTitle: t("settings.diagnostics", "Diagnostics and tests")
        groupIcon: "terminal"

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

                        DActionButton {
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
                    ? t("settings.reset_confirm_desc", "This restores every option on this page, including tracked providers, pins, notification thresholds, and bar window overrides. Recorded usage history is kept.")
                    : t("settings.reset_desc", "Restore every option on this page to its default. Recorded usage history is kept.")
                wrapMode: Text.WordWrap
                color: resetCard.armed ? Theme.error : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                spacing: Theme.spacingS

                DButton {
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

                DButton {
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

    // DDropdown shows its raw option strings, so stored values ("compact",
    // "primary", "120000") would leak into the UI untranslated. This keeps the
    // stored value and the translated label apart: `values` are persisted,
    // `labels` are what the user reads.
    component ValueDropdown: DDropdown {
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

            DIcon {
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

    component ProviderSection: Column {
        id: providerSection
        required property string title
        required property string description
        required property var providers
        property string sectionIcon: ""
        spacing: Theme.spacingS
        // A search that matches nothing here hides the whole section.
        visible: providers.some(function(p) { return root.providerMatches(p); })

        Row {
            spacing: Theme.spacingS

            DIcon {
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
                model: providerSection.providers.filter(function(p) { return root.providerMatches(p); })
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

                            DIcon {
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
                model: providerSection.providers.filter(function(p) { return root.isSelected(p.id) && root.providerMatches(p); })
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

                        DActionButton {
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
                                text: providerDetailRow.health.status === "ready" ? t("settings.health.ready", "Ready") : root.healthDetailText(providerDetailRow.health.detail)
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


    // A foldable group of settings: an icon, a title, and while folded a
    // one-line summary of what it holds. The body animates open.
    component SettingsGroup: StyledRect {
        id: group
        required property string groupId
        property string groupTitle: ""
        property string groupIcon: ""
        readonly property bool expanded: root.isGroupExpanded(groupId)
        default property alias groupContent: groupBody.data

        objectName: "settings-group-" + groupId
        width: parent ? parent.width : 0
        radius: Theme.cornerRadius + 2
        // Opaque on purpose: the window behind the page can be translucent.
        color: groupHeaderMouse.containsMouse && !expanded ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, groupHeader.activeFocus ? 0.8 : (expanded ? 0.18 : 0.1))
        implicitHeight: groupHeader.height + (expanded ? groupBody.implicitHeight + Theme.spacingM : 0)
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }

        Item {
            id: groupHeader
            width: parent.width
            height: groupHeaderRow.implicitHeight + Theme.spacingM * 2
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: group.groupTitle
            Keys.onReturnPressed: root.setGroupExpanded(group.groupId, !group.expanded)
            Keys.onSpacePressed: root.setGroupExpanded(group.groupId, !group.expanded)

            RowLayout {
                id: groupHeaderRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingM

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 34
                    height: 34
                    radius: 17
                    color: Theme.withAlpha(Theme.primary, group.expanded ? 0.18 : 0.11)
                    Behavior on color { ColorAnimation { duration: 140 } }

                    DIcon {
                        anchors.centerIn: parent
                        name: group.groupIcon
                        size: 18
                        color: Theme.primary
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    StyledText {
                        width: parent.width
                        text: group.groupTitle
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        objectName: "settings-group-summary-" + group.groupId
                        width: parent.width
                        visible: !group.expanded && text.length > 0
                        text: root.groupSummary(group.groupId)
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                }

                DIcon {
                    Layout.alignment: Qt.AlignVCenter
                    name: "expand_more"
                    size: 20
                    color: group.expanded ? Theme.primary : Theme.surfaceVariantText
                    rotation: group.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }

            MouseArea {
                id: groupHeaderMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setGroupExpanded(group.groupId, !group.expanded)
            }
        }

        Column {
            id: groupBody
            anchors.top: groupHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingM
            visible: group.expanded || group.height > groupHeader.height + 1
            opacity: group.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
    }

    // A tinted panel that groups related controls inside a settings group.
    component SubPanel: StyledRect {
        id: panel
        property string panelTitle: ""
        property string panelDescription: ""
        default property alias panelContent: panelBody.data

        width: parent ? parent.width : 0
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, 0.6)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.12)
        implicitHeight: panelColumn.implicitHeight + Theme.spacingM * 2

        Column {
            id: panelColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                visible: panel.panelTitle.length > 0
                text: panel.panelTitle
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
            }

            StyledText {
                width: parent.width
                visible: panel.panelDescription.length > 0
                text: panel.panelDescription
                wrapMode: Text.WordWrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Column {
                id: panelBody
                width: parent.width
                spacing: Theme.spacingS
            }
        }
    }

    // A boolean setting stored as "true"/"false", like every other key.
    component SettingToggle: DToggle {
        id: settingToggle
        required property string settingKey
        property bool defaultValue: false

        objectName: "setting-" + settingKey
        // DToggle insets its text by spacingM; bleed out to align with the other rows.
        x: -Theme.spacingM
        width: (parent ? parent.width : 0) + Theme.spacingM * 2
        checked: { root.settingsEpoch; return loadValue(settingKey, defaultValue ? "true" : "false") === "true"; }
        onToggled: function(checked) { saveValue(settingKey, checked ? "true" : "false"); }
    }

    // A "How it works" disclosure: long explanations stay one click away
    // instead of pushing the controls down. Extra children render under the
    // text when it is open.
    component InlineHelp: Column {
        id: help
        property string helpLabel: t("settings.how_it_works", "How it works")
        property string helpIcon: "help_outline"
        property string helpText: ""
        property bool open: false
        default property alias helpContent: helpBody.data

        width: parent ? parent.width : 0
        spacing: Theme.spacingXS

        Rectangle {
            implicitWidth: helpRow.implicitWidth + Theme.spacingM * 2
            implicitHeight: 30
            radius: 15
            color: Theme.withAlpha(Theme.primary, helpMouse.containsMouse ? 0.14 : 0.07)
            Behavior on color { ColorAnimation { duration: 140 } }
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: help.helpLabel
            Keys.onReturnPressed: help.open = !help.open
            Keys.onSpacePressed: help.open = !help.open

            Row {
                id: helpRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DIcon {
                    name: help.helpIcon
                    size: 14
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: help.helpLabel
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeSmall - 1
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }

                DIcon {
                    name: "expand_more"
                    size: 14
                    color: Theme.primary
                    rotation: help.open ? 180 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on rotation { NumberAnimation { duration: 160 } }
                }
            }

            MouseArea {
                id: helpMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: help.open = !help.open
            }
        }

        StyledText {
            width: parent.width
            visible: help.open && help.helpText.length > 0
            text: help.helpText
            wrapMode: Text.WordWrap
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        Column {
            id: helpBody
            width: parent.width
            visible: help.open
            spacing: Theme.spacingS
        }
    }

    // The bar pill as the widget draws it, on a strip that stands in for the
    // bar, with a vertical bar beside it and the hover tooltip under it.
    component PillPreview: StyledRect {
        id: preview
        readonly property var entries: root.previewProviders()
        readonly property bool compact: root.live("pillCompact", "false") === "true"
        readonly property bool names: root.live("pillShowNames", "true") === "true"
        readonly property bool tooltip: root.live("pillTooltip", "true") === "true"

        radius: Theme.cornerRadius + 2
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.14)
        implicitHeight: previewColumn.implicitHeight + Theme.spacingM * 2

        Column {
            id: previewColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                DIcon {
                    name: "visibility"
                    size: 16
                    color: Theme.primary
                    Layout.alignment: Qt.AlignVCenter
                }

                StyledText {
                    text: t("settings.preview.title", "Live preview")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignVCenter
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    text: t("settings.preview.sample", "Sample numbers")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Theme.spacingS

                    // Horizontal bar.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: 46
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.surfaceContainer, 0.9)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.surfaceText, 0.06)
                        clip: true

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            // Neighbouring bar widgets, for scale.
                            Repeater {
                                model: ["apps", "wifi"]
                                Rectangle {
                                    required property string modelData
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: Theme.withAlpha(Theme.surfaceText, 0.05)
                                    DIcon { anchors.centerIn: parent; name: parent.modelData; size: 15; color: Theme.withAlpha(Theme.surfaceText, 0.35) }
                                }
                            }

                            Rectangle {
                                objectName: "preview-pill"
                                height: 30
                                width: Math.max(30, horizontalPill.implicitWidth + 20)
                                radius: 15
                                color: Theme.widgetBaseBackgroundColor
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    id: horizontalPill
                                    anchors.centerIn: parent
                                    spacing: 0

                                    Repeater {
                                        model: preview.entries

                                        Row {
                                            id: previewEntry
                                            required property string modelData
                                            required property int index
                                            readonly property var windows: root.previewWindows(modelData)
                                            objectName: "preview-entry-" + modelData
                                            spacing: preview.compact ? 2 : 4

                                            StyledText {
                                                visible: previewEntry.index > 0
                                                text: preview.compact ? "·" : " · "
                                                leftPadding: preview.compact ? 2 : 0
                                                color: Theme.withAlpha(Theme.surfaceText, 0.3)
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            ProviderLogo {
                                                providerId: previewEntry.modelData
                                                logoSize: 14
                                                tintColor: root.providerLogoColor
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            StyledText {
                                                visible: preview.names
                                                text: root.providerDisplayName(previewEntry.modelData)
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Repeater {
                                                model: previewEntry.windows

                                                Row {
                                                    id: previewWindow
                                                    required property var modelData
                                                    required property int index
                                                    spacing: preview.compact ? 2 : 3
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    StyledText {
                                                        visible: previewWindow.index > 0
                                                        text: "/"
                                                        color: Theme.withAlpha(Theme.surfaceText, 0.3)
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.DemiBold
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }

                                                    StyledText {
                                                        visible: previewEntry.windows.length > 1
                                                        text: root.previewWindowTag(previewWindow.modelData)
                                                        color: Theme.surfaceVariantText
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.DemiBold
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }

                                                    StyledText {
                                                        objectName: "preview-number"
                                                        text: root.previewNumber(previewWindow.modelData)
                                                        color: root.previewColor(Number(previewWindow.modelData.usedPercent || 0))
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.Bold
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    StyledText {
                                        visible: preview.entries.length === 0
                                        text: t("pill.no_data", "N/A")
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }

              // The tooltip shown on hover, when it is enabled.
              Rectangle {
                  objectName: "preview-tooltip"
                  visible: preview.tooltip && preview.entries.length > 0
                  Layout.maximumWidth: parent.width
                  Layout.preferredWidth: tooltipText.implicitWidth + 13 + Theme.spacingS + Theme.spacingM * 2
                  Layout.preferredHeight: tooltipText.implicitHeight + Theme.spacingS * 2
                  radius: Theme.cornerRadius
                  color: Theme.surfaceContainerHighest
                  border.width: 1
                  border.color: Theme.withAlpha(Theme.outline, 0.25)

                  Row {
                      anchors.fill: parent
                      anchors.margins: Theme.spacingS
                      anchors.leftMargin: Theme.spacingM
                      spacing: Theme.spacingS

                      DIcon {
                          id: tooltipIcon
                          name: "mouse"
                          size: 13
                          color: Theme.surfaceVariantText
                          anchors.verticalCenter: parent.verticalCenter
                      }

                      StyledText {
                          id: tooltipText
                          width: parent.width - tooltipIcon.width - Theme.spacingS
                          text: root.previewTooltipText()
                          color: Theme.surfaceText
                          font.pixelSize: Theme.fontSizeSmall - 1
                          elide: Text.ElideRight
                          anchors.verticalCenter: parent.verticalCenter
                      }
                  }
              }
                }

                // Vertical bar: logo over number, one block per provider.
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 46
                    implicitHeight: Math.max(46, verticalPill.implicitHeight + 16)
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainer, 0.9)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.surfaceText, 0.06)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 30
                        height: verticalPill.implicitHeight + 12
                        radius: 15
                        color: Theme.widgetBaseBackgroundColor

                        Column {
                            id: verticalPill
                            anchors.centerIn: parent
                            spacing: preview.compact ? 2 : Theme.spacingXS

                            Repeater {
                                model: preview.entries.slice(0, 4)

                                Column {
                                    id: verticalEntry
                                    required property string modelData
                                    readonly property var windows: root.previewWindows(modelData)
                                    spacing: 1

                                    ProviderLogo {
                                        providerId: verticalEntry.modelData
                                        logoSize: 13
                                        tintColor: root.providerLogoColor
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    StyledText {
                                        text: root.previewNumber(verticalEntry.windows[0] || {})
                                        color: root.previewColor(BarWindows.maxPercent(verticalEntry.windows))
                                        font.pixelSize: Theme.fontSizeSmall - 3
                                        font.weight: Font.Bold
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
