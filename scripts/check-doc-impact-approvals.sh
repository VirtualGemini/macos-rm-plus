#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. "$ROOT/scripts/lib/commit-message.sh"
. "$ROOT/scripts/lib/maintainers.sh"

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <base-sha> <head-sha>" >&2
  exit 2
fi

base=$1
head=$2
required_reviews=
maintainers=$(trusted_maintainers_from_ref "$base")
maintainer_count=$(printf '%s\n' "$maintainers" | count_maintainers)
sole_maintainer=$(printf '%s\n' "$maintainers" | sole_maintainer_login)

for commit in $(git rev-list --reverse "$base..$head"); do
  message=$(git show -s --format=%B "$commit")
  impact=$(message_trailer "$message" Docs-Impact)
  if [ "$impact" = "none" ]; then
    reviewer=$(message_trailer "$message" Docs-Impact-Approved-By)
    reviewer=${reviewer#@}
    required_reviews=$(printf '%s\n%s|%s\n' "$required_reviews" "$reviewer" "$commit")
  fi
done

if [ -z "$required_reviews" ]; then
  exit 0
fi

if [ -n "${DOCS_IMPACT_PR_AUTHOR-}" ] && [ -n "${DOCS_IMPACT_APPROVED_REVIEWS-}" ]; then
  pr_author=$DOCS_IMPACT_PR_AUTHOR
  approved_reviews=$DOCS_IMPACT_APPROVED_REVIEWS
else
  : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
  : "${PR_NUMBER:?PR_NUMBER is required}"
  : "${GH_TOKEN:?GH_TOKEN is required}"

  reviews=$(mktemp)
  trap 'rm -f "$reviews"' EXIT HUP INT TERM
  pr_author=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" --jq '.user.login')
  gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/reviews" \
    --jq '.[] | [.user.login, .state, .commit_id] | @tsv' >"$reviews"
  approved_reviews=$(awk '{ state[$1] = $2; commit[$1] = $3 } END { for (user in state) if (state[user] == "APPROVED") print user "|" commit[user] }' \
    "$reviews")
fi

failed=0

while IFS='|' read -r reviewer commit; do
  if [ -z "$reviewer" ]; then
    continue
  fi
  if [ "$maintainer_count" -eq 1 ] \
    && [ "$reviewer" = "$pr_author" ] \
    && [ "$reviewer" = "$sole_maintainer" ]; then
    continue
  fi
  if [ -n "${DOCS_IMPACT_COMMIT_AUTHOR-}" ]; then
    commit_author=$DOCS_IMPACT_COMMIT_AUTHOR
  else
    commit_author=$(gh api "repos/$GITHUB_REPOSITORY/commits/$commit" --jq '.author.login // empty')
  fi
  if [ -z "$commit_author" ]; then
    echo "error: cannot verify GitHub author for exempt commit $commit" >&2
    failed=1
  elif [ "$reviewer" = "$pr_author" ]; then
    echo "error: PR author @$reviewer cannot approve Docs-Impact: none" >&2
    failed=1
  elif [ "$reviewer" = "$commit_author" ]; then
    echo "error: commit author @$reviewer cannot approve their own Docs-Impact: none" >&2
    failed=1
  else
    review_commit=$(printf '%s\n' "$approved_reviews" | sed -n "s/^$reviewer|//p" | tail -1)
    if [ -z "$review_commit" ] || ! git merge-base --is-ancestor "$commit" "$review_commit"; then
    echo "error: Docs-Impact: none requires an active APPROVED review from @$reviewer" >&2
    failed=1
    fi
  fi
done <<EOF
$required_reviews
EOF

exit "$failed"
