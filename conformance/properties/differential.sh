#!/usr/bin/env bash
# Lean model -> generated cases -> Lean reference result -> an independent implementation.
#
#   differential.sh <a checkout of verified-cli> [seed] [contracts] [environments]
#
# Generates cases with a fixed seed, takes the Lean reference evaluator's result as each
# expectation, and asks verified-cli's own conformance harness to reproduce every one beside the
# published cases. Exit 0 only if it reproduced every generated case; a disagreement is printed
# with the case and both results. The generated cases are written to ./generated and are not
# part of the corpus.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
implementation=$(cd "${1:?a checkout of verified-cli}" && pwd)
seed=${2:-20261012}; contracts=${3:-250}; environments=${4:-8}
cd "$here"
lake build wvp-generate
rm -rf generated
.lake/build/bin/wvp-generate "$seed" "$contracts" "$environments" generated
generated=$(python3 -c "import json; print(json.load(open('generated/manifest.json'))['cases'])")

# The published corpus with its differential batches replaced by the generated ones.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/work-contract/v1"
cp -R ../../test-vectors/work-contract/v1/cases "$scratch/work-contract/v1/cases"
cp -R generated/differential "$scratch/work-contract/v1/differential"
published=$(ls "$scratch/work-contract/v1/cases" | wc -l | tr -d ' ')

set +e
output=$(cd "$implementation" && VERIFIED_CONFORMANCE_DIR="$scratch" VERIFIED_CONFORMANCE_REQUIRED=1 \
  cargo test --locked -p verified-contract --test conformance -- --exact every_case_in_the_corpus_is_reproduced --nocapture 2>&1)
status=$?
set -e
ran=$(printf '%s\n' "$output" | sed -nE 's/^work-contract-1: ([0-9]+) cases reproduced; ([0-9]+) not representable.*/\1 \2/p')
if [ "$status" != 0 ] || [ -z "$ran" ]; then
  printf '%s\n' "$output" | tail -40 | sed "s#$scratch/##g"
  echo "The implementation did not reproduce the generated cases (seed $seed)." >&2
  exit 1
fi
reproduced=${ran% *}; unrepresentable=${ran#* }
if [ $((reproduced + unrepresentable)) != $((published + generated)) ]; then
  echo "The implementation ran $((reproduced + unrepresentable)) cases; $((published + generated)) were given." >&2
  exit 1
fi
echo "Differential: $generated generated cases (seed $seed, $contracts contracts) and $published published ones; the implementation reproduced $reproduced and could not represent $unrepresentable."
