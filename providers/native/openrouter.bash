# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
#
# AIOC_OPENROUTER_VIEW picks what the card's main bar shows (setting
# `openrouterView`):
#   key          the key's spending cap, or the :free model allowance for an
#                uncapped key (default, the behaviour before the setting).
#   key-balance  what is left of the key's cap, in dollars. An uncapped key
#                has no such balance and keeps the `key` bar.
#   account      the account's credit balance from GET /api/v1/credits
#                (total_credits - total_usage), the figure openrouter.ai/credits
#                shows. The docs list the route as management-key only, yet it
#                answers an ordinary key too; OPENROUTER_MANAGEMENT_KEY (or the
#                AIOC_VAULT_OPENROUTER_MANAGEMENT keyring entry) is used for it
#                when set. A refusal keeps the `key` bar and names the reason.
# GET /api/v1/activity rejects ordinary keys (403 "Only management keys can
# fetch activity"), so the per-model rollup is only asked with a management key.
fetch_openrouter_native() {
  local key="${OPENROUTER_API_KEY:-}"
  [ -n "$key" ] || key="$(vault_key openrouter)"
  if [ -z "$key" ]; then
    json_error openrouter openrouter-api 2 provider "OPENROUTER_API_KEY is not set, AIOC_VAULT_OPENROUTER found no unlocked keyring entry, and no local 9Router usage was found."
    return 0
  fi
  local management="${OPENROUTER_MANAGEMENT_KEY:-}"
  [ -n "$management" ] || management="$(vault_key openrouter_management)"
  local view="${AIOC_OPENROUTER_VIEW:-key}"
  case "$view" in
    key|key-balance|account) ;;
    *) view="key" ;;
  esac

  local tmp_body http_status
  tmp_body="$(mktemp)"
  # /api/v1/key returns the full credit picture (limit_remaining, usage_daily,
  # usage_weekly, usage_monthly); /api/v1/auth/key is a minimal subset and was
  # missing every field this bridge reads.
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    --config <(curl_header_config "Authorization: Bearer ${key}") \
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

  # Optional per-model rollup (last 30 days); without a management key, or on
  # any failure, the list stays empty and the tertiary window falls back to the
  # monthly spend figure.
  local tmp_activity
  tmp_activity="$(mktemp)"
  printf '{"data":[]}' >"$tmp_activity"
  if [ -n "$management" ]; then
    curl -sS --max-time 8 \
      --config <(curl_header_config "Authorization: Bearer ${management}") \
      -H "Accept: application/json" \
      "https://openrouter.ai/api/v1/activity" 2>/dev/null \
      | jq -c '{data: (if (.data | type) == "array" then .data else [] end)}' >"$tmp_activity.new" 2>/dev/null \
      && mv -f "$tmp_activity.new" "$tmp_activity"
    rm -f "$tmp_activity.new"
  fi

  # Account balance, asked only for the `account` view. The result is
  # {ok:true,data:{...}} or {ok:false,code,message} for the jq step below.
  local tmp_credits
  tmp_credits="$(mktemp)"
  printf '{"ok":false,"code":0,"message":""}' >"$tmp_credits"
  if [ "$view" = "account" ]; then
    local credits_key="${management:-$key}" credits_body credits_status
    credits_body="$(mktemp)"
    credits_status="$(curl -sS --max-time 8 -o "$credits_body" -w '%{http_code}' \
      --config <(curl_header_config "Authorization: Bearer ${credits_key}") \
      -H "Accept: application/json" \
      "https://openrouter.ai/api/v1/credits" 2>/dev/null || true)"
    # Slurped so an empty body still yields one answer; a body that is not
    # JSON at all fails jq and takes the fallback below.
    jq -cs --arg status "${credits_status:-0}" --arg management "${management:+1}" '
      def num: (. // null) | if type == "number" then . elif type == "string" then (tonumber? // null) else null end;
      ((.[0] // {}) | if type == "object" then . else {} end) as $b
      | if $status == "200" and ($b.data.total_credits? | num) != null and ($b.data.total_usage? | num) != null then
        {ok: true, data: {total: ($b.data.total_credits | num), used: ($b.data.total_usage | num)}}
      else
        {ok: false,
         code: ($status | tonumber? // 0),
         message: (
           if $status == "403" and $management == "" then
             "Account balance needs a management key (OPENROUTER_MANAGEMENT_KEY)"
           else
             "Account balance unavailable (HTTP " + $status + ")"
           end)}
      end
    ' "$credits_body" >"$tmp_credits" 2>/dev/null \
      || jq -cn --arg status "${credits_status:-0}" \
        '{ok:false, code:($status | tonumber? // 0), message:("Account balance unavailable (HTTP " + $status + ")")}' >"$tmp_credits"
    rm -f "$credits_body"
  fi

  jq -c --slurpfile activity "$tmp_activity" --slurpfile account "$tmp_credits" --arg view "$view" '
    def num($v): ($v // 0 | tonumber? // 0);
    def pct($used; $limit):
      if num($limit) > 0 then
        ((num($used) / num($limit)) * 100)
        | if . < 0 then 0 elif . > 100 then 100 else . end
      else 0 end;
    # Two decimals with a leading minus for a negative balance ("-$1.50"):
    # OpenRouter lets an account run slightly below zero.
    def money($v):
      (num($v) * 100 | round) as $signed
      | (if $signed < 0 then -$signed else $signed end) as $cc
      | (if $signed < 0 then "-$" else "$" end)
        + (($cc / 100) | floor | tostring) + "."
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
    | ($account[0] // {ok: false, message: ""}) as $acct
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
    # Daily request allowance for :free models (50/day, 1000/day once the
    # account bought $10 of credits). It resets at 00:00 UTC.
    | ($d.free_model_daily_requests // null) as $free
    | (if ($free | type) == "object" and num($free.limit) > 0 then {
        usedPercent:pct($free.used; $free.limit),
        windowMinutes:1440,
        resetsAt:(((now / 86400 | floor) + 1) * 86400 | todateiso8601),
        resetDescription:"Free model requests",
        displayValue:((num($free.used) | tostring) + " / " + (num($free.limit) | tostring) + " requests")
      } else null end) as $free_window
    | (if $d.limit_remaining != null then num($d.limit_remaining)
       elif $limit != null then (num($limit) - $window_used)
       else null end) as $remaining
    # A key without a spending cap is bounded only by the free-model
    # allowance, so that becomes the bar; a capped key keeps its cap.
    | (if $limit == null and $free_window != null then $free_window else {
        usedPercent:pct($window_used; $limit),
        windowMinutes:null,
        resetsAt:($d.limit_reset // null),
        resetDescription:"Key limit",
        # An uncapped key with no free-model allowance has only its spend to
        # show: a plain reading, not a 0% quota.
        hasLimit:($limit != null),
        displayValue:(
          if $limit == null then (money(num($d.usage) + $byok_usage) + " used")
          else (money($window_used) + " / " + money($limit))
          end
        )
      } end) as $key_window
    # Balance windows follow the widget contract: an amount in displayValue.
    # The key balance is measured against the spending cap of the key
    # (hasLimit), so its bar and colour show how much of the cap is spent. The account balance
    # has nothing to compare with: usedPercent only says whether it is used
    # up (0 or 100), and the card shows the amount without a bar.
    | (if $view == "key-balance" and $remaining != null then {
        usedPercent:pct($window_used; $limit),
        windowMinutes:null,
        resetsAt:null,
        resetDescription:"Key balance",
        isBalance:true,
        hasLimit:true,
        displayValue:money($remaining)
      } elif $view == "account" and $acct.ok == true then
        ($acct.data.total - $acct.data.used) as $balance
        | {
          usedPercent:(if $balance <= 0 then 100 else 0 end),
          windowMinutes:null,
          resetsAt:null,
          resetDescription:"Account balance",
          isBalance:true,
          displayValue:money($balance)
        }
      else $key_window end) as $primary
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
        primary:$primary,
        secondary:{
          usedPercent:0,
          hasLimit:false,
          windowMinutes:1440,
          resetsAt:null,
          resetDescription:"Spent today",
          displayValue:(money(num($d.usage_daily) + $byok_daily))
        },
        tertiary:(
          # The translated label names the windows ("Week and month spend",
          # "Week and top models"), so the value carries amounts only.
          (money(num($d.usage_weekly) + $byok_weekly) + " · ") as $week_prefix
          | if ($top_models | length) > 0 then {
              usedPercent:0,
              hasLimit:false,
              windowMinutes:10080,
              resetsAt:null,
              resetDescription:"Week and top models",
              displayValue:($week_prefix + ($top_models | map(short_model(.model) + " " + money(.usage)) | join(" · ")))
            } else {
              usedPercent:0,
              hasLimit:false,
              windowMinutes:10080,
              resetsAt:null,
              resetDescription:"Week and month spend",
              displayValue:($week_prefix + money($d.usage_monthly))
            } end
        ),
        updatedAt:(now|todateiso8601)
      },
      credits:(
        # The account view reports the account balance (or why it is missing);
        # the key views report what is left on the key.
        if $view == "account" then
          (if $acct.ok == true then
             {remaining:money($acct.data.total - $acct.data.used),
              account:{total:$acct.data.total, used:$acct.data.used, balance:($acct.data.total - $acct.data.used)}}
           else {remaining:($acct.message // "Account balance unavailable")} end)
        else
          {remaining:(
            if $remaining != null then (money($remaining))
            elif $limit == null then "unlimited"
            else "unknown"
            end
          )}
        end
      )
    }
  ' "$tmp_body"
  rm -f "$tmp_body" "$tmp_activity" "$tmp_credits"
}
