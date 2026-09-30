# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
# The tilde paths are literal UI hints, not paths passed to a command.
# shellcheck disable=SC2088
fetch_pi_native() {
  # pi is Analytics-only (no quota API) — the envelope stays cheap by only
  # ever reading the cache providers/get-pi-analytics maintains; it never
  # triggers the full session scan itself (that would risk the dispatcher's
  # shared timeout). The widget's own piStatsProcess refreshes that cache on
  # its own timer and drives the expanded "pi telemetry" card.
  local sessions_dir="$HOME/.pi/agent/sessions"
  if [ ! -d "$sessions_dir" ]; then
    json_error pi pi-local 2 provider "pi session directory not found (~/.pi/agent/sessions)."
    return 0
  fi

  local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/AiOverviewControl/pi-analytics-v2-cache.json"
  if [ ! -f "$cache_file" ] || ! jq -e '.data | type == "object"' "$cache_file" >/dev/null 2>&1; then
    json_note_usage pi pi-local "pi coding agent" "local" "Local session analytics — expand card for details" "~/.pi/agent/sessions"
    return 0
  fi

  jq -c '
    def money($v): if $v == null then "—" elif $v > 0 and $v < 0.01 then "<$0.01" else ("$" + (($v * 100 | round) / 100 | tostring)) end;
    def compact($v):
      (($v // 0)) as $n
      | if $n >= 1000000000 then (((($n / 100000000) | round) / 10) | tostring) + "B"
        elif $n >= 1000000 then (((($n / 100000) | round) / 10) | tostring) + "M"
        elif $n >= 1000 then (((($n / 100) | round) / 10) | tostring) + "K"
        else (($n | round) | tostring)
        end;
    .data as $d
    | {
        provider: "pi",
        source: "pi-local",
        usage: {
          identity: {providerID:"pi", accountEmail:"pi coding agent", loginMethod:"local"},
          accountEmail: "pi coding agent",
          loginMethod: "local",
          primary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Today",
            displayValue: (money($d.today.cost) + " · " + compact($d.today.tokens) + " tok")
          },
          secondary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Week",
            displayValue: (money($d.week.cost) + " · " + compact($d.week.tokens) + " tok")
          },
          tertiary: null,
          updatedAt: (now|todateiso8601)
        },
        credits: {remaining: "local analytics"}
      }
  ' "$cache_file" 2>/dev/null || json_note_usage pi pi-local "pi coding agent" "local" "Local session analytics — expand card for details" "~/.pi/agent/sessions"
}
