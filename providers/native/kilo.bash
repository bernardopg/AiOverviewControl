# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_kilo_native() {
  local key="${KILO_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error kilo kilo-gateway 2 provider "KILO_API_KEY is not set."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  # GET /api/gateway/models is OpenAI-compatible. The Kilo docs note it works
  # without auth, so a 200 is inconclusive — but a 401 reliably rejects a bad
  # key, which is the only zero-cost signal available without spending credits.
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://api.kilo.ai/api/gateway/models" 2>/dev/null || true)"
  if [ "$http_status" = "200" ]; then
    rm -f "$tmp_body"
    json_note_usage kilo kilo-gateway "Kilo account" "api-key" "Key accepted — balance at app.kilo.ai/credits" "app.kilo.ai/credits"
    return 0
  fi
  if [ "$http_status" = "401" ] || [ "$http_status" = "403" ]; then
    local message
    message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
    [ -n "$message" ] || message="Kilo API key invalid (HTTP ${http_status})."
    rm -f "$tmp_body"
    json_error kilo kilo-gateway "${http_status}" provider "$message"
    return 0
  fi
  rm -f "$tmp_body"
  json_note_usage kilo kilo-gateway "Kilo account" "api-key" "Key set; usage at app.kilo.ai/credits" "app.kilo.ai/credits"
}
