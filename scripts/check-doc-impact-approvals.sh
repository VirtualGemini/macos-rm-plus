#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <base-sha> <head-sha>" >&2
  exit 2
fi

base=$1
head=$2
required_reviewers=

for commit in $(git rev-list --reverse "$base..$head"); do
  message=$(git show -s --format=%B "$commit")
  impact=$(printf '%s\n' "$message" | sed -n 's/^Docs-Impact: //p' | tail -1)
  if [ "$impact" = "none" ]; then
    reviewer=$(printf '%s\n' "$message" \
      | sed -n 's/^Docs-Impact-Approved-By: @//p' \
      | tail -1)
    required_reviewers="$required_reviewers $reviewer"
  fi
done

if [ -z "$required_reviewers" ]; then
  exit 0
fi

if [ -n "${DOCS_IMPACT_PR_AUTHOR-}" ] && [ -n "${DOCS_IMPACT_APPROVED_REVIEWERS-}" ]; then
  pr_author=$DOCS_IMPACT_PR_AUTHOR
  approved_reviewers=$DOCS_IMPACT_APPROVED_REVIEWERS
else
  : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
  : "${PR_NUMBER:?PR_NUMBER is required}"
  : "${GH_TOKEN:?GH_TOKEN is required}"

  reviews=$(mktemp)
  trap 'rm -f "$reviews"' EXIT HUP INT TERM
  pr_author=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" --jq '.user.login')
  gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/reviews" \
    --jq '.[] | [.user.login, .state] | @tsv' >"$reviews"
  approved_reviewers=$(awk '{ state[$1] = $2 } END { for (user in state) if (state[user] == "APPROVED") print user }' \
    "$reviews")
fi

failed=0

for reviewer in $required_reviewers; do
  if [ "$reviewer" = "$pr_author" ]; then
    echo "error: PR author @$reviewer cannot approve Docs-Impact: none" >&2
    failed=1
  elif ! printf '%s\n' "$approved_reviewers" | grep -Fxq "$reviewer"; then
    echo "error: Docs-Impact: none requires an active APPROVED review from @$reviewer" >&2
    failed=1
  fi
done

exit "$failed"
