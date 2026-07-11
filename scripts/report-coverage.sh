#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
profile=$(find "$ROOT/.build" -path '*/debug/codecov/default.profdata' -type f -print -quit)
test_binary=$(find "$ROOT/.build" \
  -path '*/debug/*PackageTests.xctest/Contents/MacOS/*PackageTests' ! -path '*.dSYM/*' \
  -type f -print -quit)
production_binary=$(find "$ROOT/.build" -path '*/debug/rmp' ! -path '*.dSYM/*' -type f -print -quit)

if [ -z "$profile" ] || [ -z "$test_binary" ] || [ -z "$production_binary" ]; then
  echo "error: coverage data is unavailable; run 'make test-unit' first" >&2
  exit 1
fi

report=$(xcrun llvm-cov report "$test_binary" -object "$production_binary" -instr-profile="$profile" \
  -ignore-filename-regex='/\.build/')
printf '%s\n' "$report"

current=$(printf '%s\n' "$report" | awk '/^TOTAL/ { value=$10; sub(/%$/, "", value); print value }')
if [ -n "${COVERAGE_BASELINE_REF-}" ] \
  && git cat-file -e "$COVERAGE_BASELINE_REF:.coverage-baseline" 2>/dev/null; then
  baseline=$(git show "$COVERAGE_BASELINE_REF:.coverage-baseline")
else
  baseline=$(cat "$ROOT/.coverage-baseline")
fi

if ! awk -v current="$current" -v baseline="$baseline" 'BEGIN { exit !(current + 0.0001 >= baseline) }'; then
  echo "error: line coverage $current% is below trusted baseline $baseline%" >&2
  exit 1
fi
