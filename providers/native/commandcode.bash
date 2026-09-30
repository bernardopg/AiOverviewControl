# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_commandcode_native() {
  # Command Code (commandcode.ai) — coding-agent subscription quota. The same
  # Provider API key drives inference (/provider/v1/models) and quota
  # introspection (/alpha/billing/credits). The /alpha/ namespace is
  # experimental, so on failure we degrade to /provider/v1/models (auth-only).
  local key
  key="$(commandcode_api_key)"
  if [ -z "$key" ]; then
    json_error commandcode commandcode-api 2 provider "Command Code credentials are unavailable. Set COMMAND_CODE_API_KEY in DMS's graphical session or sign in with cmd login."
    return 0
  fi

  local tmp_body tmp_sub tmp_who http_status
  tmp_body="$(mktemp)"
  tmp_sub="$(mktemp)"
  tmp_who="$(mktemp)"

  # Primary: /alpha/billing/credits — 5h USD used/cap, weekly USD used/cap, and
  # the monthly USD credit balance. Zero token cost, no inference call.
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.commandcode.ai/alpha/billing/credits" 2>/dev/null || true)"

  if [ "$http_status" = "401" ] || [ "$http_status" = "403" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Command Code API key invalid (HTTP ${http_status})."
    rm -f "$tmp_body" "$tmp_sub" "$tmp_who"
    json_error commandcode commandcode-api "${http_status}" provider "$message"
    return 0
  fi

  if [ "$http_status" = "200" ] && jq -e '.windowLimits and .credits' "$tmp_body" >/dev/null 2>&1; then
    # Best-effort identity enrichment (4s timeouts — never fail the whole call).
    curl -sS --max-time 4 -o "$tmp_who" \
      -H "Authorization: Bearer ${key}" \
      -H "Accept: application/json" \
      "https://api.commandcode.ai/alpha/whoami" 2>/dev/null || printf '' >"$tmp_who"
    curl -sS --max-time 4 -o "$tmp_sub" \
      -H "Authorization: Bearer ${key}" \
      -H "Accept: application/json" \
      "https://api.commandcode.ai/alpha/billing/subscriptions" 2>/dev/null || printf '' >"$tmp_sub"

    jq -c --slurpfile who "$tmp_who" --slurpfile sub "$tmp_sub" '
      def clamp($n): if $n < 0 then 0 elif $n > 100 then 100 else $n end;
      def ms_to_iso($ms): if $ms then (($ms / 1000) | todate) else null end;
      def num($v): ($v // 0 | tonumber? // 0);
      def plan_name($id):
        if $id == "individual-go"      then "Go"
        elif $id == "individual-goat"   then "GOAT"
        elif $id == "individual-pro"    then "Pro"
        elif $id == "individual-max-10x"then "Max 10x"
        elif $id == "individual-max-20x"then "Max 20x"
        elif $id == "team-pro"          then "Team Pro"
        elif $id == "provider"          then "Provider API"
        else ($id // "Command Code account") end;
      def make_window($w; $minutes; $label):
        if $w == null then null
        else {
          usedPercent: clamp(((num($w.used) / num($w.cap)) * 100)),
          windowMinutes: $minutes,
          resetsAt: ms_to_iso($w.resetAt),
          resetDescription: $label,
          displayValue: ("$" + ($w.used | tostring) + " / $" + ($w.cap | tostring))
        } end;

      . as $body |
      ($who[0].user.email // null) as $email |
      ($who[0].user.name  // null) as $name |
      ($sub[0].data.planId // null) as $plan |
      plan_name($plan) as $plan_label |
      (if $email != null and $email != "" then
         (if $name != null and $name != "" then "\($name) (\($email))" else $email end)
       elif $plan != null then ("Command Code " + $plan_label)
       else "Command Code account" end) as $identity |
      ($body.credits.monthlyCredits // null) as $monthly |
      ($body.windowLimits.fiveHour // null) as $fh |
      ($body.windowLimits.weekly   // null) as $wk |
      ($fh != null or $wk != null) as $has_window |
      (if $has_window then "commandcode-alpha" else "commandcode-api" end) as $source |
      {
        provider: "commandcode",
        source: $source,
        usage: {
          identity: {providerID: "commandcode", accountEmail: $identity, loginMethod: "api-key"},
          accountEmail: $identity,
          loginMethod: "api-key",
          primary:   make_window($fh; 300;   "5h"),
          secondary: make_window($wk; 10080; "weekly"),
          tertiary:  null,
          updatedAt: (now | todate)
        },
        credits: {remaining: (if $monthly != null then ("$" + ($monthly | tostring)) else ("Command Code " + $plan_label) end)}
      }
    ' "$tmp_body"
    rm -f "$tmp_body" "$tmp_sub" "$tmp_who"
    return 0
  fi

  # /alpha/ failed (timeout, 5xx, parse error). Try the documented
  # /provider/v1/models endpoint — auth-only confirmation that the key works.
  rm -f "$tmp_body"
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.commandcode.ai/provider/v1/models" || true)"
  rm -f "$tmp_body" "$tmp_sub" "$tmp_who"

  if [ "$http_status" = "200" ]; then
    json_note_usage commandcode commandcode-models "Command Code account" "api-key" \
      "Authenticated — quota endpoint unavailable, billing at commandcode.ai/billing" \
      "commandcode.ai/billing"
    return 0
  fi
  json_note_usage commandcode commandcode-api "Command Code account" "api-key" \
    "API key set; Command Code unreachable" \
    "commandcode.ai/billing"
}
