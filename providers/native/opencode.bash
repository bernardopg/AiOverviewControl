# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_opencode_native() {
  local local_db="${OPENCODE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode}/opencode.db"
  if [ -f "$local_db" ] && [ "${OPENCODE_USAGE_SOURCE:-local}" != api ]; then
    local stats
    stats="$(bash "$SCRIPT_DIR/get-local-analytics" opencode)"
    if ! printf '%s' "$stats" | jq -e 'has("today") and (has("error") | not)' >/dev/null; then
      json_error opencode opencode-local 1 provider "OpenCode local database could not be read."
      return 0
    fi
    printf '%s' "$stats" | jq -c '
      def compact($v):
        (($v // 0)) as $n
        | if $n >= 1000000000 then (((($n / 100000000) | round) / 10) | tostring) + "B"
          elif $n >= 1000000 then (((($n / 100000) | round) / 10) | tostring) + "M"
          elif $n >= 1000 then (((($n / 100) | round) / 10) | tostring) + "K"
          else (($n | round) | tostring)
          end;
      # A window whose cost is unknown shows tokens alone rather than an
      # invented $0 — most local runs are free-tier or third-party models.
      def money($v):
        if $v == null then null
        elif $v > 0 and $v < 0.01 then "<$0.01"
        else ("$" + (($v * 100 | round) / 100 | tostring)) end;
      def window($w; $label):
        {usedPercent:0, windowMinutes:null, resetsAt:null, resetDescription:$label,
         displayValue: ((money($w.cost) | if . == null then "" else . + " \u00b7 " end)
           + compact($w.tokens) + " tok")};
      . as $d | {
        provider:"opencode", source:"opencode-local",
        usage:{identity:{providerID:"opencode", accountEmail:"OpenCode", loginMethod:"local"},
          accountEmail:"OpenCode", loginMethod:"local",
          primary: window($d.today; "Today"),
          secondary: window($d.week; "Week"),
          updatedAt:(now | todateiso8601)},
        credits:{remaining:"Local harness telemetry"}}
    '
    return 0
  fi
  # OpenCode Go (opencode.ai) — coding-agent subscription quota via OpenCode
  # Zen. /zen/go/v1/usage returns percent-already-computed 5h/weekly/monthly
  # windows. The endpoint is young (opencode PR #16513), so on failure we
  # degrade to /zen/go/v1/models (auth-only check), matching the Command Code
  # adapter's fallback shape.
  local key
  key="$(opencode_api_key)"
  if [ -z "$key" ]; then
    json_error opencode opencode-api 2 provider "OpenCode credentials are unavailable. Set OPENCODE_API_KEY or run 'opencode auth login' so ~/.local/share/opencode/auth.json has a key."
    return 0
  fi

  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://opencode.ai/zen/go/v1/usage" 2>/dev/null || true)"

  if [ "$http_status" = "401" ] || [ "$http_status" = "403" ]; then
    local message
    message="$(jq -r '.error.message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="OpenCode API key invalid (HTTP ${http_status})."
    rm -f "$tmp_body"
    json_error opencode opencode-api "${http_status}" provider "$message"
    return 0
  fi

  if [ "$http_status" = "200" ] && jq -e '
    def valid_window:
      type == "object"
      and (.usagePercent | type == "number" and . >= 0 and . <= 100)
      and (.resetInSec | type == "number" and . >= 0);
    (.rollingUsage | valid_window)
    and (.weeklyUsage | valid_window)
    and (.monthlyUsage | valid_window)
  ' "$tmp_body" >/dev/null 2>&1; then
    jq -c '
      def make_window($w; $minutes; $label): {
        usedPercent: $w.usagePercent,
        windowMinutes: $minutes,
        resetsAt: ((now + $w.resetInSec) | todate),
        resetDescription: $label
      };
      . as $body |
      {
        provider: "opencode",
        source: "opencode-usage",
        usage: {
          identity: {providerID: "opencode", accountEmail: "OpenCode Go account", loginMethod: "api-key"},
          accountEmail: "OpenCode Go account",
          loginMethod: "api-key",
          primary:   make_window($body.rollingUsage; 300;   "5h"),
          secondary: make_window($body.weeklyUsage;  10080; "weekly"),
          tertiary:  make_window($body.monthlyUsage; 43200; "monthly"),
          updatedAt: (now | todate)
        },
        credits: {
          remaining: (if $body.useBalance == true
                      then "OpenCode Go · balance fallback enabled"
                      else "OpenCode Go"
                      end)
        }
      }
    ' "$tmp_body"
    rm -f "$tmp_body"
    return 0
  fi

  # /zen/go/v1/usage failed (timeout, 5xx, parse error). Try the documented
  # /zen/go/v1/models endpoint — auth-only confirmation that the key works.
  rm -f "$tmp_body"
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://opencode.ai/zen/go/v1/models" || true)"
  rm -f "$tmp_body"

  if [ "$http_status" = "200" ]; then
    json_note_usage opencode opencode-models "OpenCode Go account" "api-key" \
      "Authenticated — quota endpoint unavailable, usage at opencode.ai/zen" \
      "OpenCode Go"
    return 0
  fi
  json_note_usage opencode opencode-api "OpenCode Go account" "api-key" \
    "API key set; OpenCode Zen unreachable" \
    "OpenCode Go"
}
