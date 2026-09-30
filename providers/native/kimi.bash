# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_kimi_native() {
  # Kimi exposes TWO independent quota systems keyed by different credentials:
  #   • Open Platform balance   — sk-xxx      on api.moonshot.ai/.cn (prepaid funds)
  #   • Kimi Code / Coding Plan — sk-kimi-xxx on api.kimi.com/coding  (subscription
  #     quota: weekly + 5h windows, same model the CLI `/usage` command reads)
  # Route to the Coding Plan tracker when an explicit coding key is set or the
  # supplied key carries the sk-kimi- prefix; otherwise read the prepaid balance.
  local coding_key="${KIMI_CODING_API_KEY:-}"
  local key="${MOONSHOT_API_KEY:-${KIMI_API_KEY:-}}"
  if [ -z "$coding_key" ]; then
    case "$key" in sk-kimi-*) coding_key="$key" ;; esac
  fi
  if [ -n "$coding_key" ] && { [ -z "$key" ] || [[ "$key" == sk-kimi-* ]]; }; then
    fetch_kimi_code_native "$coding_key"
    return 0
  fi
  if [ -z "$key" ]; then
    json_error kimi kimi-api 2 provider "MOONSHOT_API_KEY, KIMI_API_KEY, or KIMI_CODING_API_KEY is not set."
    return 0
  fi
  local tmp_body http_status host base currency symbol
  tmp_body="$(mktemp)"
  # Moonshot platform rebranded to kimi.ai (global) / kimi.com (China); the API
  # hosts are unchanged. Global platform (api.moonshot.ai, USD) and China
  # platform (api.moonshot.cn, CNY). An explicit override is exclusive — no
  # silent fallback to another host; otherwise try global first, then .cn.
  local -a hosts
  if [ -n "${MOONSHOT_API_BASE:-}" ]; then
    hosts=("${MOONSHOT_API_BASE}")
  else
    hosts=("https://api.moonshot.ai" "https://api.moonshot.cn")
  fi
  http_status=""
  for host in "${hosts[@]}"; do
    base="$host"
    http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
      -H "Authorization: Bearer ${key}" \
      "${host}/v1/users/me/balance" 2>/dev/null || true)"
    [ "$http_status" = "200" ] && break
    # Stop probing further hosts on an auth error — the key is simply invalid.
    case "$http_status" in 401|403) break ;; esac
  done
  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Kimi/Moonshot balance API returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error kimi kimi-api "${http_status:-1}" provider "$message"
    return 0
  fi
  case "$base" in
    *moonshot.cn*) currency="CNY"; symbol="¥" ;;
    *)             currency="USD"; symbol="\$" ;;
  esac
  jq -c --arg currency "$currency" --arg symbol "$symbol" '
    def num($v): ($v // 0 | tonumber? // 0);
    .data as $d
    | num($d.available_balance) as $avail
    | num($d.voucher_balance) as $voucher
    | num($d.cash_balance) as $cash
    | (if $avail <= 0 then 100 else 0 end) as $used_pct
    | {
        provider: "kimi",
        source: "kimi-api",
        usage: {
          identity: { providerID: "kimi", accountEmail: "Kimi account", loginMethod: "api-key" },
          accountEmail: "Kimi account",
          loginMethod: "api-key",
          primary: {
            usedPercent: $used_pct,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: ("Available balance (" + $currency + ")"),
            displayValue: ($symbol + ($d.available_balance | tostring))
          },
          secondary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Voucher / Cash",
            displayValue: ($symbol + ($voucher | tostring) + " / " + $symbol + ($cash | tostring))
          },
          tertiary: null,
          updatedAt: (now | todateiso8601)
        },
        credits: {
          remaining: ($symbol + ($d.available_balance | tostring))
        }
      }
  ' "$tmp_body"
  rm -f "$tmp_body"
}
