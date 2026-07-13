#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
SWIFT=${SWIFT:-swift}
SWIFT_SDK=${SWIFT_SDK:-$(xcrun --sdk macosx --show-sdk-path)}
FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
DEVELOPER_LIB="$DEVELOPER_DIR/Library/Developer/usr/lib"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-swift-toolchain.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

probe_package="$TEMP_DIR/probe"
mkdir -p "$probe_package/Tests/ProbeTests"
printf '%s\n' \
  '// swift-tools-version: 6.0' \
  'import PackageDescription' \
  'let package = Package(' \
  '  name: "ToolchainProbe",' \
  '  platforms: [.macOS(.v14)],' \
  '  targets: [.testTarget(name: "ProbeTests")]' \
  ')' \
  >"$probe_package/Package.swift"
printf '%s\n' \
  'import Foundation' \
  'import Testing' \
  '@Test func toolchainProbe() { #expect(true) }' \
  >"$probe_package/Tests/ProbeTests/ProbeTests.swift"

if ! output=$(
  CLANG_MODULE_CACHE_PATH="$TEMP_DIR/clang-module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$TEMP_DIR/swiftpm-module-cache" \
    DYLD_FRAMEWORK_PATH="$FRAMEWORKS" DYLD_LIBRARY_PATH="$DEVELOPER_LIB" \
    "$SWIFT" test --disable-sandbox --package-path "$probe_package" \
      --scratch-path "$TEMP_DIR/build" --no-parallel \
      -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
      -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
      -Xlinker -rpath -Xlinker "$DEVELOPER_LIB" 2>&1
); then
  echo "error: active Apple Swift toolchain components are incompatible" >&2
  echo "developer directory: $DEVELOPER_DIR" >&2
  echo "macOS SDK: $SWIFT_SDK" >&2
  printf '%s\n' "$output" >&2
  echo "hint: install/select one matching Xcode or Command Line Tools release" >&2
  exit 1
fi

echo "Swift compiler, macOS SDK, and Testing.framework are compatible."
