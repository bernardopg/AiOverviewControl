// Per-provider DankBar window selection (`barWindowOverrides`, issues #17 and
// #86), shared by the widget and the settings body so both read the same slot
// vocabulary. Stateless, so it needs no `.pragma library`; keeping it plain
// JavaScript lets code scanning parse the module.
//
// It lives in lib/ rather than next to the widget (issue #92): a running shell
// caches the plugin directory listing the first time it loads the plugin, and
// a file added to that directory later fails to import with "File name case
// mismatch" until the shell restarts. 2.2.1 added this module to the plugin
// root, so an update without `dms restart` left the plugin unable to load.
//
// A slot is one window ("primary", "secondary", "tertiary"), "highest" (the
// most-constrained window), "all", or a "+"-joined set of windows such as
// "primary+secondary". Sets are stored in primary/secondary/tertiary order,
// and a set naming all three is stored as "all". No slot at all (no
// override for the provider) means the headline window below.

const SLOTS = ["primary", "secondary", "tertiary"];

// Canonical form of a raw slot, or "" when it is not valid. An unknown or
// repeated part makes the whole value invalid, so a typo can never blank the
// bar or quietly drop a window the user asked for.
function normalizeSlot(value) {
    const raw = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
    if (raw === "highest" || raw === "all") return raw;
    const parts = raw.split("+");
    const picked = [];
    for (let i = 0; i < parts.length; i++) {
        const part = parts[i].trim();
        if (SLOTS.indexOf(part) < 0 || picked.indexOf(part) >= 0) return "";
        picked.push(part);
    }
    const ordered = SLOTS.filter(function(slot) { return picked.indexOf(slot) >= 0; });
    return ordered.length === SLOTS.length ? "all" : ordered.join("+");
}

// Parses "id:slot,..." into {id: slot}. `normalizeId` maps a raw provider ID
// to its canonical form (the widget resolves aliases such as z.ai -> zai);
// entries with an empty ID or an invalid slot are discarded.
function parseOverrides(raw, normalizeId) {
    const map = {};
    const text = String(raw || "").trim();
    if (text.length === 0) return map;
    const pairs = text.split(",");
    for (let i = 0; i < pairs.length; i++) {
        const kv = pairs[i].split(":");
        if (kv.length !== 2) continue;
        const id = normalizeId ? normalizeId(kv[0].trim()) : kv[0].trim().toLowerCase();
        const slot = normalizeSlot(kv[1]);
        if (id.length === 0 || slot.length === 0) continue;
        map[id] = slot;
    }
    return map;
}

// True when the slot can put more than one window in the bar.
function isMultiSlot(slot) {
    return slot === "all" || String(slot || "").indexOf("+") >= 0;
}

// True when a window has no quota left: at or past 100% used.
function isExhausted(window) {
    return !!window && Number(window.usedPercent || 0) >= 100;
}

// The window that stands for a provider when nobody chose one: the primary
// window, unless the primary still has room while a later window is
// exhausted. A Codex or Claude account blocked by its weekly limit then reads
// 100% instead of the idle 5 hour window's 0%, which would claim quota the
// account cannot use. Only exhaustion promotes a window, so a busy but usable
// weekly window never displaces the primary one.
function headlineWindow(usage) {
    if (!usage) return null;
    const first = usage.primary || usage.secondary || usage.tertiary || null;
    if (!first || isExhausted(first)) return first;
    for (let i = 0; i < SLOTS.length; i++) {
        const window = usage[SLOTS[i]];
        if (window && window !== first && isExhausted(window))
            return window;
    }
    return first;
}

// The windows the DankBar shows for one usage payload, in slot order. Payload
// shapes vary per account (Codex weekly-only has a null secondary, Claude's
// tertiary only exists with a model-scoped limit), so absent windows are
// skipped, and when none of the chosen windows exists the primary window is
// shown instead: an override must never blank or zero the bar. An empty slot
// (no override) shows the headline window; an explicit "primary" keeps the
// primary window even when another one is exhausted.
function windowsFor(usage, slot) {
    if (!usage) return [];
    const fallback = usage.primary || usage.secondary || usage.tertiary || null;
    if (!fallback) return [];
    if (slot === undefined || slot === null || slot === "")
        return [headlineWindow(usage)];
    if (slot === "highest") {
        let best = null;
        for (let i = 0; i < SLOTS.length; i++) {
            const window = usage[SLOTS[i]];
            if (window && (!best || Number(window.usedPercent || 0) > Number(best.usedPercent || 0)))
                best = window;
        }
        return [best];
    }
    const chosen = slot === "all" ? SLOTS : String(slot || "primary").split("+");
    const result = [];
    for (let i = 0; i < SLOTS.length; i++) {
        if (chosen.indexOf(SLOTS[i]) >= 0 && usage[SLOTS[i]])
            result.push(usage[SLOTS[i]]);
    }
    return result.length > 0 ? result : [fallback];
}

// Highest used percentage among `windows`, or 0 for an empty list.
function maxPercent(windows) {
    let max = 0;
    for (let i = 0; i < (windows || []).length; i++)
        max = Math.max(max, Number(windows[i].usedPercent || 0));
    return max;
}
