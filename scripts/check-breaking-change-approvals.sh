#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. "$ROOT/scripts/lib/commit-message.sh"

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <base-sha> <head-sha>" >&2
  exit 2
fi

base=$1
head=$2

for commit in $(git rev-list --reverse "$base..$head"); do
  message=$(git show -s --format=%B "$commit")
  if ! message_is_breaking "$message"; then
    continue
  fi

  approval=$(message_trailer "$message" Breaking-Approval)
  if ! printf '%s\n' "$approval" | grep -Eq '^\.scratch/[^/]+/issues/[^/]+\.md$'; then
    echo "error: breaking commit $commit requires a valid Breaking-Approval path" >&2
    exit 1
  fi

  if ! git cat-file -e "$base:$approval" 2>/dev/null; then
    echo "error: breaking approval must exist on trusted base $base before implementation: $approval" >&2
    exit 1
  fi

  ticket=$(git show "$base:$approval")
  if missing_field=$(validate_breaking_ticket_fields "$ticket"); then
    :
  else
    echo "error: trusted breaking approval ticket is missing required field: $missing_field" >&2
    exit 1
  fi

  approver=$(printf '%s\n' "$ticket" | sed -n 's/^Approved by: //p' | tail -1)
  maintainers=$(git show "$base:.github/maintainers.txt")
  if ! printf '%s\n' "$maintainers" | grep -Fxq "$approver"; then
    echo "error: breaking approval is not from a trusted maintainer: $approver" >&2
    exit 1
  fi

  approval_commit=$(git log -1 --format=%H "$base" -- "$approval")
  if ! git merge-base --is-ancestor "$approval_commit" "$commit"; then
    echo "error: breaking implementation must descend from the approval commit" >&2
    exit 1
  fi
done
