#!/usr/bin/env bash
# Ollama Cloud, Anthropic API, OpenAI API and Vercel AI Gateway adapters —
# fake-curl fixture tests. Each base fixture is the provider's documented
# example response; variants are derived from it with jq.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$TMP/bin" "$HOME"
FIX="$ROOT/tests/fixtures"
SECRET="sk-test-spend-0000"

# Fake curl: the Nth request reads $FAKE_BODY_N (falling back to $FAKE_BODY),
# writes it to the -o file and prints $FAKE_STATUS for -w. Headers, URLs and
# query parameters are logged; a secret on the command line is flagged.
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
case " $* " in *"$FAKE_SECRET"*) : >"$FAKE_DIR/argv-leak" ;; esac
_cfg=(); while [ $# -gt 0 ]; do if [ "$1" = --config ] || [ "$1" = -K ]; then while IFS= read -r _l; do case "$_l" in 'header = "'*) _v="${_l#header = \"}"; _cfg+=(-H "${_v%\"}") ;; esac; done < "$2"; shift 2; else _cfg+=("$1"); shift; fi; done; set -- "${_cfg[@]}"
n=$(( $(cat "$FAKE_DIR/count" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FAKE_DIR/count"
out=""; write_code=0; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -w) write_code=1 ;;
    -H) printf 'H %s\n' "${args[$((i + 1))]}" >>"$FAKE_LOG" ;;
    --data-urlencode) printf 'Q%s %s\n' "$n" "${args[$((i + 1))]}" >>"$FAKE_LOG" ;;
    http*) printf 'U %s\n' "${args[$i]}" >>"$FAKE_LOG" ;;
  esac
done
body_var="FAKE_BODY_$n"; body="${!body_var:-$FAKE_BODY}"
[ -z "$out" ] || cp "$body" "$out"
[ "$write_code" -eq 0 ] || printf '%s' "${FAKE_STATUS:-200}"
exit 0
STUB
chmod +x "$TMP/bin/curl"

fail() { echo "FAIL: $1" >&2; exit 1; }
# run <provider> <body> [status] — every credential the adapters read is set.
run() {
  : >"$TMP/log"; rm -f "$TMP/count" "$TMP/argv-leak"
  local out
  out="$(PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_LOG="$TMP/log" FAKE_SECRET="$SECRET" \
    FAKE_BODY="$2" FAKE_STATUS="${3:-200}" \
    OLLAMA_API_KEY="$SECRET" ANTHROPIC_ADMIN_KEY="$SECRET" OPENAI_ADMIN_KEY="$SECRET" \
    AI_GATEWAY_API_KEY="$SECRET" "$ROOT/providers/get-provider-usage" "$1" 2>/dev/null)"
  [ ! -e "$TMP/argv-leak" ] || fail "$1: credential passed to curl on the command line"
  case "$out" in *"$SECRET"*) fail "$1: credential leaked into output" ;; esac
  printf '%s' "$out"
}
check() { jq -e "$2" <<<"$3" >/dev/null || fail "$1: $3"; }
variant() { local file="$TMP/variant-$RANDOM.json"; jq "$2" "$1" >"$file"; printf '%s' "$file"; }
missing() {
  local out
  out="$(env -u "$2" PATH="$TMP/bin:$PATH" FAKE_DIR="$TMP" FAKE_LOG="$TMP/log" FAKE_SECRET="$SECRET" \
    FAKE_BODY=/dev/null "$ROOT/providers/get-provider-usage" "$1" 2>/dev/null)"
  check "$1 without $2" ".[0].error.code == 2 and (.[0].error.message | contains(\"$2\"))" "$out"
}

# --- Ollama Cloud ---------------------------------------------------------
out="$(run ollama-cloud "$FIX/ollama-cloud-balance.json")"
check "ollama monthly" '.[0].provider == "ollama-cloud" and .[0].source == "ollama-cloud-api"
  and .[0].usage.primary.usedPercent == 27.5 and .[0].usage.primary.windowMinutes == 43200
  and .[0].usage.primary.resetsAt == "2026-10-15T09:30:00Z"
  and .[0].usage.primary.displayValue == "$72.50 / $100.00"
  and .[0].usage.secondary.resetDescription == "Credits" and .[0].usage.secondary.displayValue == "$25.00"
  and .[0].usage.secondary.usedPercent == 0 and .[0].credits.remaining == "$25.00"' "$out"
grep -qx "H Authorization: Bearer $SECRET" "$TMP/log" || fail "ollama: bearer header"
grep -qx 'U https://ollama.com/api/balance' "$TMP/log" || fail "ollama: endpoint"

out="$(run ollama-cloud "$FIX/ollama-cloud-balance-legacy.json")"
check "ollama legacy" '.[0].usage.primary.usedPercent == 25 and .[0].usage.primary.windowMinutes == 300
  and .[0].usage.primary.resetsAt == "2026-10-26T20:00:00Z"
  and .[0].usage.secondary.usedPercent == 60 and .[0].usage.secondary.windowMinutes == 10080
  and .[0].usage.tertiary.usedPercent == 100 and .[0].usage.tertiary.displayValue == "$0.00"' "$out"

