# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_vercel_native() {
  # Vercel AI Gateway — the team's AI Gateway Credits balance and lifetime
  # spend from one read-only call. Needs an AI Gateway API key; a plain Vercel
  # access token is rejected. Docs:
  # https://vercel.com/docs/ai-gateway/sdks-and-apis/rest-api#check-credit-balance
  local key="${AI_GATEWAY_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error vercel vercel-ai-gateway 2 provider "AI_GATEWAY_API_KEY is not set."
    return 0
  fi

  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    --config <(curl_header_config "Authorization: Bearer ${key}") \
    -H "Content-Type: application/json" \
    "${AI_GATEWAY_API_BASE:-https://ai-gateway.vercel.sh}/v1/credits" 2>/dev/null || true)"

  if [ "$http_status" != "200" ] || ! jq -e '(.balance | tonumber? | type) == "number"' "$tmp_body" >/dev/null 2>&1; then
    local message
    message="$(jq -r '.error.message // (.error | strings) // empty' "$tmp_body" 2>/dev/null || true)"
    case "$http_status" in
      401) message="AI Gateway rejected the API key (HTTP 401)." ;;
      200) message="AI Gateway credits API returned an unexpected payload." ;;
      *) [ -n "$message" ] || message="AI Gateway credits API returned HTTP ${http_status:-0}." ;;
    esac
    rm -f "$tmp_body"
    json_error vercel vercel-ai-gateway "${http_status:-1}" provider "$message"
    return 0
  fi

  jq -c '
    def fix2: (. * 100 | round) as $c | ($c | fabs) as $a
      | (if $c < 0 then "-" else "" end)
        + (($a / 100 | floor) | tostring) + "."
        + (($a - ($a / 100 | floor) * 100) | tostring | if length == 1 then "0" + . else . end);
    def usd: "$" + fix2;
    (.balance | tonumber) as $balance
    | (.total_used | tonumber? // 0) as $used
    | {
        provider: "vercel",
        source: "vercel-ai-gateway",
        usage: {
          identity: {providerID: "vercel", accountEmail: "AI Gateway team", loginMethod: "api-key"},
          accountEmail: "AI Gateway team",
          loginMethod: "api-key",
          # Credits have no fixed total to measure against: the bar fills only
          # when the balance is used up, as for the other prepaid balances.
          primary: {
            usedPercent: (if $balance > 0 then 0 else 100 end),
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Balance",
            displayValue: ($balance | usd)
          },
          secondary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Total used",
            displayValue: ($used | usd)
          },
          tertiary: null,
          updatedAt: (now | todateiso8601)
        },
        credits: {remaining: ($balance | usd)}
      }
  ' "$tmp_body"
  rm -f "$tmp_body"
}
