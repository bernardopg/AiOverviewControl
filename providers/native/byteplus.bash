# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_byteplus_native() {
  local key="${BYTEPLUS_API_KEY:-${ARK_API_KEY:-}}"
  if [ -z "$key" ]; then
    json_error byteplus byteplus-ark 2 provider "BYTEPLUS_API_KEY or ARK_API_KEY is not set. BytePlus usage requires separate IAM AccessKey/SecretKey credentials."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://ark.ap-southeast.bytepluses.com/api/v3/models" 2>/dev/null || true)"
  if [ "$http_status" = "200" ]; then
    rm -f "$tmp_body"
    json_note_usage byteplus byteplus-ark "BytePlus ModelArk account" "api-key" "Authenticated — IAM-signed usage API is available separately; billing at console.byteplus.com" "console.byteplus.com"
    return 0
  fi
  local message
  message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
  [ -n "$message" ] || message="BytePlus ModelArk API key invalid (HTTP ${http_status:-0}). Usage requires IAM Signature V4 credentials; check console.byteplus.com."
  rm -f "$tmp_body"
  json_error byteplus byteplus-ark "${http_status:-1}" provider "$message"
}
