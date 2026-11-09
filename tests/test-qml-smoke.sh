#!/usr/bin/env bash
# Runtime smoke for the extracted fetch component, without a live DMS session.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v qs >/dev/null || { echo 'QML smoke requires Quickshell (qs)' >&2; exit 1; }
TMP="$(mktemp -d)"
pid=""
trap 'if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT
cp "$ROOT/LocalAnalyticsReader.qml" "$ROOT/lib/BarWindows.js" "$ROOT/ClaudeProfiles.js" "$ROOT/detect/ProviderDetect.js" "$TMP/"
python3 - "$ROOT/AiOverviewControlWidget.qml" "$TMP/ProviderOrder.js" <<'PY'
import re, sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
function = re.search(r'    function reorderedPins\(.*?(?=\n    function )', source, re.S)
assert function, 'Pinned-order function missing'
Path(sys.argv[2]).write_text('.pragma library\n' + function.group(0) + '\n')
PY
printf 'LocalAnalyticsReader 1.0 LocalAnalyticsReader.qml\n' > "$TMP/qmldir"
cat > "$TMP/adapter" <<'SH'
case "${1:-empty}" in
  empty) [[ $# == 0 ]] || exit 1; printf '{"tokens":7}\n' ;;
  success) printf '{"tokens":42}\n' ;;
  malformed) printf 'not json\n' ;;
  error) printf '{"error":"fixture"}\n' ;;
  failed) printf '{"tokens":42}\n'; exit 1 ;;
  hang) exec sleep 10 ;;
