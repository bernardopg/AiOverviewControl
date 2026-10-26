# Sourced adapter; shared transport/normalization helpers live in get-provider-usage.
groq_rate_limit_probe() {
  # Groq has no usage or limits API: the x-ratelimit-* headers only come back on
  # a served completion (rejected requests carry none). With GROQ_QUOTA_MODEL
  # set, spend one 1-token completion on that model at most every
  # GROQ_QUOTA_TTL seconds (default 1800 = 48 requests/day) and cache the
  # headers. Prints the cached probe JSON, or nothing.
  local key="$1" model="$2"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/AiOverviewControl"
  local cache_file ttl now
  cache_file="$cache_dir/groq-rate-limits-$(printf '%s' "$model" | tr -c 'A-Za-z0-9._-' '_').json"
  ttl="${GROQ_QUOTA_TTL:-1800}"
  case "$ttl" in '' | *[!0-9]*) ttl=1800 ;; esac
  now="$(date +%s)"
  if [ -f "$cache_file" ] && jq -e --argjson now "$now" --argjson ttl "$ttl" \
      '($now - (.probedAt // 0)) < $ttl' "$cache_file" >/dev/null 2>&1; then
    cat "$cache_file"
    return 0
  fi

  local tmp_headers tmp_body http_status
  tmp_headers="$(mktemp)"
  tmp_body="$(mktemp)"
  http_status="$(jq -cn --arg model "$model" \
      '{model:$model, messages:[{role:"user", content:"."}], max_completion_tokens:1}' \
    | curl -sS --max-time 10 -D "$tmp_headers" -o "$tmp_body" -w '%{http_code}' \
      --config <(curl_header_config "Authorization: Bearer ${key}") -H "Content-Type: application/json" \
      --data-binary @- "https://api.groq.com/openai/v1/chat/completions" 2>/dev/null || true)"
  # Only a 200 or 429 reports the limits; anything else keeps the old cache.
  if [ "$http_status" = "200" ] || [ "$http_status" = "429" ]; then
    mkdir -p "$cache_dir"
    tr -d '\r' <"$tmp_headers" | jq -R -n --arg model "$model" --argjson now "$now" --arg status "$http_status" '
      [inputs | capture("^(?<k>(x-ratelimit-[a-z-]+|retry-after)):\\s*(?<v>.*)$"; "i")?
        | {key: (.k | ascii_downcase), value: .v}] | from_entries
      | {model: $model, probedAt: $now, status: ($status | tonumber), headers: .}
    ' >"$cache_file.tmp" && mv "$cache_file.tmp" "$cache_file"
  fi
  rm -f "$tmp_headers" "$tmp_body"
  [ -f "$cache_file" ] && cat "$cache_file"
  return 0
}

fetch_groq_native() {
  local key="${GROQ_API_KEY:-}"
  if [ -z "$key" ]; then
    json_error groq groq-api 2 provider "GROQ_API_KEY is not set. Groq has no public quota endpoint — set key to confirm auth."
    return 0
  fi
  local tmp_body http_status
  tmp_body="$(mktemp)"
  http_status="$(curl -sS --max-time 8 -o "$tmp_body" -w '%{http_code}' \
    --config <(curl_header_config "Authorization: Bearer ${key}") \
    -H "Accept: application/json" \
    "https://api.groq.com/openai/v1/models" 2>/dev/null || true)"
  if [ "$http_status" = "200" ]; then
    rm -f "$tmp_body"
    local model="${GROQ_QUOTA_MODEL:-}" probe=""
    [ -z "$model" ] || probe="$(groq_rate_limit_probe "$key" "$model")"
    if [ -n "$probe" ] && jq -e '.headers["x-ratelimit-limit-requests"]' <<<"$probe" >/dev/null 2>&1; then
      jq -c '
        def num($v): ($v // "0" | tonumber? // 0);
        # Go-style durations: "2m59.56s", "7.66s", "547ms", "1h2m3s".
        def seconds($d):
          ($d // "") as $s
          | if ($s | test("^[0-9.]+ms$")) then ($s | rtrimstr("ms") | tonumber) / 1000
            else [$s | scan("([0-9.]+)(h|m|s)") | (.[0] | tonumber) * (if .[1] == "h" then 3600 elif .[1] == "m" then 60 else 1 end)] | add // 0
            end;
        def pct($limit; $remaining): if num($limit) > 0 then ((num($limit) - num($remaining)) / num($limit) * 100) | if . < 0 then 0 elif . > 100 then 100 else . end else 0 end;
        .headers as $h
        | .probedAt as $at
        | (.status == 429) as $limited
        | {
            provider: "groq",
            source: "groq-ratelimit",
            usage: {
              identity: {providerID: "groq", accountEmail: ("Groq · " + .model), loginMethod: "api-key"},
              accountEmail: ("Groq · " + .model),
              loginMethod: "api-key",
              # Groq reports requests per day and tokens per minute in these headers.
              primary: {
                usedPercent: (if $limited and num($h["x-ratelimit-remaining-requests"]) == 0 then 100 else pct($h["x-ratelimit-limit-requests"]; $h["x-ratelimit-remaining-requests"]) end),
                windowMinutes: 1440,
                resetsAt: (($at + seconds($h["x-ratelimit-reset-requests"])) | floor | todateiso8601),
                resetDescription: "Requests per day",
                displayValue: ((num($h["x-ratelimit-limit-requests"]) - num($h["x-ratelimit-remaining-requests"]) | tostring) + " / " + (num($h["x-ratelimit-limit-requests"]) | tostring) + " requests")
              },
              secondary: {
                usedPercent: pct($h["x-ratelimit-limit-tokens"]; $h["x-ratelimit-remaining-tokens"]),
                windowMinutes: 1,
                resetsAt: (($at + seconds($h["x-ratelimit-reset-tokens"])) | floor | todateiso8601),
                resetDescription: "Tokens per minute",
                displayValue: ((num($h["x-ratelimit-limit-tokens"]) - num($h["x-ratelimit-remaining-tokens"]) | tostring) + " / " + (num($h["x-ratelimit-limit-tokens"]) | tostring) + " tokens")
              },
              tertiary: null,
              updatedAt: ($at | todateiso8601)
            },
            credits: {remaining: ((num($h["x-ratelimit-remaining-requests"]) | tostring) + " requests left")}
          }
      ' <<<"$probe"
      return 0
    fi
    json_note_usage groq groq-api "Groq account" "api-key" "Authenticated — usage at console.groq.com/dashboard/usage" "console.groq.com/dashboard/usage"
    return 0
  fi
  local message
  message="$(jq -r '.error.message // .message // empty' "$tmp_body" 2>/dev/null || true)"
  [ -n "$message" ] || message="Groq API key invalid (HTTP ${http_status:-0}). No public quota endpoint — check console.groq.com/dashboard/usage."
  rm -f "$tmp_body"
  json_error groq groq-api "${http_status:-1}" provider "$message"
}
