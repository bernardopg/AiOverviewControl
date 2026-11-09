# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_deepseek_native() {
  local key="${DEEPSEEK_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error deepseek deepseek-api 2 provider "DEEPSEEK_API_KEY is not set."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    --config <(curl_header_config "Authorization: Bearer ${key}") \
    "https://api.deepseek.com/user/balance" 2>/dev/null || true)"
  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="DeepSeek balance API returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error deepseek deepseek-api "${http_status:-1}" provider "$message"
    return 0
  fi
  jq -c '
    def num($v): ($v // 0 | tonumber? // 0);
    # The API reports CNY or USD; other codes keep their ISO prefix.
    def money($code; $v):
      ({"CNY": "¥", "USD": "$"}[$code] // ($code + " "))
      + ((($v * 100) | round) / 100 | tostring
         | if test("\\.") then (if test("\\.[0-9]$") then . + "0" else . end) else . + ".00" end);
    # Accounts carry one entry per currency (USD and CNY). Report the first
    # entry that holds funds, in API order: amounts in different currencies
    # are not comparable without an exchange rate, so "largest" would be
    # nominal. Non-object entries are skipped so one bad entry cannot hide a
    # funded one.
    (.balance_infos | if type == "array" then map(objects) else [] end) as $infos
    | (first($infos[] | select(num(.total_balance) > 0)) // $infos[0] // {}) as $b
    | num($b.total_balance) as $total
    | num($b.granted_balance) as $granted
    | num($b.topped_up_balance) as $topped_up
    | ($b.currency // "CNY") as $currency
    # The balance API reports remaining funds, not consumption — there is no
    # original total to derive a usage percent from. Mirror the Kimi pattern:
    # full bar only when the balance is depleted. `is_available` sits at the
    # response root (documented and live); a per-entry flag is still honoured
    # as a fallback. Test the type rather than using `//`, which treats
    # `false` as missing and would let a positive total override it.
    | (if (.is_available | type) == "boolean" then .is_available
       elif ($b.is_available | type) == "boolean" then $b.is_available
       else $total > 0 end) as $available
    | (if $available then 0 else 100 end) as $used_pct
    | {
        provider: "deepseek",
        source: "deepseek-api",
        usage: {
          identity: { providerID: "deepseek", accountEmail: "DeepSeek account", loginMethod: "api-key" },
          accountEmail: "DeepSeek account",
          loginMethod: "api-key",
          primary: {
            usedPercent: $used_pct,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Balance",
            isBalance: true,
            displayValue: money($currency; $total)
          },
          secondary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Granted credits",
            isBalance: true,
            displayValue: money($currency; $granted)
          },
          tertiary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Paid balance",
            isBalance: true,
            displayValue: money($currency; $topped_up)
          },
          updatedAt: (now | todateiso8601)
        },
        credits: {
          remaining: money($currency; $total)
        }
      }
  ' "$tmp_body"
  rm -f "$tmp_body"
}
