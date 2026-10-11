#!/usr/bin/env bash
# Builds the model of RFC 0003 and audits the axioms of its theorems. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")"
if grep -nE '\b(sorry|admit|axiom|native_decide)\b' <(sed 's/--.*//' WvpV03.lean | grep -v '^#print axioms'); then
  echo "Forbidden proof escape hatch in WvpV03.lean" >&2
  exit 1
fi
report=$(lake build 2>&1) || { printf '%s\n' "$report"; exit 1; }
printf '%s\n' "$report"
declared=$(grep -cE '^theorem ' WvpV03.lean)
audited=$(printf '%s\n' "$report" | grep -cE "depends on axioms|does not depend on any axioms" || true)
if [ "$declared" != "$audited" ]; then
  echo "Declared $declared theorems and audited $audited" >&2
  exit 1
fi
if printf '%s\n' "$report" | grep -E "depends on axioms" | grep -vE "axioms: \[((propext|Classical\.choice|Quot\.sound)(, )?)+\]$"; then
  echo "A theorem depends on an axiom other than Lean's standard three" >&2
  exit 1
fi
echo "Audited $declared theorems of the RFC 0003 model; no placeholder or custom axiom."
