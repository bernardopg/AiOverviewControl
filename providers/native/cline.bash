# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
cline_api_token() {
  # CLINE_API_KEY (app.cline.bot -> Settings -> API Keys) wins. Otherwise reuse
  # the Cline CLI sign-in while its access token is still valid. The token is
  # never refreshed here: a refresh can rotate the refresh token, and this
  # plugin must not write into Cline's own data directory.
  if [ -n "${CLINE_API_KEY:-}" ]; then
    printf '%s' "$CLINE_API_KEY"
    return 0
  fi
  local providers_file="${CLINE_DATA_DIR:-$HOME/.cline/data}/settings/providers.json"
  [ -r "$providers_file" ] || return 0
  jq -r --argjson now "$(date +%s)" '
    .providers.cline.settings.auth as $a
    | if ($a.accessToken | type) == "string" and ($a.accessToken | length) > 0
         and (($a.expiresAt // 0) | tonumber? // 0) > ($now * 1000)
      then $a.accessToken else empty end
  ' "$providers_file" 2>/dev/null || true
}

cline_cli_signed_in() {
  local providers_file="${CLINE_DATA_DIR:-$HOME/.cline/data}/settings/providers.json"
  [ -r "$providers_file" ] && jq -e '(.providers.cline.settings.auth.accessToken | type) == "string"' "$providers_file" >/dev/null 2>&1
}

fetch_cline_native() {
  # Cline account API (https://docs.cline.bot/enterprise-solutions/api-reference),
  # the same calls the Cline CLI makes: /users/me, then the personal or active
  # organization balance and the current plan. Responses may be wrapped in a
  # {success, data} envelope. Balances are micro-USD (the CLI divides by 1e6).
  local token
  token="$(cline_api_token)"
  if [ -z "$token" ]; then
    if cline_cli_signed_in; then
      json_error cline cline-api 2 provider "Cline CLI sign-in expired. Run cline once to renew it, or set CLINE_API_KEY."
    else
      json_error cline cline-api 2 provider "Cline credentials are unavailable. Set CLINE_API_KEY or sign in with the Cline CLI."
    fi
    return 0
  fi

  local base="https://api.cline.bot/api/v1"
  local tmp_me tmp_balance tmp_plan http_status
  tmp_me="$(mktemp)"
  tmp_balance="$(mktemp)"
  tmp_plan="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_me" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" -H "Accept: application/json" \
    "$base/users/me" 2>/dev/null || true)"

  local user_id org_id
  user_id="$(jq -r '(if (.success | type) == "boolean" then .data else . end) | .id // empty' "$tmp_me" 2>/dev/null || true)"
  if [ "$http_status" != "200" ] || [ -z "$user_id" ]; then
    local message
    message="$(jq -r '.error // .message // empty | strings' "$tmp_me" 2>/dev/null || true)"
    case "$http_status" in
      401|403) message="Cline credentials were rejected (HTTP ${http_status}). Renew the CLI sign-in or check CLINE_API_KEY." ;;
      200) message="Cline account API returned an unexpected payload." ;;
      *) [ -n "$message" ] || message="Cline account API returned HTTP ${http_status:-0}." ;;
    esac
    rm -f "$tmp_me" "$tmp_balance" "$tmp_plan"
    json_error cline cline-api "${http_status:-1}" provider "$message"
    return 0
  fi

  # Organization accounts bill against the active organization's credits.
  org_id="$(jq -r '(if (.success | type) == "boolean" then .data else . end)
    | [.organizations[]? | select(.active == true) | .organizationId][0] // empty' "$tmp_me" 2>/dev/null || true)"
  local balance_path="users/${user_id}/balance"
  [ -z "$org_id" ] || balance_path="organizations/${org_id}/balance"
  http_status="$(curl -sS --max-time 8 -o "$tmp_balance" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" -H "Accept: application/json" \
    "$base/$balance_path" 2>/dev/null || true)"
  [ "$http_status" = "200" ] || printf '' >"$tmp_balance"
  # The plan is best-effort enrichment (ClinePass billing period).
  curl -sS --max-time 4 -o "$tmp_plan" \
    -H "Authorization: Bearer ${token}" -H "Accept: application/json" \
    "$base/users/me/plan" 2>/dev/null || printf '' >"$tmp_plan"
  # Keep --slurpfile below safe from HTML error pages.
  jq -e . "$tmp_balance" >/dev/null 2>&1 || printf '' >"$tmp_balance"
  jq -e . "$tmp_plan" >/dev/null 2>&1 || printf '' >"$tmp_plan"
  local login="oauth"
  [ -z "${CLINE_API_KEY:-}" ] || login="api-key"

  jq -cn --slurpfile me "$tmp_me" --slurpfile bal "$tmp_balance" --slurpfile plan "$tmp_plan" --arg org "$org_id" --arg login "$login" '
    def unwrap: if type == "object" and (.success | type) == "boolean" then .data else . end;
    def fix2: (. * 100 | round) as $c | ($c | fabs) as $a
      | (if $c < 0 then "-" else "" end)
        + (($a / 100 | floor) | tostring) + "."
        + (($a - ($a / 100 | floor) * 100) | tostring | if length == 1 then "0" + . else . end);
    ($me[0] | unwrap) as $user
    | (($bal[0] // null) | unwrap | .balance? // null | tonumber? // null) as $micro
    | (($plan[0] // null) | unwrap) as $p
    | (if ($p | type) == "object" then $p else null end) as $p
    | ($p.plan.displayName // $p.plan.name // null) as $plan_name
    | ($user.email // $user.displayName // "Cline account") as $identity
    | (if $micro == null then null else $micro / 1000000 end) as $usd
    | {
        provider: "cline",
        source: "cline-api",
        usage: {
          identity: {providerID: "cline", accountEmail: $identity, loginMethod: $login},
          accountEmail: $identity,
          loginMethod: $login,
          primary: {
            # Prepaid credits have no total, so only a depleted balance fills the bar.
            usedPercent: (if $usd == null then 0 elif $usd > 0 then 0 else 100 end),
            windowMinutes: null,
            resetsAt: null,
            resetDescription: (if $org != "" then "Credits · " + ([$user.organizations[]? | select(.active == true) | .name][0] // "Organization") else "Credits" end),
            displayValue: (if $usd == null then "Balance unavailable" else "$" + ($usd | fix2) end)
          },
          secondary: (if $plan_name != null then {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: ($p.currentPeriodEnd // null),
            resetDescription: "Plan",
            displayValue: $plan_name
          } else null end),
          tertiary: null,
          updatedAt: (now | todateiso8601)
        },
        credits: {remaining: (if $usd == null then "app.cline.bot" else "$" + ($usd | fix2) end)}
      }
  '
  rm -f "$tmp_me" "$tmp_balance" "$tmp_plan"
}
