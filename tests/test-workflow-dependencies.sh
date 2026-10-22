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

security = Path('.github/workflows/security.yml').read_text()
for name in ('GITLEAKS', 'TRUFFLEHOG', 'ZIZMOR'):
    if not re.search(r'^\s+' + name + r'_SHA256: "[a-f0-9]{64}"$', security, re.M):
        errors.append(f'{name}: missing artifact checksum')
for command in ('gitleaks git', 'trufflehog git file://.', '--results=verified', 'zizmor --format=github'):
    if command not in security:
        errors.append(f'security.yml no longer runs: {command}')
for file in Path('.github/workflows').glob('*.yml'):
    text = file.read_text()
    if re.search(r'^\s*secrets:\s*inherit\b', text, re.M):
        errors.append(f'{file}: forwards every secret (secrets: inherit)')
    # A persisted checkout token is readable by every later step.
    for match in re.finditer(r'uses: actions/checkout@\S+[^\n]*\n((?:\s{8,}[^\n]*\n){0,6})', text):
        if 'persist-credentials: false' not in match.group(1):
            line = text[:match.start()].count('\n') + 1
            errors.append(f'{file}:{line}: checkout persists credentials')
release = Path('.github/workflows/release.yml').read_text()
if 'actions/attest-build-provenance@' not in release or '--verify-tag' not in release:
    errors.append('release.yml must attest provenance and publish only a pushed tag')
if errors:
    raise SystemExit('\n'.join(errors))
print('OK: immutable action references, artifact checksums, Crowdin 5 native launcher, '
      'secret/workflow scans, scoped secrets and release provenance')
PY
