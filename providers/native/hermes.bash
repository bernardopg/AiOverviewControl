# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_hermes_native() {
  local hermes_home="${HERMES_HOME:-$HOME/.hermes}"
  local state_db="$hermes_home/state.db"
  if [ ! -f "$state_db" ]; then
    json_error hermes hermes-local 2 provider "hermes state database not found (~/.hermes/state.db)."
    return 0
  fi
  if ! command -v sqlite3 >/dev/null 2>&1; then
    json_error hermes hermes-local 127 runtime "sqlite3 is required to read hermes state."
    return 0
  fi

  # shellcheck source=providers/local-cost-common
  source "$SCRIPT_DIR/local-cost-common"
  local usage_columns price_file
  usage_columns="$(hermes_usage_columns "$state_db")"
  price_file="$(hermes_price_file)"
  local today_key week_epoch today_row week_row
  today_key=$(date +%Y-%m-%d)
  week_epoch=$(date -d '6 days ago 00:00' +%s 2>/dev/null || date -v-6d +%s 2>/dev/null || echo 0)
  # Today vs trailing-7-day per-model rows straight from the usage ledger
  # (hermes_usage_columns; unpriced rows are priced in jq below). Both windows
  # bucket by session start day, matching get-hermes-analytics.
  # A failed query (locked, corrupt, or a schema without the usage ledger) must
  # surface as a provider error — reporting zeros would render a healthy-looking
  # card that silently hides a broken database.
  if ! today_row="$(sqlite3 -readonly -separator $'\t' "$state_db" "
    SELECT $usage_columns
    FROM session_model_usage u
    JOIN sessions s ON s.id = u.session_id
    WHERE date(s.started_at, 'unixepoch', 'localtime') = '$today_key'
    GROUP BY u.model;
  " 2>/dev/null)"; then
    json_error hermes hermes-local 1 provider \
      "hermes state database could not be read (locked, corrupt, or unsupported schema)."
    return 0
  fi
  if ! week_row="$(sqlite3 -readonly -separator $'\t' "$state_db" "
    SELECT $usage_columns
    FROM session_model_usage u
    JOIN sessions s ON s.id = u.session_id
    WHERE CAST(s.started_at AS INTEGER) >= CAST('$week_epoch' AS INTEGER)
    GROUP BY u.model;
  " 2>/dev/null)"; then
    json_error hermes hermes-local 1 provider \
      "hermes state database could not be read (locked, corrupt, or unsupported schema)."
    return 0
  fi
  local default_model="" model_provider="" active_provider="" sessions_total=0
  if [ -f "$hermes_home/config.yaml" ]; then
    default_model=$(awk '/^model:/{f=1; next} f && /^[^ \t]/{f=0} f && /^[ \t]+default:/{sub(/^[ \t]+default:[ \t]*/, ""); gsub(/["'"'"']/, ""); print; exit}' "$hermes_home/config.yaml" 2>/dev/null)
    model_provider=$(awk '/^model:/{f=1; next} f && /^[^ \t]/{f=0} f && /^[ \t]+provider:/{sub(/^[ \t]+provider:[ \t]*/, ""); gsub(/["'"'"']/, ""); print; exit}' "$hermes_home/config.yaml" 2>/dev/null)
  fi
  [ -f "$hermes_home/auth.json" ] \
    && active_provider=$(jq -r '.active_provider // ""' "$hermes_home/auth.json" 2>/dev/null)
  sessions_total=$(sqlite3 -readonly "$state_db" "SELECT COUNT(*) FROM sessions;" 2>/dev/null | head -n 1)
  case "$sessions_total" in ''|*[!0-9]*) sessions_total=0 ;; esac

  # Account label shows both natures: routing provider + configured model.
  local account="$active_provider"
  [ -n "$default_model" ] && account="${account:+$account · }$default_model"
  [ -n "$account" ] || account="hermes agent"

  jq -cn \
    --arg account "$account" \
    --arg model_provider "$model_provider" \
    --argjson sessions_total "$sessions_total" \
    --arg today "$today_row" \
    --arg week "$week_row" \
    --slurpfile prices "${price_file:-/dev/null}" \
    "$HERMES_PRICE_JQ"'
    # Window totals: tokens summed; cost null when any model stays unpriced.
    def window($s):
      [$s | split("\n")[] | select(length > 0) | split("\t") | hermes_row(0; $prices[0].models // {})]
      | {tokens: (map(.tokens) | add // 0),
         cost: (if any(.[]; .cost == null) then null else (map(.cost) | add // 0) end)};
    def money($v): if $v == null then "—" elif $v > 0 and $v < 0.01 then "<$0.01" else ("$" + ((($v * 100) | round) / 100 | tostring)) end;
    def compact($v):
      (($v // 0)) as $n
      | if $n >= 1000000000 then (((($n / 100000000) | round) / 10) | tostring) + "B"
        elif $n >= 1000000 then (((($n / 100000) | round) / 10) | tostring) + "M"
        elif $n >= 1000 then (((($n / 100) | round) / 10) | tostring) + "K"
        else (($n | round) | tostring)
        end;
    {
      provider: "hermes",
      source: "hermes-local",
      usage: {
        identity: {providerID: "hermes", accountEmail: $account, loginMethod: ($model_provider | if . == "" then "local" else . end)},
        accountEmail: $account,
        loginMethod: ($model_provider | if . == "" then "local" else . end),
        primary: {
          usedPercent: 0,
          windowMinutes: null,
          resetsAt: null,
          resetDescription: "Today",
          displayValue: (window($today) | money(.cost) + " · " + compact(.tokens) + " tok")
        },
        secondary: {
          usedPercent: 0,
          windowMinutes: null,
          resetsAt: null,
          resetDescription: "Week",
          displayValue: (window($week) | money(.cost) + " · " + compact(.tokens) + " tok")
        },
        tertiary: null,
        updatedAt: (now | todateiso8601)
      },
      credits: {remaining: ("agent · " + ($sessions_total | tostring) + " sessions")}
    }'
}
