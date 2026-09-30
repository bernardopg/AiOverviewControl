# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_claude_native() {
  if [ ! -f "$CLAUDE_SCRIPT" ]; then
    json_error claude claude-local 127 runtime "Local Claude usage helper is missing."
    return 0
  fi

  local tmp_out tmp_err status
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  bash "$CLAUDE_SCRIPT" >"$tmp_out" 2>"$tmp_err"
  status=$?

  if [ "$status" -ne 0 ]; then
    local message
    message="$(cat "$tmp_err" 2>/dev/null || true)"
    [ -n "$message" ] || message="Claude local usage helper exited with status $status."
    rm -f "$tmp_out" "$tmp_err"
    json_error claude claude-local "$status" runtime "$message"
    return 0
  fi

  local usage_error_kind usage_error_message
  usage_error_kind="$(sed -n 's/^USAGE_ERROR_KIND=//p' "$tmp_out" | head -1)"
  usage_error_message="$(sed -n 's/^USAGE_ERROR_MESSAGE=//p' "$tmp_out" | head -1)"
  if [ -n "$usage_error_message" ]; then
    rm -f "$tmp_out" "$tmp_err"
    json_error claude claude-oauth 1 "${usage_error_kind:-provider}" "$usage_error_message"
    return 0
  fi

  jq -Rn '
    def num($k): ((.[$k] // 0) | tonumber? // 0);
    def text($k): (.[$k] // "");
    def nullable($v): if ($v == null or $v == "") then null else $v end;
    def clamp($n): if $n < 0 then 0 elif $n > 100 then 100 else $n end;
    reduce inputs as $line ({};
      ($line | capture("^(?<key>[^=]+)=(?<value>.*)$")?) as $kv
      | if $kv then .[$kv.key] = $kv.value else . end
    )
    | . as $d
    | {
      provider:"claude",
      source:"claude-local",
      usage:{
        identity:{
          providerID:"claude",
          accountEmail:"Claude Code",
          loginMethod:($d.SUBSCRIPTION_TYPE // "unknown")
        },
        accountEmail:"Claude Code",
        loginMethod:($d.SUBSCRIPTION_TYPE // "unknown"),
        primary:{
          usedPercent:clamp(($d.FIVE_HOUR_UTIL // 0 | tonumber? // 0)),
          windowMinutes:300,
          resetsAt:nullable($d.FIVE_HOUR_RESET),
          resetDescription:"5 hour"
        },
        secondary:{
          usedPercent:clamp(($d.SEVEN_DAY_UTIL // 0 | tonumber? // 0)),
          windowMinutes:10080,
          resetsAt:nullable($d.SEVEN_DAY_RESET),
          resetDescription:"7 day"
        },
        tertiary:(
          if (($d.SCOPED_LIMIT_MODEL // "") != "") then {
            usedPercent:clamp(($d.SCOPED_LIMIT_UTIL // 0 | tonumber? // 0)),
            windowMinutes:10080,
            resetsAt:nullable($d.SCOPED_LIMIT_RESET),
            resetDescription:("7 day · " + $d.SCOPED_LIMIT_MODEL)
          } else null end
        ),
        updatedAt:(now|todateiso8601)
      },
      credits:{remaining:($d.RATE_LIMIT_TIER // "unknown")}
      ,analytics:{
        weekMessages:num("WEEK_MESSAGES"),
        weekSessions:num("WEEK_SESSIONS"),
        weekTokens:num("WEEK_TOKENS"),
        monthTokens:num("MONTH_TOKENS"),
        alltimeSessions:num("ALLTIME_SESSIONS"),
        alltimeMessages:num("ALLTIME_MESSAGES"),
        firstSession:nullable($d.FIRST_SESSION),
        todayCost:num("TODAY_COST"),
        weekCost:num("WEEK_COST"),
        monthCost:num("MONTH_COST"),
        dailyTokens:(text("DAILY") | split(",") | map(tonumber? // 0)),
        dailyCosts:(text("DAILY_COSTS") | split(",") | map(tonumber? // 0)),
        weekModels:text("WEEK_MODELS"),
        weekModelCosts:text("WEEK_MODEL_COSTS"),
        weekProjects:text("WEEK_PROJECTS"),
        extraUsage:{
          enabled:(text("EXTRA_USAGE_ENABLED") == "true"),
          used:num("EXTRA_USAGE_USED"), limit:num("EXTRA_USAGE_LIMIT"),
          utilization:num("EXTRA_USAGE_UTIL"), currency:text("EXTRA_USAGE_CURRENCY")
        }
      }
    }
  ' < "$tmp_out"
  rm -f "$tmp_out" "$tmp_err"
}
