# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_kimi_code_native() {
  # Kimi Code (Coding Plan) subscription quota — 5h burst window plus (per
  # plan) weekly and monthly pools, the same data the
  # Kimi CLI `/usage` command shows. Endpoint: GET .../usages (older
  # deployments answer on /usage; try both). Requires a Coding Plan key
  # (sk-kimi-xxx); an Open Platform key (sk-xxx) returns 401/404 here.
  local key="$1"
  # Kimi Code's CLI calls this KIMI_CODE_BASE_URL. Keep KIMI_BASE_URL as
  # a backwards-compatible alias for existing AiOverviewControl setups.
  local base="${KIMI_CODE_BASE_URL:-${KIMI_BASE_URL:-https://api.kimi.com/coding/v1}}"
  local tmp_body http_status url
  tmp_body="$(mktemp)"
  url="${base%/}/usages"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    -H "User-Agent: KimiCLI/1.6" \
    "$url" 2>/dev/null || true)"
  if [ "$http_status" = "404" ]; then
    url="${base%/}/usage"
    http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
      -H "Authorization: Bearer ${key}" \
      -H "Accept: application/json" \
      -H "User-Agent: KimiCLI/1.6" \
      "$url" 2>/dev/null || true)"
  fi
  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    if [ -z "$message" ]; then
      case "$http_status" in
        401|403) message="Kimi Code quota API rejected the key (HTTP ${http_status}). Use a Coding Plan key (sk-kimi-xxx) from the Kimi Code console, not an Open Platform sk-xxx key." ;;
        404)     message="Kimi Code quota endpoint not found (HTTP 404). Check KIMI_BASE_URL points at https://api.kimi.com/coding/v1." ;;
        *)       message="Kimi Code quota API returned HTTP ${http_status:-0}." ;;
      esac
    fi
    rm -f "$tmp_body"
    json_error kimi kimi-code "${http_status:-1}" provider "$message"
    return 0
  fi
  jq -c '
    def num($v): ($v // null | if . == null then null else (tonumber? // null) end);
    def as_iso($v):
      if $v == null then null
      elif ($v|type) == "number" then ($v | todateiso8601)
      else ($v | tostring) end;
    def build($o; $win; $hint):
      ( num($o.limit) // num($o.limit_amount) ) as $limit
      | ( num($o.used) // num($o.used_amount)
          // ( (num($o.remaining)) as $r
               | if ($r != null and $limit != null) then ($limit - $r) else null end ) ) as $used
      | ( $o.name // $o.title // $o.model_name // "Limit" ) as $rawlabel
      | ( ($hint // $rawlabel) | ascii_downcase ) as $ll
      | ( num($win.duration) ) as $wd
      | ( ($win.timeUnit // $win.time_unit // "" | ascii_upcase) ) as $tu
      | ( if $wd != null then
            ( if ($tu|test("MINUTE")) then $wd
              elif ($tu|test("HOUR")) then ($wd * 60)
              elif ($tu|test("DAY")) then ($wd * 1440)
              elif ($tu|test("MONTH")) then ($wd * 43200)
              else null end )
          else null end ) as $wmin_win
      | ( if $ll == "all" or ($ll|test("week|weekly")) then {m:10080,d:"Weekly",r:0}
          elif ($ll|test("5h|5 ?hour|5-hour|five")) then {m:300,d:"5h",r:1}
          elif ($ll|test("month")) then {m:43200,d:"Monthly",r:2}
          else {m:null,d:$rawlabel,r:3} end ) as $wl
      | ( $wmin_win // $wl.m ) as $wmin
      | ( if $wmin == 10080 then "Weekly" elif $wmin == 300 then "5h" elif $wmin == 43200 then "Monthly" else $wl.d end ) as $desc
      | ( if $wmin == 10080 then 0 elif $wmin == 300 then 1 elif $wmin == 43200 then 2 else $wl.r end ) as $rank
      | if ($used == null and $limit == null) then null else
          { usedPercent: (if ($limit != null and $limit > 0) then (($used // 0) / $limit * 100) else 0 end),
            windowMinutes: $wmin,
            resetsAt: ( as_iso($o.resetTime // $o.reset_at // $o.reset_time)
                        // ( num($o.reset_in) as $ri | if $ri != null then (($ri + now) | todateiso8601) else null end ) ),
            # Emit a raw label only for unrecognized windows; known windows carry
            # windowMinutes so the widget localizes them via getWindowLabel().
            resetDescription: (if $wmin == null then $desc else null end),
            # No displayValue: formatUsageLine() in the widget prefers it
            # over the percentage, which would hide both the percent and the
            # reset countdown behind a raw "used / limit" count.
            displayValue: null,
            _rank: $rank,
            _min: ($wmin // 999999) }
        end;
    # Current Kimi Code plans also emit ratio pools under `usages`. The
    # first-party CLI renders limit_5h and limit_7d as windows and
    # limit_month_total as one monthly window. limit_month_code is only the
    # code share used to break down that monthly total; it is not an
    # independent allowance and must not become a second monthly window.
    def ratio_build($entry; $wmin; $rank; $label):
      (num($entry.used_ratio) // num($entry.usedRatio)) as $ratio
      | if ($ratio == null or $ratio < 0 or $ratio > 1) then null else
          { usedPercent: ($ratio * 100),
            windowMinutes: $wmin,
            resetsAt: as_iso($entry.reset_time // $entry.resetTime),
            resetDescription: $label,
            displayValue: null,
            _rank: $rank,
            _min: $wmin }
        end;
    . as $payload
    | ( if (.data | type) == "array" then
        [ .data[] | select(type == "object")
          | build(.; {}; (if .model_name == "all" then "all" else null end)) ]
      else
        ( [ if (.usage | type) == "object" then (.usage | build(.; {}; "all")) else empty end ]
          + [ (.limits // [])[] | select(type == "object")
              | (if (.detail | type) == "object" then .detail else . end) as $d
              | (if (.window | type) == "object" then .window else {} end) as $w
              | build($d; $w; null) ] )
      end ) | map(select(. != null)) as $legacy_rows
    | ($payload.usages // {}) as $ratio_pools
    | ( $legacy_rows
        + [ if ($legacy_rows | any(.windowMinutes == 300)) then empty
            else ratio_build($ratio_pools.limit_5h; 300; 1; null) end,
            if ($legacy_rows | any(.windowMinutes == 10080)) then empty
            else ratio_build($ratio_pools.limit_7d; 10080; 0; null) end,
            if ($legacy_rows | any(.windowMinutes == 43200)) then empty
            else ratio_build($ratio_pools.limit_month_total; 43200; 2; null) end ]
      ) | map(select(. != null)) as $rows
    | ($rows | sort_by([._rank, ._min])) as $sorted
    | ( def clean($w): if $w == null then null else ($w | del(._rank, ._min)) end;
        { provider: "kimi",
          source: "kimi-code",
          usage: {
            identity: { providerID: "kimi", accountEmail: "Kimi Code account", loginMethod: "coding-plan" },
            accountEmail: "Kimi Code account",
            loginMethod: "coding-plan",
            primary:   clean($sorted[0]),
            secondary: clean($sorted[1]),
            tertiary:  clean($sorted[2]),
            updatedAt: (now | todateiso8601)
          },
          credits: {
            remaining: (if ($sorted[0] and $sorted[0].displayValue) then $sorted[0].displayValue else "Kimi Code subscription" end)
          }
        } )
  ' "$tmp_body"
  rm -f "$tmp_body"
}
