#!/usr/bin/env bash
# Offline coverage for 9Router JSON fallback, aggregation, and routed aliases.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$HOME/.9router"
TODAY="$(date +%F)"
YESTERDAY="$(date -d 'yesterday' +%F)"
jq -n --arg today "$TODAY" --arg yesterday "$YESTERDAY" '{dailySummary:{($today):{requests:2,cost:0.5,promptTokens:1000,cachedTokens:250,completionTokens:300,byModel:{"model-a|openrouter":{rawModel:"model-a",provider:"openrouter",requests:2,cost:0.5,promptTokens:1000,cachedTokens:250,completionTokens:300}},byProvider:{openrouter:{requests:2,cost:0.5}}},($yesterday):{requests:3,cost:1.25,promptTokens:2000,cachedTokens:0,completionTokens:500,byModel:{"model-a|openrouter":{provider:"openrouter",requests:3,cost:1.25,promptTokens:2000,cachedTokens:0,completionTokens:500},"model-b|anthropic":{provider:"anthropic",requests:1,cost:2,promptTokens:900,cachedTokens:10,completionTokens:90}},byProvider:{openrouter:{requests:2,cost:1.25},anthropic:{requests:1,cost:2}}}}}' > "$HOME/.9router/usage.json"
fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(bash "$ROOT/providers/get-9router-analytics")"
jq -e '.days|length==7' <<<"$out" >/dev/null || fail "seven calendar buckets"
jq -e --arg today "$TODAY" --arg yesterday "$YESTERDAY" '(.days[]|select(.date==$today)|.requests)==2 and (.days[]|select(.date==$yesterday)|.cachedTokens)==0 and .today.cost==0.5 and .week.requests==5 and .month.completionTokens>=800 and .topModels[0].model=="model-b" and .byProvider[0].provider=="anthropic"' <<<"$out" >/dev/null || fail "analytics totals and model/provider ordering"

json_error() { jq -cn --arg p "$1" --arg s "$2" --argjson c "$3" --arg k "$4" --arg m "$5" '{provider:$p,source:$s,error:{code:$c,kind:$k,message:$m}}'; }
source "$ROOT/providers/native/9router.bash"
out="$(fetch_9router_native)"
jq -e '.provider=="9router" and .usage.primary.displayValue=="$0.50 · 2 req" and .usage.secondary.displayValue=="$1.75 · 5 req" and .usage.tertiary.displayValue=="3K in · 250 cached · 800 out"' <<<"$out" >/dev/null || fail "native all-routed totals"
out="$(fetch_9router_native openrouter openrouter)"
jq -e '.provider=="openrouter" and (.usage.primary.resetDescription|contains("not openrouter quota"))' <<<"$out" >/dev/null || fail "native provider alias labeling"

# A provider 9router never routed is an error card, or a quiet decline when it
# only backs another adapter.
out="$(fetch_9router_native xai xai)"
jq -e '.provider=="xai" and .error.code==2 and (.error.message|contains("no recorded usage for xai"))' <<<"$out" >/dev/null || fail "unrouted provider error"
if fetch_9router_native xai xai soft; then fail "soft fallback should decline an unrouted provider"; fi

# The SQLite ledger wins over usage.json when both exist.
if command -v sqlite3 >/dev/null 2>&1; then
  mkdir -p "$HOME/.9router/db"
  sqlite3 "$HOME/.9router/db/data.sqlite" "CREATE TABLE usageDaily(dateKey TEXT, data TEXT);
    INSERT INTO usageDaily VALUES('$TODAY', '{\"requests\":7,\"cost\":3,\"promptTokens\":10,\"cachedTokens\":0,\"completionTokens\":5}');"
  out="$(fetch_9router_native)"
  jq -e '.usage.primary.displayValue=="$3.00 · 7 req" and .usage.secondary.displayValue=="$3.00 · 7 req"' <<<"$out" >/dev/null || fail "SQLite ledger: $out"
  rm -rf "$HOME/.9router/db"
fi

mv "$HOME/.9router/usage.json" "$TMP/usage.json"
out="$(fetch_9router_native)"
jq -e '.error.code==2 and (.error.message|contains("database not found"))' <<<"$out" >/dev/null || fail "missing data error"
if fetch_9router_native openrouter openrouter soft; then fail "soft fallback should decline without data"; fi

printf '{broken' > "$HOME/.9router/usage.json"
out="$(bash "$ROOT/providers/get-9router-analytics")"
jq -e '.error=="9router usage database not found"' <<<"$out" >/dev/null || fail "malformed usage file error"

echo 'OK: 9Router analytics and native coverage'
