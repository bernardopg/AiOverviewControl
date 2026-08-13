#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cache"

cat > "$TMP/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >> "$NOTIFY_LOG"
printf '\n' >> "$NOTIFY_LOG"
printf '42\n'
SH
chmod +x "$TMP/bin/notify-send"

export PATH="$TMP/bin:$PATH"
export XDG_CACHE_HOME="$TMP/cache"
export NOTIFY_LOG="$TMP/notify.log"

alert() {
  "$ROOT/providers/send-quota-alert" \
    test:primary:300:window 3600 "$1" dialog-warning '#6750A4' \
    'Quota test' 'Fixture body'
}

alert normal
[ "$(wc -l < "$NOTIFY_LOG")" -eq 1 ]
jq -e '.["test:primary:300:window"] == {last: .["test:primary:300:window"].last, id: 42, level: 1}' \
  "$XDG_CACHE_HOME/AiOverviewControl/notify-state.json" >/dev/null

# Same-level repeats are suppressed during the cooldown, but a critical
# escalation bypasses it once and reuses the daemon notification ID.
alert normal
[ "$(wc -l < "$NOTIFY_LOG")" -eq 1 ]
alert critical
[ "$(wc -l < "$NOTIFY_LOG")" -eq 2 ]
grep -q -- '-r 42' "$NOTIFY_LOG"

# A critical alert is never downgraded. Clearing the key re-arms it.
alert normal
[ "$(wc -l < "$NOTIFY_LOG")" -eq 2 ]
"$ROOT/providers/send-quota-alert" --clear test:primary:300:window
alert normal
[ "$(wc -l < "$NOTIFY_LOG")" -eq 3 ]

echo 'Quota alert deduplication: OK'
