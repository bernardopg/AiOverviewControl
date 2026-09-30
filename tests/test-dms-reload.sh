#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
cat > "$TMP/bin/qs" <<'SH'
#!/usr/bin/env bash
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
bash "$ROOT/scripts/reload-plugin" | grep -q 'shell: PLUGIN_RELOAD_SUCCESS'
if RELOAD_DISABLED=1 bash "$ROOT/scripts/reload-plugin" >/dev/null 2>&1; then exit 1; fi
if RELOAD_FAIL=1 bash "$ROOT/scripts/reload-plugin" >/dev/null 2>&1; then exit 1; fi
if bash "$ROOT/scripts/reload-plugin" 'unsafe;id' >/dev/null 2>&1; then exit 1; fi
echo 'OK: running DMS discovery, disabled/missing plugin and reload failure'
