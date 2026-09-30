#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
printf '%s\n' '{"provider":"codex","usage":{"primary":{"usedPercent":25}},"credits":{"balance":"12.5"}}' > "$TMP/codex.json"
printf '%s\n' '{"provider":"codex","usage":{"primary":{"usedPercent":0}},"credits":{"balance":"0"}}' > "$TMP/zero.json"
printf '%s\n' '{"provider":"codex","usage":{"primary":{"usedPercent":3}},"credits":{"balance":"not available","remaining":"100"}}' > "$TMP/unknown.json"
printf '%s\n' '{"provider":"nvidia","usage":{"primary":{"usedPercent":0}},"credits":{"balance":"42"}}' > "$TMP/info.json"
printf '%s\n' '{"provider":"codex","usage":{"primary":{"usedPercent":0}},"credits":{"balance":-1}}' > "$TMP/negative.json"
bash "$ROOT/providers/record-usage-history" "$TMP"/*.json
history="$XDG_CACHE_HOME/AiOverviewControl/usage-history.jsonl"
jq -se 'length == 3 and any(.pct == 25 and .creditBalance == 12.5) and any(.creditBalance == 0 and (has("pct") | not)) and any(.pct == 3 and (has("creditBalance") | not))' "$history" >/dev/null
bash "$ROOT/providers/get-usage-history" | jq -e '.codex | length == 2' >/dev/null
csv="$(bash "$ROOT/providers/export-usage-history" csv "$TMP/export")"
grep -q 'credit_balance$' "$csv"
grep -q ',"codex",,0$' "$csv"
# Concurrent appends must not lose credit readings or corrupt JSONL.
for _ in {1..12}; do bash "$ROOT/providers/record-usage-history" "$TMP/zero.json" & done
wait
jq -se 'length == 15' "$history" >/dev/null
# Retention is serialized with append and accepts a bounded integer only.
for _ in {1..90}; do bash "$ROOT/providers/record-usage-history" "$TMP/zero.json"; done
AIOC_HISTORY_MAX=50 bash "$ROOT/providers/record-usage-history" "$TMP/zero.json"
jq -se 'length == 50 and all(.creditBalance == 0)' "$history" >/dev/null
AIOC_HISTORY_MAX=999999999999999999999 bash "$ROOT/providers/record-usage-history" "$TMP/zero.json"
bash "$ROOT/providers/get-history-stats" | jq -e '.count == 51 and .trimmed > 0' >/dev/null
printf '%s\n' 'not-json' '{"provider":"codex","pct":"invalid"}' >> "$history"
bash "$ROOT/providers/get-usage-history" | jq -e '. == {}' >/dev/null
echo 'OK: Codex credit history, zero balances, exports, concurrent retention'
