#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tc-integration-runner-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

TRACE_FILE="$TEMP_DIR/trace"
FAKE_BINARY="$TEMP_DIR/tc-test"
cat >"$FAKE_BINARY" <<'EOF'
#!/bin/sh
set -eu
[ "$#" -eq 2 ]
[ "$1" = --test-run-id ]
printf '%s\n' "$1 $2" >"$TC_TEST_TRACE"
printf 'tc-test build=TC_TESTING run=%s ready\n' "$2"
EOF
chmod 755 "$FAKE_BINARY"

RUN_ID=12345678-1234-1234-1234-123456789abc
output=$(
  TC_TEST_TRACE="$TRACE_FILE" \
    TC_TEST_BINARY="$FAKE_BINARY" \
    TEST_RUN_ID="$RUN_ID" \
    "$ROOT/scripts/run-integration-tests.sh"
)

if [ "$output" != "tc-test build=TC_TESTING run=$RUN_ID ready" ]; then
  echo 'test failure: integration runner did not preserve canonical executable output' >&2
  exit 1
fi
if [ "$(cat "$TRACE_FILE")" != "--test-run-id $RUN_ID" ]; then
  echo 'test failure: integration runner exposed paths or changed the run identity' >&2
  exit 1
fi

WRONG_BINARY="$TEMP_DIR/other-test"
cp "$FAKE_BINARY" "$WRONG_BINARY"
if TC_TEST_TRACE="$TRACE_FILE" TC_TEST_BINARY="$WRONG_BINARY" TEST_RUN_ID="$RUN_ID" \
  "$ROOT/scripts/run-integration-tests.sh" >/dev/null 2>&1; then
  echo 'test failure: integration runner accepted a noncanonical executable identity' >&2
  exit 1
fi

if TC_TEST_TRACE="$TRACE_FILE" TC_TEST_BINARY=tc-test TEST_RUN_ID="$RUN_ID" \
  "$ROOT/scripts/run-integration-tests.sh" >/dev/null 2>&1; then
  echo 'test failure: integration runner accepted a relative executable path' >&2
  exit 1
fi

NON_EXECUTABLE_DIR="$TEMP_DIR/non-executable"
mkdir "$NON_EXECUTABLE_DIR"
NON_EXECUTABLE_BINARY="$NON_EXECUTABLE_DIR/tc-test"
cp "$FAKE_BINARY" "$NON_EXECUTABLE_BINARY"
chmod 644 "$NON_EXECUTABLE_BINARY"
if TC_TEST_TRACE="$TRACE_FILE" TC_TEST_BINARY="$NON_EXECUTABLE_BINARY" TEST_RUN_ID="$RUN_ID" \
  "$ROOT/scripts/run-integration-tests.sh" >/dev/null 2>&1; then
  echo 'test failure: integration runner accepted a non-executable file' >&2
  exit 1
fi

echo 'Integration runner tests passed.'
