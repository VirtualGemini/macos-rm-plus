#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

capability_file=Sources/RMPPlatform/FinderTrashClient.swift
macos_capability_file=Sources/RMPPlatform/MacOSTrashClient.swift
foundation_symlink_capability_file=TestSupport/RMPTestSafety/FoundationSymlinkTrashClient.swift
put_back_capability_file=TestSupport/RMPTestSafety/WhitelistedPutBackClient.swift
put_back_wiring_file=TestSupport/RMPTestSafety/PutBackRaceAcceptance.swift
put_back_test_file=Tests/RMPPlatformTests/PutBackRaceAcceptanceTests.swift
production_wiring_file=Sources/rmp/main.swift
whitelist_file=TestSupport/RMPTestSafety/WhitelistedTrashClient.swift
finder_injection_test_file=Tests/RMPPlatformTests/FinderTrashClientTests.swift
macos_injection_test_file=Tests/RMPPlatformTests/MacOSTrashClientTests.swift
macos_acceptance_file=TestSupport/RMPTestSafety/WhitelistedMacOSTrashClient.swift
macos_acceptance_test_file=Tests/RMPPlatformTests/WhitelistedMacOSTrashClientTests.swift
foundation_symlink_test_file=Tests/RMPPlatformTests/FoundationSymlinkTrashClientTests.swift
injection_test_file=Tests/RMPPlatformTests/WhitelistedTrashClientTests.swift
finalizer_test_file=Tests/RMPPlatformTests/FoundationTrashFinalizerTests.swift
finder_injection_factory=makeInjectedFinderTrashClient
macos_injection_factory=makeInjectedMacOSTrashClient
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

  if [ "$file" != "$foundation_symlink_capability_file" ] \
    && [ "$file" != "$macos_capability_file" ] \
    && printf '%s\n' "$normalized" \
    | grep -E 'FileManager([[:space:]]*\.[[:space:]]*default)?[[:space:]]*\.[[:space:]]*trashItem|resultingItemURL[[:space:]]*:' >/dev/null 2>&1; then
    echo "error: Foundation Trash API is outside approved adapters: $file" >&2
    failed=1
  fi

  if printf '%s\n' "$normalized" \
    | grep -E '\.[[:space:]]*recycle([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: failed Workspace Trash candidate is prohibited: $file" >&2
    failed=1
  fi

  if [ "$file" != "$capability_file" ] \
    && [ "$file" != "$put_back_capability_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E 'NSAppleScript|NSAppleEventDescriptor|com\.apple\.finder|(^|[^[:alnum:]_])osascript([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: Finder Automation capability is outside $capability_file: $file" >&2
    failed=1
  fi

  if [ "$file" != "$foundation_symlink_capability_file" ] \
    && [ "$file" != "$whitelist_file" ] \
    && [ "$file" != "$foundation_symlink_test_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E '(^|[^[:alnum:]_])FoundationSymlinkTrashClient([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: Foundation symbolic-link Trash client bypasses approved test wiring: $file" >&2
    failed=1
  fi

  if [ "$file" != "$put_back_capability_file" ] \
    && [ "$file" != "$put_back_wiring_file" ] \
    && [ "$file" != "$put_back_test_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E '(^|[^[:alnum:]_])WhitelistedPutBackClient([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: Finder Put Back client bypasses its isolated acceptance wiring: $file" >&2
    failed=1
  fi

  if [ "$file" != "$capability_file" ] \
    && [ "$file" != "$macos_capability_file" ] \
    && [ "$file" != "$whitelist_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E '(^|[^[:alnum:]_])FinderTrashClient([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: Finder Trash client reference bypasses approved wiring: $file" >&2
    failed=1
  fi

  if [ "$file" != "$capability_file" ] \
    && [ "$file" != "$finder_injection_test_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E "(^|[^[:alnum:]_])$finder_injection_factory([^[:alnum:]_]|$)" >/dev/null 2>&1; then
    echo "error: Finder Trash injection factory is outside its adapter test: $file" >&2
    failed=1
  fi

  if [ "$file" != "$macos_capability_file" ] \
    && [ "$file" != "$production_wiring_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E '(^|[^[:alnum:]_])MacOSTrashClient([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: macOS Trash client reference bypasses production wiring: $file" >&2
    failed=1
  fi

  if [ "$file" != "$macos_capability_file" ] \
    && [ "$file" != "$macos_injection_test_file" ] \
    && [ "$file" != "$macos_acceptance_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E "(^|[^[:alnum:]_])$macos_injection_factory([^[:alnum:]_]|$)" >/dev/null 2>&1; then
    echo "error: macOS Trash injection factory is outside its adapter test: $file" >&2
    failed=1
  fi

  if [ "$file" != "$injection_test_file" ] \
    && [ "$file" != "$finalizer_test_file" ] \
    && [ "$file" != "$macos_acceptance_test_file" ] \
    && printf '%s\n' "$normalized" \
      | grep -E '\.[[:space:]]*testingOnly([^[:alnum:]_]|$)' >/dev/null 2>&1; then
    echo "error: injectable Trash client construction is outside $injection_test_file: $file" >&2
    failed=1
  fi
done <<EOF
$files
EOF

exit "$failed"
