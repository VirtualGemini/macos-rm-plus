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
  -ignore-filename-regex='/(Tests|TestSupport|\.build)/')
printf '%s\n' "$report"

current=$(printf '%s\n' "$report" | awk '/^TOTAL/ { value=$10; sub(/%$/, "", value); print value }')
metric_version=$(cat "$ROOT/.coverage-metric-version")
trusted_metric_version=
if [ -n "${COVERAGE_BASELINE_REF-}" ] \
  && git cat-file -e "$COVERAGE_BASELINE_REF:.coverage-metric-version" 2>/dev/null; then
  trusted_metric_version=$(git show "$COVERAGE_BASELINE_REF:.coverage-metric-version")
fi

if [ -n "${COVERAGE_BASELINE_REF-}" ] && [ "$trusted_metric_version" = "$metric_version" ] \
  && git cat-file -e "$COVERAGE_BASELINE_REF:.coverage-baseline" 2>/dev/null; then
  baseline=$(git show "$COVERAGE_BASELINE_REF:.coverage-baseline")
else
  baseline=$(cat "$ROOT/.coverage-baseline")
fi

if ! awk -v current="$current" -v baseline="$baseline" 'BEGIN { exit !(current + 0.0001 >= baseline) }'; then
  echo "error: line coverage $current% is below trusted baseline $baseline%" >&2
  exit 1
fi

declared=$(cat "$ROOT/.coverage-baseline")
if ! awk -v current="$current" -v declared="$declared" 'BEGIN { exit !(declared == current) }'; then
  echo "error: .coverage-baseline must ratchet to current production coverage $current%" >&2
  exit 1
fi
