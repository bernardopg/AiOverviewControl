# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_openrouter_native() {
  local key="${OPENROUTER_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error openrouter openrouter-api 2 provider "OPENROUTER_API_KEY is not set and no local 9Router usage was found."
    return 0
  fi

  local tmp_body http_status
  tmp_body="$(mktemp)"
  # /api/v1/key returns the full credit picture (limit_remaining, usage_daily,
  # usage_weekly, usage_monthly); /api/v1/auth/key is a minimal subset and was
  # missing every field this bridge reads.
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://openrouter.ai/api/v1/key" 2>/dev/null || true)"

  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="OpenRouter key check returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error openrouter openrouter-api "${http_status:-1}" provider "$message"
    return 0
  fi

  # Optional documented per-model rollup; failures leave an empty list and the
  # tertiary window falls back to the monthly spend figure.
  local tmp_activity
  tmp_activity="$(mktemp)"
  curl -sS --max-time 8 \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://openrouter.ai/api/v1/activity" 2>/dev/null \
    | jq -c '{data: (.data // [])}' >"$tmp_activity" 2>/dev/null \
    || printf '{"data":[]}' >"$tmp_activity"

  jq -c --slurpfile activity "$tmp_activity" '
    def num($v): ($v // 0 | tonumber? // 0);
    def pct($used; $limit):
      if num($limit) > 0 then
        ((num($used) / num($limit)) * 100)
        | if . < 0 then 0 elif . > 100 then 100 else . end
      else 0 end;
    def money($v):
      (num($v) * 100 | round) as $cc
      | "$" + (($cc / 100) | floor | tostring) + "."
        + ((100 + ($cc % 100) | tostring) | .[1:]);
    def short_model($m):
      ($m // "" | split("/") | last // "") | .[0:24];
    (
      [($activity[0].data // [])[]]
      | group_by(.model)
      | map({model: .[0].model, usage: (map(num(.usage)) | add)})
      | sort_by(-.usage)
      | .[0:2]
    ) as $top_models
    | .data as $d
    | ($d.label // $d.name // "OpenRouter API key") as $label
    | ($d.limit // null) as $limit
    | (if ($d.include_byok_in_limit // false) then num($d.byok_usage) else 0 end) as $byok_usage
    | (if ($d.include_byok_in_limit // false) then num($d.byok_usage_daily) else 0 end) as $byok_daily
    | (if ($d.include_byok_in_limit // false) then num($d.byok_usage_weekly) else 0 end) as $byok_weekly
    | (if ($d.include_byok_in_limit // false) then num($d.byok_usage_monthly) else 0 end) as $byok_monthly
    # $d.usage is the key lifetime spend, while $limit resets with limit_reset
    # (daily/weekly/monthly). Lifetime / limit reads 100% forever once lifetime
    # spend passes the cap, so measure the current window instead: limit minus
    # limit_remaining, else the usage_* counter matching limit_reset. A key with
    # no reset is a lifetime cap and keeps the lifetime figure.
    | (if $limit == null then null
       elif $d.limit_remaining != null then (num($limit) - num($d.limit_remaining))
       elif $d.limit_reset == "daily" then (num($d.usage_daily) + $byok_daily)
       elif $d.limit_reset == "weekly" then (num($d.usage_weekly) + $byok_weekly)
       elif $d.limit_reset == "monthly" then (num($d.usage_monthly) + $byok_monthly)
       else (num($d.usage) + $byok_usage) end) as $window_used
    | (if $d.limit_remaining != null then num($d.limit_remaining)
       elif $limit != null then (num($limit) - $window_used)
       else null end) as $remaining
    | {
      provider:"openrouter",
      source:"openrouter-api",
      usage:{
        identity:{
          providerID:"openrouter",
          accountEmail:$label,
          loginMethod:(if ($d.is_free_tier // false) then "free-tier" else "api-key" end)
        },
        accountEmail:$label,
        loginMethod:(if ($d.is_free_tier // false) then "free-tier" else "api-key" end),
        primary:{
          usedPercent:pct($window_used; $limit),
          windowMinutes:null,
          resetsAt:($d.limit_reset // null),
          resetDescription:"Key limit",
          displayValue:(
            if $limit == null then (money(num($d.usage) + $byok_usage) + " used")
            else (money($window_used) + " / " + money($limit))
            end
          )
        },
        secondary:{
          usedPercent:0,
          windowMinutes:1440,
          resetsAt:null,
          resetDescription:"Spent today",
          displayValue:(money(num($d.usage_daily) + $byok_daily))
        },
        tertiary:(
          ("Week " + money(num($d.usage_weekly) + $byok_weekly) + " · ") as $week_prefix
          | if ($top_models | length) > 0 then {
              usedPercent:0,
              windowMinutes:10080,
              resetsAt:null,
              resetDescription:"Week and top models",
              displayValue:($week_prefix + ($top_models | map(short_model(.model) + " " + money(.usage)) | join(" · ")))
            } else {
              usedPercent:0,
              windowMinutes:10080,
              resetsAt:null,
              resetDescription:"Week and month spend",
              displayValue:($week_prefix + "Month " + money($d.usage_monthly))
            } end
        ),
        updatedAt:(now|todateiso8601)
      },
      credits:{
        remaining:(
          if $remaining != null then (money($remaining))
          elif $limit == null then "unlimited"
          else "unknown"
          end
        )
      }
    }
  ' "$tmp_body"
  rm -f "$tmp_body" "$tmp_activity"
}
