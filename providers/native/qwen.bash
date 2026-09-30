# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_qwen_native() {
  local key="${DASHSCOPE_API_KEY:-${QWEN_API_KEY:-}}"
  if [ -z "$key" ]; then
    json_error qwen dashscope-api 2 provider "DASHSCOPE_API_KEY or QWEN_API_KEY is not set. Alibaba DashScope has no programmatic quota endpoint."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  local -a headers=(-H "Authorization: Bearer ${key}" -H "Accept: application/json")
  if [ -n "${DASHSCOPE_WORKSPACE_ID:-}" ]; then
    headers+=(-H "X-DashScope-WorkSpace: ${DASHSCOPE_WORKSPACE_ID}")
  fi
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    "${headers[@]}" \
    "https://dashscope.aliyuncs.com/compatible-mode/v1/models" 2>/dev/null || true)"
  if [ "$http_status" = "200" ]; then
    rm -f "$tmp_body"
    json_note_usage qwen dashscope-api "DashScope account" "api-key" "Authenticated — quota at dashscope.console.aliyun.com" "dashscope.console.aliyun.com"
    return 0
  fi
  json_error qwen dashscope-api "${http_status:-1}" provider "DashScope API key invalid (HTTP ${http_status:-0}). Quota visible at dashscope.console.aliyun.com only."
}
