# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_ai21_native() {
  local key="${AI21_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error ai21 ai21-api 2 provider "AI21_API_KEY is not set."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.ai21.com/studio/v1/models" 2>/dev/null || true)"
  if [ "$http_status" = "200" ]; then
    rm -f "$tmp_body"
    json_note_usage ai21 ai21-api "AI21 account" "api-key" "Authenticated — no documented read-only usage endpoint" "studio.ai21.com"
    return 0
  fi
  local message
  message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
  [ -n "$message" ] || message="AI21 API key validation returned HTTP ${http_status:-0}."
  rm -f "$tmp_body"
  json_error ai21 ai21-api "${http_status:-1}" provider "$message"
}
