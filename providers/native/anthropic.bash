# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_anthropic_native() {
  # Anthropic API (Claude Console organization) — month-to-date spend from the
  # Usage and Cost Admin API. Needs an Admin API key (sk-ant-admin...); regular
  # API keys cannot read cost data. The API exposes no prepaid balance or spend
  # limit for Console organizations, so ANTHROPIC_MONTHLY_BUDGET_USD optionally
  # turns the spend into a percentage.
  # Docs: https://platform.claude.com/docs/en/manage-claude/usage-cost-api
  local key="${ANTHROPIC_ADMIN_KEY:-${ANTHROPIC_ADMIN_API_KEY:-}}"
  if [ -z "$key" ]; then
    json_error anthropic anthropic-admin-api 2 provider "ANTHROPIC_ADMIN_KEY is not set."
    return 0
  fi

  local base="${ANTHROPIC_ADMIN_API_BASE:-https://api.anthropic.com}"
  local month_start pages tmp_body http_status page="" count=0
  month_start="$(date -u +%Y-%m-01)T00:00:00Z"
  pages="$(mktemp)"
  tmp_body="$(mktemp)"
  # One daily bucket per day of the month fits in one page (limit 31); follow
  # next_page anyway, bounded, in case the API pages earlier.
  while :; do
    local -a page_arg=()
    [ -z "$page" ] || page_arg=(--data-urlencode "page=${page}")
    http_status="$(curl -sS --max-time 10 -o "$tmp_body" -w '%{http_code}' \
      --config <(curl_header_config "x-api-key: ${key}") \
      -H "anthropic-version: 2023-06-01" \
      -H "User-Agent: AiOverviewControl (https://github.com/bernardopg/AiOverviewControl)" \
      -G "$base/v1/organizations/cost_report" \
      --data-urlencode "starting_at=${month_start}" \
      --data-urlencode "bucket_width=1d" \
      --data-urlencode "limit=31" \
      "${page_arg[@]}" 2>/dev/null || true)"
    if [ "$http_status" != "200" ] || ! jq -e '.data | type == "array"' "$tmp_body" >/dev/null 2>&1; then
      local message
      message="$(jq -r '.error.message // empty | strings' "$tmp_body" 2>/dev/null || true)"
      case "$http_status" in
        401) message="Anthropic rejected the Admin API key (HTTP 401)." ;;
        403) [ -n "$message" ] || message="This key cannot read cost data; use an Admin API key from an organization (HTTP 403)." ;;
        429) message="Anthropic cost report rate limited (HTTP 429); retrying on the next refresh." ;;
        200) message="Anthropic cost report returned an unexpected payload." ;;
        *) [ -n "$message" ] || message="Anthropic cost report returned HTTP ${http_status:-0}." ;;
      esac
      rm -f "$tmp_body" "$pages"
      json_error anthropic anthropic-admin-api "${http_status:-1}" provider "$message"
      return 0
    fi
    jq -c '.data[]' "$tmp_body" >>"$pages"
    count=$((count + 1))
    page="$(jq -r 'select(.has_more == true) | .next_page // empty | strings' "$tmp_body")"
    [ -n "$page" ] && [ "$count" -lt 3 ] || break
  done
  rm -f "$tmp_body"

  jq -sc --arg today "$(date -u +%Y-%m-%d)" --arg budget "${ANTHROPIC_MONTHLY_BUDGET_USD:-}" \
    --arg reset "$(date -u -d "$(date -u +%Y-%m-01) +1 month" +%Y-%m-%dT00:00:00Z 2>/dev/null || true)" '
    def fix2: (. * 100 | round) as $c | ($c | fabs) as $a
      | (if $c < 0 then "-" else "" end)
        + (($a / 100 | floor) | tostring) + "."
        + (($a - ($a / 100 | floor) * 100) | tostring | if length == 1 then "0" + . else . end);
    def usd: "$" + fix2;
    # Amounts are decimal strings in cents.
    def bucket_usd: [.results[]? | .amount | tonumber? // 0] | add // 0 | . / 100;
    (map(bucket_usd) | add // 0) as $month
    | (map(select((.starting_at // "") | startswith($today)) | bucket_usd) | add // 0) as $day
    | ($budget | tonumber? // 0) as $limit
    | {
        provider: "anthropic",
        source: "anthropic-admin-api",
        usage: {
          identity: {providerID: "anthropic", accountEmail: "Anthropic API", loginMethod: "admin-key"},
          accountEmail: "Anthropic API",
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
