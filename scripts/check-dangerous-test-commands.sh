#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

pattern='(^|[;&|[:space:]])(swift[[:space:]]+run[[:space:]]+)?rmp(-test)?([[:space:]]+[^;&|]*)?[[:space:]]+/(($)|[[:space:];&|])|(^|[;&|[:space:]])rm[[:space:]]+-[^;&|]*r[^;&|]*f[^;&|]*[[:space:]]+/'
failed=0

files=$(git ls-files --cached --others --exclude-standard \
  Makefile scripts .githooks .github TestSupport Tests 2>/dev/null)

while IFS= read -r file; do
  if [ -z "$file" ]; then
    continue
  fi

  if [ "$file" = "scripts/check-dangerous-test-commands.sh" ]; then
    continue
  fi

  if grep -nE "$pattern" "$file" >/dev/null 2>&1; then
    echo "error: possible dangerous real command in $file" >&2
    grep -nE "$pattern" "$file" >&2
    failed=1
  fi
done <<EOF
$files
EOF

exit "$failed"
