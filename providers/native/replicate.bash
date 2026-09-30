# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_replicate_native() {
  local token="${REPLICATE_API_TOKEN:-}"
  if [ -z "$token" ]; then
    json_error replicate replicate-api 2 provider "REPLICATE_API_TOKEN is not set."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    "https://api.replicate.com/v1/account" 2>/dev/null || true)"
  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.detail // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Replicate account API returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error replicate replicate-api "${http_status:-1}" provider "$message"
    return 0
  fi
  jq -c '
    . as $r
    | {
        provider: "replicate",
        source: "replicate-api",
        usage: {
          identity: { providerID: "replicate", accountEmail: ($r.username // $r.github_url // "Replicate account"), loginMethod: "api-token" },
          accountEmail: ($r.username // "Replicate account"),
          loginMethod: "api-token",
          primary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Account",
            displayValue: ("Authenticated as " + ($r.username // "account"))
          },
          secondary: null,
          tertiary: null,
          updatedAt: (now | todateiso8601)
        },
        credits: { remaining: "replicate.com/account/billing" }
      }
  ' "$tmp_body"
  rm -f "$tmp_body"
}
