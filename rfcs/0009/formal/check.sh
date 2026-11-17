#!/bin/sh
# Checks the model and prints the axioms each theorem rests on. Needs Lean 4.24.0 (elan).
set -e
cd "$(dirname "$0")"
! grep -n 'sorry\|admit\|native_decide\|^axiom' Interval.lean
lean -o Interval.olean Interval.lean
LEAN_PATH=.:$(lean --print-prefix)/lib/lean lean Audit.lean
rm -f Interval.olean
