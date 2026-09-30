#!/usr/bin/env bash
# Locale contract: static QML lookup coverage and interpolation parity.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import json, re
from pathlib import Path
base = json.loads(Path('i18n/en.json').read_text())
errors = []
for file in Path('.').glob('*.qml'):
    source = file.read_text()
    for match in re.finditer(r'\bt\("([^"\n]+)"\s*[,)]', source):
        if match.group(1) not in base:
            errors.append(f'{file}: missing key {match.group(1)}')
settings = Path('AiOverviewControlSettings.qml').read_text()
for provider in re.findall(r'\{ id:"([^"]+)".*?note:', settings):
    if f'provider.note.{provider}' not in base:
        errors.append(f'Provider note not localized: {provider}')
for file in Path('i18n').glob('*.json'):
    bundle = json.loads(file.read_text())
    if set(bundle) != set(base):
        errors.append(f'{file}: key mismatch')
    for key, english in base.items():
        text = bundle.get(key)
        if not isinstance(text, str) or not text.strip():
            errors.append(f'{file}: empty/non-string {key}')
            continue
        parameters = lambda s: set(re.findall(r'\{([A-Za-z_][A-Za-z0-9_]*)\}', s))
        if parameters(text) != parameters(english):
            errors.append(f'{file}: placeholder mismatch {key}')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'OK: QML lookup coverage and placeholder parity in {len(list(Path("i18n").glob("*.json")))} locales')
PY
