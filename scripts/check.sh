#!/usr/bin/env bash
# Run all validation gates. Exit non-zero on the first failure.
# Usage: bash scripts/check.sh [--no-codegen]
set -euo pipefail

export PATH="$PATH:/opt/flutter/bin"
cd "$(dirname "$0")/.."

run() { echo ""; echo "â–¶ $*"; "$@"; }

if [[ "${1:-}" != "--no-codegen" ]]; then
  run dart run build_runner build --delete-conflicting-outputs
fi

run flutter analyze
run flutter test
run dart format --set-exit-if-changed .

echo ""
echo "âœ… All gates green."
