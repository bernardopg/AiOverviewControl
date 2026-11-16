# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
# The tilde paths are literal UI hints, not paths passed to a command.
# shellcheck disable=SC2088
#
# Ori (OpenRouter's coding agent CLI) runs every turn through OpenRouter and
# records each session it runs in its global workspace, whatever directory it
# was started from: ~/.ori/global/.ori/logs/sessions/<id>/metadata.json holds
# the session's cumulative `usage` (costUsd, inputTokens, outputTokens, model)
# plus startedAt/endedAt. This adapter only reads those files: it never opens
# Ori's SQLite stores (Ori forbids writing its live state database) and never
# touches ~/.ori/auth, whose encrypted credentials are Ori's alone.
fetch_ori_native() {
  local ori_home="$HOME/.ori"
  local sessions_dir="$ori_home/global/.ori/logs/sessions"
  if [ ! -d "$sessions_dir" ]; then
    if command -v ori >/dev/null 2>&1; then
      json_note_usage ori ori-local "Ori · OpenRouter" "local" "No Ori sessions recorded yet" "~/.ori/global/.ori/logs/sessions"
    else
      json_error ori ori-local 2 provider "Ori session directory not found (~/.ori/global/.ori/logs/sessions)."
    fi
    return 0
  fi

  local today_start week_start month_start
  today_start="$(date -d 'today 00:00' +%s)"
  week_start=$(( today_start - 6 * 86400 ))
  month_start="$(date -d "$(date +%Y-%m-01) 00:00" +%s)"

  local login_mode=""
  [ -f "$ori_home/config.json" ] \
    && login_mode="$(jq -r '.loginMode // empty | strings' "$ori_home/config.json" 2>/dev/null || true)"

  # One compact row per session touched this month or in the last 7 days.
  # Each file is parsed on its own so one damaged file only drops its session.
  # ponytail: a session's whole cumulative cost lands on the day it last ran
  # (endedAt); per-turn days would need Ori's history database, which this
  # adapter deliberately leaves alone.
  local rows="" file row since
  since=$(( week_start < month_start ? week_start : month_start ))
  local -a files=()
  mapfile -d '' -t files < <(find "$sessions_dir" -mindepth 2 -maxdepth 2 -name metadata.json \
    -newermt "@$since" -print0 2>/dev/null | head -z -n 2000)
  for file in "${files[@]}"; do
    row="$(jq -c '
      select(type == "object")
      | def num($v): if ($v | type) == "number" then $v else null end;
        (.endedAt // .startedAt // "" | strings | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601? // null) as $at
      | select($at != null)
      | (.usage // {}) as $u
      | {at: $at,
         cost: num($u.costUsd),
         tokens: ((num($u.inputTokens) // 0) + (num($u.outputTokens) // 0)),
         model: ($u.model // ((.runIds // []) | last | .model?) // "")}
    ' "$file" 2>/dev/null || true)"
    [ -n "$row" ] && rows+="$row"$'\n'
  done

  local total_sessions
  total_sessions="$(find "$sessions_dir" -mindepth 2 -maxdepth 2 -name metadata.json 2>/dev/null | wc -l)"

  printf '%s' "$rows" | jq -cs \
    --argjson today "$today_start" \
    --argjson week "$week_start" \
    --argjson month "$month_start" \
    --argjson sessions "${total_sessions:-0}" \
    --arg login "${login_mode:-local}" '
    # Totals: tokens summed; cost null when any session reported none.
    def window($from):
      [.[] | select(.at >= $from)]
      | {tokens: (map(.tokens) | add // 0),
         cost: (if any(.[]; .cost == null) then null else (map(.cost) | add // 0) end),
         count: length};
    def money($v): if $v == null then "—" elif $v > 0 and $v < 0.01 then "<$0.01" else ("$" + ((($v * 100) | round) / 100 | tostring)) end;
    def compact($v):
      (($v // 0)) as $n
      | if $n >= 1000000000 then (((($n / 100000000) | round) / 10) | tostring) + "B"
        elif $n >= 1000000 then (((($n / 100000) | round) / 10) | tostring) + "M"
        elif $n >= 1000 then (((($n / 100) | round) / 10) | tostring) + "K"
        else (($n | round) | tostring)
        end;
    def line($w): money($w.cost) + " · " + compact($w.tokens) + " tok";
    (sort_by(.at) | last | .model // "") as $model
    | ("Ori · OpenRouter" + (if $model != "" then " · " + $model else "" end)) as $account
    | window($today) as $t
    | window($week) as $w
    | window($month) as $m
    | {
        provider: "ori",
        source: "ori-local",
        usage: {
          identity: {providerID: "ori", accountEmail: $account, loginMethod: $login},
          accountEmail: $account,
          loginMethod: $login,
          primary: {usedPercent: 0, hasLimit: false, windowMinutes: null, resetsAt: null, resetDescription: "Today", displayValue: line($t)},
          secondary: {usedPercent: 0, hasLimit: false, windowMinutes: null, resetsAt: null, resetDescription: "Week", displayValue: line($w)},
          tertiary: {usedPercent: 0, hasLimit: false, windowMinutes: null, resetsAt: null, resetDescription: "Month", displayValue: line($m)},
          updatedAt: (now | todateiso8601)
        },
        credits: {remaining: ("agent · " + ($sessions | tostring) + " sessions")}
      }'
}
