#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu
base=$1
head=$2
merge_base=$(git merge-base "$base" "$head")
changed=$(git diff --name-only --diff-filter=ACMRD "$merge_base" "$head")
policy=$(git show "$base:.policy-files")
requires_approval=0
while IFS= read -r file; do
  while IFS= read -r pattern; do
    case "$pattern" in '' | \#*) continue ;; esac
    # shellcheck disable=SC2254
    case "$file" in $pattern) requires_approval=1 ;; esac
  done <<EOF
$policy
EOF
done <<EOF
$changed
EOF
[ "$requires_approval" -eq 1 ] || exit 0
: "${GITHUB_REPOSITORY:?}"; : "${PR_NUMBER:?}"; : "${GH_TOKEN:?}"
maintainers=$(git show "$base:.github/maintainers.txt")
approved=$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/reviews" \
  --jq '.[] | [.user.login, .state, .commit_id] | @tsv' \
  | awk -v head="$(git rev-parse "$head")" '$2 == "APPROVED" && $3 == head { print "@" $1 }')
for reviewer in $approved; do
  if printf '%s\n' "$maintainers" | grep -Fxq "$reviewer"; then exit 0; fi
done
echo "error: policy executor changes require trusted maintainer approval of the current PR head" >&2
exit 1
