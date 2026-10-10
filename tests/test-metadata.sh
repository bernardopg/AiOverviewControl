#!/usr/bin/env bash
# Mutate an isolated metadata fixture: never touch the user's checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"/{scripts,i18n,tests,providers,docs,.github/workflows}
cp "$ROOT/scripts/check-metadata" "$ROOT/scripts/check-changelog" "$TMP/scripts/"
cp "$ROOT/plugin.json" "$ROOT/CHANGELOG.md" "$ROOT"/*.qml "$TMP/"
cp "$ROOT/docs/installation.md" "$TMP/docs/"
cp "$ROOT"/i18n/*.json "$TMP/i18n/"
printf '#!/bin/bash\n' > "$TMP/tests/test-example.sh"
printf '#!/bin/bash\n' > "$TMP/providers/get-example"
chmod +x "$TMP/tests/test-example.sh" "$TMP/providers/get-example"
printf 'jobs:\n  integration:\n    steps:\n      - run: tests/test-example.sh\n' > "$TMP/.github/workflows/ci.yml"
check() { bash "$TMP/scripts/check-metadata" >/dev/null 2>&1; }
reject() { if check; then echo "FAIL: accepted $1" >&2; exit 1; fi; }
check
cp "$TMP/docs/installation.md" "$TMP/docs/installation.backup"
python3 - "$TMP/docs/installation.md" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('./*.qml', 'AiOverviewControlWidget.qml'))
PY
reject 'checkout install missing root QML files'
mv "$TMP/docs/installation.backup" "$TMP/docs/installation.md"
cp "$TMP/docs/installation.md" "$TMP/docs/installation.backup"
python3 - "$TMP/docs/installation.md" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('providers scripts assets', 'providers assets'))
PY
reject 'checkout install missing scripts directory'
mv "$TMP/docs/installation.backup" "$TMP/docs/installation.md"
chmod -x "$TMP/tests/test-example.sh"
reject 'non-executable test'
chmod +x "$TMP/tests/test-example.sh"
printf '# tests/test-example.sh\n' > "$TMP/.github/workflows/ci.yml"
reject 'test mentioned only in a comment'
printf '      - name: tests/test-example.sh\n' > "$TMP/.github/workflows/ci.yml"
reject 'test mentioned only in a step name'
printf '      - run: |\n          setup\n          tests/test-example.sh\n' > "$TMP/.github/workflows/ci.yml"
check || { echo 'FAIL: rejected a test run inside a run block' >&2; exit 1; }
printf '      - run: |\n          setup\n      # tests/test-example.sh\n' > "$TMP/.github/workflows/ci.yml"
reject 'test in a comment after a run block'
printf 'run: tests/test-example.sh\n' > "$TMP/.github/workflows/ci.yml"
cp "$TMP/i18n/en.json" "$TMP/i18n/en.backup"
printf '{}\n' > "$TMP/i18n/en.json"
reject 'locale key mismatch'
mv "$TMP/i18n/en.backup" "$TMP/i18n/en.json"
printf '## 999.999.999\n' > "$TMP/CHANGELOG.md"
reject 'missing release heading'
cp "$ROOT/CHANGELOG.md" "$TMP/CHANGELOG.md"
python3 - "$TMP/plugin.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d['version'] = 'not-semver'
p.write_text(json.dumps(d))
PY
reject 'invalid semver'
echo 'OK: metadata success and rejection gates'
