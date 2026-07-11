#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
artifact_root="$ROOT/.build/artifacts/swiftlint"
os=$(uname -s)
arch=$(uname -m)

case "$os-$arch" in
  Darwin-*) artifact_path='*/macos/swiftlint' ;;
  Linux-aarch64 | Linux-arm64) artifact_path='*/linux/arm64/swiftlint' ;;
  Linux-x86_64 | Linux-amd64) artifact_path='*/linux/amd64/swiftlint' ;;
  *)
    echo "error: unsupported SwiftLint host: $os $arch" >&2
    exit 1
    ;;
esac

swiftlint=$(find "$artifact_root" -type f -path "$artifact_path" -print -quit 2>/dev/null || true)

if [ -z "$swiftlint" ]; then
  echo "error: SwiftLint artifact is unavailable; run 'make bootstrap'" >&2
  exit 1
fi

if [ "$os" = "Darwin" ]; then
  developer_dir=$(xcode-select -p)
  DYLD_FRAMEWORK_PATH="$developer_dir/usr/lib:$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/lib"
  export DYLD_FRAMEWORK_PATH
fi

exec "$swiftlint" lint --strict --config "$ROOT/.swiftlint.yml"
