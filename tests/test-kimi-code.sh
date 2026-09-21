#!/usr/bin/env bash
# Kimi Code (Coding Plan) subscription quota tracking — fake-curl unit test.
# Verifies key routing (sk-kimi- / KIMI_CODING_API_KEY -> coding, sk- -> balance)
# and that the coding /usages payload maps to weekly (primary) + 5h (secondary).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Sandbox the history writer so fixture-backed dispatcher runs never append
# snapshots to the developer's real usage-history.jsonl (see record_history
# in providers/get-provider-usage).
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$TMP/bin"

cat > "$TMP/bin/curl" <<SH
#!/usr/bin/env bash
out=""; url=""; accepts_json=0; args=("\$@")
for ((i=0;i<\${#args[@]};i++)); do
  case "\${args[\$i]}" in
    -o) out="\${args[\$((i+1))]}";;
    "Accept: application/json") accepts_json=1;;
    http*) url="\${args[\$i]}";;
  esac
done
case "\$url" in
  *coding*)
    [ "\$accepts_json" = 1 ] || { printf '400'; exit 0; }
    [ -n "\$out" ] && cp "$ROOT/tests/fixtures/\${KIMI_TEST_FIXTURE:-kimi-code-usages.json}" "\$out"
    ;;
  *balance*) [ -n "\$out" ] && echo '{"data":{"available_balance":12.5,"voucher_balance":2,"cash_balance":10.5}}' > "\$out";;
esac
printf '200'
SH
chmod +x "$TMP/bin/curl"

run() { PATH="$TMP/bin:$PATH" "$@" "$ROOT/providers/get-provider-usage" kimi 2>/dev/null; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Explicit coding key -> coding source, weekly primary (10080m), 5h secondary (300m).
#    Known windows leave resetDescription null so the widget localizes the label.
out="$(run env -u MOONSHOT_API_KEY -u KIMI_API_KEY KIMI_CODING_API_KEY=sk-kimi-test)"
[ "$(jq -r '.[0].source' <<<"$out")" = "kimi-code" ] || fail "coding key routing"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "10080" ] || fail "weekly minutes"
[ "$(jq -r '.[0].usage.primary.resetDescription' <<<"$out")" = "null" ] || fail "weekly label localized (null)"
[ "$(jq -r '.[0].usage.secondary.windowMinutes' <<<"$out")" = "300" ] || fail "5h minutes"
[ "$(jq -r '.[0].usage.primary.usedPercent|floor' <<<"$out")" = "75" ] || fail "weekly percent"

# 2. Newer Kimi Pro accounts return an exact 5h count plus ratio-based
#    monthly pools. Keep the exact count as a percentage (no displayValue, so
#    the widget shows percent + reset), expose the combined monthly pool, and
#    do not misrepresent its code breakdown as another allowance.
out="$(run env -u MOONSHOT_API_KEY -u KIMI_API_KEY KIMI_CODING_API_KEY=sk-kimi-pro KIMI_TEST_FIXTURE=kimi-code-pro-usages.json)"
[ "$(jq -r '.[0].usage.primary.windowMinutes' <<<"$out")" = "300" ] || fail "Pro 5h minutes"
[ "$(jq -r '.[0].usage.primary.displayValue' <<<"$out")" = "null" ] || fail "Pro 5h percent-only display"
[ "$(jq -r '.[0].usage.primary.usedPercent' <<<"$out")" = "0" ] || fail "Pro 5h percent"
[ "$(jq -r '.[0].usage.secondary.windowMinutes' <<<"$out")" = "43200" ] || fail "Pro monthly minutes"
[ "$(jq -r '.[0].usage.secondary.usedPercent' <<<"$out")" = "12" ] || fail "Pro monthly ratio"
[ "$(jq -r '.[0].usage.secondary.resetsAt' <<<"$out")" = "2026-11-01T00:00:00Z" ] || fail "Pro monthly reset"
[ "$(jq -r '.[0].usage.tertiary' <<<"$out")" = "null" ] || fail "Pro code-monthly is a breakdown, not a window"

# 3. The first-party KIMI_CODE_BASE_URL wins over the legacy plugin alias,
#    and coding requests explicitly accept JSON.
out="$(run env -u MOONSHOT_API_KEY -u KIMI_API_KEY KIMI_CODING_API_KEY=sk-kimi-global \
  KIMI_CODE_BASE_URL=https://api.kimi.ai/coding/v1 KIMI_BASE_URL=https://invalid.example/v1)"
[ "$(jq -r '.[0].source' <<<"$out")" = "kimi-code" ] || fail "first-party base URL override"

# 4. sk-kimi- prefix on KIMI_API_KEY auto-routes to coding.
out="$(run env -u MOONSHOT_API_KEY -u KIMI_CODING_API_KEY KIMI_API_KEY=sk-kimi-auto)"
[ "$(jq -r '.[0].source' <<<"$out")" = "kimi-code" ] || fail "sk-kimi- prefix routing"

# 5. Open Platform key (sk-xxx) still reads the prepaid balance.
out="$(run env -u KIMI_API_KEY -u KIMI_CODING_API_KEY MOONSHOT_API_KEY=sk-openplat)"
[ "$(jq -r '.[0].source' <<<"$out")" = "kimi-api" ] || fail "open key -> balance"

echo "OK: test-kimi-code"
