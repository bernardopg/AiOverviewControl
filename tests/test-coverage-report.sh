#!/usr/bin/env bash
# scripts/coverage-report counts shell statements only: the bodies of
# multi-line quoted programs, heredocs and backslash continuations are not
# statements, and the --min gate fails below the threshold.
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
SAMPLE
# kcov marks every physical line; only lines 1, 2, 5, 8, 10, 11 and 14 are
# statement starts. Lines 2 and 11 were not executed.
jq -n --arg f "$TMP/sample.bash" --argjson h '{"1":1,"2":0,"3":0,"4":0,"5":1,"6":0,"7":0,"8":1,"9":0,"10":1,"11":0,"12":0,"13":0,"14":1,"15":0,"16":0,"17":1,"18":1}' '{coverage: {($f): $h}}' > "$TMP/codecov.json"

out="$("$ROOT/scripts/coverage-report" "$TMP/codecov.json" "$TMP" --files "$TMP/files.tsv")"
[ "$out" = "Statement coverage: 77.78% (7/9 statements in 1 files)" ] || fail "multiline quote was not covered by its closing line: $out"
[ "$(cat "$TMP/files.tsv")" = $'77.78%\t7/9\tsample.bash' ] || fail "wrong per-file row"

if "$ROOT/scripts/coverage-report" "$TMP/codecov.json" "$TMP" --min 80 >/dev/null 2>"$TMP/err"; then
  fail "accepted coverage below --min"
fi
grep -q 'below the 80% minimum' "$TMP/err" || fail "no minimum message"
"$ROOT/scripts/coverage-report" "$TMP/codecov.json" "$TMP" --min 70 >/dev/null || fail "rejected coverage above --min"

echo "OK: coverage-report statement counting and minimum gate"
