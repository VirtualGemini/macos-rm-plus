#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-swift-toolchain-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

fake_swift="$TEMP_DIR/swift"
cat >"$fake_swift" <<'EOF'
#!/bin/sh
if [ "${FAKE_SWIFTC_RESULT:-failure}" = success ]; then
  exit 0
fi
echo 'error: failed to build module Testing' >&2
exit 1
EOF
chmod +x "$fake_swift"

output="$TEMP_DIR/output"
if SWIFT="$fake_swift" SWIFT_SDK="$TEMP_DIR/SDK" DEVELOPER_DIR="$TEMP_DIR/Developer" \
  "$ROOT/scripts/check-swift-toolchain.sh" >"$output" 2>&1; then
  echo "test failure: incompatible Swift components were accepted" >&2
  exit 1
fi
grep -Fq "active Apple Swift toolchain components are incompatible" "$output"
grep -Fq "failed to build module Testing" "$output"

FAKE_SWIFTC_RESULT=success SWIFT="$fake_swift" SWIFT_SDK="$TEMP_DIR/SDK" \
  DEVELOPER_DIR="$TEMP_DIR/Developer" \
  "$ROOT/scripts/check-swift-toolchain.sh"

echo "Swift toolchain compatibility tests passed."
