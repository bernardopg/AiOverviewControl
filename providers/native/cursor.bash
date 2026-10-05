# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
#
# Cursor publishes no individual-user quota API. The web dashboard reads
# https://cursor.com/api/usage-summary with the session the IDE or
# cursor-agent already stored. This adapter only reads that session and
# sends it to cursor.com. It never writes, refreshes, or logs the token.
#
# The included-usage screen is two pools, Cursor Models and Other Models.
# plan.used / plan.limit can read 100 while those pools are still partly
# unused, so that ratio is not a bar. On-demand is a third bar only after
# the user turns that spend on.

cursor_jwt_payload() {
  local token="$1" payload pad i
  payload="${token#*.}"
  payload="${payload%%.*}"
  [ "$payload" != "$token" ] && [ -n "$payload" ] || return 1
  payload="${payload//-/+}"
  payload="${payload//_/\/}"
  pad=$(((4 - ${#payload} % 4) % 4))
  for ((i = 0; i < pad; i++)); do payload+="="; done
  printf '%s' "$payload" | base64 -d 2>/dev/null
}

cursor_consider_token() {
  local live_file="$1" expired_file="$2" token="$3" email="$4" membership="$5" source="$6"
  local payload subject exp now obj
  [ -n "$token" ] || return 0
  payload="$(cursor_jwt_payload "$token" || true)"
  [ -n "$payload" ] || return 0
  subject="$(printf '%s' "$payload" | jq -r 'if (.sub | type) == "string" then .sub else empty end' 2>/dev/null || true)"
  [ -n "$subject" ] || return 0
  exp="$(printf '%s' "$payload" | jq -r 'if (.exp | type) == "number" then (.exp | floor) else empty end' 2>/dev/null || true)"
  obj="$(jq -nc \
    --arg token "$token" \
    --arg subject "$subject" \
    --arg email "$email" \
    --arg membership "$membership" \
    --arg source "$source" \
    --arg exp "$exp" \
    '{token:$token, subject:$subject, email:$email, membership:$membership, source:$source,
      exp:(if $exp == "" then null else ($exp | tonumber) end)}')"
  now="$(date +%s)"
  if [ -n "$exp" ] && [ "$exp" -le "$now" ]; then
    [ -s "$expired_file" ] || printf '%s\n' "$obj" >"$expired_file"
    return 0
  fi
  printf '%s\n' "$obj" >>"$live_file"
}

cursor_cli_identity() {
  local config="$1"
  [ -r "$config" ] || return 0
  jq -r '[.authInfo.email // "", .authInfo.displayName // ""] | @tsv' "$config" 2>/dev/null || true
}

cursor_read_auth_file() {
  local live_file="$1" expired_file="$2" auth_file="$3"
  local token email identity
  [ -r "$auth_file" ] || return 0
  token="$(jq -r 'if (.accessToken | type) == "string" then .accessToken else empty end' "$auth_file" 2>/dev/null || true)"
  identity="$(cursor_cli_identity "${CURSOR_CLI_CONFIG:-}")"
  if [ -z "$identity" ]; then
    local sibling
    sibling="$(dirname "$auth_file")/cli-config.json"
    identity="$(cursor_cli_identity "$sibling")"
  fi
  email="${identity%%$'\t'*}"
  cursor_consider_token "$live_file" "$expired_file" "$token" "$email" "" "cli"
}

cursor_read_state_db() {
  local live_file="$1" expired_file="$2" db="$3"
  local token email membership
  [ -r "$db" ] || return 0
  command -v sqlite3 >/dev/null 2>&1 || return 0
  token="$(sqlite3 "file:${db}?mode=ro" "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;" 2>/dev/null || true)"
  email="$(sqlite3 "file:${db}?mode=ro" "SELECT value FROM ItemTable WHERE key='cursorAuth/cachedEmail' LIMIT 1;" 2>/dev/null || true)"
  membership="$(sqlite3 "file:${db}?mode=ro" "SELECT value FROM ItemTable WHERE key='cursorAuth/stripeMembershipType' LIMIT 1;" 2>/dev/null || true)"
  token="${token//$'\n'/}"
  email="${email//$'\n'/}"
  membership="${membership//$'\n'/}"
  cursor_consider_token "$live_file" "$expired_file" "$token" "$email" "$membership" "desktop"
}

# Prints one session JSON object, or nothing when no token parses.
cursor_resolve_session() {
  local live_file expired_file
  live_file="$(mktemp)"
  expired_file="$(mktemp)"
  : >"$live_file"

  if [ -n "${CURSOR_AUTH_FILE+x}" ] || [ -n "${CURSOR_STATE_DB+x}" ]; then
    [ -z "${CURSOR_AUTH_FILE:-}" ] || cursor_read_auth_file "$live_file" "$expired_file" "$CURSOR_AUTH_FILE"
    [ -z "${CURSOR_STATE_DB:-}" ] || cursor_read_state_db "$live_file" "$expired_file" "$CURSOR_STATE_DB"
  else
    local auth_file db
    for auth_file in \
      "${XDG_CONFIG_HOME:-$HOME/.config}/cursor/auth.json" \
      "$HOME/.cursor/auth.json"; do
      cursor_read_auth_file "$live_file" "$expired_file" "$auth_file"
    done
    for db in \
      "${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/globalStorage/state.vscdb" \
      "$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"; do
      cursor_read_state_db "$live_file" "$expired_file" "$db"
    done
  fi

  if [ -s "$live_file" ]; then
    head -n 1 "$live_file"
  elif [ -s "$expired_file" ]; then
    head -n 1 "$expired_file"
  fi
  rm -f "$live_file" "$expired_file"
}

cursor_map_summary() {
  local body="$1" email="$2" membership="$3"
  jq -c \
    --arg email "$email" \
    --arg membership "$membership" \
    '
    def num($v):
      if ($v | type) == "number" then
        if (($v | isnan) or ($v | isinfinite)) then null else $v end
      elif ($v | type) == "string" and ($v | test("^-?[0-9]+([.][0-9]+)?$")) then ($v | tonumber)
      else null end;
    def clamp($n):
      if $n == null then null else ([0, $n] | max | [100, .] | min) end;
    def ts_ms($v):
      if ($v | type) == "number" and ((. | isnan) or (. | isinfinite) | not) then
        if $v > 1000000000000 then $v else $v * 1000 end
      elif ($v | type) == "string" and ($v | test("^[0-9]+$")) then ts_ms($v | tonumber)
      elif ($v | type) == "string" and ($v | length) > 0 then
        try (($v | sub("[.][0-9]+"; "") | sub("[+]00:00$"; "Z") | fromdateiso8601) * 1000) catch null
      else null end;
    # On-demand is a spend cap the user enabled. The included pools are not:
    # their used/limit ratio can hit 100 while autoPercentUsed is still ~16,
    # which is the number the Cursor included-usage screen shows.
    def allowance($pool):
      if $pool == null then null
      else
        (num($pool.used)) as $u | (num($pool.limit)) as $l
        | if $u != null and $l != null and $l > 0 then clamp($u / $l * 100)
          else clamp(num($pool.totalPercentUsed))
          end
      end;
    def reported($pool; $field):
      if $pool == null then null else clamp(num($pool[$field])) end;
    def window($pct; $minutes; $resets; $label):
      {usedPercent:$pct, windowMinutes:$minutes, resetsAt:$resets, resetDescription:$label};

    . as $body
    | ($body.individualUsage.plan // null) as $plan
    | ($body.individualUsage.onDemand // null) as $demand
    | ($body.isUnlimited == true) as $unlimited
    | (if ($body.membershipType | type) == "string" and ($body.membershipType | gsub("^\\s+|\\s+$"; "") | length) > 0
        then ($body.membershipType | gsub("^\\s+|\\s+$"; ""))
        else $membership end) as $plan_name
    | (ts_ms($body.billingCycleStart)) as $start
    | (ts_ms($body.billingCycleEnd)) as $end
    | (if $start != null and $end != null and $end > $start
        then (((($end - $start) / 60000) | round) | if . < 1 then 1 else . end)
        else 43200 end) as $minutes
    | (if $end == null then null else ($end / 1000 | todate) end) as $resets
    | (if $plan != null and ($plan.enabled != false) then $plan else null end) as $owned
    | [
        (reported($owned; "autoPercentUsed") as $pct | if $pct == null then empty else window($pct; $minutes; $resets; "Cursor Models") end),
        (reported($owned; "apiPercentUsed") as $pct | if $pct == null then empty else window($pct; $minutes; $resets; "Other Models") end),
        (if $demand != null and $demand.enabled == true then
           (allowance($demand) as $pct | if $pct == null then empty else window($pct; $minutes; $resets; "On-demand") end)
         else empty end)
      ] as $pools
    | (if ($pools | length) > 0 then $pools
       elif $owned != null then
         (reported($owned; "totalPercentUsed") as $pct | if $pct == null then [] else [window($pct; $minutes; $resets; "Plan")] end)
       else [] end) as $windows
    | (if ($email | length) > 0 then $email else "Cursor account" end) as $account
    | (if ($plan_name | length) > 0 then $plan_name else "session" end) as $login
    | if $unlimited then
        {kind:"unlimited", account:$account, login:$login}
      elif ($windows | length) == 0 then
        {kind:"empty", account:$account, login:$login}
      else
        {kind:"usage", account:$account, login:$login,
         usage:{
           provider:"cursor",
           source:"cursor-dashboard",
           usage:{
             identity:{providerID:"cursor", accountEmail:$account, loginMethod:$login},
             accountEmail:$account,
             loginMethod:$login,
             primary:$windows[0],
             secondary:($windows[1] // null),
             tertiary:($windows[2] // null),
             updatedAt:(now | todateiso8601)
           },
           credits:{remaining:$login}
         }}
      end
    ' "$body"
}

cursor_legacy_window() {
  local body="$1"
  # strptime/mktime follow the process timezone. Pin UTC so a month boundary
  # does not shift with the machine's local offset.
  TZ=UTC jq -c '
    def num($v):
      if ($v | type) == "number" then
        if (($v | isnan) or ($v | isinfinite)) then null else $v end
      elif ($v | type) == "string" and ($v | test("^-?[0-9]+([.][0-9]+)?$")) then ($v | tonumber)
      else null end;
    def ts_ms($v):
      if ($v | type) == "number" then (if $v > 1000000000000 then $v else $v * 1000 end)
      elif ($v | type) == "string" and ($v | test("^[0-9]+$")) then ts_ms($v | tonumber)
      elif ($v | type) == "string" and ($v | length) > 0 then
        try (($v | sub("[.][0-9]+"; "") | sub("[+]00:00$"; "Z") | fromdateiso8601) * 1000) catch null
      else null end;
    def add_month($ms):
      ((($ms / 1000) | strftime("%Y-%m-%dT%H:%M:%SZ") | strptime("%Y-%m-%dT%H:%M:%SZ"))) as $p
      | (if $p[1] == 11 then ($p[0] + 1) else $p[0] end) as $y
      | (if $p[1] == 11 then 0 else ($p[1] + 1) end) as $m
      | [31, (if ($y % 4 == 0 and $y % 100 != 0) or ($y % 400 == 0) then 29 else 28 end), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] as $dim
      | [$y, $m, ([$p[2], $dim[$m]] | min), $p[3], $p[4], $p[5], 0, 0]
      | mktime;
    [to_entries[]
      | select(.value | type == "object")
      | (num(.value.maxRequestUsage)) as $limit
      | (num(.value.numRequests)) as $used
      | select($limit != null and $limit > 0 and $used != null)
      | {name:.key, used:$used, limit:$limit}
    ] as $rows
    | if ($rows | length) == 0 then null
      else
        (($rows | map(select(.name == "gpt-4")) | .[0]) // ($rows | sort_by(-.limit) | .[0])) as $q
        | (ts_ms(.startOfMonth)) as $start
        | (if $start == null then null else (add_month($start) | todate) end) as $resets
        | {
            usedPercent: ([0, ($q.used / $q.limit * 100)] | max | [100, .] | min),
            windowMinutes: 43200,
            resetsAt: $resets,
            resetDescription: "Plan"
          }
      end
  ' "$body"
}

cursor_dashboard_get() {
  local url="$1" cookie="$2" body="$3"
  curl -sS --max-time 10 --proto '=https' --max-redirs 0 \
    -o "$body" -w '%{http_code}' \
    -H "Cookie: ${cookie}" \
    -H "Accept: application/json" \
    -H "Origin: https://cursor.com" \
    -H "Referer: https://cursor.com/dashboard" \
    "$url" 2>/dev/null || true
}

fetch_cursor_native() {
  local session token subject email membership cookie enc_subject
  local summary_body summary_status mapped kind
  session="$(cursor_resolve_session || true)"
  if [ -z "$session" ]; then
    json_error cursor cursor-dashboard 2 provider "No Cursor sign-in on this computer. Sign in with the Cursor IDE or cursor-agent login."
    return 0
  fi
  token="$(printf '%s' "$session" | jq -r '.token')"
  subject="$(printf '%s' "$session" | jq -r '.subject')"
  email="$(printf '%s' "$session" | jq -r '.email // ""')"
  membership="$(printf '%s' "$session" | jq -r '.membership // ""')"
  if [ "$(printf '%s' "$session" | jq -r 'if .exp == null then "live" elif .exp <= now then "expired" else "live" end')" = "expired" ]; then
    json_error cursor cursor-dashboard 401 provider "Cursor sign-in expired. Sign in with the Cursor IDE or run cursor-agent login again."
    return 0
  fi

  enc_subject="$(jq -nr --arg v "$subject" '$v | @uri')"
  cookie="WorkosCursorSessionToken=${enc_subject}%3A%3A${token}"
  summary_body="$(mktemp)"
  summary_status="$(cursor_dashboard_get "https://cursor.com/api/usage-summary" "$cookie" "$summary_body")"
  case "$summary_status" in
    401|403)
      rm -f "$summary_body"
      json_error cursor cursor-dashboard "$summary_status" provider "Cursor sign-in expired. Sign in with the Cursor IDE or run cursor-agent login again."
      return 0
      ;;
    429)
      rm -f "$summary_body"
      json_error cursor cursor-dashboard 429 provider "Cursor usage is rate limited right now."
      return 0
      ;;
    200) ;;
    *)
      rm -f "$summary_body"
      json_error cursor cursor-dashboard 1 runtime "Cursor usage request failed (HTTP ${summary_status:-0})."
      return 0
      ;;
  esac

  if ! mapped="$(cursor_map_summary "$summary_body" "$email" "$membership" 2>/dev/null)"; then
    rm -f "$summary_body"
    json_error cursor cursor-dashboard 1 provider "Cursor usage response could not be parsed."
    return 0
  fi
  rm -f "$summary_body"
  kind="$(printf '%s' "$mapped" | jq -r '.kind')"
  case "$kind" in
    usage)
      printf '%s' "$mapped" | jq -c '.usage'
      return 0
      ;;
    unlimited)
      json_note_usage cursor cursor-dashboard \
        "$(printf '%s' "$mapped" | jq -r '.account')" \
        "$(printf '%s' "$mapped" | jq -r '.login')" \
        "Unlimited" "cursor.com/settings"
      return 0
      ;;
  esac

  local legacy_body legacy_status user_q legacy_window account login
  account="$(printf '%s' "$mapped" | jq -r '.account')"
  login="$(printf '%s' "$mapped" | jq -r '.login')"
  user_q="$(jq -nr --arg v "$subject" '$v | @uri')"
  legacy_body="$(mktemp)"
  legacy_status="$(cursor_dashboard_get "https://cursor.com/api/usage?user=${user_q}" "$cookie" "$legacy_body")"
  if [ "$legacy_status" = "200" ]; then
    legacy_window="$(cursor_legacy_window "$legacy_body" 2>/dev/null || true)"
  fi
  rm -f "$legacy_body"
  if [ -n "${legacy_window:-}" ] && [ "$legacy_window" != "null" ]; then
    jq -nc \
      --arg account "$account" \
      --arg login "$login" \
      --argjson window "$legacy_window" \
      '{
        provider:"cursor",
        source:"cursor-dashboard",
        usage:{
          identity:{providerID:"cursor", accountEmail:$account, loginMethod:$login},
          accountEmail:$account,
          loginMethod:$login,
          primary:$window,
          secondary:null,
          tertiary:null,
          updatedAt:(now | todateiso8601)
        },
        credits:{remaining:$login}
      }'
    return 0
  fi

  json_error cursor cursor-dashboard 1 provider "Cursor reported no usage allowance for this account."
}
