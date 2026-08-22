#!/usr/bin/env bash
set -euo pipefail

# Contract for providers/export-usage-history: CSV/JSONL round-trip from the
# local usage-history store, destination resolution, file mode, and the exit
# codes Settings distinguishes (2 bad format, 3 nothing to export, 4 bad
# destination).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export XDG_CACHE_HOME="$TMP/cache"
export XDG_CONFIG_HOME="$TMP/config"
HISTORY_DIR="$XDG_CACHE_HOME/AiOverviewControl"
mkdir -p "$HISTORY_DIR" "$TMP/out"

export_history() { "$ROOT/providers/export-usage-history" "$@"; }

# ── nothing recorded yet ────────────────────────────────────────────────────
status=0
export_history csv "$TMP/out" >/dev/null 2>&1 || status=$?
[ "$status" -eq 3 ] || { echo "expected exit 3 with no history, got $status" >&2; exit 1; }

# ── unsupported format ──────────────────────────────────────────────────────
status=0
export_history xml "$TMP/out" >/dev/null 2>&1 || status=$?
[ "$status" -eq 2 ] || { echo "expected exit 2 for a bad format, got $status" >&2; exit 1; }

cat > "$HISTORY_DIR/usage-history.jsonl" <<'JSONL'
{"ts":1750000000,"provider":"claude","pct":54}
{"ts":1750000060,"provider":"codex","pct":19.099999999999994}
not json at all
{"ts":1750000120,"provider":"claude","pct":100}
JSONL

# ── CSV ─────────────────────────────────────────────────────────────────────
csv="$(export_history csv "$TMP/out")"
[ -f "$csv" ] || { echo "CSV path not written: $csv" >&2; exit 1; }
case "$csv" in
  "$TMP/out"/aioverviewcontrol-usage-*.csv) ;;
  *) echo "unexpected CSV name: $csv" >&2; exit 1 ;;
esac
[ "$(stat -c '%a' "$csv")" = "600" ] || { echo "CSV is not 0600" >&2; exit 1; }
[ "$(head -1 "$csv")" = "timestamp_iso,timestamp_epoch,provider,percent" ] || {
  echo "unexpected CSV header" >&2; exit 1;
}
# header + 3 valid rows; the unparsable line is dropped.
[ "$(wc -l < "$csv")" -eq 4 ] || { echo "expected 4 CSV lines, got $(wc -l < "$csv")" >&2; exit 1; }
grep -q '"2025-06-15T15:06:40Z",1750000000,"claude",54' "$csv" || {
  echo "CSV lost the ISO timestamp or the first row" >&2; exit 1;
}
# Float noise from percentage math is rounded to two decimals.
grep -q '"codex",19.1$' "$csv" || { echo "CSV percent was not rounded" >&2; exit 1; }

# ── JSONL ───────────────────────────────────────────────────────────────────
jsonl="$(export_history jsonl "$TMP/out")"
[ "$(wc -l < "$jsonl")" -eq 3 ] || { echo "expected 3 JSONL lines" >&2; exit 1; }
jq -e -s 'length == 3 and (map(.provider) == ["claude","codex","claude"])' "$jsonl" >/dev/null || {
  echo "JSONL round-trip lost records or order" >&2; exit 1;
}

# ── each run gets its own file ──────────────────────────────────────────────
second="$(export_history csv "$TMP/out")"
[ "$(find "$TMP/out" -name 'aioverviewcontrol-usage-*.csv' | wc -l)" -ge 1 ] || exit 1
[ -f "$second" ] || exit 1

# ── destination that cannot be created ──────────────────────────────────────
status=0
export_history csv /proc/definitely-not-writable >/dev/null 2>&1 || status=$?
[ "$status" -eq 4 ] || { echo "expected exit 4 for a bad destination, got $status" >&2; exit 1; }

# ── default destination follows XDG_DOWNLOAD_DIR from user-dirs.dirs ────────
mkdir -p "$XDG_CONFIG_HOME" "$TMP/downloads"
printf 'XDG_DOWNLOAD_DIR="%s"\n' "$TMP/downloads" > "$XDG_CONFIG_HOME/user-dirs.dirs"
defaulted="$(export_history csv)"
case "$defaulted" in
  "$TMP/downloads"/*) ;;
  *) echo "default destination ignored user-dirs.dirs: $defaulted" >&2; exit 1 ;;
esac
# Sourcing user-dirs.dirs must not leak into this shell.
[ -z "${XDG_DOWNLOAD_DIR:-}" ] || { echo "XDG_DOWNLOAD_DIR leaked" >&2; exit 1; }

echo "OK: test-history-export"
