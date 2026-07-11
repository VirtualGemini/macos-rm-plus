#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <base-sha> <head-sha>" >&2
  exit 2
fi

base=$1
head=$2
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

temporary_message=$(mktemp)
trap 'rm -f "$temporary_message"' EXIT HUP INT TERM

for commit in $(git rev-list --reverse "$base..$head"); do
  git show -s --format=%B "$commit" >"$temporary_message"
  echo "Validating commit $commit"
  ./scripts/validate-commit-message.sh "$temporary_message"
  ./scripts/check-doc-impact.sh --commit "$commit"
done

echo "Validating documentation impact across $base..$head"
./scripts/check-doc-impact.sh --range "$base" "$head"

echo "Validating breaking-change approvals on trusted base $base"
./scripts/check-breaking-change-approvals.sh "$base" "$head"
