# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_9router_native() {
  local output_provider="${1:-9router}"
  local target_provider="${2:-$output_provider}"
  local soft_fail="${3:-false}"
  local source_label="9router-local"
  local db_path="$HOME/.9router/db/data.sqlite"
  local usage_json="$HOME/.9router/usage.json"
  local tmp_rows
  tmp_rows="$(mktemp)"

  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$db_path" ]; then
    sqlite3 -json "$db_path" 'select dateKey as date, data from usageDaily order by dateKey' >"$tmp_rows" 2>/dev/null || true
  fi

  if [ ! -s "$tmp_rows" ] && [ -f "$usage_json" ]; then
    jq -c '[.dailySummary // {} | to_entries[] | {date:.key,data:(.value|tojson)}]' "$usage_json" >"$tmp_rows" 2>/dev/null || true
  fi

  if [ ! -s "$tmp_rows" ]; then
    rm -f "$tmp_rows"
    if [ "$soft_fail" = "soft" ]; then
      return 1
    fi
    json_error "$output_provider" "$source_label" 2 provider "9router usage database not found. Start 9router once so ~/.9router/db/data.sqlite or ~/.9router/usage.json exists."
    return 0
  fi

  local item
  item="$(jq -c \
    --arg output "$output_provider" \
    --arg target "$target_provider" \
    --arg source "$source_label" '
    def num($v): ($v // 0 | tonumber? // 0);
    # Always render two decimal places ("$0.00", "$0.50"). jq tostring on a float
    # drops trailing zeros, giving inconsistent "$0"/"$0.5". This jq program is
    # interpolated inside a double-quoted command substitution, so the formatter
    # must avoid bash-significant tokens (no (( )), no < or > comparisons): pad
    # the cents by formatting (100 + cents) and slicing off the leading "1".
    def money($v):
      (num($v) * 100 | round) as $cc
      | "$" + (($cc / 100) | floor | tostring) + "."
        + ((100 + ($cc % 100) | tostring) | .[1:]);
    def compact($v):
      (num($v)) as $n
      | if $n >= 1000000000 then (((($n / 100000000) | round) / 10) | tostring) + "B"
        elif $n >= 1000000 then (((($n / 100000) | round) / 10) | tostring) + "M"
        elif $n >= 1000 then (((($n / 100) | round) / 10) | tostring) + "K"
        else (($n | round) | tostring)
        end;
    def request_text($v): (num($v) | floor | tostring) + " req";
    def provider_data($day; $provider):
      if $provider == "9router" then $day
      else ($day.byProvider[$provider] // null)
      end;
    [ .[] | {date, day:(.data | if type == "string" then fromjson else . end)} ] as $days
    | [ $days[] | {date, data:provider_data(.day; $target)} | select(.data != null) ] as $matches
    | if ($matches | length) == 0 then empty
      else
        ($matches | sort_by(.date) | last) as $latest
        | (reduce $matches[] as $entry ({requests:0,promptTokens:0,cachedTokens:0,completionTokens:0,cost:0};
            .requests += num($entry.data.requests)
            | .promptTokens += num($entry.data.promptTokens)
            | .cachedTokens += num($entry.data.cachedTokens)
            | .completionTokens += num($entry.data.completionTokens)
            | .cost += num($entry.data.cost)
          )) as $total
        | (if $output == "9router" then "9router · all routed models" else ($output + " via 9router (local)") end) as $account
        | (if $output == "9router" then "" else " · local-routed, not " + $output + " quota" end) as $routed_note
        | {
            provider:$output,
            source:$source,
            usage:{
              identity:{providerID:$output,accountEmail:$account,loginMethod:"local-db"},
              accountEmail:$account,
              loginMethod:"local-db",
              primary:{
                # 9router is a local proxy with no quota of its own, so a
                # usage percentage would be meaningless. Keep the bar empty
                # and let displayValue carry the cost/request figures. When
                # this stands in for another provider (no API key set), the
                # label says so explicitly so the card is never mistaken for
                # that provider real quota.
                usedPercent:0,
                windowMinutes:null,
                resetsAt:null,
                resetDescription:("Latest day " + $latest.date + $routed_note),
                displayValue:(money($latest.data.cost) + " · " + request_text($latest.data.requests))
              },
              secondary:{
                usedPercent:0,
                windowMinutes:null,
                resetsAt:null,
                resetDescription:"Tracked total",
                displayValue:(money($total.cost) + " · " + request_text($total.requests))
              },
              tertiary:{
                usedPercent:0,
                windowMinutes:null,
                resetsAt:null,
                resetDescription:"Tokens",
                displayValue:(compact($total.promptTokens) + " in · " + compact($total.cachedTokens) + " cached · " + compact($total.completionTokens) + " out")
              },
              updatedAt:(now|todateiso8601)
            },
            credits:{remaining:(money($total.cost) + " total")}
          }
      end
  ' "$tmp_rows" 2>/dev/null || true)"

  rm -f "$tmp_rows"

  if [ -z "$item" ]; then
    if [ "$soft_fail" = "soft" ]; then
      return 1
    fi
    json_error "$output_provider" "$source_label" 2 provider "9router has no recorded usage for ${target_provider}."
    return 0
  fi

  printf '%s\n' "$item"
}
