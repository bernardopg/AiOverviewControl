#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
pid=""
trap 'if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT
command -v qs >/dev/null || { echo 'Currency smoke requires Quickshell' >&2; exit 1; }
cp "$ROOT/CurrencyFormatter.qml" "$ROOT/LocalAnalyticsReader.qml" "$TMP/"
printf 'CurrencyFormatter 1.0 CurrencyFormatter.qml\nLocalAnalyticsReader 1.0 LocalAnalyticsReader.qml\n' > "$TMP/qmldir"
cat > "$TMP/adapter" <<'SH'
stale=false
case "$1" in
 BRL) rate=5; stale=true ;;
 EUR) rate=0.9 ;;
 JPY) rate=150 ;;
 CNY) sleep 0.3; rate=7 ;;
 CHF) echo '{"error":"offline"}'; exit 0 ;;
 *) exit 1 ;;
esac
printf '{"base":"USD","currency":"%s","rate":%s,"date":"2026-09-29","stale":%s}\n' "$1" "$rate" "$stale"
SH
cat > "$TMP/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
    id: root
    property int step: 0
    property bool failed: false
    FloatingWindow { visible: true; implicitWidth: 1; implicitHeight: 1 }
    CurrencyFormatter {
        id: money
        scriptPath: Qt.resolvedUrl("adapter").toString().replace("file://", "")
    }
    function check(ok, message) {
        if (!ok) {
            failed = true;
            console.error("SMOKE FAIL: " + message);
        }
    }
    Timer {
        interval: 20; repeat: true; running: !root.failed
        onTriggered: {
            if (root.step === 0) {
                root.check(money.format(1234.5, "en_US") === "$1,234.50", "USD precision");
                root.check(money.format(0.001, "en_US") === "<$0.01", "sub-cent cost");
                for (const amount of [null, undefined, NaN, Infinity, true, false, [], {}, "", "   "])
                    root.check(money.format(amount, "en_US") === "—", "invalid amounts");
                root.check(money.format("2", "en_US") === "$2.00", "numeric string amount");
                root.check(money.format(-2, "en_US") === "$-2.00", "refunds");
                money.currency = "BRL"; root.step = 1;
            } else if (root.step === 1 && money.available && !money.loading) {
                root.check(money.format(2, "pt_BR") === "BRL 10,00", "BRL and locale");
                money.currency = "EUR"; root.step = 2;
            } else if (root.step === 2 && money.available && !money.loading) {
                root.check(money.format(2, "en_US") === "EUR 1.80", "EUR switch");
                money.currency = "CHF"; root.step = 3;
            } else if (root.step === 3 && money.quote === null && !money.loading) {
                root.check(!money.available && money.format(2, "en_US") === "$2.00", "honest USD fallback");
                money.currency = "JPY"; root.step = 4;
            } else if (root.step === 4 && money.available && !money.loading) {
                root.check(money.format(2, "en_US") === "JPY 300", "JPY zero decimals");
                money.currency = "CNY"; switchBusy.start(); root.step = 5;
            } else if (root.step === 5 && money.currency === "BRL" && money.available && !money.loading) {
                root.check(money.format(2, "en_US") === "BRL 10.00", "latest selection wins while busy");
                root.check(money.stale, "cached quote indication");
                money.currency = "USD";
                root.check(money.format(2, "en_US") === "$2.00", "reset does not convert twice");
                root.step = 6;
                if (!root.failed) console.warn("CURRENCY_SMOKE_OK");
            }
        }
    }
    Timer { id: switchBusy; interval: 30; onTriggered: money.currency = "BRL" }
}
QML
env -u WAYLAND_DISPLAY -u QSG_USE_SIMPLE_ANIMATION_DRIVER -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen timeout 15 qs --no-color -p "$TMP/shell.qml" > "$TMP/log" 2>&1 &
pid=$!
for _ in {1..100}; do
 grep -q 'CURRENCY_SMOKE_OK' "$TMP/log" && break
 kill -0 "$pid" 2>/dev/null || break
 sleep 0.1
done
grep -q 'CURRENCY_SMOKE_OK' "$TMP/log" || { printf '%s\n' "$(<"$TMP/log")" >&2; exit 1; }
if grep -Ei 'SMOKE FAIL|ReferenceError|TypeError|binding loop|Failed to load configuration' "$TMP/log"; then exit 1; fi
echo 'OK: runtime currency conversion, locale, fallback, precision and in-flight settings changes'
