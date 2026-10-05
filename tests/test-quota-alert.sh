#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
# A failed assertion must not leave blocked fake notify-send waiters behind.
trap 'touch "$TMP/click" 2>/dev/null; wait; rm -rf "$TMP"' EXIT
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

# Click action: the waiter must not hold the state lock, must forward a
# default-action click to the focus IPC, and a re-send must replace (kill)
# the previous waiter instead of stacking one per reminder.
# Direct /bin/bash shebang: /proc/<pid>/comm must read "notify-send" (as for
# the real binary) or the helper will refuse to kill the stale waiter.
cat > "$TMP/bin/notify-send" <<'SH'
#!/bin/bash
printf '%q ' "$@" >> "$NOTIFY_LOG"
printf '\n' >> "$NOTIFY_LOG"
printf '%s\n' "${NOTIFY_ID:-42}"
# Like the real tool, only an action makes it wait; then block until the
# test "clicks" (creates CLICK_FILE).
[[ " $* " == *" -A "* ]] || exit 0
while [ ! -e "$CLICK_FILE" ]; do sleep 0.05; done
printf 'default\n'
SH
cat > "$TMP/bin/dms" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DMS_LOG"
SH
chmod +x "$TMP/bin/notify-send" "$TMP/bin/dms"
export DMS_LOG="$TMP/dms.log" CLICK_FILE="$TMP/click"
: > "$NOTIFY_LOG"
state="$XDG_CACHE_HOME/AiOverviewControl/notify-state.json"

click_alert() {
  "$ROOT/providers/send-quota-alert" \
    click:primary:300:window "$2" "$1" dialog-warning '#6750A4' \
    'Quota test' 'Fixture body' 'Open dashboard' "$3" &
}
waiter_of() { jq -r '.["click:primary:300:window"].waiter // 0' "$state" 2>/dev/null || echo 0; }
# Polls until the stored waiter pid differs from $1.
wait_for_waiter() {
  for _ in $(seq 100); do
    [ "$(waiter_of)" != "$1" ] && return 0
    sleep 0.05
  done
  echo "timeout waiting for a new notify-send waiter" >&2; exit 1
}
# Bounded wait: a regression must fail the test, not hang CI.
reap() {
  for _ in $(seq 100); do
    kill -0 "$1" 2>/dev/null || { wait "$1"; return; }
    sleep 0.05
  done
  echo "helper $1 did not exit" >&2; exit 1
}

click_alert normal 0 codex
first_helper=$!
wait_for_waiter 0
first_waiter=$(waiter_of)
grep -qF -- '-A default=Open\ dashboard' "$NOTIFY_LOG"
# The lock is free while the waiter blocks: an unrelated alert goes through.
timeout 5 "$ROOT/providers/send-quota-alert" other:primary:300:window 0 normal \
  dialog-warning '#6750A4' 'Other' 'Body'
[ "$(jq -r '.["other:primary:300:window"].id' "$state")" = 42 ]

# Escalation replaces the notification and kills the stale waiter.
NOTIFY_ID=43 click_alert critical 0 codex
second_helper=$!
wait_for_waiter "$first_waiter"
reap "$first_helper"
if kill -0 "$first_waiter" 2>/dev/null; then echo 'stale waiter survived' >&2; exit 1; fi
grep -q -- '-r 42' "$NOTIFY_LOG"

touch "$CLICK_FILE"
reap "$second_helper"
[ "$(cat "$DMS_LOG")" = 'ipc call aiOverviewControl focus codex' ]
rm -f "$CLICK_FILE"

# A provider id that is not a plain id never reaches the IPC call.
"$ROOT/providers/send-quota-alert" --clear click:primary:300:window
: > "$NOTIFY_LOG"
touch "$CLICK_FILE"
click_alert normal 0 'codex; rm -rf /'
reap $!
if grep -q -- '-A' "$NOTIFY_LOG"; then echo 'unsafe provider got an action' >&2; exit 1; fi
[ "$(wc -l < "$DMS_LOG")" -eq 1 ]
[ "$(jq -r '.["click:primary:300:window"].waiter // "none"' "$state")" = none ]
[ -z "$(find "$XDG_CACHE_HOME/AiOverviewControl" -name '.notify-waiter.*')" ]

# Without notify-send the alert falls back to `dms notify`, still deduped.
mkdir -p "$TMP/nolibnotify"
for tool in env bash jq flock date mktemp mv cat sed awk sha256sum cut rm mkdir head; do
  ln -s "$(command -v "$tool")" "$TMP/nolibnotify/$tool"
done
ln -s "$TMP/bin/dms" "$TMP/nolibnotify/dms"
: > "$DMS_LOG"
fallback_alert() {
  PATH="$TMP/nolibnotify" "$ROOT/providers/send-quota-alert" fallback:primary:300:window 3600 critical \
    dialog-warning '#6750A4' 'Quota test' 'Fixture body' 'Open dashboard' claude
}
fallback_alert
fallback_alert
[ "$(wc -l < "$DMS_LOG")" -eq 1 ]
grep -qF 'notify --app AiOverviewControl --icon dialog-warning Quota test Fixture body' "$DMS_LOG"
[ "$(jq -r '.["fallback:primary:300:window"].id' "$state")" = 0 ]

echo 'Quota alert deduplication and click action: OK'
