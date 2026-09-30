# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_together_native() {
  local key="${TOGETHER_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error together together-api 2 provider "TOGETHER_API_KEY is not set."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    "https://api.together.xyz/v1/models" 2>/dev/null || true)"
  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Together AI models API returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error together together-api "${http_status:-1}" provider "$message"
    return 0
  fi
  rm -f "$tmp_body"
  json_note_usage together together-api "Together AI account" "api-key" "Authenticated — Together AI does not document a read-only credits endpoint; billing is available in the console" "api.together.ai/settings/billing"
}
