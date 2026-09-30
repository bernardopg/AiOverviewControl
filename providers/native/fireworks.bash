# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_fireworks_native() {
  local key="${FIREWORKS_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error fireworks fireworks-api 2 provider "FIREWORKS_API_KEY is not set."
    return 0
  fi
  local tmp_body http_status account_id
  account_id="${FIREWORKS_ACCOUNT_ID:-}"
  if [ -n "$account_id" ]; then
    tmp_body="$(mktemp)"
    http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
      -H "Authorization: Bearer ${key}" \
      -H "Accept: application/json" \
      "https://api.fireworks.ai/v1/accounts/${account_id}/quotas?pageSize=200" 2>/dev/null || true)"
    if [ "$http_status" = "200" ] && jq -e '(.quotas // []) | type == "array"' "$tmp_body" >/dev/null 2>&1; then
      jq -c --arg account "$account_id" '
        def num($v): ($v // 0 | tonumber? // 0);
        def pct($used; $limit): if num($limit) > 0 then ((num($used) / num($limit)) * 100 | if . > 100 then 100 elif . < 0 then 0 else . end) else 0 end;
        def window($quota): if $quota == null then null else {usedPercent:pct($quota.usage; $quota.value), windowMinutes:null, resetsAt:null, resetDescription:$quota.name, displayValue:(($quota.usage | tostring) + " / " + ($quota.value | tostring) + " (max " + ($quota.max | tostring) + ")")} end;
        [(.quotas // [])[] | {name:(.name // "quota" | split("/") | last), usage:num(.usage), value:num(.value), max:num(.maxValue), update:(.updateTime // null)}]
        | sort_by(-pct(.usage; .value)) as $quotas
        | {
            provider:"fireworks", source:"fireworks-quotas",
            usage:{identity:{providerID:"fireworks", accountEmail:("Fireworks account " + $account), loginMethod:"api-key"}, accountEmail:("Fireworks account " + $account), loginMethod:"api-key", primary:window($quotas[0]), secondary:window($quotas[1]), tertiary:window($quotas[2]), updatedAt:(now | todateiso8601)},
            credits:{remaining:(if ($quotas | length) == 0 then "No quotas returned" else (($quotas[0].usage | tostring) + " / " + ($quotas[0].value | tostring)) end)}
          }
      ' "$tmp_body"
      rm -f "$tmp_body"
      return 0
    fi
    if [ "$http_status" = "401" ] || [ "$http_status" = "403" ]; then
      local quota_message
      quota_message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
      [ -n "$quota_message" ] || quota_message="Fireworks quota API authorization failed (HTTP ${http_status})."
      rm -f "$tmp_body"
      json_error fireworks fireworks-quotas "$http_status" provider "$quota_message"
      return 0
    fi
    rm -f "$tmp_body"
  fi
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    "https://api.fireworks.ai/inference/v1/models" 2>/dev/null || true)"
  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Fireworks AI models API returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error fireworks fireworks-api "${http_status:-1}" provider "$message"
    return 0
  fi
  rm -f "$tmp_body"
  if [ -n "$account_id" ]; then
    json_note_usage fireworks fireworks-api "Fireworks AI account ${account_id}" "api-key" "Authenticated; quota API is temporarily unavailable, billing is available in the Fireworks console" "app.fireworks.ai"
  else
    json_note_usage fireworks fireworks-api "Fireworks AI account" "api-key" "Authenticated — set FIREWORKS_ACCOUNT_ID to display documented account quotas" "app.fireworks.ai"
  fi
}
