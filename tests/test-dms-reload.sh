#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/plugin/scripts"
cp "$ROOT/scripts/reload-plugin" "$TMP/plugin/scripts/"
cp "$ROOT"/*.qml "$ROOT"/*.js "$ROOT/plugin.json" "$ROOT/qmldir" "$TMP/plugin/"
cp -r "$ROOT/i18n" "$TMP/plugin/"
RELOAD="$TMP/plugin/scripts/reload-plugin"
export QS_CALLS="$TMP/qs-calls"
cat > "$TMP/bin/qs" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QS_CALLS"
case "$*" in
  'list --all') printf 'Instance mail:\nInstance shell:\n' ;;
  'ipc -i mail call plugins list') echo 'otherPlugin [loaded]' ;;
  'ipc -i shell call plugins list')
    [[ "${RELOAD_DISABLED:-0}" == 1 ]] && echo 'aiOverviewControl [disabled]' || echo 'aiOverviewControl [loaded]' ;;
  'ipc -i shell call plugins reload aiOverviewControl')
    [[ "${RELOAD_FAIL:-0}" == 1 ]] && echo 'PLUGIN_RELOAD_FAILED: aiOverviewControl' || echo 'PLUGIN_RELOAD_SUCCESS: aiOverviewControl' ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TMP/bin/qs"
export PATH="$TMP/bin:$PATH"
bash "$RELOAD" | grep -q 'shell: PLUGIN_RELOAD_SUCCESS'
if RELOAD_DISABLED=1 bash "$RELOAD" >/dev/null 2>&1; then exit 1; fi
if RELOAD_FAIL=1 bash "$RELOAD" >/dev/null 2>&1; then exit 1; fi
if bash "$RELOAD" 'unsafe;id' >/dev/null 2>&1; then exit 1; fi
# A broken checkout must never unload the healthy widget already in the shell.
printf '<<<<<<< HEAD\n' > "$TMP/plugin/i18n/en.json"
: > "$QS_CALLS"
if bash "$RELOAD" > "$TMP/invalid-json.log" 2>&1; then
  echo 'FAIL: reload accepted a malformed translation bundle' >&2; exit 1
fi
[[ ! -s "$QS_CALLS" ]] || { echo 'FAIL: invalid JSON reached the running shell' >&2; exit 1; }
cp "$ROOT/i18n/en.json" "$TMP/plugin/i18n/en.json"
rm "$TMP/plugin/ClaudeProfiles.js"
if bash "$RELOAD" > "$TMP/missing-module.log" 2>&1; then
  echo 'FAIL: reload accepted a missing JavaScript module' >&2; exit 1
fi
[[ ! -s "$QS_CALLS" ]] || { echo 'FAIL: missing module reached the running shell' >&2; exit 1; }
cp "$ROOT/ClaudeProfiles.js" "$TMP/plugin/"
mv "$TMP/plugin/AiOverviewControlWidget.qml" "$TMP/plugin/widget.backup"
if bash "$RELOAD" > "$TMP/missing-widget.log" 2>&1; then
  echo 'FAIL: reload accepted a missing widget entry point' >&2; exit 1
fi
[[ ! -s "$QS_CALLS" ]] || { echo 'FAIL: missing widget reached the running shell' >&2; exit 1; }
mv "$TMP/plugin/widget.backup" "$TMP/plugin/AiOverviewControlWidget.qml"
mv "$TMP/plugin/CurrencyFormatter.qml" "$TMP/plugin/currency.backup"
if bash "$RELOAD" > "$TMP/missing-type.log" 2>&1; then
  echo 'FAIL: reload accepted a missing qmldir type' >&2; exit 1
fi
[[ ! -s "$QS_CALLS" ]] || { echo 'FAIL: missing QML type reached the running shell' >&2; exit 1; }
mv "$TMP/plugin/currency.backup" "$TMP/plugin/CurrencyFormatter.qml"
printf '\n<<<<<<< HEAD\n' >> "$TMP/plugin/AiOverviewControlWidget.qml"
if bash "$RELOAD" > "$TMP/conflict.log" 2>&1; then
  echo 'FAIL: reload accepted unresolved runtime source' >&2; exit 1
fi
[[ ! -s "$QS_CALLS" ]] || { echo 'FAIL: unresolved source reached the running shell' >&2; exit 1; }
echo 'OK: DMS discovery, disabled/missing plugin, reload failure and fail-closed runtime preflight'
