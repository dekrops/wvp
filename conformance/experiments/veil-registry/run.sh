#!/usr/bin/env bash
# Checks the three registry models with Veil, in a checkout of Veil at a pinned commit.
#
#   run.sh [directory to clone Veil into; default: a temporary one]
#
# Veil brings its own Lean toolchain, an SMT solver and a widget built with npm: it needs
# elan, Node.js and Clang, and its first build takes many minutes. Nothing else in this
# repository depends on it.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
veil_commit=52f9c27d93bfd755aa49754e95b399a2a645abba
work=${1:-$(mktemp -d)}
if [ ! -d "$work/.git" ]; then
  git init -q "$work"
  git -C "$work" remote add origin https://github.com/verse-lab/veil
fi
git -C "$work" fetch -q --depth 1 origin "$veil_commit"
git -C "$work" checkout -q FETCH_HEAD
mkdir -p "$work/Examples/Wvp"
cp "$here"/Registry*.lean "$work/Examples/Wvp/"
cd "$work"

# The two models that must hold: no violation in the instances explored, and every clause of the
# invariant preserved by every action, with the solver's proofs reconstructed in Lean.
for model in RegistryAtomic RegistryOrdered; do
  output=$(lake build "Examples.Wvp.$model" 2>&1) || { printf '%s\n' "$output" | tail -60; exit 1; }
  printf '%s\n' "$output" | grep -E "No violation|Violation|❌|Trusting SMT" || true
  if printf '%s\n' "$output" | grep -qE "❌|Violation|Trusting SMT"; then
    echo "$model: a check failed, or a proof was trusted and not reconstructed" >&2
    exit 1
  fi
  printf '%s\n' "$output" | grep -q "No violation" || { echo "$model: the model checker did not run" >&2; exit 1; }
  echo "$model: holds."
done

# The model that must not: replicas that accept on what they have observed.
set +e
output=$(lake build Examples.Wvp.RegistryReplicated 2>&1)
status=$?
set -e
printf '%s\n' "$output" | sed -n '/Violation/,/registered = \[0, 1\]/p'
if [ "$status" = 0 ] || ! printf '%s\n' "$output" | grep -q "Violation: safety_failure (violates: unit_exclusive)"; then
  echo "RegistryReplicated: expected a violation of unit_exclusive and found none" >&2
  exit 1
fi
echo "RegistryReplicated: violated, as expected, in two steps."
