#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib/tool-versions.sh"

swiftlint_version=$(tool_value swiftlint)
if ! grep -Eq "^[[:space:]]*\.package\(url: .*SwiftLint\.git.*, exact: \"$swiftlint_version\"\)" \
  "$ROOT/Package.swift"; then
  echo "error: Package.swift SwiftLint version must match .tool-versions.lock" >&2
  exit 1
fi

swift_mode=$(tool_value swift-language-mode)
grep -Fq "// swift-tools-version: $swift_mode.0" "$ROOT/Package.swift" \
  || { echo "error: Package.swift tools version must match .tool-versions.lock" >&2; exit 1; }
grep -Fq "swiftLanguageModes: [.v$swift_mode]" "$ROOT/Package.swift" \
  || { echo "error: Package.swift language mode must match .tool-versions.lock" >&2; exit 1; }

checkout_sha=$(tool_value actions-checkout)
for workflow in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
  [ -e "$workflow" ] || continue
  while IFS= read -r reference; do
    actual=$(printf '%s\n' "$reference" \
      | sed -E 's#.*actions/checkout@([^"'"'"'[:space:]#]+).*#\1#')
    [ "$actual" = "$checkout_sha" ] \
      || { echo "error: actions/checkout SHA drift in $workflow: $reference" >&2; exit 1; }
  done <<EOF
$(grep -E '^[[:space:]]*[^#]*actions/checkout@' "$workflow" || true)
EOF
done

latest_swift=$(tool_value swift-latest-verified)
grep -Fq "Latest upstream toolchain verification: Swift $latest_swift." "$ROOT/docs/development.md" \
  || { echo "error: documented verified Swift version must match .tool-versions.lock" >&2; exit 1; }
