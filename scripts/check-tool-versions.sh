#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib/tool-versions.sh"

swiftlint_version=$(tool_value swiftlint)
if ! grep -Fq "exact: \"$swiftlint_version\"" "$ROOT/Package.swift"; then
  echo "error: Package.swift SwiftLint version must match .tool-versions.lock" >&2
  exit 1
fi
