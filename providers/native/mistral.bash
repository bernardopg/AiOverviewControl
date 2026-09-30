# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_mistral_native() {
  local key="${MISTRAL_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error mistral mistral-api 2 provider "MISTRAL_API_KEY is not set. Mistral has no programmatic usage endpoint — set key to confirm authentication only."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.mistral.ai/v1/models" 2>/dev/null || true)"
  if [ "$http_status" = "200" ]; then
    rm -f "$tmp_body"
    json_note_usage mistral mistral-api "Mistral account" "api-key" "Authenticated — usage at console.mistral.ai" "console.mistral.ai"
    return 0
  fi
  json_error mistral mistral-api "${http_status:-1}" provider "Mistral API key invalid (HTTP ${http_status:-0}). Mistral has no programmatic quota endpoint."
}
