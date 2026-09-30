# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_glm_native() {
  # GLM and Z.ai share one credential family. Honor ZAI_API_KEY here too so a
  # single key drives both cards (matches docs/providers.md credential matrix).
  local key="${GLM_API_KEY:-${ZHIPU_API_KEY:-${ZAI_API_KEY:-}}}"
  if [ -z "$key" ]; then
    json_error glm glm-api 2 provider "GLM_API_KEY, ZHIPU_API_KEY, or ZAI_API_KEY is not set."
    return 0
  fi
  local base="${GLM_API_BASE:-https://open.bigmodel.cn/api/paas/v4}"
  local console="open.bigmodel.cn"
  case "$base" in *bigmodel.cn*) console="bigmodel.cn" ;; esac
  # Derive quota host from the configured API base — supports custom endpoints.
  local quota_host
  quota_host="$(printf '%s' "$base" | sed 's|/api/paas.*||')"
  [ -n "$quota_host" ] || quota_host="https://open.bigmodel.cn"

  local tmp_body http_status
  tmp_body="$(mktemp)"
  # /api/monitor/usage/quota/limit — zero token cost, returns per-window
  # percentages and reset timestamps identical to the Z.ai endpoint.
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "${quota_host}/api/monitor/usage/quota/limit" 2>/dev/null || true)"

  if [ "$http_status" = "200" ] && jq -e '.success == true and (.data.limits | type) == "array"' "$tmp_body" >/dev/null 2>&1; then
    jq -c --arg console "$console" '
      def clamp($n): if $n < 0 then 0 elif $n > 100 then 100 else $n end;
      def ms_to_iso($ms): if $ms then (($ms / 1000) | todate) else null end;
      # Z.ai/Zhipu period units (confirmed against the live quota API cross-
      # referenced with the official Usage page):
      #   unit 4 -> 5-hour session window   (n * 300 min)
      #   unit 6 -> weekly window           (n * 10080 min)   [reset matched 07-02]
      #   unit 5 -> monthly window          (n * 43200 min)   [reset matched 07-18]
      #   unit 3 -> total token allotment   (no reset window)
      # The previous table had 5/6 swapped, which mislabeled the weekly 20%
      # window as "diário" and the monthly window as 5h.
      def win_min($unit; $n):
        if $unit == 4 then ($n * 300)
        elif $unit == 6 then ($n * 10080)
        elif $unit == 5 then ($n * 43200)
        else null end;
      def win_label($type; $unit; $n):
        ( if $type == "TIME_LIMIT" then
            if $unit == 4 then "5h" elif $unit == 6 then "weekly" elif $unit == 5 then "monthly" else "window" end
          else
            if $unit == 4 then "tokens/5h" elif $unit == 6 then "tokens/week" elif $unit == 5 then "tokens/month" elif $unit == 3 then "total tokens" else "tokens" end
          end
        ) + (if $n > 1 then " ×\($n)" else "" end);
      def make_window($lim):
        { usedPercent: clamp(($lim.percentage // 0) | tonumber),
          windowMinutes: win_min($lim.unit; $lim.number),
          resetsAt: ms_to_iso($lim.nextResetTime),
          resetDescription: win_label($lim.type; $lim.unit; $lim.number),
          displayValue: (if ($lim.usage? != null and $lim.currentValue? != null) then "\($lim.currentValue) / \($lim.usage)" else null end) };

      .data as $d |
      ($d.limits // []) as $limits |
      ( ($limits | map(select(.nextResetTime != null))
                 | sort_by([-((.percentage // 0) | tonumber), .nextResetTime]))
        + ($limits | map(select(.nextResetTime == null)))
      ) as $sorted |

      {
        provider: "glm",
        source: "glm-api",
        usage: {
          identity: {providerID: "glm", accountEmail: "GLM account", loginMethod: "api-key"},
          accountEmail: "GLM account",
          loginMethod: "api-key",
          primary:   (if $sorted[0] then make_window($sorted[0]) else null end),
          secondary: (if $sorted[1] then make_window($sorted[1]) else null end),
          tertiary:  (if $sorted[2] then make_window($sorted[2]) else null end),
          updatedAt: (now | todate)
        },
        credits: {remaining: ($d.level // "unknown")}
      }
    ' "$tmp_body"
    rm -f "$tmp_body"
    return 0
  fi

  if [ "$http_status" = "401" ] || [ "$http_status" = "403" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="GLM API key invalid (HTTP ${http_status})."
    rm -f "$tmp_body"
    json_error glm glm-api "${http_status}" provider "$message"
    return 0
  fi

  # Quota endpoint unavailable: fall back to auth-only /models check.
  rm -f "$tmp_body"
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "${base}/models" 2>/dev/null || true)"
  rm -f "$tmp_body"

  if [ "$http_status" = "200" ]; then
    json_note_usage glm glm-api "GLM account" "api-key" "Authenticated — billing at ${console}" "$console"
    return 0
  fi
  json_error glm glm-api "${http_status:-1}" provider "GLM API key invalid (HTTP ${http_status:-0}). Billing visible at ${console} only."
}
