pragma Singleton

import QtQuick
import qs.Services

QtObject {
    id: root

    readonly property string pluginId: "aiOverviewControl"
    property string languageOverride: "auto"
    property string localeName: {
        try {
            return (Qt.locale().name || "en_US").toString();
        } catch (error) {
            return "en_US";
        }
    }

    readonly property string normalizedLocale: normalizeLocale(languageOverride === "auto" ? localeName : languageOverride)
    // bundleEpoch is a binding dependency so refresh() can force the two
    // translation properties to re-read the JSON files. This singleton survives
    // plugin hot-reloads, so without an explicit bust the cache would keep
    // serving the bundle that was on disk when the quickshell process started —
    // new keys added during a dev session would silently fall back to English.
    property int bundleEpoch: 0
    readonly property var fallbackTranslations: { bundleEpoch; return loadBundle("en_US"); }
    readonly property var activeTranslations: { bundleEpoch; return loadBundle(normalizedLocale); }
    property var bundleCache: ({})

    function refresh() {
        bundleCache = ({});
        bundleEpoch += 1;
    }

    function normalizeLocale(value) {
        const raw = (value || "en_US").toString().replace("-", "_").trim();
        if (!raw) return "en_US";
        const lower = raw.toLowerCase();
        if (lower.indexOf("pt") === 0) return "pt_BR";
        if (lower.indexOf("zh") === 0) return "zh_CN";
        if (lower.indexOf("es") === 0) return "es_ES";
        if (lower.indexOf("de") === 0) return "de_DE";
        return "en_US";
    }

    function bundleFile(locale) {
        if (locale === "pt_BR") return "i18n/pt_BR.json";
        if (locale === "zh_CN") return "i18n/zh_CN.json";
        if (locale === "es_ES") return "i18n/es_ES.json";
        if (locale === "de_DE") return "i18n/de_DE.json";
        return "i18n/en.json";
    }

    function loadBundle(locale) {
        const normalized = normalizeLocale(locale);
        if (bundleCache[normalized]) return bundleCache[normalized];
        const xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", Qt.resolvedUrl(bundleFile(normalized)), false);
            xhr.send();
            if (xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300)) {
                const parsed = JSON.parse(xhr.responseText || "{}");
                bundleCache[normalized] = parsed;
                return parsed;
            }
        } catch (error) {
            console.warn("AiOverviewControl i18n load failed", normalized, error);
        }
        bundleCache[normalized] = (normalized === "en_US") ? ({}) : loadBundle("en_US");
        return bundleCache[normalized];
    }

    function tr(key, fallback, params) {
        let text = activeTranslations[key];
        if (text === undefined || text === null || text === "") text = fallbackTranslations[key];
        if (text === undefined || text === null || text === "") text = fallback || key;
        if (!params) return text;
        for (const param in params) {
            const value = params[param] === undefined || params[param] === null ? "" : params[param].toString();
            text = text.replace(new RegExp("\{" + param + "\}", "g"), value);
        }
        return text;
    }

    function loadSettings() {
        const stored = PluginService.loadPluginData(pluginId, "languageOverride");
        languageOverride = (stored === undefined || stored === null || stored === "") ? "auto" : stored.toString();
    }

    property var pluginDataConnection: Connections {
        target: PluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId) loadSettings();
        }
    }

    Component.onCompleted: loadSettings()
}
