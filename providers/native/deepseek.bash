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
    -H "Authorization: Bearer ${key}" \
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
    (.balance_infos // []) as $infos
    | ($infos[0] // {}) as $b
    | num($b.total_balance) as $total
    | num($b.granted_balance) as $granted
    | num($b.topped_up_balance) as $topped_up
    # The balance API reports remaining funds, not consumption — there is no
    # original total to derive a usage percent from. Mirror the Kimi pattern:
    # full bar only when the balance is depleted.
    | (if ($b.is_available // ($total > 0)) then 0 else 100 end) as $used_pct
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
            displayValue: (($b.currency // "CNY") + " " + ($total | tostring))
          },
          secondary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Granted credits",
            displayValue: (($b.currency // "CNY") + " " + ($granted | tostring))
          },
          tertiary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Paid balance",
            displayValue: (($b.currency // "CNY") + " " + ($topped_up | tostring))
          },
          updatedAt: (now | todateiso8601)
        },
        credits: {
          remaining: (($b.currency // "CNY") + " " + ($total | tostring))
        }
      }
  ' "$tmp_body"
  rm -f "$tmp_body"
}
