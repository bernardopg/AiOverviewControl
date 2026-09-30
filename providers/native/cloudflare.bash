# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_cloudflare_native() {
  local token="${CLOUDFLARE_AI_TOKEN:-${CLOUDFLARE_API_TOKEN:-}}"
  local account="${CLOUDFLARE_ACCOUNT_ID:-}"
  if [ -z "$token" ]; then
    json_error cloudflare cloudflare-ai 2 provider "CLOUDFLARE_AI_TOKEN or CLOUDFLARE_API_TOKEN is not set."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    "https://api.cloudflare.com/client/v4/user/tokens/verify" 2>/dev/null || true)"
  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.errors[0].message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Cloudflare API token verification returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error cloudflare cloudflare-ai "${http_status:-1}" provider "$message"
    return 0
  fi
  rm -f "$tmp_body"

  # With an account id we can read documented Workers AI analytics via the
  # GraphQL aiInferenceAdaptiveGroups dataset. Schema drift or missing
  # permissions degrade gracefully to the token-verified note card.
  if [ -n "$account" ]; then
    local tmp_graph graph_status start_date end_date
    tmp_graph="$(mktemp)"
    end_date="$(date +%Y-%m-%d)"
    start_date="$(date -d '6 days ago' +%Y-%m-%d)"
    graph_status="$(jq -cn --arg tag "$account" --arg start "$start_date" --arg end "$end_date" '
      {
        query: "query($tag: String!, $start: Date!, $end: Date!) { viewer { accounts(filter: {accountTag: $tag}) { aiInferenceAdaptiveGroups(limit: 1000, orderBy: [date_ASC], filter: {date_geq: $start, date_leq: $end}) { sum { requests neurons } dimensions { date } } } } }",
        variables: {tag: $tag, start: $start, end: $end}
      }' | curl -sS --max-time 8 -o "$tmp_graph" -w '%{http_code}' \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        --data @- \
        "https://api.cloudflare.com/client/v4/graphql" 2>/dev/null || true)"

    if [ "$graph_status" = "200" ] \
      && jq -e '(.errors // []) == [] and (.data.viewer.accounts[0].aiInferenceAdaptiveGroups | type == "array")' "$tmp_graph" >/dev/null 2>&1; then
      jq -c --arg account "$account" '
        def num($v): ($v // 0 | tonumber? // 0);
        (.data.viewer.accounts[0].aiInferenceAdaptiveGroups) as $groups
        | (reduce $groups[] as $g ({requests: 0, neurons: 0};
            .requests += num($g.sum.requests) | .neurons += num($g.sum.neurons))) as $total
        | ($groups | sort_by(.dimensions.date) | last) as $latest
        | {
            provider: "cloudflare",
            source: "cloudflare-graphql",
            usage: {
              identity: {providerID: "cloudflare", accountEmail: ("Account " + $account), loginMethod: "api-token"},
              accountEmail: ("Account " + $account),
              loginMethod: "api-token",
              primary: {
                usedPercent: 0,
                windowMinutes: 10080,
                resetsAt: null,
                resetDescription: "Workers AI · 7 days",
                displayValue: (($total.requests | tostring) + " req · " + ($total.neurons | tostring) + " neurons")
              },
              secondary: (if $latest != null then {
                usedPercent: 0,
                windowMinutes: 1440,
                resetsAt: null,
                resetDescription: ("Latest day " + ($latest.dimensions.date // "")),
                displayValue: ((num($latest.sum.requests) | tostring) + " req · " + (num($latest.sum.neurons) | tostring) + " neurons")
              } else null end),
              tertiary: null,
              updatedAt: (now | todateiso8601)
            },
            credits: {remaining: "dash.cloudflare.com"}
          }
      ' "$tmp_graph"
      rm -f "$tmp_graph"
      return 0
    fi
    rm -f "$tmp_graph"
  fi

  [ -n "$account" ] || account="unknown"
  json_note_usage cloudflare cloudflare-api "Cloudflare account ${account}" "api-token" "Token verified; Workers AI usage is available in dashboard analytics" "dash.cloudflare.com"
}
