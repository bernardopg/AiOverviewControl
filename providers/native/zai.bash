# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_zai_native() {
  local key="${ZAI_API_KEY:-${GLM_API_KEY:-${ZHIPU_API_KEY:-}}}"
  if [ -z "$key" ]; then
    json_error zai zai-api 2 provider "ZAI_API_KEY is not set. Get your key at z.ai/manage-apikey/apikey-list"
    return 0
  fi

  local tmp_body http_status
  tmp_body="$(mktemp)"
  # /api/monitor/usage/quota/limit returns the real GLM Coding Plan quota:
  # per-window percentages, reset timestamps and the plan level — zero token
  # cost, no inference call.
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.z.ai/api/monitor/usage/quota/limit" 2>/dev/null || true)"

  if [ "$http_status" = "200" ] && jq -e '.success == true and (.data.limits | type) == "array"' "$tmp_body" >/dev/null 2>&1; then
    jq -c '
      def clamp($n): if $n < 0 then 0 elif $n > 100 then 100 else $n end;
      def ms_to_iso($ms): if $ms then (($ms / 1000) | todate) else null end;
      # Z.ai/Zhipu period units (confirmed against the live quota API cross-
      # referenced with docs.z.ai/devpack/overview and the official Usage page):
      #   unit 4 -> 5-hour window   (n * 300 min)   "resets 5 hours after consumption"
      #   unit 6 -> weekly window   (n * 10080 min) "resets every 7 days from subscription"
      #   unit 5 -> monthly window  (n * 43200 min) e.g. shared MCP tool-call pool
      #   unit 3 -> total token allotment (no reset window)
      def win_min($unit; $n):
        if $unit == 4 then ($n * 300)
        elif $unit == 6 then ($n * 10080)
        elif $unit == 5 then ($n * 43200)
        else null end;
      def win_label($lim):
        ($lim.unit) as $unit | ($lim.number // 1) as $n |
        # Limits carrying usageDetails meter the shared MCP tool pool
        # (Search / Reader / Zread), not model prompts.
        (if ($lim.usageDetails? != null) then "MCP " else "" end) as $mcp |
        ( if $lim.type == "TIME_LIMIT" then
            $mcp + (if $unit == 4 then "5h" elif $unit == 6 then "weekly" elif $unit == 5 then "monthly" else "window" end)
          else
            $mcp + (if $unit == 4 then "tokens/5h" elif $unit == 6 then "tokens/week" elif $unit == 5 then "tokens/month" elif $unit == 3 then "total tokens" else "tokens" end)
          end
        ) + (if $n > 1 then " ×\($n)" else "" end);
      def display($lim):
        if ($lim.usage? != null and $lim.currentValue? != null) then
          "\($lim.currentValue) / \($lim.usage)"
        else null end;
      def make_window($lim):
        { usedPercent: clamp(($lim.percentage // 0) | tonumber),
          windowMinutes: win_min($lim.unit; ($lim.number // 1)),
          resetsAt: ms_to_iso($lim.nextResetTime),
          resetDescription: win_label($lim),
          displayValue: display($lim) };
      def plan_name($level):
        if $level == "lite" then "GLM Coding Lite"
        elif $level == "pro" then "GLM Coding Pro"
        elif $level == "max" then "GLM Coding Max"
        else ($level // "Z.ai account") end;

      .data as $d |
      ($d.limits // []) as $limits |
      # timed limits first (most critical by % desc, then soonest reset), then untimed
      ( ($limits | map(select(.nextResetTime != null))
                 | sort_by([-((.percentage // 0) | tonumber), .nextResetTime]))
        + ($limits | map(select(.nextResetTime == null)))
      ) as $sorted |

      {
        provider: "zai",
        source: "zai-api",
        usage: {
          identity: {providerID: "zai", accountEmail: plan_name($d.level), loginMethod: "api-key"},
          accountEmail: plan_name($d.level),
          loginMethod: "api-key",
          primary:   (if $sorted[0] then make_window($sorted[0]) else null end),
          secondary: (if $sorted[1] then make_window($sorted[1]) else null end),
          tertiary:  (if $sorted[2] then make_window($sorted[2]) else null end),
          updatedAt: (now | todate)
        },
        credits: {remaining: plan_name($d.level)}
      }
    ' "$tmp_body"
    rm -f "$tmp_body"
    return 0
  fi

  if [ "$http_status" = "401" ] || [ "$http_status" = "403" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Z.ai API key invalid (HTTP ${http_status})."
    rm -f "$tmp_body"
    json_error zai zai-api "${http_status}" provider "$message"
    return 0
  fi

  # Quota endpoint unavailable: fall back to auth-only /models check.
  rm -f "$tmp_body"
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.z.ai/api/paas/v4/models" 2>/dev/null || true)"
  rm -f "$tmp_body"

  if [ "$http_status" = "200" ]; then
    json_note_usage zai zai-api "Z.ai account" "api-key" \
      "Authenticated — billing at z.ai/manage-apikey/billing" \
      "z.ai/manage-apikey/billing"
    return 0
  fi

  json_note_usage zai zai-api "Z.ai account" "api-key" \
    "API key set; quota endpoint unavailable" \
    "z.ai/manage-apikey/billing"
}
