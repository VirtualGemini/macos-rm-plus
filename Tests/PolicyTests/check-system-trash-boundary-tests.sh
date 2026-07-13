#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-system-trash-boundary-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

repo="$TEMP_DIR/repo"
mkdir -p \
  "$repo/scripts" \
  "$repo/Sources" \
  "$repo/TestSupport/RMPTestSafety" \
  "$repo/Tests/RMPPlatformTests" \
  "$repo/TestSupport/rmp-test" \
  "$repo/FutureTarget"
cp "$ROOT/scripts/check-system-trash-boundary.sh" "$repo/scripts/"

cat >"$repo/TestSupport/RMPTestSafety/WhitelistedTrashClient.swift" <<'EOF'
try FileManager.default.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
EOF
cat >"$repo/Tests/RMPPlatformTests/WhitelistedTrashClientTests.swift" <<'EOF'
let client = WhitelistedTrashClient.testingOnly(
  context: context,
  authorization: authorization,
  systemTrash: spy.call
)
EOF
cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
print("safe")
EOF

"$repo/scripts/check-system-trash-boundary.sh"

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
try FileManager.default.trashItem(at: target, resultingItemURL: nil)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: direct Foundation Trash escaped the capability boundary" >&2
  exit 1
fi

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
print("safe again")
EOF

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client: WhitelistedTrashClient = .testingOnly(
  context: context,
  authorization: .accepting,
  systemTrash: { url in url }
)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: production-like test code constructed an injectable Trash client" >&2
  exit 1
fi

echo "System Trash boundary tests passed."
