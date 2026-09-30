#!/usr/bin/env bash
# Exercise the executable changelog contract in an isolated Git repository.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts"
cp "$ROOT/scripts/check-changelog" "$TMP/scripts/"
printf '{"version":"1.0.0"}\n' > "$TMP/plugin.json"
printf '# Changes\n\n## Unreleased\n\n## 1.0.0 - 2026-09-30\n\n- Initial working release.\n' > "$TMP/CHANGELOG.md"
git -C "$TMP" init -q
git -C "$TMP" add .
git -C "$TMP" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm baseline
check() { python3 "$TMP/scripts/check-changelog" "$@"; }
reject() {
    local label="$1"; shift
    if check "$@" >"$TMP/output" 2>&1; then
        echo "FAIL: accepted $label" >&2; exit 1
    fi
}
check >/dev/null
reject 'PR with unchanged notes' --base HEAD
for content in '' '### Fixed' '<!-- - Invisible change. -->' '- TBD' '- ' $'```\n- Not a release note.\n```'; do
    printf '## Unreleased\n\n## 1.0.0\n\n%s\n' "$content" > "$TMP/CHANGELOG.md"
    reject 'empty/comment/placeholder-only release'
done
printf '## 1.0.0\n- One change.\n## [1.0.0]\n- Another change.\n' > "$TMP/CHANGELOG.md"
reject 'duplicate version sections'
printf '## Unreleased\n- Fix the provider gesture.\n## [1.0.0] - 2026-09-30\n- Initial working release.\n' > "$TMP/CHANGELOG.md"
check --base HEAD >/dev/null
printf '## Unreleased\n\n## 1.1.0 - 2026-09-30\n- See [currency](./docs/currency.md) and [usage](docs/usage.md).\n- Keep [external](https://example.invalid/x) and [anchor](#section).\n\n## 1.0.0\n- Initial working release.\n' > "$TMP/CHANGELOG.md"
printf '{"version":"1.1.0"}\n' > "$TMP/plugin.json"
check --base HEAD >/dev/null
check --notes --repository example/plugin --tag v1.1.0 > "$TMP/notes"
python3 - "$TMP/notes" <<'PY'
from pathlib import Path
import sys
notes = Path(sys.argv[1]).read_text()
# Emitted Markdown is the release-body protocol, not implementation source.
assert 'https://github.com/example/plugin/blob/v1.1.0/docs/currency.md' in notes
assert 'https://github.com/example/plugin/blob/v1.1.0/docs/usage.md' in notes
assert 'https://example.invalid/x' in notes and '](#section)' in notes
assert 'Initial working release.' not in notes
PY
reject 'tag/manifest mismatch' --tag v1.0.0
printf '{"version":"0.9.0"}\n' > "$TMP/plugin.json"
printf '## Unreleased\n## 0.9.0\n- Downgrade release.\n' > "$TMP/CHANGELOG.md"
reject 'version rollback' --base HEAD
printf 'OK: release/PR changelog rejection, exact extraction, version advance and immutable links\n'
