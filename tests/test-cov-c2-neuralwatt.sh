#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; a=("$@"); for ((i=0;i<${#a[@]};i++)); do [ "${a[$i]}" = -o ] && out="${a[$((i+1))]}"; done
case "$CASE" in ok) printf '%s' '{"balance":{"credits_remaining_usd":2,"total_credits_usd":10,"credits_used_usd":8},"subscription":{"plan":"Pro","status":"paused","kwh_included":10,"kwh_used":12,"in_overage":true,"billing_interval":"year"},"key":{"allowance":{"spent_usd":4,"limit_usd":5,"blocked":true,"period":"monthly"}},"snapshot_at":"snapshot"}' >"$out"; printf 200;;
  shape) printf '%s' '{"balance":null}' >"$out"; printf 200;;
  rate) printf '%s' '{}' >"$out"; printf 429;;
  error) printf '%s' '{"detail":"service down"}' >"$out"; printf 500;; esac
STUB
chmod +x "$TMP/bin/curl"; fail(){ echo "FAIL: $1" >&2; exit 1; }; run(){ CASE="$1" PATH="$TMP/bin:$PATH" NEURALWATT_API_KEY=sk-test "$ROOT/providers/get-provider-usage" neuralwatt 2>/dev/null; }
out="$(run ok)"; jq -e '.[0].usage.primary.usedPercent == 100 and .[0].usage.primary.windowMinutes == 525600 and (.[0].usage.accountEmail | contains("paused"))' <<<"$out" >/dev/null || fail success
out="$(run shape)"; jq -e '.[0].error.message | contains("unexpected payload")' <<<"$out" >/dev/null || fail shape
out="$(run rate)"; jq -e '.[0].error.message | contains("rate limited")' <<<"$out" >/dev/null || fail rate
out="$(run error)"; jq -e '.[0].error.message == "service down"' <<<"$out" >/dev/null || fail error-message
out="$(env -u NEURALWATT_API_KEY PATH="$TMP/bin:$PATH" "$ROOT/providers/get-provider-usage" neuralwatt 2>/dev/null)"; jq -e '.[0].error' <<<"$out" >/dev/null || fail missing-key
echo 'OK: test-cov-c2-neuralwatt'
