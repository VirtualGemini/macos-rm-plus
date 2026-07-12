#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
base=$1
head=$2
merge_base=$(git merge-base "$base" "$head")
changed=$(git diff --name-only --diff-filter=ACMRD "$merge_base" "$head")
policy=$(git show "$base:.policy-files")
requires_approval=0

if git cat-file -e "$base:.coverage-metric-version" 2>/dev/null \
  && git cat-file -e "$head:.coverage-metric-version" 2>/dev/null; then
  base_metric=$(git show "$base:.coverage-metric-version")
  head_metric=$(git show "$head:.coverage-metric-version")
  if [ "$base_metric" != "$head_metric" ]; then
    while IFS= read -r file; do
      case "$file" in
        .coverage-baseline | .coverage-metric-version | CHANGELOG.md | docs/development.md) ;;
        *)
          echo "error: coverage metric migration must be a dedicated pull request: $file" >&2
          exit 1
          ;;
      esac
    done <<EOF
$changed
EOF
  fi
fi
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
maintainers=$(git show "$base:.github/maintainers.txt")
if [ -n "${POLICY_REVIEWS_TSV-}" ]; then
  reviews=$POLICY_REVIEWS_TSV
else
  : "${GITHUB_REPOSITORY:?}"; : "${PR_NUMBER:?}"; : "${GH_TOKEN:?}"
  reviews=$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/reviews" \
    --jq '.[] | [.user.login, .state, .commit_id] | @tsv')
fi
approved=$(printf '%s\n' "$reviews" | awk -v head="$(git rev-parse "$head")" '
  { state[$1] = $2; commit[$1] = $3 }
  END { for (user in state) if (state[user] == "APPROVED" && commit[user] == head) print "@" user }')
for reviewer in $approved; do
  if printf '%s\n' "$maintainers" | grep -Fxq "$reviewer"; then exit 0; fi
done
echo "error: policy executor changes require trusted maintainer approval of the current PR head" >&2
exit 1
