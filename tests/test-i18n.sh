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
# Readiness details come from the health helper in English; every prose one
# needs a health.detail.<slug> key, built the way healthDetailText() builds it.
def health_slug(text):
    slug = re.sub(r'^_|_$', '', re.sub(r'[^a-z0-9]+', '_', text.lower()))
    return slug[:60].rstrip('_')
health = Path('providers/get-provider-health').read_text()
for detail in sorted(set(re.findall(r'detail="([^"]*)"', health))):
    if re.fullmatch(r'[A-Z0-9_]+', detail) or detail in ('Configured', 'sqlite3'):
        continue
    if f'health.detail.{health_slug(detail)}' not in base:
        errors.append(f'Readiness detail not localized: {detail!r} (health.detail.{health_slug(detail)})')
    elif base[f'health.detail.{health_slug(detail)}'] != detail:
        errors.append(f'Readiness detail key holds different English text: {detail!r}')
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
# DMS renders the plugin.json DankDash strings itself, through
# I18n.trFor(pluginId, term), from translations/<lang>.json. Every non-English
# locale in i18n/ needs a file there covering every manifest term.
manifest = json.loads(Path('plugin.json').read_text())
dash = manifest.get('dash', {})
terms = {dash['title']} if 'title' in dash else set()
if 'title' in dash.get('card', {}):
    terms.add(dash['card']['title'])
for option in dash.get('options', []):
    terms.add(option.get('text', option['key']))
    for choice in option.get('choices', []):
        terms.add(choice.get('text', choice['value']))
terms = {term for term in terms if not term.isdigit()}
# translations/en.json is the Crowdin source for those terms: each maps to
# itself, so Dux Shell shows the English term unchanged.
languages = {file.stem.split('_')[0] for file in Path('i18n').glob('*.json')}
shipped = {file.stem for file in Path('translations').glob('*.json')}
if shipped != languages:
    errors.append(f'translations/: expected {sorted(languages)}, found {sorted(shipped)}')
for file in sorted(Path('translations').glob('*.json')):
    table = json.loads(file.read_text())
    if set(table) != terms:
        errors.append(f'{file}: missing {sorted(terms - set(table))}, extra {sorted(set(table) - terms)}')
    for term in terms & set(table):
        bucket = table[term]
        text = bucket.get(term) if isinstance(bucket, dict) else None
        if file.stem == 'en':
            if text != term:
                errors.append(f'{file}: source term {term!r} must map to itself')
        elif not isinstance(text, str) or not text.strip() or text == term:
            errors.append(f'{file}: untranslated manifest term {term!r}')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'OK: QML lookup coverage and placeholder parity in {len(list(Path("i18n").glob("*.json")))} locales, '
      f'{len(terms)} manifest terms in {len(shipped)} DMS translation files')
PY
