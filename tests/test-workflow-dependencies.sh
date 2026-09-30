#!/usr/bin/env bash
# Offline supply-chain contract, not a claim about future upstream releases.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import re
from pathlib import Path

def unpinned(source):
    result = []
    for match in re.finditer(r'^\s*(?:-\s*)?uses:\s*(\S+)', source, re.M):
        action = match.group(1)
        if action.startswith('./'):
            continue
        if not re.fullmatch(r'[^@\s]+@[a-f0-9]{40}', action):
            result.append(action)
    return result

assert unpinned('    - uses: actions/checkout@v4\n') == ['actions/checkout@v4']
assert not unpinned('    - uses: actions/checkout@' + 'a' * 40 + ' # v7.0.1\n')
assert not unpinned('    uses: ./.github/workflows/ci.yml\n')
assert unpinned('    uses: owner/repo/workflow.yml@main\n')
errors = []
for file in Path('.github/workflows').glob('*.yml'):
    errors.extend(f'{file}: mutable external reference {x}' for x in unpinned(file.read_text()))
source = Path('.github/workflows/ci.yml').read_text()
for name in ('ACTIONLINT', 'SHELLCHECK', 'CROWDIN_CLI'):
    if not re.search(r'^\s+' + name + r'_SHA256: "[a-f0-9]{64}"$', source, re.M):
        errors.append(f'{name}: missing artifact checksum')
if 'crowdin-linux-x64' not in source or 'steps.crowdin_cli.outputs.binary' not in source:
    errors.append('Crowdin native CLI artifact/output contract missing')
if 'steps.crowdin_cli.outputs.jar' in source or 'CROWDIN_JAR' in source:
    errors.append('Crowdin 5 must not use the legacy Java launcher')
if errors:
    raise SystemExit('\n'.join(errors))
print('OK: immutable action references, artifact checksums and Crowdin 5 native launcher')
PY
