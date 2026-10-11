#!/usr/bin/env bash
# Replays compiled Lean declarations through the kernel, independently of the elaborator that
# produced them.
#
#   kernel-check.sh <path to a lean4checker binary built with the same toolchain>
#
# Two passes over the published definitions (formal/lean):
#   1. every module, starting from the environment its imports provide;
#   2. the audit module, which imports every theorem, into a fresh environment: every constant
#      it depends on, Lean's own library included, is sent through the kernel again.
# and the first pass over each model that accompanies an RFC.
#
# This catches a declaration that reached a compiled file without the kernel having accepted
# it. It is the same kernel, not a second one: it does not guard against a fault in the kernel.
set -euo pipefail
checker=$(cd "$(dirname "${1:?path to lean4checker}")" && pwd)/$(basename "$1")
root=$(cd "$(dirname "$0")/../.." && pwd)

cd "$root/formal/lean"
lake build
lake env "$checker" Verified
echo "kernel: every module of the published definitions replayed."
lake env "$checker" --fresh Verified.Audit
echo "kernel: Verified.Audit and everything it depends on replayed into a fresh environment."

for model in "$root"/rfcs/*/formal; do
  [ -f "$model/lakefile.toml" ] || continue
  library=$(sed -nE 's/^defaultTargets = \["([^"]+)"\]/\1/p' "$model/lakefile.toml")
  (cd "$model" && lake build && lake env "$checker" "$library")
  echo "kernel: $library replayed."
done
