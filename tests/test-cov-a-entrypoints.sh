#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Isolate every cache and config path so no real credential or history is read.
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$TMP/bin" "$HOME"

cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '{"error":"offline fixture"}'
SH
chmod +x "$TMP/bin/curl"

# Copy each thin adapter beside a recording wrapper so the test never reads
# credentials, caches, or databases from the invoking user's home directory.
for stub in "$ROOT"/providers/get-*-usage; do
  grep -q 'get-provider-wrapper' "$stub" || continue
  id="${stub##*/get-}"
  id="${id%-usage}"
  stub_dir="$TMP/$id"
  mkdir -p "$stub_dir"
  cp "$stub" "$stub_dir/$(basename "$stub")"
  cat >"$stub_dir/get-provider-wrapper" <<'SH'
#!/usr/bin/env bash
jq -cn --arg provider "${1:?}" '{provider:$provider}'
SH
  chmod +x "$stub_dir/get-provider-wrapper"
  output="$(bash "$stub_dir/$(basename "$stub")")"
  jq -e --arg id "$id" '.provider == $id' <<<"$output" >/dev/null
done

# Wrapper validates its required argument before invoking the dispatcher.
if "$ROOT/providers/get-provider-wrapper" >/dev/null 2>&1; then
  echo 'wrapper accepted a missing provider id' >&2
  exit 1
fi

# Dispatcher returns an error envelope for an unknown provider, rejects an
# invalid profile before touching credentials, and handles informational
# providers and multi-provider output without network or local data access.
unknown="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-provider-usage" 'not-a-provider')"
jq -e '.[0].provider == "not-a-provider" and .[0].error.kind == "provider"' <<<"$unknown" >/dev/null
profile="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-provider-usage" 'claude-invalid-profile')"
jq -e '.[0].provider == "claude-invalid-profile" and .[0].error.kind == "configuration"' <<<"$profile" >/dev/null
info="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-provider-usage" 'perplexity,amp')"
jq -e 'length == 2 and .[0].provider == "perplexity" and .[1].provider == "amp"' <<<"$info" >/dev/null
normalized="$(PATH="$TMP/bin:$PATH" bash "$ROOT/providers/get-provider-usage" '  PERPLEXITY , AMP  , , KIMI-CODE')"
jq -e 'length == 3 and .[0].provider == "perplexity" and .[1].provider == "amp" and .[2].provider == "kimi-code" and .[2].error.kind == "provider"' <<<"$normalized" >/dev/null

