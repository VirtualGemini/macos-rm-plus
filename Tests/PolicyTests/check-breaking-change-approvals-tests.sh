#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-breaking-approval-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

repo="$TEMP_DIR/repo"
mkdir -p "$repo/scripts/lib" "$repo/.github" "$repo/.scratch/change/issues"
cp "$ROOT/scripts/check-breaking-change-approvals.sh" "$repo/scripts/"
cp "$ROOT/scripts/lib/commit-message.sh" "$repo/scripts/lib/"
printf '%s\n' '@VirtualGemini' >"$repo/.github/maintainers.txt"
cat >"$repo/.scratch/change/issues/01-approved.md" <<'EOF'
Breaking change: yes
Approval: approved
Approved by: @VirtualGemini
Approved at: 2026-07-12
Migration plan: update callers
EOF

git -C "$repo" init -q
git -C "$repo" config user.name "Policy Tests"
git -C "$repo" config user.email "policy-tests@example.invalid"
git -C "$repo" add .
GIT_AUTHOR_DATE='2026-07-12T00:00:00Z' GIT_COMMITTER_DATE='2026-07-12T00:00:00Z' \
  git -C "$repo" commit -qm "docs: approve breaking change"
base=$(git -C "$repo" rev-parse HEAD)

printf '%s\n' 'breaking implementation' >"$repo/implementation.txt"
git -C "$repo" add implementation.txt
GIT_AUTHOR_DATE='2026-07-12T01:00:00Z' GIT_COMMITTER_DATE='2026-07-12T01:00:00Z' \
  git -C "$repo" commit -qm "feat!: change contract" \
  -m "BREAKING-CHANGE: update callers" \
  -m "Breaking-Approval: .scratch/change/issues/01-approved.md"
head=$(git -C "$repo" rev-parse HEAD)

"$repo/scripts/check-breaking-change-approvals.sh" "$base" "$head"

printf '%s\n' '@SomeoneElse' >"$repo/.github/maintainers.txt"
git -C "$repo" add .github/maintainers.txt
git -C "$repo" commit -qm "chore: change trusted maintainers"
untrusted_base=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' 'second break' >>"$repo/implementation.txt"
git -C "$repo" add implementation.txt
git -C "$repo" commit -qm "feat!: change contract again" \
  -m "BREAKING-CHANGE: update callers again" \
  -m "Breaking-Approval: .scratch/change/issues/01-approved.md"
untrusted_head=$(git -C "$repo" rev-parse HEAD)

if "$repo/scripts/check-breaking-change-approvals.sh" "$untrusted_base" "$untrusted_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  echo "test failure: untrusted maintainer approval was accepted" >&2
  exit 1
fi
grep -Fq "not from a trusted maintainer" "$TEMP_DIR/stderr"

echo "Breaking-change approval tests passed."
