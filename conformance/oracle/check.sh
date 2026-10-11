#!/usr/bin/env bash
# Builds the oracle and checks its interface: the corpus, the examples, determinism and every
# exit code. Run from anywhere; it expects the corpus at ../../test-vectors.
set -euo pipefail
cd "$(dirname "$0")"
lake build
oracle=.lake/build/bin/wvp-oracle
corpus=../../test-vectors/work-contract/v1
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# 0: every published case has a result that agrees with its expectation.
"$oracle" evaluate "$corpus/cases" "$corpus/differential" > "$scratch/corpus.jsonl"
cases=$(wc -l < "$scratch/corpus.jsonl" | tr -d ' ')
agreeing=$(grep -c '"agrees":true' "$scratch/corpus.jsonl")
[ "$cases" = "$agreeing" ] || { echo "only $agreeing of $cases corpus cases agree" >&2; exit 1; }

# The examples yield exactly the recorded output, twice.
"$oracle" evaluate examples > "$scratch/first.jsonl"
"$oracle" evaluate examples > "$scratch/second.jsonl"
cmp "$scratch/first.jsonl" "$scratch/second.jsonl"
cmp "$scratch/first.jsonl" examples/expected-output.jsonl

# Standard input gives the results the files give.
for file in examples/batch.json examples/no-completeness.json; do python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))" "$file"; done \
  | "$oracle" evaluate | sed 's/"case":"stdin:[0-9]*/"case":"x/' > "$scratch/stdin.jsonl"
sed 's/"case":"examples\/[a-z-]*\.json/"case":"x/' "$scratch/first.jsonl" > "$scratch/files.jsonl"
cmp "$scratch/stdin.jsonl" "$scratch/files.jsonl"

expect() { # expect <code> <description> <command...>
  local code=$1 what=$2; shift 2
  set +e; "$@" > /dev/null 2>&1; local got=$?; set -e
  [ "$got" = "$code" ] || { echo "$what: exit $got, expected $code" >&2; exit 1; }
}
# 1: a result that disagrees with the expectation a case states.
python3 -c "import json,sys; c=json.load(open(sys.argv[1])); c['expected']={'refused':'WORK_LIMIT'}; print(json.dumps(c))" "$corpus/cases/01-valid.json" > "$scratch/wrong.json"
expect 1 "a disagreeing expectation" "$oracle" evaluate "$scratch/wrong.json"
# 2: input that is not a case.
echo 'not json' > "$scratch/bad.json"
expect 2 "text that is not JSON" "$oracle" evaluate "$scratch/bad.json"
echo '{"contract":{}}' > "$scratch/partial.json"
expect 2 "a case without an environment" "$oracle" evaluate "$scratch/partial.json"
# 3: the command could not run.
expect 3 "a path that does not exist" "$oracle" evaluate "$scratch/absent.json"
expect 3 "no command" "$oracle"
# A refusal is a result, not an error: a contract that is not one is refused with exit 0.
echo '{"contract":{},"environment":{}}' > "$scratch/refused.json"
expect 0 "a refused contract" "$oracle" evaluate "$scratch/refused.json"
"$oracle" evaluate "$scratch/refused.json" 2>/dev/null | grep -q '"result":{"refused":"CONTRACT_MALFORMED"}'

echo "Oracle: $cases corpus cases agree; examples, standard input, determinism and exit codes as documented."
