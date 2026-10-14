# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_nvidia_native() {
  local key="${NVIDIA_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error nvidia nvidia-nim 2 provider "NVIDIA_API_KEY is not set (prefix: nvapi-). NVIDIA NIM has no programmatic balance endpoint — set key to confirm auth."
    return 0
  fi
  # The public models catalog answers 200 to any key, so it cannot validate
  # one. NGC's caller-info endpoint (used by the official ngc CLI) rejects an
  # invalid nvapi- key with 401 and returns the key type and owner for a valid
  # one. The key goes in the form body on stdin, never in argv or the URL.
  # Credits and rate limits are still only visible at build.nvidia.com.
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(printf '%s' "$key" | curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    -X POST -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "credentials@-" \
    "https://api.ngc.nvidia.com/v3/keys/get-caller-info" 2>/dev/null || true)"

  if [ "$http_status" = "200" ] && jq -e 'type == "object"' "$tmp_body" >/dev/null 2>&1; then
    jq -c '
      def first_text($v): if ($v | type) == "array" then ($v[0] // null) else $v end;
      (first_text(.user) // {}) as $user
      | (if ($user | type) == "object" then ($user.email // $user.name // null) else null end) as $who
      | (first_text(.orgName) // null) as $org
      | (first_text(.type) // "") as $type
      | (if $type == "SERVICE_KEY" then "Service key"
         elif $type == "PERSONAL_KEY" then "Personal key"
         else "API key" end) as $kind
      | ($who // (if $org != null then "NVIDIA org " + ($org | tostring) else "NVIDIA NIM account" end)) as $identity
      | {
          provider: "nvidia",
          source: "nvidia-ngc",
          usage: {
            identity: {providerID: "nvidia", accountEmail: $identity, loginMethod: "api-key"},
            accountEmail: $identity,
            loginMethod: "api-key",
            primary: {
              usedPercent: 0,
              windowMinutes: null,
              resetsAt: null,
              resetDescription: ($kind + " verified; credits and rate limits at build.nvidia.com")
            },
            secondary: null,
            tertiary: null,
            updatedAt: (now | todateiso8601)
          },
          credits: {remaining: "build.nvidia.com"}
        }
    ' "$tmp_body"
    rm -f "$tmp_body"
    return 0
  fi
  rm -f "$tmp_body"

  if [ "$http_status" = "401" ] || [ "$http_status" = "403" ]; then
    json_error nvidia nvidia-ngc "$http_status" provider "NVIDIA API key invalid or revoked (HTTP ${http_status}). Create a new key at build.nvidia.com."
    return 0
  fi
  # Key service unreachable: keep the card usable instead of reporting an error
  # for a key that may well be valid.
  json_note_usage nvidia nvidia-nim "NVIDIA NIM account" "api-key" "API key set; NVIDIA key check unavailable (HTTP ${http_status:-0}); credits at build.nvidia.com" "build.nvidia.com"
}
