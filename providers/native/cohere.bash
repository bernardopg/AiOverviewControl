# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_cohere_native() {
  local key="${COHERE_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error cohere cohere-api 2 provider "COHERE_API_KEY is not set."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.cohere.ai/v1/models?page_size=1" 2>/dev/null || true)"
  if [ "$http_status" != "200" ]; then
    local message
    message="$(jq -r '.message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Cohere models API returned HTTP ${http_status:-0}."
    rm -f "$tmp_body"
    json_error cohere cohere-api "${http_status:-1}" provider "$message"
    return 0
  fi
  rm -f "$tmp_body"
  json_note_usage cohere cohere-api "Cohere account" "api-key" "Authenticated; billing limits are managed in the Cohere dashboard" "dashboard.cohere.com/billing"
}