body="$(variant "$FIX/ollama-cloud-balance.json" '.included.balance_usd = 0 | del(.purchased)')"
out="$(run ollama-cloud "$body")"
check "ollama exhausted" '.[0].usage.primary.usedPercent == 100 and .[0].usage.secondary == null
  and .[0].credits.remaining == "unknown"' "$out"

printf '{"error":"Account is suspended"}' >"$TMP/err.json"
out="$(run ollama-cloud "$TMP/err.json" 401)"
check "ollama 401" '.[0].error.code == 401 and (.[0].error.message | contains("invalid"))' "$out"
out="$(run ollama-cloud "$TMP/err.json" 403)"
check "ollama 403" '.[0].error.code == 403 and .[0].error.message == "Account is suspended"' "$out"
out="$(run ollama-cloud "$TMP/err.json" 429)"
check "ollama 429" '.[0].error.code == 429 and (.[0].error.message | contains("rate limited"))' "$out"
out="$(run ollama-cloud "$TMP/err.json" 503)"
check "ollama 503" '.[0].error.code == 503 and .[0].error.kind == "provider"' "$out"
printf '{"unexpected":true}' >"$TMP/odd.json"
out="$(run ollama-cloud "$TMP/odd.json")"
check "ollama schema" '.[0].error.code == 200 and (.[0].error.message | contains("unexpected"))' "$out"
missing ollama-cloud OLLAMA_API_KEY

# --- Anthropic API --------------------------------------------------------
TODAY="$(date -u +%Y-%m-%d)"
MONTH_START="$(date -u +%Y-%m-01)T00:00:00Z"
jq --arg today "${TODAY}T00:00:00Z" '.data += [{starting_at: $today, ending_at: $today, results: [{amount: "250.5", currency: "USD"}]}]' \
  "$FIX/anthropic-cost-report.json" >"$TMP/anthropic-today.json"
out="$(run anthropic "$TMP/anthropic-today.json")"
check "anthropic month" '.[0].provider == "anthropic" and .[0].source == "anthropic-admin-api"
  and .[0].usage.primary.resetDescription == "Month to date"
  and .[0].usage.primary.displayValue == "$13.74" and .[0].usage.primary.usedPercent == 0
  and (.[0].usage.primary.resetsAt | test("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$"))
  and .[0].usage.secondary.resetDescription == "Today" and .[0].usage.secondary.displayValue == "$2.51"' "$out"
grep -qx "H x-api-key: $SECRET" "$TMP/log" || fail "anthropic: x-api-key header"
grep -qx 'H anthropic-version: 2023-06-01' "$TMP/log" || fail "anthropic: version header"
grep -qx 'U https://api.anthropic.com/v1/organizations/cost_report' "$TMP/log" || fail "anthropic: endpoint"
grep -qx "Q1 starting_at=$MONTH_START" "$TMP/log" || fail "anthropic: month start"
grep -qx 'Q1 limit=31' "$TMP/log" || fail "anthropic: one page per month"

out="$(ANTHROPIC_MONTHLY_BUDGET_USD=50 run anthropic "$TMP/anthropic-today.json")"
check "anthropic budget" '.[0].usage.primary.usedPercent == 27.49
  and .[0].usage.primary.displayValue == "$13.74 / $50.00"' "$out"

jq '.has_more = true | .next_page = "page_fixture"' "$FIX/anthropic-cost-report.json" >"$TMP/anthropic-page1.json"
out="$(FAKE_BODY_1="$TMP/anthropic-page1.json" FAKE_BODY_2="$TMP/anthropic-today.json" run anthropic /dev/null)"
check "anthropic pages" '.[0].usage.primary.displayValue == "$24.98"' "$out"
grep -qx 'Q2 page=page_fixture' "$TMP/log" || fail "anthropic: next_page not followed"

printf '{"type":"error","error":{"type":"permission_error","message":"Admin key required"}}' >"$TMP/anthropic-err.json"
out="$(run anthropic "$TMP/anthropic-err.json" 401)"
check "anthropic 401" '.[0].error.code == 401 and (.[0].error.message | contains("Admin API key"))' "$out"
out="$(run anthropic "$TMP/anthropic-err.json" 403)"
check "anthropic 403" '.[0].error.code == 403 and .[0].error.message == "Admin key required"' "$out"
out="$(run anthropic "$TMP/odd.json")"
check "anthropic schema" '.[0].error.code == 200 and (.[0].error.message | contains("unexpected"))' "$out"
out="$(run anthropic "$TMP/odd.json" 429)"
check "anthropic 429" '.[0].error.code == 429 and (.[0].error.message | contains("rate limited"))' "$out"
out="$(run anthropic "$TMP/odd.json" 502)"
check "anthropic 502" '.[0].error.code == 502 and .[0].error.message == "Anthropic cost report returned HTTP 502."' "$out"
missing anthropic ANTHROPIC_ADMIN_KEY

