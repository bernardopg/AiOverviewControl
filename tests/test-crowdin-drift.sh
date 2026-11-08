#!/usr/bin/env bash
# scripts/crowdin-drift compares a Crowdin export with the repository's
# translated bundles: identical bundles pass, and a changed, missing or
# unexpected translation is reported with its file and key. Offline.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
drift() { "$ROOT/scripts/crowdin-drift" "$@"; }

export_copy() { # a pristine "Crowdin export" of the repository
  rm -rf "$TMP/export"
  mkdir -p "$TMP/export"
  cp -r "$ROOT/i18n" "$ROOT/translations" "$TMP/export/"
}

# 1. An export identical to the repository passes.
export_copy
out="$(drift "$TMP/export")" || fail "identical export reported drift: $out"
grep -q '^Crowdin matches the repository (8 translated bundles)$' <<<"$out" || fail "summary: $out"

# 2. The English sources are never compared: Crowdin exports no copy of them.
rm "$TMP/export/i18n/en.json" "$TMP/export/translations/en.json"
drift "$TMP/export" >/dev/null || fail "missing English sources counted as drift"

# 3. A translation approved in Crowdin but not in the repository is reported
#    by file and key, and the run fails.
export_copy
jq '.["settings.health.ready"] = "Pronto!"' "$ROOT/i18n/pt_BR.json" > "$TMP/export/i18n/pt_BR.json"
if out="$(drift "$TMP/export" 2>"$TMP/err")"; then fail "changed translation not reported"; fi
grep -qF "i18n/pt_BR.json: settings.health.ready: repository 'Pronto', Crowdin 'Pronto!'" <<<"$out" || fail "changed key line: $out"
grep -qx '1 difference(s) between Crowdin and the repository' "$TMP/err" || fail "count: $(cat "$TMP/err")"

# 4. A nested dash-card term names its context and term.
export_copy
jq '.["AI quotas"]["AI quotas"] = "Cotas"' "$ROOT/translations/pt.json" > "$TMP/export/translations/pt.json"
out="$(drift "$TMP/export" 2>/dev/null)" && fail "changed dash term not reported"
grep -qF "translations/pt.json: AI quotas › AI quotas: repository 'Cotas de IA', Crowdin 'Cotas'" <<<"$out" || fail "nested line: $out"

# 5. A bundle the export lacks, and one only the export has, are both reported.
export_copy
rm "$TMP/export/i18n/de_DE.json"
printf '{}\n' > "$TMP/export/i18n/fr_FR.json"
out="$(drift "$TMP/export" 2>/dev/null)" && fail "missing/extra bundle not reported"
grep -qx 'i18n/de_DE.json: not in the Crowdin export' <<<"$out" || fail "missing bundle: $out"
grep -qx 'i18n/fr_FR.json: exported by Crowdin but not in the repository' <<<"$out" || fail "extra bundle: $out"

# 6. A reference other than the repository (the previous commit, in the sync
#    workflow) is compared instead of the working tree.
export_copy
cp -r "$TMP/export" "$TMP/reference"
jq '.["settings.health.ready"] = "Listo!"' "$ROOT/i18n/es_ES.json" > "$TMP/reference/i18n/es_ES.json"
cp "$TMP/reference/i18n/es_ES.json" "$TMP/export/i18n/es_ES.json"
drift "$TMP/export" "$TMP/reference" >/dev/null || fail "explicit reference root ignored"

# 7. Wrong usage exits 2 with the usage line.
if drift 2>"$TMP/err"; then fail "ran without an export root"; fi
grep -q '^Usage: scripts/crowdin-drift' "$TMP/err" || fail "usage: $(cat "$TMP/err")"

echo 'OK: crowdin-drift reports changed, missing and extra translations'
