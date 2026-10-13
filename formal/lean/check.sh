#!/usr/bin/env bash
# Builds the Lean definitions, audits the axioms of every theorem, and runs the reference
# evaluator of Work Contract Language 1 over the shared corpus. Run from anywhere; it expects
# the corpus at ../../test-vectors, as in the repository.
set -euo pipefail
cd "$(dirname "$0")"
lake build
# Every file that prints the axioms its theorems depend on: the protocol's, and the ledger
# model's where that is present.
report=""
for audit in Verified/Audit.lean Verified/LedgerAudit.lean; do
  if [ -f "$audit" ]; then
    report+=$(lake env lean -DwarningAsError=true "$audit")$'\n'
  fi
done
printf '%s\n' "$report"
# Audit every declared public theorem. Only Lean's standard logical axioms are
# allowed; in particular sorryAx, custom axioms and native_decide dependencies fail.
python3 - "$report" <<'PY'
import pathlib
import re
import sys
report = sys.argv[1]
theorems = []
for source in sorted(pathlib.Path('Verified').rglob('*.lean')):
    text = source.read_text()
    if re.search(r'\b(sorry|admit|axiom|native_decide)\b', re.sub(r'--[^\n]*', '', text)):
        raise SystemExit(f'Forbidden proof escape hatch in {source}')
    # Theorems are declared directly inside the file's first namespace.
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
        raise SystemExit(f'Unexpected axioms for {name}: {axioms - allowed}')
print(f'Audited {len(theorems)} theorems; no placeholder or custom axiom dependencies.')
PY
# The reference evaluator of Work Contract Language 1 must reproduce every expected outcome of
# the shared corpus: the cases written by hand and the generated differential set.
lake build contract-reference
lake exe contract-reference ../../test-vectors/work-contract/v1/cases ../../test-vectors/work-contract/v1/differential
# A worked example outside the corpus, in the same form: the same evaluator must agree on it.
lake exe contract-reference ../../protocols/work-contract/v1/examples/purchase-order-approval/cases
lake exe contract-reference ../../protocols/work-contract/v1/examples/purchase-order-authorization/attested/cases
lake exe contract-reference ../../protocols/work-contract/v1/examples/purchase-order-authorization/recomputed/cases
