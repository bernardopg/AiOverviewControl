#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import re
from pathlib import Path
source = Path('providers/get-provider-usage').read_text()
workflow = Path('.github/workflows/ci.yml').read_text()
assert 'find providers -type f -print0 | xargs -0 -n 1 bash -n' in workflow, 'CI must syntax-check every provider file, not pass later files as script arguments'
modules = sorted(Path('providers/native').glob('*.bash'))
assert len(modules) >= 31, 'Native provider module set incomplete'
functions = set()
for module in modules:
    names = re.findall(r'^fetch_([a-z0-9_]+)_native\(\)', module.read_text(), re.M)
    assert names, f'{module}: no adapter interface'
    assert not functions.intersection(names), f'{module}: duplicate adapter interface'
    functions.update(names)
    assert f'source "$SCRIPT_DIR/native/{module.name}"' in source, f'{module}: missing explicit import'
assert len(functions) >= 33
assert not re.search(r'^fetch_\w+_native\(\)', source, re.M), 'Native implementations belong in modules'
for call in re.findall(r'\bfetch_([a-z0-9_]+)_native\b', source):
    assert call in functions, f'Undefined native dispatcher target: {call}'
print(f'OK: {len(functions)} adapter interfaces in {len(modules)} explicitly imported modules')
PY
find providers/native -type f -name '*.bash' -print0 | xargs -0 -n 1 bash -n