esac
SH
cat > "$TMP/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "ProviderOrder.js" as ProviderOrder
import "BarWindows.js" as BarWindows
import "ClaudeProfiles.js" as ClaudeProfiles
import "ProviderDetect.js" as ProviderDetect
ShellRoot {
    id: root
    FloatingWindow { visible: true; implicitWidth: 1; implicitHeight: 1 }
    property int step: 0
    property bool readerDone: false
    property bool retainedDone: false
    function finish() { if (readerDone && retainedDone) console.warn("QML_SMOKE_OK"); }
    property var cases: ["success", "malformed", "error", "failed", "hang", "success"]
    LocalAnalyticsReader {
        id: reader
        providerId: "success"
        scriptPath: Qt.resolvedUrl("adapter").toString().replace("file://", "")
        timeoutMs: 250
        onCompleted: {
            const valid = root.cases[root.step] === "success";
            if ((valid && (!result || result.tokens !== 42)) || (!valid && result !== null)) {
                console.error("SMOKE FAIL: " + root.cases[root.step]);
                return;
            }
            root.step++;
            if (root.step === root.cases.length) {
                root.readerDone = true;
                root.finish();
            } else {
                providerId = root.cases[root.step];
                next.start();
            }
        }
    }
    Timer { id: next; interval: 20; onTriggered: { reader.refresh(); reader.refresh(); } }
    property int retainedStep: 0
    property var retainedCases: ["success", "malformed", "failed", "hang", "error", "success", "empty"]
    LocalAnalyticsReader {
        id: retained
        providerId: root.retainedCases[root.retainedStep] || "success"
        commandArguments: providerId === "empty" ? [] : [providerId]
        scriptPath: reader.scriptPath
        timeoutMs: 250
        retainOnFailure: true
        onCompleted: {
            const expected = providerId === "error" ? null : (providerId === "empty" ? 7 : 42);
            if ((expected === null && result !== null) || (expected !== null && (!result || result.tokens !== expected))) {
                console.error("SMOKE FAIL: retention " + providerId);
                return;
            }
            root.retainedStep++;
            if (root.retainedStep === root.retainedCases.length) {
                root.retainedDone = true;
                root.finish();
            } else {
                nextRetained.start();
            }
        }
    }
    Timer { id: nextRetained; interval: 20; onTriggered: { retained.refresh(); retained.refresh(); } }
    function claudeDetailsOk() {
        const profiles = {"claude-work": {name: "Work", configDir: "/w"}};
        const now = new Date(2026, 9, 10, 12, 0, 0);
        const analytics = {
            weekTokens: 1000, weekCost: 2, monthTokens: 5000, monthCost: 10, todayCost: 0.5,
            dailyTokens: [1, 2, "3"], dailyCosts: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
            weekModels: "opus:900,sonnet:100", weekModelCosts: "opus:1.50",
            weekProjects: "/a:b/c:42,/home/me:7", rateLimitTier: "default_claude_max_20x",
            scopedModel: "Fable", alltimeSessions: 3, alltimeMessages: 9, firstSession: "2025-01-01",
            extraUsage: {enabled: false}
        };
        const usage = {
            primary: {usedPercent: 30, resetsAt: "2026-10-10T15:00:00Z", windowMinutes: 300},
            secondary: {usedPercent: 60, resetsAt: "2026-10-12T00:00:00Z"},
            tertiary: {usedPercent: 40, resetsAt: "2026-10-12T00:00:00Z"}
        };
        const d = ClaudeProfiles.details({provider: "claude-work", usage: usage, analytics: analytics}, profiles, now);
        const failed = ClaudeProfiles.details({provider: "claude", error: {kind: "authentication"}, analytics: analytics}, profiles, now);
        const checks = [
            ClaudeProfiles.details({provider: "codex", analytics: analytics}, profiles, now) === null,
            ClaudeProfiles.details({provider: "claude-x", analytics: analytics}, profiles, now) === null,
            ClaudeProfiles.details({provider: "claude", usage: usage}, profiles, now) === null,
            d !== null && d.tier === "default_claude_max_20x",
            d && JSON.stringify(d.models) === JSON.stringify([{name: "Opus", tokens: 900, cost: 1.5}, {name: "Sonnet", tokens: 100, cost: 0}]),
            d && d.projects.length === 2 && d.projects[0].path === "/a:b/c" && d.projects[0].tokens === 42,
            d && d.dailyTokens.length === 7 && d.dailyTokens[2] === 3 && d.dailyTokens[6] === 0,
            d && d.dailyCosts.length === 7 && d.dailyCosts[6] === 0.7,
            d && d.session.percent === 30 && d.weekly.percent === 60,
            // The window length travels with each details window, so the
            // panel paces it like any other quota window; none reads null.
            d && d.session.windowMinutes === 300 && d.weekly.windowMinutes === null,
            d && d.scoped && d.scoped.model === "Fable" && d.scoped.percent === 40 && d.scoped.windowMinutes === null,
            d && Math.abs(d.monthProjection - 31) < 1e-9,
            failed !== null && failed.session === null && failed.weekly === null && failed.weekTokens === 1000
        ];
        const bad = checks.indexOf(false);
        if (bad >= 0) console.error("SMOKE FAIL: claude details check " + bad);
        return bad < 0;
    }
    // Issue #86: one provider can put several quota windows in the bar.
    function barWindowsOk() {
        const usage = {
            primary: {usedPercent: 45, windowMinutes: 300},
            secondary: {usedPercent: 80, windowMinutes: 10080},
            tertiary: null
        };
        const weeklyOnly = {primary: null, secondary: {usedPercent: 12}, tertiary: null};
        const blocked = {primary: {usedPercent: 0, windowMinutes: 300}, secondary: {usedPercent: 100, windowMinutes: 10080}, tertiary: null};
        const blockedTertiary = {primary: {usedPercent: 10}, secondary: {usedPercent: 90}, tertiary: {usedPercent: 100}};
        const bothExhausted = {primary: {usedPercent: 100}, secondary: {usedPercent: 100}, tertiary: null};
        const pcts = windows => windows.map(w => w.usedPercent).join(",");
        const alias = id => ({"z.ai": "zai"})[id.toLowerCase()] || id.toLowerCase();
        const map = BarWindows.parseOverrides(
            " claude:Secondary+PRIMARY, codex:all,z.ai:highest,glm:primary+bogus,kimi:primary+primary,x:,:all,bad, cline:primary+secondary+tertiary", alias);
        const checks = [
            BarWindows.normalizeSlot("secondary+primary") === "primary+secondary",
            BarWindows.normalizeSlot("tertiary+secondary+primary") === "all",
            BarWindows.normalizeSlot("primary+") === "" && BarWindows.normalizeSlot(undefined) === "",
            JSON.stringify(map) === JSON.stringify({claude: "primary+secondary", codex: "all", zai: "highest", cline: "all"}),
            pcts(BarWindows.windowsFor(usage, "primary+secondary")) === "45,80",
            pcts(BarWindows.windowsFor(usage, "all")) === "45,80",
            pcts(BarWindows.windowsFor(usage, "secondary")) === "80",
            pcts(BarWindows.windowsFor(usage, "highest")) === "80",
            pcts(BarWindows.windowsFor(usage, "tertiary")) === "45",
            pcts(BarWindows.windowsFor(usage, undefined)) === "45",
            pcts(BarWindows.windowsFor(weeklyOnly, "primary+tertiary")) === "12",
            BarWindows.windowsFor(null, "all").length === 0 && BarWindows.windowsFor({}, "all").length === 0,
            BarWindows.isMultiSlot("all") && BarWindows.isMultiSlot("primary+secondary") && !BarWindows.isMultiSlot("highest"),
            BarWindows.maxPercent(BarWindows.windowsFor(usage, "all")) === 80 && BarWindows.maxPercent([]) === 0,
            // No override: an exhausted later window headlines while the
            // primary still has room; an explicit "primary" keeps the primary.
            pcts(BarWindows.windowsFor(blocked, "")) === "100",
            pcts(BarWindows.windowsFor(blocked, undefined)) === "100",
            pcts(BarWindows.windowsFor(blocked, "primary")) === "0",
            BarWindows.headlineWindow(blocked) === blocked.secondary,
            BarWindows.headlineWindow(blockedTertiary) === blockedTertiary.tertiary,
            BarWindows.headlineWindow(bothExhausted) === bothExhausted.primary,
            BarWindows.headlineWindow(usage) === usage.primary,
            BarWindows.headlineWindow(weeklyOnly) === weeklyOnly.secondary,
            BarWindows.headlineWindow(null) === null && BarWindows.headlineWindow({}) === null,
            BarWindows.isExhausted({usedPercent: 100}) && BarWindows.isExhausted({usedPercent: "120"})
                && !BarWindows.isExhausted({usedPercent: 99.9}) && !BarWindows.isExhausted(null)
        ];
        const bad = checks.indexOf(false);
        if (bad >= 0) console.error("SMOKE FAIL: bar windows check " + bad);
        return bad < 0;
    }
    // Pace of a quota window: the even-use share elapsed, and a projection
    // that only speaks past 15% of the window and 5 points over even use.
    function paceOk() {
        const now = Date.parse("2026-10-10T12:00:00Z");
        const at = minutes => new Date(now + minutes * 60000).toISOString();
        // 5 h window, 2 h in (40% elapsed), reset in 3 h.
        const win = used => ({usedPercent: used, windowMinutes: 300, resetsAt: at(180)});
        const hot = BarWindows.pace(win(70), now);
        const even = BarWindows.pace(win(44), now);
        const calm = BarWindows.pace(win(20), now);
        const idle = BarWindows.pace(win(0), now);
        const full = BarWindows.pace(win(100), now);
        // 7 d window, 10 h in: under 15% elapsed, too early to project.
        const early = BarWindows.pace({usedPercent: 90, windowMinutes: 10080, resetsAt: at(9480)}, now);
        const near = (a, b) => Math.abs(a - b) < 1e-6;
        const checks = [
            hot !== null && near(hot.expected, 40) && near(hot.resetMinutes, 180),
            // 70% in 120 min: the remaining 30% lasts 51.43 min, before the 3 h reset.
            hot.projects && hot.runsOut && near(hot.exhaustMinutes, 30 * 120 / 70),
            even.projects && !even.runsOut && even.exhaustMinutes === null,
            calm.projects && !calm.runsOut,
            !idle.projects && !idle.runsOut && near(idle.expected, 40),
            !full.projects && !full.runsOut,
            early !== null && !early.projects && !early.runsOut && near(early.expected, 600 / 10080 * 100),
            // Nothing to pace: no window, a balance, no length, a bad
            // percentage, no or an unreadable reset, a reset already past
            // or further away than the window is long.
            BarWindows.pace(null, now) === null,
            BarWindows.pace({usedPercent: 0, isBalance: true, windowMinutes: 300, resetsAt: at(60)}, now) === null,
            BarWindows.pace({usedPercent: 0, displayValue: "Unlimited", windowMinutes: 43200, resetsAt: at(600)}, now) === null,
            BarWindows.pace({usedPercent: 0, displayValue: "300 / 300 remaining", windowMinutes: 43200, resetsAt: at(600)}, now) !== null,
            BarWindows.pace({usedPercent: 10, resetsAt: at(60)}, now) === null,
            BarWindows.pace({usedPercent: 10, windowMinutes: 0, resetsAt: at(60)}, now) === null,
            BarWindows.pace({usedPercent: "n/a", windowMinutes: 300, resetsAt: at(60)}, now) === null,
            BarWindows.pace({usedPercent: 10, windowMinutes: 300}, now) === null,
            BarWindows.pace({usedPercent: 10, windowMinutes: 300, resetsAt: "soon"}, now) === null,
            BarWindows.pace({usedPercent: 10, windowMinutes: 300, resetsAt: at(-1)}, now) === null,
            BarWindows.pace({usedPercent: 10, windowMinutes: 300, resetsAt: at(0)}, now) === null,
            BarWindows.pace({usedPercent: 10, windowMinutes: 300, resetsAt: at(300)}, now) === null,
            BarWindows.pace({usedPercent: "12", windowMinutes: "300", resetsAt: at(150)}, now).expected === 50
        ];
        const bad = checks.indexOf(false);
        if (bad >= 0) console.error("SMOKE FAIL: pace check " + bad);
        return bad < 0;
    }
    // Provider detection: strong evidence is offered ticked, weak evidence
    // unticked, tracked and non-ready providers are not offered, and only
    // catalog IDs count.
    function detectOk() {
        const catalog = [
            {id: "codex", name: "Codex"}, {id: "deepseek", name: "DeepSeek"},
            {id: "vertexai", name: "Vertex AI"}, {id: "claude", name: "Claude"},
            {id: "mistral", name: "Mistral"}, {id: "perplexity", name: "Perplexity"},
            {id: "antigravity"}, {id: "pi", name: "pi"}, {id: "absent", name: "Absent"}
        ];
        const items = [
            {provider: "codex", status: "ready", evidence: {kind: "login", label: "~/.codex/auth.json"}},
            {provider: "deepseek", status: "ready", evidence: {kind: "key", label: "DEEPSEEK_API_KEY"}},
            {provider: "vertexai", status: "ready", evidence: {kind: "cli", label: "gcloud"}},
            {provider: "claude", status: "ready", evidence: {kind: "local", label: "~/.claude"}},
            {provider: "mistral", status: "missing", detail: "MISTRAL_API_KEY", evidence: null},
            {provider: "perplexity", status: "info", evidence: null},
            {provider: "antigravity", status: "ready", evidence: {kind: "keyring", label: "secret-tool"}},
            {provider: "pi", status: "ready"},
            {provider: "claude-work", status: "ready", evidence: {kind: "login", label: "x"}},
            null, {status: "ready"}
        ];
        const result = ProviderDetect.classify(items, catalog, ["claude"]);
        const ids = rows => rows.map(row => row.id).join(",");
        const checks = [
            ids(result.found) === "codex,deepseek",
            ids(result.possible) === "vertexai,antigravity,pi",
            ids(result.tracked) === "claude",
            result.scanned === 8,
            result.found[1].kind === "key" && result.found[1].label === "DEEPSEEK_API_KEY",
            result.possible[1].name === "antigravity" && result.possible[2].kind === "" && result.possible[2].label === "",
            ProviderDetect.defaultPicks(result).join(",") === "codex,deepseek",
            ProviderDetect.defaultPicks(null).length === 0,
            ProviderDetect.isStrong({kind: "vault"}) && !ProviderDetect.isStrong({kind: "cli"}) && !ProviderDetect.isStrong(null),
            ProviderDetect.classify(null, null, null).scanned === 0,
            ProviderDetect.merge(["codex", "claude"], ["Claude", " deepseek ", "", "deepseek"]).join(",") === "codex,claude,deepseek",
            ProviderDetect.merge(null, ["groq"]).join(",") === "groq",
            ProviderDetect.toggled(["a", "b"], "a").join(",") === "b",
            ProviderDetect.toggled(null, "a").join(",") === "a"
        ];
        const bad = checks.indexOf(false);
        if (bad >= 0) console.error("SMOKE FAIL: provider detection check " + bad);
        return bad < 0;
    }
    Component.onCompleted: {
        if (!claudeDetailsOk() || !barWindowsOk() || !paceOk() || !detectOk()) return;
        const pins = ["codex", "claude", "kimi-code"];
        if (ProviderOrder.reorderedPins(pins, "kimi-code", "codex").join(",") !== "kimi-code,codex,claude"
            || ProviderOrder.reorderedPins(pins, "codex", "kimi-code").join(",") !== "claude,codex,kimi-code"
            || ProviderOrder.reorderedPins(pins, "unknown", "codex").join(",") !== pins.join(",")
            || ProviderOrder.reorderedPins(pins, "codex", "codex").join(",") !== pins.join(",")
            || pins.join(",") !== "codex,claude,kimi-code") {
            console.error("SMOKE FAIL: pinned order");
            return;
        }
        next.start();
        nextRetained.start();
    }
}
QML
env -u WAYLAND_DISPLAY -u QSG_USE_SIMPLE_ANIMATION_DRIVER -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen timeout 15 qs --no-color -p "$TMP/shell.qml" > "$TMP/log" 2>&1 &
pid=$!
for _ in {1..100}; do
    grep -q 'QML_SMOKE_OK' "$TMP/log" && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
grep -q 'QML_SMOKE_OK' "$TMP/log" || { printf '%s\n' "$(<"$TMP/log")" >&2; exit 1; }
if grep -Ei 'SMOKE FAIL|ReferenceError|TypeError|binding loop|Failed to load configuration' "$TMP/log"; then exit 1; fi
echo 'OK: Claude details view model, quota window pace, provider detection, QML JSON parsing, failure retention, timeout, retry, empty arguments and refresh deduplication'
