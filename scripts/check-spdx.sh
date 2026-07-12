#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

failed=0

check_file() {
  file=$1
  if ! sed -n '1,5p' "$file" | grep -q 'SPDX-License-Identifier: Apache-2.0'; then
    echo "error: missing Apache-2.0 SPDX header: $file" >&2
    failed=1
  fi
}

for directory in Sources TestSupport Tests scripts .githooks .github; do
  if [ -d "$directory" ]; then
    while IFS= read -r file; do
      check_file "$file"
    done <<EOF
$(find "$directory" -type f | sort)
EOF
  fi
done

for file in Makefile Package.swift; do
  check_file "$file"
done

exit "$failed"
