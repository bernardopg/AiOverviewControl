# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_openai_native() {
  # OpenAI API (Platform organization) — month-to-date spend from the
  # organization Costs API. Needs an Admin API key; the API exposes no prepaid
  # balance or budget, so OPENAI_MONTHLY_BUDGET_USD optionally turns the spend
  # into a percentage. ChatGPT plan limits are the Codex card.
  # Docs: https://developers.openai.com/api/docs/guides/admin-apis
  local key="${OPENAI_ADMIN_KEY:-}"
  if [ -z "$key" ]; then
    json_error openai openai-admin-api 2 provider "OPENAI_ADMIN_KEY is not set."
    return 0
  fi

  local base="${OPENAI_ADMIN_API_BASE:-https://api.openai.com}"
  local month_start pages tmp_body http_status page="" count=0
  month_start="$(date -u -d "$(date -u +%Y-%m-01)" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$(date -u +%Y-%m-01)" +%s)"
  pages="$(mktemp)"
  tmp_body="$(mktemp)"
  while :; do
    local -a page_arg=()
    [ -z "$page" ] || page_arg=(--data-urlencode "page=${page}")
    http_status="$(curl -sS --max-time 10 -o "$tmp_body" -w '%{http_code}' \
      --config <(curl_header_config "Authorization: Bearer ${key}") \
      -H "Content-Type: application/json" \
      -G "$base/v1/organization/costs" \
      --data-urlencode "start_time=${month_start}" \
      --data-urlencode "bucket_width=1d" \
      --data-urlencode "limit=31" \
      "${page_arg[@]}" 2>/dev/null || true)"
    if [ "$http_status" != "200" ] || ! jq -e '.data | type == "array"' "$tmp_body" >/dev/null 2>&1; then
      local message
      message="$(jq -r '.error.message // empty | strings' "$tmp_body" 2>/dev/null || true)"
      case "$http_status" in
        401) message="OpenAI rejected the Admin API key (HTTP 401)." ;;
        403) [ -n "$message" ] || message="This key cannot read organization costs; use an Admin API key (HTTP 403)." ;;
        429) message="OpenAI costs API rate limited (HTTP 429); retrying on the next refresh." ;;
        200) message="OpenAI costs API returned an unexpected payload." ;;
        *) [ -n "$message" ] || message="OpenAI costs API returned HTTP ${http_status:-0}." ;;
      esac
      rm -f "$tmp_body" "$pages"
      json_error openai openai-admin-api "${http_status:-1}" provider "$message"
      return 0
    fi
    jq -c '.data[]' "$tmp_body" >>"$pages"
    count=$((count + 1))
    page="$(jq -r 'select(.has_more == true) | .next_page // empty | strings' "$tmp_body")"
    [ -n "$page" ] && [ "$count" -lt 3 ] || break
  done
  rm -f "$tmp_body"

  jq -sc --argjson today "$(date -u -d "$(date -u +%Y-%m-%d)" +%s 2>/dev/null || echo 0)" \
    --arg budget "${OPENAI_MONTHLY_BUDGET_USD:-}" \
    --arg reset "$(date -u -d "$(date -u +%Y-%m-01) +1 month" +%Y-%m-%dT00:00:00Z 2>/dev/null || true)" '
    def fix2: (. * 100 | round) as $c | ($c | fabs) as $a
      | (if $c < 0 then "-" else "" end)
        + (($a / 100 | floor) | tostring) + "."
        + (($a - ($a / 100 | floor) * 100) | tostring | if length == 1 then "0" + . else . end);
    def usd: "$" + fix2;
    def bucket_usd: [.results[]? | .amount.value | tonumber? // 0] | add // 0;
    (map(bucket_usd) | add // 0) as $month
    | (map(select((.start_time // 0) >= $today) | bucket_usd) | add // 0) as $day
    | ($budget | tonumber? // 0) as $limit
    | {
        provider: "openai",
        source: "openai-admin-api",
        usage: {
          identity: {providerID: "openai", accountEmail: "OpenAI API", loginMethod: "admin-key"},
          accountEmail: "OpenAI API",
          loginMethod: "admin-key",
          primary: {
            usedPercent: (if $limit > 0 then ([$month / $limit * 100, 100] | min | . * 100 | round / 100) else 0 end),
            windowMinutes: null,
            resetsAt: (if $reset != "" then $reset else null end),
            resetDescription: "Month to date",
            displayValue: (($month | usd) + (if $limit > 0 then " / " + ($limit | usd) else "" end))
          },
          secondary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Today",
            displayValue: ($day | usd)
          },
          tertiary: null,
          updatedAt: (now | todateiso8601)
        }
      }
  ' "$pages"
  rm -f "$pages"
}
