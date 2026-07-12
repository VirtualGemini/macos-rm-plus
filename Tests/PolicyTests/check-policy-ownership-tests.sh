#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-policy-owner-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

mkdir -p "$TEMP_DIR/repo/scripts" "$TEMP_DIR/repo/.github"
cp "$ROOT/scripts/check-policy-ownership.sh" "$TEMP_DIR/repo/scripts/"
printf '%s\n' 'gate.sh' >"$TEMP_DIR/repo/.policy-files"
printf '%s\n' '@maintainer' >"$TEMP_DIR/repo/.github/maintainers.txt"
printf '%s\n' '# gate.sh @maintainer' >"$TEMP_DIR/repo/.github/CODEOWNERS"

if "$TEMP_DIR/repo/scripts/check-policy-ownership.sh" >/dev/null 2>&1; then
  echo "test failure: a CODEOWNERS comment satisfied policy ownership" >&2
  exit 1
fi

printf '%s\n' 'gate.sh @maintainer' >"$TEMP_DIR/repo/.github/CODEOWNERS"
"$TEMP_DIR/repo/scripts/check-policy-ownership.sh"
echo "Policy ownership tests passed."
