#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

if [ -n "${TC_TEST_BINARY:-}" ]; then
  SOURCE_TC_TEST=$TC_TEST_BINARY
  if [ "${SOURCE_TC_TEST#/}" = "$SOURCE_TC_TEST" ] \
    || [ ! -f "$SOURCE_TC_TEST" ] \
    || [ ! -x "$SOURCE_TC_TEST" ] \
    || [ "$(basename -- "$SOURCE_TC_TEST")" != tc-test ]; then
    echo 'error: TC_TEST_BINARY must be an absolute executable path named tc-test' >&2
    exit 1
  fi
else
  if ! make -C "$ROOT" build-release; then
    echo 'error: release test executable build failed' >&2
    exit 1
  fi
  SOURCE_TC_TEST="$ROOT/.build/release/tc-test"
fi

if [ -n "${TEST_RUN_ID:-}" ]; then
  RUN_ID=$TEST_RUN_ID
else
  RUN_ID=$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')
fi

"$SOURCE_TC_TEST" --test-run-id "$RUN_ID"
