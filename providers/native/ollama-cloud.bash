# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_ollama_cloud_native() {
  # Ollama Cloud — one read-only call returns the included credits for the
  # monthly period (or the session/weekly limits of a legacy plan) and the
  # purchased credits. Docs: https://docs.ollama.com/api/balance
  local key="${OLLAMA_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error ollama-cloud ollama-cloud-api 2 provider "OLLAMA_API_KEY is not set."
    return 0
  fi

  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    --config <(curl_header_config "Authorization: Bearer ${key}") \
    -H "Accept: application/json" \
    "${OLLAMA_CLOUD_API_BASE:-https://ollama.com}/api/balance" 2>/dev/null || true)"

  if [ "$http_status" != "200" ] || ! jq -e '.included | type == "object"' "$tmp_body" >/dev/null 2>&1; then
    local message
    message="$(jq -r '.error | strings' "$tmp_body" 2>/dev/null || true)"
    case "$http_status" in
      401) message="Ollama API key is missing or invalid (HTTP 401)." ;;
      403) [ -n "$message" ] || message="Ollama account is suspended (HTTP 403)." ;;
      # 10 requests per minute per user, shared across keys and devices.
      429) message="Ollama balance API rate limited (HTTP 429); retrying on the next refresh." ;;
      200) message="Ollama balance API returned an unexpected payload." ;;
      *) [ -n "$message" ] || message="Ollama balance API returned HTTP ${http_status:-0}." ;;
    esac
    rm -f "$tmp_body"
    json_error ollama-cloud ollama-cloud-api "${http_status:-1}" provider "$message"
    return 0
  fi

  jq -c '
    def num($v): ($v // 0 | tonumber? // 0);
    # Rounded to 0.01 so a float artifact (27.500000000000004) never reaches the UI.
    def clamp($n): (if $n < 0 then 0 elif $n > 100 then 100 else $n end) | . * 100 | round / 100;
    def fix2: (. * 100 | round) as $c | ($c | fabs) as $a
      | (if $c < 0 then "-" else "" end)
        + (($a / 100 | floor) | tostring) + "."
        + (($a - ($a / 100 | floor) * 100) | tostring | if length == 1 then "0" + . else . end);
    def usd($v): "$" + (num($v) | fix2);
    def legacy($w; $minutes):
      if ($w | type) == "object" then {
        usedPercent: clamp(100 - num($w.remaining_percent)),
        windowMinutes: $minutes,
        resetsAt: ($w.resets_at // null),
        resetDescription: null,
        displayValue: null
      } else null end;

    .included as $i
    | (.purchased.balance_usd // null) as $bought
    | (if ($i.allowance_usd | type) == "number" then
        [{
          # Included credits reset monthly, even on annual plans.
          usedPercent: (if num($i.allowance_usd) > 0
            then clamp((num($i.allowance_usd) - num($i.balance_usd)) / num($i.allowance_usd) * 100)
            else 0 end),
          windowMinutes: 43200,
          resetsAt: ($i.period.until // null),
          resetDescription: null,
          displayValue: (usd($i.balance_usd) + " / " + usd($i.allowance_usd))
        }]
      else [legacy($i.session; 300), legacy($i.weekly; 10080)] | map(select(. != null)) end) as $windows
    | ($windows + (if $bought != null then [{
        usedPercent: (if num($bought) > 0 then 0 else 100 end),
        windowMinutes: null,
        resetsAt: null,
        resetDescription: "Credits",
        displayValue: usd($bought)
      }] else [] end)) as $all
    | {
        provider: "ollama-cloud",
        source: "ollama-cloud-api",
        usage: {
          identity: {providerID: "ollama-cloud", accountEmail: "Ollama Cloud", loginMethod: "api-key"},
          accountEmail: "Ollama Cloud",
          loginMethod: "api-key",
          primary: ($all[0] // null),
          secondary: ($all[1] // null),
          tertiary: ($all[2] // null),
          updatedAt: (now | todateiso8601)
        },
        credits: {remaining: (if $bought != null then usd($bought) else "unknown" end)}
      }
    | if .usage.primary == null then
        {provider: "ollama-cloud", source: "ollama-cloud-api",
         error: {code: 1, kind: "provider", message: "Ollama balance API returned an unexpected payload."}}
      else . end
  ' "$tmp_body"
  rm -f "$tmp_body"
}
