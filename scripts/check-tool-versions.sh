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

swift_mode=$(tool_value swift-language-mode)
grep -Fq "// swift-tools-version: $swift_mode.0" "$ROOT/Package.swift" \
  || { echo "error: Package.swift tools version must match .tool-versions.lock" >&2; exit 1; }
grep -Fq "swiftLanguageModes: [.v$swift_mode]" "$ROOT/Package.swift" \
  || { echo "error: Package.swift language mode must match .tool-versions.lock" >&2; exit 1; }

checkout_sha=$(tool_value actions-checkout)
for workflow in "$ROOT"/.github/workflows/*.yml; do
  grep -Fq "actions/checkout@$checkout_sha" "$workflow" \
    || { echo "error: actions/checkout SHA drift in $workflow" >&2; exit 1; }
done

latest_swift=$(tool_value swift-latest-verified)
grep -Fq "Latest upstream toolchain verification: Swift $latest_swift." "$ROOT/docs/development.md" \
  || { echo "error: documented verified Swift version must match .tool-versions.lock" >&2; exit 1; }
