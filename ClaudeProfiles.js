// Stateless, so it needs no `.pragma library`; keeping it plain JavaScript
// lets code scanning parse the module.
// ponytail: the settings editor supports 16 local Claude profiles; move to a
// paged account manager if installations need larger fleets.
function parse(value) {
    let source;
    try { source = typeof value === "string" ? JSON.parse(value) : value; }
    catch (error) { return {}; }
    if (!source || typeof source !== "object" || Array.isArray(source)) return {};
    const result = {};
    const ids = Object.keys(source);
    for (let i = 0; i < ids.length && Object.keys(result).length < 16; i++) {
        const id = ids[i];
        const profile = source[id];
        if (!/^claude-[a-z0-9][a-z0-9_-]{0,55}$/.test(id) || !profile) continue;
        if (typeof profile.configDir !== "string" || !profile.configDir.startsWith("/")
            || /[\x00-\x1f\x7f]/.test(profile.configDir)) continue;
        const name = typeof profile.name === "string" ? profile.name.trim() : id;
        if (!name || name.length > 80 || /[\x00-\x1f\x7f]/.test(name)) continue;
        result[id] = {name: name, configDir: profile.configDir};
    }
    return result;
}

// View model for one provider's "Claude Code details" panel, built only from
// that provider's own dispatcher item. Returns null for anything that is not
// a known Claude provider carrying local analytics.
function details(provider, profiles, now) {
    if (!provider || typeof provider !== "object") return null;
    const id = provider.provider;
    const known = id === "claude"
        || (typeof id === "string" && !!profiles && Object.prototype.hasOwnProperty.call(profiles, id));
    const analytics = provider.analytics;
    if (!known || !analytics || typeof analytics !== "object" || Array.isArray(analytics)) return null;
    const usage = provider.usage && typeof provider.usage === "object" ? provider.usage : null;

    function num(value) {
        const n = Number(value);
        return isFinite(n) ? n : 0;
    }
    function week(values) {
        const source = Array.isArray(values) ? values : [];
        const result = [];
        for (let i = 0; i < 7; i++) result.push(num(source[i]));
        return result;
    }
    function rate(window) {
        if (!window || typeof window !== "object") return null;
        return {percent: num(window.usedPercent), resetsAt: window.resetsAt || null};
    }
    function pairs(text) {
        const result = [];
        const entries = typeof text === "string" && text !== "" ? text.split(",") : [];
        for (let i = 0; i < entries.length; i++) {
            const split = entries[i].lastIndexOf(":");
            if (split <= 0) continue;
            result.push({key: entries[i].slice(0, split), value: num(entries[i].slice(split + 1))});
        }
        return result;
    }

    const costs = {};
    const costPairs = pairs(analytics.weekModelCosts);
    for (let i = 0; i < costPairs.length; i++) costs[costPairs[i].key] = costPairs[i].value;
    const models = pairs(analytics.weekModels).map(function (entry) {
        return {
            name: entry.key.charAt(0).toUpperCase() + entry.key.slice(1),
            tokens: entry.value,
            cost: costs[entry.key] || 0
        };
    });
    const projects = pairs(analytics.weekProjects).map(function (entry) {
        return {path: entry.key, tokens: entry.value};
    });

    const scopedWindow = usage ? rate(usage.tertiary) : null;
    const scoped = scopedWindow && analytics.scopedModel && scopedWindow.percent > 0
        ? {model: String(analytics.scopedModel), percent: scopedWindow.percent, resetsAt: scopedWindow.resetsAt}
        : null;

    const monthCost = num(analytics.monthCost);
    const date = now instanceof Date ? now : new Date();
    const daysInMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();

    return {
        tier: typeof analytics.rateLimitTier === "string" ? analytics.rateLimitTier : "unknown",
        extraUsage: analytics.extraUsage && typeof analytics.extraUsage === "object" ? analytics.extraUsage : null,
        session: usage ? rate(usage.primary) : null,
        weekly: usage ? rate(usage.secondary) : null,
        scoped: scoped,
        dailyTokens: week(analytics.dailyTokens),
        dailyCosts: week(analytics.dailyCosts),
        todayCost: num(analytics.todayCost),
        weekTokens: num(analytics.weekTokens),
        weekCost: num(analytics.weekCost),
        monthTokens: num(analytics.monthTokens),
        monthCost: monthCost,
        monthProjection: monthCost > 0 ? monthCost / date.getDate() * daysInMonth : 0,
        models: models,
        projects: projects,
        alltimeSessions: num(analytics.alltimeSessions),
        alltimeMessages: num(analytics.alltimeMessages),
        firstSession: analytics.firstSession || null
    };
}
