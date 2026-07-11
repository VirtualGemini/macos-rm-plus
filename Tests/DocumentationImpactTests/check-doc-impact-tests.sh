#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-doc-impact-tests.XXXXXX")

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "test failure: $1" >&2
  exit 1
}

assert_contains() {
  file=$1
  expected=$2
  if ! grep -Fq "$expected" "$file"; then
    cat "$file" >&2
    fail "expected output to contain: $expected"
  fi
}

repo="$TEMP_DIR/repo"
mkdir -p "$repo/scripts/lib" "$repo/Sources/rmp"
cp "$ROOT/.docs-impact.yml" "$repo/.docs-impact.yml"
cp "$ROOT/.policy-files" "$repo/.policy-files"
cp "$ROOT/scripts/check-doc-impact.sh" "$repo/scripts/check-doc-impact.sh"
cp "$ROOT/scripts/check-doc-impact-approvals.sh" "$repo/scripts/check-doc-impact-approvals.sh"
cp "$ROOT/scripts/validate-commit-message.sh" "$repo/scripts/validate-commit-message.sh"
cp "$ROOT/scripts/lib/commit-message.sh" "$repo/scripts/lib/commit-message.sh"

git -C "$repo" init -q
git -C "$repo" config user.name "Documentation Impact Tests"
git -C "$repo" config user.email "docs-impact-tests@example.invalid"

printf '%s\n' '# Test README' >"$repo/README.md"
printf '%s\n' '# Test spec' >"$repo/spec.md"
printf '%s\n' '# Test changelog' >"$repo/CHANGELOG.md"
printf '%s\n' '# Development' >"$repo/docs-development.md"
printf '%s\n' '// scaffold' >"$repo/Sources/rmp/main.swift"

cat >"$repo/.docs-impact.yml" <<'EOF'
{
  "rules": [
    {
      "name": "cli-contract",
      "paths": ["Sources/rmp/**"],
      "documents": ["README.md", "spec.md", "CHANGELOG.md"],
      "require": "all"
    }
  ]
}
EOF

git -C "$repo" add .
git -C "$repo" commit -qm "chore: create fixture"
base=$(git -C "$repo" rev-parse HEAD)

printf '%s\n' '// changed behavior' >"$repo/Sources/rmp/main.swift"
git -C "$repo" add Sources/rmp/main.swift
git -C "$repo" commit -qm "feat: change CLI behavior" \
  -m "Docs-Impact: updated"
head=$(git -C "$repo" rev-parse HEAD)

if "$repo/scripts/check-doc-impact.sh" --range "$base" "$head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "PR-range validation accepted a CLI change without all required documents"
fi

assert_contains "$TEMP_DIR/stderr" "documentation rule 'cli-contract'"
assert_contains "$TEMP_DIR/stderr" "README.md"
assert_contains "$TEMP_DIR/stderr" "spec.md"
assert_contains "$TEMP_DIR/stderr" "CHANGELOG.md"

deletion_base=$head
git -C "$repo" rm -q Sources/rmp/main.swift
git -C "$repo" commit -qm "refactor: remove CLI entrypoint" \
  -m "Docs-Impact: updated"
deletion_head=$(git -C "$repo" rev-parse HEAD)

if "$repo/scripts/check-doc-impact.sh" --range "$deletion_base" "$deletion_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "PR-range validation ignored a deleted CLI file"
fi
assert_contains "$TEMP_DIR/stderr" "documentation rule 'cli-contract'"

cat >"$TEMP_DIR/invalid-approval-message" <<'EOF'
refactor: reorganize internals

Signed-off-by: Example Author <author@example.invalid>
Docs-Impact: none
Docs-Impact-Reason: behavior is unchanged
Docs-Impact-Approved-By: Example Reviewer
EOF

if "$repo/scripts/validate-commit-message.sh" "$TEMP_DIR/invalid-approval-message" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "commit validation accepted a non-GitHub documentation approver"
fi
assert_contains "$TEMP_DIR/stderr" "requires Docs-Impact-Approved-By"

cat >"$TEMP_DIR/footer-breaking-message" <<'EOF'
feat: change public contract

BREAKING-CHANGE: consumers must migrate
Signed-off-by: Example Author <author@example.invalid>
Docs-Impact: none
Docs-Impact-Reason: incorrectly claimed exemption
Docs-Impact-Approved-By: @example-reviewer
EOF

if "$repo/scripts/validate-commit-message.sh" "$TEMP_DIR/footer-breaking-message" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "commit validation accepted Docs-Impact: none with a BREAKING-CHANGE footer"
fi
assert_contains "$TEMP_DIR/stderr" "breaking changes cannot declare Docs-Impact: none"

