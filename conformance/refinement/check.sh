#!/usr/bin/env bash
# Builds the correspondence proofs, audits their axioms, and checks the evaluator's lowering
# against the total one on every published contract.
set -euo pipefail
cd "$(dirname "$0")"
if grep -nE '\b(sorry|admit|axiom|native_decide)\b' <(sed 's/--.*//' Refinement.lean | grep -v '^#print axioms'); then
  echo "Forbidden proof escape hatch in Refinement.lean" >&2
  exit 1
fi
rm -rf .lake/build/lib/lean/Refinement.olean
report=$(lake build 2>&1) || { printf '%s\n' "$report"; exit 1; }
printf '%s\n' "$report" | grep -E "depends on axioms|does not depend" || true
declared=$(grep -cE '^theorem ' Refinement.lean)
audited=$(printf '%s\n' "$report" | grep -cE "depends on axioms|does not depend on any axioms" || true)
if [ "$declared" != "$audited" ]; then
  echo "Declared $declared theorems and audited $audited" >&2
  exit 1
fi
if printf '%s\n' "$report" | grep -E "depends on axioms" | grep -vE "axioms: \[((propext|Classical\.choice|Quot\.sound)(, )?)+\]$"; then
  echo "A theorem depends on an axiom other than Lean's standard three" >&2
  exit 1
fi
echo "Audited $declared theorems of the correspondence; no placeholder or custom axiom."
.lake/build/bin/wvp-lowering ../../test-vectors/work-contract/v1/cases ../../test-vectors/work-contract/v1/differential
