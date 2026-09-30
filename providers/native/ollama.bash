# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
fetch_ollama_native() {
  local base="${OLLAMA_HOST:-http://localhost:11434}"
  base="${base%/}"
  local tmp_body tmp_ps http_status
  tmp_body="$(mktemp)"
  tmp_ps="$(mktemp)"
  http_status="$(curl -sS --max-time 5 -o "$tmp_body" -w '%{http_code}' \
    "${base}/api/tags" 2>/dev/null || true)"
  if [ "$http_status" != "200" ]; then
    rm -f "$tmp_body" "$tmp_ps"
    json_error ollama ollama-local 2 provider "Ollama not running at ${base}. Start with: ollama serve"
    return 0
  fi
  curl -sS --max-time 5 -o "$tmp_ps" "${base}/api/ps" 2>/dev/null || printf '{"models":[]}' >"$tmp_ps"
  jq -cs --arg base "$base" '
    def num($v): ($v // 0 | tonumber? // 0);
    (.[0].models // []) as $models
    | (.[1].models // []) as $running
    | ($models | length) as $count
    | ($models | map(.name // "") | join(", ") | if . == "" then "No models loaded" else . end) as $model_list
    | ($running | map(.name // .model // "") | join(", ") | if . == "" then "No models running" else . end) as $running_list
    | {
        provider: "ollama",
        source: "ollama-local",
        usage: {
          identity: { providerID: "ollama", accountEmail: ($base), loginMethod: "local" },
          accountEmail: $base,
          loginMethod: "local",
          primary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: ("Local — " + ($count | tostring) + " model(s)"),
            displayValue: $model_list
          },
          secondary: {
            usedPercent: 0,
            windowMinutes: null,
            resetsAt: null,
            resetDescription: "Running now",
            displayValue: $running_list
          },
          tertiary: null,
          updatedAt: (now | todateiso8601)
        },
        credits: { remaining: "local" }
      }
  ' "$tmp_body" "$tmp_ps"
  rm -f "$tmp_body" "$tmp_ps"
}
