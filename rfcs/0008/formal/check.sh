#!/usr/bin/env bash
# Builds the Work Contract Language 2 model of RFC 0008 and audits every theorem's axioms, under the
# rules of formal/lean/check.sh: no sorry, admit, custom axiom or native_decide, and only Lean's
# propext, Classical.choice and Quot.sound.
set -euo pipefail
cd "$(dirname "$0")"
lake build
report=$(lake env lean -DwarningAsError=true Audit.lean)
printf '%s\n' "$report"
python3 - "$report" <<'PY'
import pathlib, re, sys
report = sys.argv[1]
theorems = []
for source in sorted(pathlib.Path('WCL2').rglob('*.lean')):
    text = source.read_text()
    if re.search(r'\b(sorry|admit|axiom|native_decide)\b', re.sub(r'--[^\n]*', '', text)):
        raise SystemExit(f'Forbidden proof escape hatch in {source}')
    namespace = re.search(r'^namespace\s+(\S+)', text, re.M)
    theorems += [f'{namespace.group(1)}.{name}' for name in re.findall(r'^theorem\s+(\w+)', text, re.M)]
if not theorems:
    raise SystemExit('No theorems found')
allowed = {'propext', 'Classical.choice', 'Quot.sound'}
for name in theorems:
    match = re.search(r"'" + re.escape(name) + r"' (?:depends on axioms: \[([^\]]*)\]|does not depend on any axioms)", report)
    if not match:
        raise SystemExit(f'Missing axiom audit: {name}')
    axioms = {item.strip() for item in (match.group(1) or '').split(',') if item.strip()}
    if not axioms <= allowed:
        raise SystemExit(f'{name} depends on {sorted(axioms - allowed)}')
print(f'{len(theorems)} theorems audited')
PY
