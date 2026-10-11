#!/usr/bin/env bash
# Builds the generator and the properties, and runs the properties with their fixed seed.
set -euo pipefail
cd "$(dirname "$0")"
lake build
.lake/build/bin/wvp-properties
