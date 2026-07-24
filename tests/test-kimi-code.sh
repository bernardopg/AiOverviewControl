#!/usr/bin/env bash
# Kimi Code (Coding Plan) subscription quota tracking — fake-curl unit test.
# Verifies key routing (sk-kimi- / KIMI_CODING_API_KEY -> coding, sk- -> balance)
# and that the coding /usages payload maps to weekly (primary) + 5h (secondary).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/curl" <<SH
#!/usr/bin/env bash
out=""; url=""; args=("\$@")
for ((i=0;i<\${#args[@]};i++)); do
  case "\${args[\$i]}" in
    -o) out="\${args[\$((i+1))]}";;
    http*) url="\${args[\$i]}";;
  esac
done
case "\$url" in
  *coding*) [ -n "\$out" ] && cp "$ROOT/tests/fixtures/kimi-code-usages.json" "\$out";;
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

# 2. sk-kimi- prefix on KIMI_API_KEY auto-routes to coding.
out="$(run env -u MOONSHOT_API_KEY -u KIMI_CODING_API_KEY KIMI_API_KEY=sk-kimi-auto)"
[ "$(jq -r '.[0].source' <<<"$out")" = "kimi-code" ] || fail "sk-kimi- prefix routing"

# 3. Open Platform key (sk-xxx) still reads the prepaid balance.
out="$(run env -u KIMI_API_KEY -u KIMI_CODING_API_KEY MOONSHOT_API_KEY=sk-openplat)"
[ "$(jq -r '.[0].source' <<<"$out")" = "kimi-api" ] || fail "open key -> balance"

echo "OK: test-kimi-code"
