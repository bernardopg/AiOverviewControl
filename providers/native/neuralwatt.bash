# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_neuralwatt_native() {
  # Neuralwatt Cloud — one read-only call returns the prepaid USD balance, the
  # subscription kWh allowance for the billing period and the optional per-key
  # spending allowance. Docs: https://docs.neuralwatt.com/api/quota
  local key="${NEURALWATT_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error neuralwatt neuralwatt-api 2 provider "NEURALWATT_API_KEY is not set."
    return 0
  fi

  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    --config <(curl_header_config "Authorization: Bearer ${key}") \
    -H "Accept: application/json" \
    "https://api.neuralwatt.com/v1/quota" 2>/dev/null || true)"

  if [ "$http_status" != "200" ] || ! jq -e '.balance | type == "object"' "$tmp_body" >/dev/null 2>&1; then
    local message
    message="$(jq -r '.detail // .error.message // .message // (.error | strings) // empty' "$tmp_body" 2>/dev/null || true)"
    case "$http_status" in
      401) [ -n "$message" ] || message="Neuralwatt API key is missing or invalid (HTTP 401)." ;;
      # The endpoint allows one request per second per customer.
      429) message="Neuralwatt quota API rate limited (HTTP 429); retrying on the next refresh." ;;
      200) message="Neuralwatt quota API returned an unexpected payload." ;;
      *) [ -n "$message" ] || message="Neuralwatt quota API returned HTTP ${http_status:-0}." ;;
    esac
    rm -f "$tmp_body"
    json_error neuralwatt neuralwatt-api "${http_status:-1}" provider "$message"
    return 0
  fi

  jq -c '
    def num($v): ($v // 0 | tonumber? // 0);
    def clamp($n): if $n < 0 then 0 elif $n > 100 then 100 else $n end;
    def fix2: (. * 100 | round) as $c | ($c | fabs) as $a
      | (if $c < 0 then "-" else "" end)
        + (($a / 100 | floor) | tostring) + "."
        + (($a - ($a / 100 | floor) * 100) | tostring | if length == 1 then "0" + . else . end);
    def usd($v): "$" + (num($v) | fix2);
    def pct($used; $total): if num($total) > 0 then clamp(num($used) / num($total) * 100) else 0 end;
    def period_minutes($p):
      if $p == "daily" then 1440 elif $p == "weekly" then 10080
      elif $p == "monthly" or $p == "month" then 43200
      elif $p == "year" then 525600 else null end;

    .balance as $b
    | .subscription as $s
    | (.key.allowance // null) as $a
    | ($s != null and $s.kwh_included != null) as $has_kwh
    | {
        usedPercent: pct($b.credits_used_usd; $b.total_credits_usd),
        windowMinutes: null,
        resetsAt: null,
        resetDescription: "Balance",
        displayValue: (usd($b.credits_remaining_usd) + " / " + usd($b.total_credits_usd))
      } as $balance
    | (if $has_kwh then {
        # kwh_used is the billed basis (consumed x pricing multiplier), which is
        # what counts against the included allowance; overage stays at 100%.
        usedPercent: (if $s.in_overage == true then 100 else pct($s.kwh_used; $s.kwh_included) end),
        windowMinutes: period_minutes($s.billing_interval // "month"),
        resetsAt: $s.current_period_end,
        resetDescription: null,
        displayValue: ((num($s.kwh_used) | fix2) + " / " + (num($s.kwh_included) | fix2) + " kWh")
      } else null end) as $kwh
    | (if $a != null then {
        usedPercent: (if $a.blocked == true then 100 else pct($a.spent_usd; $a.limit_usd) end),
        windowMinutes: null,
        resetsAt: null,
        resetDescription: ("Key limit · " + ($a.period // "")),
        displayValue: (usd($a.spent_usd) + " / " + usd($a.limit_usd))
      } else null end) as $key_window
    | ([$kwh, $balance, $key_window] | map(select(. != null))) as $windows
    | (if $s != null then
         "Neuralwatt " + ($s.plan // "subscription")
         + (if ($s.status // "active") != "active" then " (" + $s.status + ")" else "" end)
       else "Neuralwatt prepaid" end) as $identity
    | {
        provider: "neuralwatt",
        source: "neuralwatt-api",
        usage: {
          identity: {providerID: "neuralwatt", accountEmail: $identity, loginMethod: "api-key"},
          accountEmail: $identity,
          loginMethod: "api-key",
          primary: $windows[0],
          secondary: ($windows[1] // null),
          tertiary: ($windows[2] // null),
          updatedAt: (.snapshot_at // (now | todateiso8601))
        },
        credits: {remaining: usd($b.credits_remaining_usd)}
      }
  ' "$tmp_body"
  rm -f "$tmp_body"
}
