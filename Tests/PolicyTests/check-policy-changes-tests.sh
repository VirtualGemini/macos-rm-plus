#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-policy-change-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
repo="$TEMP_DIR/repo"
mkdir -p "$repo/scripts" "$repo/.github"
cp "$ROOT/scripts/check-policy-changes.sh" "$repo/scripts/"
printf '%s\n' 'Makefile' >"$repo/.policy-files"
printf '%s\n' '@maintainer' >"$repo/.github/maintainers.txt"
printf '%s\n' 'original' >"$repo/Makefile"
git -C "$repo" init -q
git -C "$repo" config user.name Tests
git -C "$repo" config user.email tests@example.invalid
git -C "$repo" add .
git -C "$repo" commit -qm base
base=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' 'changed' >"$repo/Makefile"
git -C "$repo" add Makefile
git -C "$repo" commit -qm change
head=$(git -C "$repo" rev-parse HEAD)

reviews=$(printf 'maintainer\tAPPROVED\t%s\nmaintainer\tCHANGES_REQUESTED\t%s\n' "$head" "$head")
if POLICY_REVIEWS_TSV="$reviews" "$repo/scripts/check-policy-changes.sh" "$base" "$head" \
  >/dev/null 2>&1; then
  echo "test failure: stale approval survived CHANGES_REQUESTED" >&2
  exit 1
fi
POLICY_REVIEWS_TSV=$(printf 'maintainer\tAPPROVED\t%s\n' "$head") \
  "$repo/scripts/check-policy-changes.sh" "$base" "$head"

git -C "$repo" switch -q --detach "$base"
printf '%s\n' '1' >"$repo/.coverage-metric-version"
printf '%s\n' '0.00' >"$repo/.coverage-baseline"
git -C "$repo" add .
git -C "$repo" commit -qm "ci: establish coverage metric"
metric_base=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' '2' >"$repo/.coverage-metric-version"
printf '%s\n' 'implementation' >"$repo/source.swift"
git -C "$repo" add .
git -C "$repo" commit -qm "ci: mix metric migration with implementation"
metric_head=$(git -C "$repo" rev-parse HEAD)
if POLICY_REVIEWS_TSV=$(printf 'maintainer\tAPPROVED\t%s\n' "$metric_head") \
  "$repo/scripts/check-policy-changes.sh" "$metric_base" "$metric_head" >/dev/null 2>&1; then
  echo "test failure: mixed coverage metric migration was accepted" >&2
  exit 1
fi
echo "Policy change approval tests passed."
