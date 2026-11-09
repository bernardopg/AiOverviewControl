// Provider detection, shared by the dashboard's "Detect providers" header
// button and the settings Providers group. Both run providers/get-provider-health
// over the provider catalog and pass its JSON here, so they offer the same
// providers for the same reasons. Stateless and plain JavaScript, like
// lib/BarWindows.js.
//
// It lives in its own directory for the reason lib/ does (issue #92): a
// running shell caches the file list of every plugin directory it has loaded
// from, so a module added to an existing one cannot load until a restart.
//
// Each ready provider carries the evidence the health check found: a `kind`
// and a `label` (a variable name, a command or a path under ~, never a secret).
// Strong evidence means an adapter can read the account as it is: an API key,
// a saved sign-in, the tool's local data or a keyring entry the user set up.
// Weak evidence only shows the tool is installed (a CLI on PATH, the desktop
// keyring tool) with the sign-in unverified, so those providers are offered
// but left unticked: tracking an account that is not signed in would only add
// an error card.

const STRONG_KINDS = ["key", "login", "local", "vault"];

// A plain array from an array or an array-like: a list that crossed a QML
// signal or property can arrive as a sequence wrapper that Array.isArray()
// rejects although it has a length and indexes.
function toList(value) {
    const result = [];
    if (value === null || value === undefined || typeof value === "string")
        return result;
    const length = Number(value.length) || 0;
    for (let i = 0; i < length; i++)
        result.push(value[i]);
    return result;
}

// True when `evidence` shows a usable account, not just an installed tool.
function isStrong(evidence) {
    return !!evidence && STRONG_KINDS.indexOf(String(evidence.kind || "")) >= 0;
}

// Splits a health result into what detection shows. `catalog` lists the
// providers to offer, as [{id, name}] in display order; health items for any
// other ID (Claude profiles, unknown IDs) are ignored, and so is every status
// other than "ready" ("missing", the "info" of providers without an API).
// Returns {found, possible, tracked, scanned}: ready providers not tracked yet
// with strong evidence, the same with weak evidence, ready providers already
// tracked, and how many catalog providers the result covered. Each row is
// {id, name, kind, label}.
function classify(items, catalog, trackedIds) {
    const byId = {};
    const list = toList(items);
    for (let i = 0; i < list.length; i++) {
        const item = list[i];
        if (item && typeof item.provider === "string")
            byId[item.provider] = item;
    }
    const tracked = toList(trackedIds);
    const result = {found: [], possible: [], tracked: [], scanned: 0};
    const entries = toList(catalog);
    for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        const item = entry ? byId[entry.id] : undefined;
        if (!item)
            continue;
        result.scanned++;
        if (item.status !== "ready")
            continue;
        const evidence = item.evidence || null;
        const row = {
            id: entry.id,
            name: String(entry.name || entry.id),
            kind: evidence ? String(evidence.kind || "") : "",
            label: evidence ? String(evidence.label || "") : ""
        };
        if (tracked.indexOf(entry.id) >= 0)
            result.tracked.push(row);
        else if (isStrong(evidence))
            result.found.push(row);
        else
            result.possible.push(row);
    }
    return result;
}

// The IDs ticked when results arrive: every strongly evidenced provider.
function defaultPicks(result) {
    return toList(result && result.found).map(function(row) { return row.id; });
}

// `selected` with every ID of `picked` appended once, keeping the order of
// both: the tracked providers stay where the user put them.
function merge(selected, picked) {
    const result = [];
    const add = function(id) {
        const value = String(id || "").trim().toLowerCase();
        if (value.length > 0 && result.indexOf(value) < 0)
            result.push(value);
    };
    toList(selected).forEach(add);
    toList(picked).forEach(add);
    return result;
}

// `picked` with `id` added or removed.
function toggled(picked, id) {
    const result = toList(picked);
    const index = result.indexOf(id);
    if (index >= 0)
        result.splice(index, 1);
    else
        result.push(id);
    return result;
}