approval_base=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' '# internal fixture' >"$repo/internal.txt"
git -C "$repo" add internal.txt
git -C "$repo" commit -qm "refactor: add internal fixture" \
  -m "Docs-Impact: none
Docs-Impact-Reason: no documented behavior changed
Docs-Impact-Approved-By: @example-reviewer"
approval_head=$(git -C "$repo" rev-parse HEAD)

if DOCS_IMPACT_PR_AUTHOR=example-author DOCS_IMPACT_COMMIT_AUTHOR=example-author \
  DOCS_IMPACT_APPROVED_REVIEWS="another-reviewer|$approval_head" \
  "$repo/scripts/check-doc-impact-approvals.sh" "$approval_base" "$approval_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "PR validation accepted a documentation exemption without the named approving review"
fi
assert_contains "$TEMP_DIR/stderr" "active APPROVED review from @example-reviewer"

DOCS_IMPACT_PR_AUTHOR=example-author DOCS_IMPACT_COMMIT_AUTHOR=example-author \
  DOCS_IMPACT_APPROVED_REVIEWS="example-reviewer|$approval_head" \
  "$repo/scripts/check-doc-impact-approvals.sh" "$approval_base" "$approval_head"

trusted_base=$(git -C "$repo" rev-parse HEAD)
mkdir -p "$repo/Sources/rmp"
printf '%s\n' '// restored CLI' >"$repo/Sources/rmp/main.swift"
printf '%s\n' '{"rules":[]}' >"$repo/.docs-impact.yml"
git -C "$repo" add .docs-impact.yml Sources/rmp/main.swift
git -C "$repo" commit -qm "ci: weaken documentation policy" \
  -m "Docs-Impact: updated"
untrusted_head=$(git -C "$repo" rev-parse HEAD)

if "$repo/scripts/check-doc-impact.sh" --range "$trusted_base" "$untrusted_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "PR validation trusted a documentation matrix weakened by the PR itself"
fi
assert_contains "$TEMP_DIR/stderr" "documentation rule 'cli-contract'"

none_repo="$TEMP_DIR/none-repo"
mkdir -p "$none_repo/scripts/lib" "$none_repo/Sources/rmp"
cp "$repo/scripts/check-doc-impact.sh" "$none_repo/scripts/check-doc-impact.sh"
cp "$repo/scripts/lib/commit-message.sh" "$none_repo/scripts/lib/commit-message.sh"
cp "$repo/.policy-files" "$none_repo/.policy-files"
cp "$repo/.docs-impact.yml" "$none_repo/.docs-impact.yml"
cat >"$none_repo/.docs-impact.yml" <<'EOF'
{
  "rules": [
    {
      "name": "cli-contract",
      "paths": ["Sources/rmp/**"],
      "documents": ["README.md"],
      "require": "all"
    }
  ]
}
EOF
printf '%s\n' '# README' >"$none_repo/README.md"
printf '%s\n' '// initial' >"$none_repo/Sources/rmp/main.swift"
git -C "$none_repo" init -q
git -C "$none_repo" config user.name "Documentation Impact Tests"
git -C "$none_repo" config user.email "docs-impact-tests@example.invalid"
git -C "$none_repo" add .
git -C "$none_repo" commit -qm "chore: create none fixture"
none_base=$(git -C "$none_repo" rev-parse HEAD)
printf '%s\n' '// internal refactor' >"$none_repo/Sources/rmp/main.swift"
git -C "$none_repo" add Sources/rmp/main.swift
git -C "$none_repo" commit -qm "refactor: preserve CLI behavior" \
  -m "Docs-Impact: none
Docs-Impact-Reason: public behavior is unchanged
Docs-Impact-Approved-By: @example-reviewer"
none_head=$(git -C "$none_repo" rev-parse HEAD)

if ! "$none_repo/scripts/check-doc-impact.sh" --range "$none_base" "$none_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  cat "$TEMP_DIR/stderr" >&2
  fail "aggregate PR validation rejected an approved Docs-Impact: none change"
fi

policy_base=$none_head
printf '%s\n' '{"rules":[]}' >"$none_repo/.docs-impact.yml"
git -C "$none_repo" add .docs-impact.yml
git -C "$none_repo" commit -qm "ci: remove documentation rules" \
  -m "Docs-Impact: none
Docs-Impact-Reason: incorrectly claimed policy exemption
Docs-Impact-Approved-By: @example-reviewer"
policy_head=$(git -C "$none_repo" rev-parse HEAD)

if "$none_repo/scripts/check-doc-impact.sh" --range "$policy_base" "$policy_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "aggregate PR validation allowed Docs-Impact: none to weaken its own policy"
fi
assert_contains "$TEMP_DIR/stderr" "cannot use Docs-Impact: none"

echo "Documentation impact tests passed."
