#!/usr/bin/env bash
# scripts/coverage-report counts shell statements only: the bodies of
# multi-line quoted programs, heredocs, backslash continuations and array
# assignments are not statements, nor are lines that run no command, and the
# --min gate fails below the threshold.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cat > "$TMP/sample.bash" <<'SAMPLE'
a=1
cat <<EOF
body $a
EOF
jq -n '
  .x
  | .y' file
c=3 \
  d
echo "it's #not a comment"
cat <<-'TABBED'
	inside
	TABBED
e=4
q="$(printf '%s' "
  WHERE a = 'b'
")"
echo "$q"
arr=(-H "a (b)"
  -H c)
case "$q" in
  a) ;;
  *) if true; then
      echo b
    fi ;;
esac
{
  echo c
} >"$TMP/out"
SAMPLE
# kcov marks every physical line; only lines 1, 2, 5, 8, 10, 11, 14, 17, 18,
# 19, 21, 23, 24 and 28 are statement starts. Lines 2 and 11 were not executed.
# Line 20 continues the array; lines 22, 25 and 29 run no command and are
# never traced.
jq -n --arg f "$TMP/sample.bash" --argjson h '{"1":1,"2":0,"3":0,"4":0,"5":1,"6":0,"7":0,"8":1,"9":0,"10":1,"11":0,"12":0,"13":0,"14":1,"15":0,"16":0,"17":1,"18":1,"19":1,"20":0,"21":1,"22":0,"23":1,"24":1,"25":0,"28":1,"29":0}' '{coverage: {($f): $h}}' > "$TMP/codecov.json"

out="$("$ROOT/scripts/coverage-report" "$TMP/codecov.json" "$TMP" --files "$TMP/files.tsv")"
[ "$out" = "Statement coverage: 85.71% (12/14 statements in 1 files)" ] || fail "statement grouping: $out"
[ "$(cat "$TMP/files.tsv")" = $'85.71%\t12/14\tsample.bash' ] || fail "wrong per-file row"

if "$ROOT/scripts/coverage-report" "$TMP/codecov.json" "$TMP" --min 90 >/dev/null 2>"$TMP/err"; then
  fail "accepted coverage below --min"
fi
grep -q 'below the 90% minimum' "$TMP/err" || fail "no minimum message"
"$ROOT/scripts/coverage-report" "$TMP/codecov.json" "$TMP" --min 80 >/dev/null || fail "rejected coverage above --min"

echo "OK: coverage-report statement counting and minimum gate"
