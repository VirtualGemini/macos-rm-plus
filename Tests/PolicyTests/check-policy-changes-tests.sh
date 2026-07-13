#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-policy-change-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
repo="$TEMP_DIR/repo"
mkdir -p "$repo/scripts" "$repo/.github"
cp "$ROOT/scripts/check-policy-changes.sh" "$repo/scripts/"
printf '%s\n' 'Makefile' '.coverage-baseline' '.coverage-metric-version' >"$repo/.policy-files"
printf '%s\n' '@maintainer' >"$repo/.github/maintainers.txt"
printf '%s\n' 'original' >"$repo/Makefile"
printf '%s\n' '80.00' >"$repo/.coverage-baseline"
printf '%s\n' '1' >"$repo/.coverage-metric-version"
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
POLICY_PR_AUTHOR=maintainer \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' "$head") \
  "$repo/scripts/check-policy-changes.sh" "$base" "$head"

git -C "$repo" switch -q --detach "$base"
printf '%s\n' '82.04' >"$repo/.coverage-baseline"
printf '%s\n' 'feature implementation' >"$repo/source.swift"
git -C "$repo" add .
git -C "$repo" commit -qm "test: raise coverage baseline with feature"
ratchet_head=$(git -C "$repo" rev-parse HEAD)
POLICY_PR_AUTHOR=maintainer \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' "$ratchet_head") \
  "$repo/scripts/check-policy-changes.sh" "$base" "$ratchet_head"
if POLICY_PR_AUTHOR=contributor \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' "$ratchet_head") \
  "$repo/scripts/check-policy-changes.sh" "$base" "$ratchet_head" >/dev/null 2>&1; then
  echo "test failure: untrusted author bypassed coverage baseline approval" >&2
  exit 1
fi

git -C "$repo" switch -q --detach "$base"
printf '%s\n' '82.04' >"$repo/.coverage-baseline"
printf '%s\n' 'changed again' >"$repo/Makefile"
git -C "$repo" add .
git -C "$repo" commit -qm "test: raise baseline with policy executor"
mixed_policy_head=$(git -C "$repo" rev-parse HEAD)
POLICY_PR_AUTHOR=maintainer \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' "$mixed_policy_head") \
  "$repo/scripts/check-policy-changes.sh" "$base" "$mixed_policy_head"

git -C "$repo" switch -q --detach "$base"
printf '%s\n' '@reviewer' >>"$repo/.github/maintainers.txt"
git -C "$repo" add .github/maintainers.txt
git -C "$repo" commit -qm "test: add second maintainer"
multi_maintainer_base=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' 'changed with independent review available' >"$repo/Makefile"
git -C "$repo" add Makefile
git -C "$repo" commit -qm "test: change policy with two maintainers"
multi_maintainer_head=$(git -C "$repo" rev-parse HEAD)
if POLICY_PR_AUTHOR=maintainer \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' "$multi_maintainer_head") \
  "$repo/scripts/check-policy-changes.sh" "$multi_maintainer_base" "$multi_maintainer_head" \
  >/dev/null 2>&1; then
  echo "test failure: maintainer bypassed independent review when another maintainer existed" >&2
  exit 1
fi
POLICY_PR_AUTHOR=maintainer \
  POLICY_REVIEWS_TSV=$(printf 'reviewer\tAPPROVED\t%s\n' "$multi_maintainer_head") \
  "$repo/scripts/check-policy-changes.sh" "$multi_maintainer_base" "$multi_maintainer_head"

git -C "$repo" switch -q --detach "$multi_maintainer_base"
printf '%s\n' '82.04' >"$repo/.coverage-baseline"
git -C "$repo" add .coverage-baseline
git -C "$repo" commit -qm "test: ratchet coverage with two maintainers"
multi_maintainer_ratchet_head=$(git -C "$repo" rev-parse HEAD)
if POLICY_PR_AUTHOR=maintainer \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' \
    "$multi_maintainer_ratchet_head") \
  "$repo/scripts/check-policy-changes.sh" "$multi_maintainer_base" \
    "$multi_maintainer_ratchet_head" >/dev/null 2>&1; then
  echo "test failure: coverage ratchet bypassed review when another maintainer existed" >&2
  exit 1
fi
POLICY_PR_AUTHOR=maintainer \
  POLICY_REVIEWS_TSV=$(printf 'reviewer\tAPPROVED\t%s\n' "$multi_maintainer_ratchet_head") \
  "$repo/scripts/check-policy-changes.sh" "$multi_maintainer_base" \
    "$multi_maintainer_ratchet_head"

git -C "$repo" switch -q --detach "$base"
printf '%s\n' 'not-a-number' >"$repo/.coverage-baseline"
printf '%s\n' 'feature implementation' >"$repo/source.swift"
git -C "$repo" add .
git -C "$repo" commit -qm "test: use invalid coverage baseline"
invalid_head=$(git -C "$repo" rev-parse HEAD)
if POLICY_PR_AUTHOR=contributor \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' "$invalid_head") \
  "$repo/scripts/check-policy-changes.sh" "$base" "$invalid_head" >/dev/null 2>&1; then
  echo "test failure: invalid coverage baseline bypassed policy approval" >&2
  exit 1
fi

git -C "$repo" switch -q --detach "$base"
printf '%s\n' '79.99' >"$repo/.coverage-baseline"
printf '%s\n' 'feature implementation' >"$repo/source.swift"
git -C "$repo" add .
git -C "$repo" commit -qm "test: lower coverage baseline with feature"
lowered_head=$(git -C "$repo" rev-parse HEAD)
if POLICY_PR_AUTHOR=contributor \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' "$lowered_head") \
  "$repo/scripts/check-policy-changes.sh" "$base" "$lowered_head" >/dev/null 2>&1; then
  echo "test failure: lowered coverage baseline bypassed policy approval" >&2
  exit 1
fi

git -C "$repo" switch -q --detach "$base"
printf '%s\n' '2' >"$repo/.coverage-metric-version"
git -C "$repo" add .coverage-metric-version
git -C "$repo" commit -qm "test: change coverage metric version"
metric_only_head=$(git -C "$repo" rev-parse HEAD)
if POLICY_PR_AUTHOR=contributor \
  POLICY_REVIEWS_TSV=$(printf 'maintainer\tCHANGES_REQUESTED\t%s\n' "$metric_only_head") \
  "$repo/scripts/check-policy-changes.sh" "$base" "$metric_only_head" >/dev/null 2>&1; then
  echo "test failure: coverage metric change bypassed policy approval" >&2
  exit 1
fi

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
