#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
profile=$(find "$ROOT/.build" -path '*/debug/codecov/default.profdata' -type f -print -quit)
test_binary=$(find "$ROOT/.build" \
  -path '*PackageTests.xctest/Contents/MacOS/*PackageTests' ! -path '*.dSYM/*' -type f -print -quit)

if [ -z "$profile" ] || [ -z "$test_binary" ]; then
  echo "error: coverage data is unavailable; run 'make test-unit' first" >&2
  exit 1
fi

xcrun llvm-cov report "$test_binary" -instr-profile="$profile" \
  -ignore-filename-regex='/\.build/'
