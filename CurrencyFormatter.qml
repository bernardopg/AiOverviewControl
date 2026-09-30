import QtQuick

// Display-only money module: amounts stay USD at the storage/adapter boundary.
Item {
    id: formatter
    required property string scriptPath
    property string currency: "USD"
    readonly property bool loading: readerLoader.item ? readerLoader.item.running : false
    readonly property var quote: readerLoader.item ? readerLoader.item.result : null
    readonly property bool available: currency === "USD" || (quote !== null
        && quote.base === "USD" && quote.currency === currency
        && typeof quote.rate === "number" && Number.isFinite(quote.rate) && quote.rate > 0)
    readonly property string effectiveCurrency: available ? currency : "USD"
    readonly property bool stale: available && currency !== "USD" && quote.stale === true
    readonly property string sourceDate: available && currency !== "USD" ? String(quote.date || "") : ""
    property bool refreshPending: false
    visible: false

    function format(usd, localeName) {
        if ((typeof usd !== "number" && typeof usd !== "string")
                || (typeof usd === "string" && usd.trim() === "")
                || !Number.isFinite(Number(usd)))
            return "—";
        const original = Number(usd);
        let code = effectiveCurrency;
        let value = original * (code === "USD" ? 1 : quote.rate);
        // An extreme malformed amount must never produce an Infinity label.
        if (!Number.isFinite(value)) {
            code = "USD";
            value = original;
        }
        const digits = code === "JPY" ? 0 : 2;
        const minimum = Math.pow(10, -digits);
        const prefix = code === "USD" ? "$" : code + " ";
        const locale = Qt.locale(localeName || "en_US");
        if (value > 0 && value < minimum)
            return "<" + prefix + minimum.toLocaleString(locale, 'f', digits);
        return prefix + value.toLocaleString(locale, 'f', digits);
    }

    function refresh() {
        if (currency === "USD") {
            refreshPending = false;
            return;
        }
        if (!readerLoader.item || readerLoader.item.running) {
            refreshPending = true;
            return;
        }
        refreshPending = false;
        readerLoader.item.scriptPath = scriptPath;
        readerLoader.item.commandArguments = [currency];
        readerLoader.item.refresh();
    }
    onCurrencyChanged: refresh()
    onScriptPathChanged: refresh()

    Loader {
        id: readerLoader
        Component.onCompleted: setSource(Qt.resolvedUrl("LocalAnalyticsReader.qml"), {
            providerId: "currency",
            scriptPath: formatter.scriptPath,
            timeoutMs: 25000
        })
        onLoaded: formatter.refresh()
    }
    Connections {
        target: readerLoader.item
        function onCompleted() {
            if (formatter.refreshPending)
                retry.start();
        }
    }
    Timer { id: retry; interval: 1; onTriggered: formatter.refresh() }
    Timer {
        interval: 3600000
        running: formatter.currency !== "USD"
        repeat: true
        onTriggered: formatter.refresh()
    }
}
