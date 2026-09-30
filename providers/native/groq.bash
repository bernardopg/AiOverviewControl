# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_groq_native() {
  local key="${GROQ_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error groq groq-api 2 provider "GROQ_API_KEY is not set. Groq has no public quota endpoint — set key to confirm auth."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.groq.com/openai/v1/models" 2>/dev/null || true)"
  if [ "$http_status" = "200" ]; then
    rm -f "$tmp_body"
    json_note_usage groq groq-api "Groq account" "api-key" "Authenticated — usage at console.groq.com/dashboard/usage" "console.groq.com/dashboard/usage"
    return 0
  fi
  local message
  message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
  [ -n "$message" ] || message="Groq API key invalid (HTTP ${http_status:-0}). No public quota endpoint — check console.groq.com/dashboard/usage."
  rm -f "$tmp_body"
  json_error groq groq-api "${http_status:-1}" provider "$message"
}
