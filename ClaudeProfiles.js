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
