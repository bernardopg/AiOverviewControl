pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services

QtObject {
    id: root

    readonly property string pluginId: "aiOverviewControl"
    property string languageOverride: "auto"
    // "auto" detection chain, first usable value wins:
    //   1. DMS's own language setting (SessionData.locale), so the plugin
    //      follows the language the user configured in the shell;
    //   2. Qt.locale() — only when it names a real locale. DMS runs as a
    //      systemd user service whose manager environment may still carry
    //      LANG=C.UTF-8, which makes Qt.locale().name report "C" and would
    //      silently pin the UI to English even on a pt_BR desktop;
    //   3. the login-session locale exported in the process environment
    //      (LANGUAGE / LC_ALL / LC_MESSAGES / LANG);
    //   4. the system locale recorded in /etc/locale.conf or
    //      ~/.config/locale.conf (readable because DMS exports
    //      QML_XHR_ALLOW_FILE_READ=1 for the shell process).
    readonly property string localeName: detectLocale()

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

    // "C"/"POSIX" (and "C.UTF-8") carry no language information: they mean
    // "no locale configured", not "English".
    function isUsableLocale(value) {
        const v = (value || "").toString().trim();
        if (!v) return false;
        const lower = v.toLowerCase();
        return lower !== "c" && lower !== "posix" && lower.indexOf("c.") !== 0 && lower.indexOf("posix.") !== 0;
    }

    function detectLocale() {
        try {
            if (typeof SessionData !== "undefined" && isUsableLocale(SessionData.locale))
                return SessionData.locale;
        } catch (error) {}
        try {
            const qtName = (Qt.locale().name || "").toString();
            if (isUsableLocale(qtName)) return qtName;
        } catch (error) {}
        try {
            const envNames = ["LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"];
            for (let i = 0; i < envNames.length; i++) {
                let value = (Quickshell.env(envNames[i]) || "").toString();
                // LANGUAGE may be a colon-separated priority list.
                if (value.indexOf(":") !== -1) value = value.split(":")[0];
                if (isUsableLocale(value)) return value;
            }
        } catch (error) {}
        const home = (Quickshell.env("HOME") || "").toString();
        // Per-user locale.conf overrides the system-wide default.
        const files = [home + "/.config/locale.conf", "/etc/locale.conf"];
        const keys = ["LC_MESSAGES", "LANG", "LANGUAGE"];
        for (let f = 0; f < files.length; f++) {
            const contents = readTextFile("file://" + files[f]);
            if (!contents) continue;
            for (let k = 0; k < keys.length; k++) {
                const match = contents.match(new RegExp("^\\s*" + keys[k] + "\\s*=\\s*\"?([^\"\\n]+)", "m"));
                if (match && isUsableLocale(match[1])) return match[1].trim();
            }
        }
        return "en_US";
    }

    function readTextFile(url) {
        const xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", url, false);
            xhr.send();
            if (xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300)) return xhr.responseText;
        } catch (error) {}
        return "";
    }

    function normalizeLocale(value) {
        // Strip colon-list fallbacks (LANGUAGE=pt_BR:en), charset suffixes
        // (pt_BR.UTF-8) and modifiers (sr_RS@latin) before matching.
        let raw = (value || "").toString().trim();
        if (raw.indexOf(":") !== -1) raw = raw.split(":")[0];
        raw = raw.replace("-", "_").split(".")[0].split("@")[0].trim();
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
            const escapedParam = String(param).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            text = text.replace(new RegExp("\\{" + escapedParam + "\\}", "g"), () => value);
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
