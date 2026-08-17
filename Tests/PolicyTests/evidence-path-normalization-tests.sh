#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tc-evidence-path-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

. "$ROOT/scripts/lib/evidence-paths.sh"

mkdir -p "$TEMP_DIR/physical/run"
ln -s "$TEMP_DIR/physical" "$TEMP_DIR/logical"

LOGICAL_ROOT="$TEMP_DIR/logical/run"
CANONICAL_ROOT=$(CDPATH='' cd -- "$LOGICAL_ROOT" && pwd -P)
if [ "$LOGICAL_ROOT" = "$CANONICAL_ROOT" ]; then
  echo 'test failure: fixture did not create distinct logical and canonical paths' >&2
  exit 1
fi

INPUT_FILE="$TEMP_DIR/input"
ACTUAL_FILE="$TEMP_DIR/actual"
EXPECTED_FILE="$TEMP_DIR/expected"

printf 'repository=%s\nlogical=%s/item\ncanonical=%s/item\n' \
  "$ROOT" "$LOGICAL_ROOT" "$CANONICAL_ROOT" >"$INPUT_FILE"
normalize_evidence_file \
  "$INPUT_FILE" "$ROOT" "$LOGICAL_ROOT" "$CANONICAL_ROOT" >"$ACTUAL_FILE"
printf '%s\n' \
  'repository=REPO_ROOT' \
  'logical=TEST_ROOT/item' \
  'canonical=TEST_ROOT/item' >"$EXPECTED_FILE"

if ! diff -u "$EXPECTED_FILE" "$ACTUAL_FILE"; then
  echo 'test failure: evidence paths were not fully normalized' >&2
  exit 1
fi

echo 'Evidence path normalization tests passed.'
