# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_nvidia_native() {
  local key="${NVIDIA_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error nvidia nvidia-nim 2 provider "NVIDIA_API_KEY is not set (prefix: nvapi-). NVIDIA NIM has no programmatic balance endpoint — set key to confirm auth."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Accept: application/json" \
    "https://integrate.api.nvidia.com/v1/models" 2>/dev/null || true)"
  rm -f "$tmp_body"
  if [ "$http_status" = "200" ]; then
    json_note_usage nvidia nvidia-nim "NVIDIA NIM account" "api-key" "API key set (the public models endpoint cannot validate it); credits at build.nvidia.com" "build.nvidia.com"
    return 0
  fi
  json_error nvidia nvidia-nim "${http_status:-1}" provider "NVIDIA NIM API key invalid (HTTP ${http_status:-0}). Credits visible at build.nvidia.com only."
}