# --- OpenAI API -----------------------------------------------------------
TODAY_EPOCH="$(date -u -d "$TODAY" +%s)"
MONTH_EPOCH="$(date -u -d "$(date -u +%Y-%m-01)" +%s)"
jq --argjson today "$TODAY_EPOCH" '.data += [{object: "bucket", start_time: $today, end_time: ($today + 86400),
  results: [{object: "organization.costs.result", amount: {value: 1.25, currency: "usd"}}]}]' \
  "$FIX/openai-costs.json" >"$TMP/openai-today.json"
out="$(run openai "$TMP/openai-today.json")"
check "openai month" '.[0].provider == "openai" and .[0].source == "openai-admin-api"
  and .[0].usage.primary.resetDescription == "Month to date"
  and .[0].usage.primary.displayValue == "$13.88" and .[0].usage.primary.usedPercent == 0
  and .[0].usage.secondary.displayValue == "$1.25"' "$out"
grep -qx "H Authorization: Bearer $SECRET" "$TMP/log" || fail "openai: bearer header"
grep -qx 'U https://api.openai.com/v1/organization/costs' "$TMP/log" || fail "openai: endpoint"
grep -qx "Q1 start_time=$MONTH_EPOCH" "$TMP/log" || fail "openai: month start"

out="$(OPENAI_MONTHLY_BUDGET_USD=10 run openai "$TMP/openai-today.json")"
check "openai budget" '.[0].usage.primary.usedPercent == 100 and .[0].usage.primary.displayValue == "$13.88 / $10.00"' "$out"

jq '.has_more = true | .next_page = "page_openai"' "$FIX/openai-costs.json" >"$TMP/openai-page1.json"
out="$(FAKE_BODY_1="$TMP/openai-page1.json" FAKE_BODY_2="$TMP/openai-today.json" run openai /dev/null)"
check "openai pages" '.[0].usage.primary.displayValue == "$26.51"' "$out"
grep -qx 'Q2 page=page_openai' "$TMP/log" || fail "openai: next_page not followed"

printf '{"error":{"message":"Missing scopes: api.usage.read","type":"invalid_request_error"}}' >"$TMP/openai-err.json"
out="$(run openai "$TMP/openai-err.json" 403)"
check "openai 403" '.[0].error.code == 403 and .[0].error.message == "Missing scopes: api.usage.read"' "$out"
out="$(run openai "$TMP/openai-err.json" 401)"
check "openai 401" '.[0].error.code == 401 and (.[0].error.message | contains("Admin API key"))' "$out"
out="$(run openai "$TMP/openai-err.json" 429)"
check "openai 429" '.[0].error.code == 429 and (.[0].error.message | contains("rate limited"))' "$out"
out="$(run openai "$TMP/odd.json")"
check "openai schema" '.[0].error.code == 200 and (.[0].error.message | contains("unexpected"))' "$out"
out="$(run openai "$TMP/odd.json" 502)"
check "openai 502" '.[0].error.code == 502 and .[0].error.message == "OpenAI costs API returned HTTP 502."' "$out"
missing openai OPENAI_ADMIN_KEY

# --- Vercel AI Gateway ----------------------------------------------------
out="$(run vercel "$FIX/vercel-credits.json")"
check "vercel credits" '.[0].provider == "vercel" and .[0].source == "vercel-ai-gateway"
  and .[0].usage.primary.usedPercent == 0 and .[0].usage.primary.displayValue == "$95.50"
  and .[0].usage.secondary.resetDescription == "Total used" and .[0].usage.secondary.displayValue == "$4.50"
  and .[0].credits.remaining == "$95.50"' "$out"
grep -qx 'U https://ai-gateway.vercel.sh/v1/credits' "$TMP/log" || fail "vercel: endpoint"
grep -qx "H Authorization: Bearer $SECRET" "$TMP/log" || fail "vercel: bearer header"

body="$(variant "$FIX/vercel-credits.json" '.balance = "0.00"')"
out="$(run vercel "$body")"
check "vercel exhausted" '.[0].usage.primary.usedPercent == 100' "$out"
out="$(run ai-gateway "$FIX/vercel-credits.json")"
check "vercel alias" '.[0].usage.primary.displayValue == "$95.50"' "$out"
printf '{"error":{"message":"Invalid API key","type":"authentication_error"}}' >"$TMP/vercel-err.json"
out="$(run vercel "$TMP/vercel-err.json" 401)"
check "vercel 401" '.[0].error.code == 401 and (.[0].error.message | contains("rejected"))' "$out"
out="$(run vercel "$TMP/vercel-err.json" 500)"
check "vercel 500" '.[0].error.code == 500 and .[0].error.message == "Invalid API key"' "$out"
out="$(run vercel "$TMP/odd.json")"
check "vercel schema" '.[0].error.code == 200 and (.[0].error.message | contains("unexpected"))' "$out"
missing vercel AI_GATEWAY_API_KEY

echo 'OK: Ollama Cloud, Anthropic API, OpenAI API and Vercel AI Gateway adapters'
