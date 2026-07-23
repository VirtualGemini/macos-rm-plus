#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

capability_file=Sources/RMPPlatform/WorkspaceTrashClient.swift
production_wiring_file=Sources/rmp/main.swift
whitelist_file=TestSupport/RMPTestSafety/WhitelistedTrashClient.swift
workspace_injection_test_file=Tests/RMPPlatformTests/WorkspaceTrashClientTests.swift
injection_test_file=Tests/RMPPlatformTests/WhitelistedTrashClientTests.swift
workspace_injection_factory=makeInjectedWorkspaceTrashClient
failed=0

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files=$(git ls-files --cached --others --exclude-standard -- '*.swift')
else
  files=$(find . -type f -name '*.swift' -print | sed 's|^\./||' | sort)
fi

while IFS= read -r file; do
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    continue
  fi

  normalized=$(tr '\n' ' ' <"$file")

  if printf '%s\n' "$normalized" \
    | grep -E 'FileManager([[:space:]]*\.[[:space:]]*default)?[[:space:]]*\.[[:space:]]*trashItem|resultingItemURL[[:space:]]*:' >/dev/null 2>&1; then
    echo "error: legacy Foundation Trash API is prohibited: $file" >&2
    failed=1
  fi

  if [ "$file" != "$capability_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E '\.[[:space:]]*recycle([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: Workspace Trash API is outside $capability_file: $file" >&2
    failed=1
  fi

  if [ "$file" != "$capability_file" ] \
    && [ "$file" != "$production_wiring_file" ] \
    && [ "$file" != "$whitelist_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E '(^|[^[:alnum:]_])WorkspaceTrashClient([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: Workspace Trash client reference bypasses approved wiring: $file" >&2
    failed=1
  fi

  if [ "$file" != "$capability_file" ] \
    && [ "$file" != "$workspace_injection_test_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E "(^|[^[:alnum:]_])$workspace_injection_factory([^[:alnum:]_]|$)" >/dev/null 2>&1; then
    echo "error: Workspace Trash injection factory is outside its adapter test: $file" >&2
    failed=1
  fi

  if [ "$file" != "$injection_test_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E '\.[[:space:]]*testingOnly([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: injectable Trash client construction is outside $injection_test_file: $file" >&2
    failed=1
  fi
done <<EOF
$files
EOF

exit "$failed"
