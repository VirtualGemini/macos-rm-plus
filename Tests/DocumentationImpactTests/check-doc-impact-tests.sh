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
mkdir -p "$repo/.github" "$repo/scripts/lib" "$repo/Sources/rmp"
cp "$ROOT/.docs-impact.yml" "$repo/.docs-impact.yml"
cp "$ROOT/.policy-files" "$repo/.policy-files"
cp "$ROOT/scripts/check-doc-impact.sh" "$repo/scripts/check-doc-impact.sh"
cp "$ROOT/scripts/check-doc-impact-approvals.sh" "$repo/scripts/check-doc-impact-approvals.sh"
cp "$ROOT/scripts/validate-commit-message.sh" "$repo/scripts/validate-commit-message.sh"
cp "$ROOT/scripts/lib/commit-message.sh" "$repo/scripts/lib/commit-message.sh"
cp "$ROOT/scripts/lib/maintainers.sh" "$repo/scripts/lib/maintainers.sh"

git -C "$repo" init -q
git -C "$repo" config user.name "Documentation Impact Tests"
git -C "$repo" config user.email "docs-impact-tests@example.invalid"

printf '%s\n' '# Test README' >"$repo/README.md"
printf '%s\n' '# Test spec' >"$repo/spec.md"
printf '%s\n' '# Test changelog' >"$repo/CHANGELOG.md"
printf '%s\n' '# Development' >"$repo/docs-development.md"
printf '%s\n' '// scaffold' >"$repo/Sources/rmp/main.swift"
printf '%s\n' '@example-reviewer' >"$repo/.github/maintainers.txt"

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

bootstrap_repo="$TEMP_DIR/bootstrap-repo"
mkdir -p "$bootstrap_repo/scripts/lib" "$bootstrap_repo/Sources/rmp"
cp "$ROOT/scripts/check-doc-impact.sh" "$bootstrap_repo/scripts/check-doc-impact.sh"
cp "$ROOT/scripts/lib/commit-message.sh" "$bootstrap_repo/scripts/lib/commit-message.sh"
printf '%s\n' '# Bootstrap spec' >"$bootstrap_repo/spec.md"
printf '%s\n' '// initial CLI' >"$bootstrap_repo/Sources/rmp/main.swift"
git -C "$bootstrap_repo" init -q
git -C "$bootstrap_repo" config user.name "Documentation Impact Tests"
git -C "$bootstrap_repo" config user.email "docs-impact-tests@example.invalid"
git -C "$bootstrap_repo" add .
git -C "$bootstrap_repo" commit -qm "chore: create bootstrap fixture"
bootstrap_base=$(git -C "$bootstrap_repo" rev-parse HEAD)

printf '%s\n' '// changed CLI' >"$bootstrap_repo/Sources/rmp/main.swift"
cat >"$bootstrap_repo/.docs-impact.yml" <<'EOF'
{
  "rules": [
    {
      "name": "cli-contract",
      "paths": ["Sources/rmp/**"],
      "documents": ["spec.md"],
      "require": "all"
    }
  ]
}
EOF
git -C "$bootstrap_repo" add .docs-impact.yml Sources/rmp/main.swift
git -C "$bootstrap_repo" commit -qm "ci: initialize documentation policy" \
  -m "Docs-Impact: updated"
bootstrap_head=$(git -C "$bootstrap_repo" rev-parse HEAD)

if ! "$bootstrap_repo/scripts/check-doc-impact.sh" --commit "$bootstrap_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  cat "$TEMP_DIR/stderr" >&2
  fail "commit validation applied the newly introduced matrix to its bootstrap commit"
fi

if ! "$bootstrap_repo/scripts/check-doc-impact.sh" --range "$bootstrap_base" "$bootstrap_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  cat "$TEMP_DIR/stderr" >&2
  fail "range validation applied the newly introduced matrix before it became trusted"
fi

git -C "$bootstrap_repo" switch -q --detach "$bootstrap_base"
printf '%s\n' '// staged CLI change' >"$bootstrap_repo/Sources/rmp/main.swift"
git -C "$bootstrap_repo" show "$bootstrap_head:.docs-impact.yml" \
  >"$bootstrap_repo/.docs-impact.yml"
git -C "$bootstrap_repo" add .docs-impact.yml Sources/rmp/main.swift
cat >"$TEMP_DIR/bootstrap-message" <<'EOF'
ci: initialize documentation policy

Docs-Impact: updated
EOF
if ! "$bootstrap_repo/scripts/check-doc-impact.sh" --staged \
  --message-file "$TEMP_DIR/bootstrap-message" >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  cat "$TEMP_DIR/stderr" >&2
  fail "staged validation applied an uncommitted matrix before it became trusted"
fi

git -C "$bootstrap_repo" commit -qm "ci: initialize staged documentation policy" \
  -m "Docs-Impact: updated"
initialized_head=$(git -C "$bootstrap_repo" rev-parse HEAD)
printf '%s\n' '// later CLI change' >"$bootstrap_repo/Sources/rmp/main.swift"
git -C "$bootstrap_repo" add Sources/rmp/main.swift
git -C "$bootstrap_repo" commit -qm "feat: change CLI after policy initialization" \
  -m "Docs-Impact: updated"
post_initialization_head=$(git -C "$bootstrap_repo" rev-parse HEAD)

if "$bootstrap_repo/scripts/check-doc-impact.sh" --commit "$post_initialization_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "commit validation did not enforce the initialized matrix on a subsequent commit"
fi
assert_contains "$TEMP_DIR/stderr" "documentation rule 'cli-contract'"

if "$bootstrap_repo/scripts/check-doc-impact.sh" --range \
  "$initialized_head" "$post_initialization_head" >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "range validation did not enforce the initialized matrix from its trusted base"
fi
assert_contains "$TEMP_DIR/stderr" "documentation rule 'cli-contract'"

git -C "$bootstrap_repo" switch -q --detach "$initialized_head"
printf '%s\n' '// later staged CLI change' >"$bootstrap_repo/Sources/rmp/main.swift"
git -C "$bootstrap_repo" add Sources/rmp/main.swift
cat >"$TEMP_DIR/post-initialization-message" <<'EOF'
feat: change CLI after policy initialization

Docs-Impact: updated
EOF
if "$bootstrap_repo/scripts/check-doc-impact.sh" --staged \
  --message-file "$TEMP_DIR/post-initialization-message" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "staged validation did not enforce the initialized HEAD matrix"
fi
assert_contains "$TEMP_DIR/stderr" "documentation rule 'cli-contract'"

registry_base=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' '# weakened registry' >"$repo/.policy-files"
git -C "$repo" add .policy-files
git -C "$repo" commit -qm "ci: weaken policy registry" \
  -m "Docs-Impact: updated"
printf '%s\n' '# disabled' >"$repo/scripts/check-doc-impact-approvals.sh"
git -C "$repo" add scripts/check-doc-impact-approvals.sh
git -C "$repo" commit -qm "ci: disable approval gate" \
  -m "Docs-Impact: none
Docs-Impact-Reason: invalid exemption
Docs-Impact-Approved-By: @example-reviewer"
registry_head=$(git -C "$repo" rev-parse HEAD)

if "$repo/scripts/check-doc-impact.sh" --range "$registry_base" "$registry_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "PR validation trusted a policy registry weakened earlier in the PR"
fi
assert_contains "$TEMP_DIR/stderr" "cannot use Docs-Impact: none"
git -C "$repo" switch -q --detach "$head"

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

BREAKING CHANGE: consumers must migrate
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

if ! DOCS_IMPACT_PR_AUTHOR=example-reviewer DOCS_IMPACT_COMMIT_AUTHOR=example-reviewer \
  DOCS_IMPACT_APPROVED_REVIEWS="another-reviewer|$approval_head" \
  "$repo/scripts/check-doc-impact-approvals.sh" "$approval_base" "$approval_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  cat "$TEMP_DIR/stderr" >&2
  fail "PR validation rejected a documentation exemption from the sole maintainer"
fi

if DOCS_IMPACT_PR_AUTHOR=example-contributor DOCS_IMPACT_COMMIT_AUTHOR=example-reviewer \
  DOCS_IMPACT_APPROVED_REVIEWS="another-reviewer|$approval_head" \
  "$repo/scripts/check-doc-impact-approvals.sh" "$approval_base" "$approval_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "untrusted PR author bypassed approval by using the maintainer's commit identity"
fi
assert_contains "$TEMP_DIR/stderr" \
  "commit author @example-reviewer cannot approve their own Docs-Impact: none"

git -C "$repo" switch -q --detach "$approval_base"
printf '%s\n' '# contributor fixture' >"$repo/contributor.txt"
git -C "$repo" add contributor.txt
git -C "$repo" commit -qm "refactor: add contributor fixture" \
  -m "Docs-Impact: none
Docs-Impact-Reason: no documented behavior changed
Docs-Impact-Approved-By: @example-contributor"
contributor_head=$(git -C "$repo" rev-parse HEAD)

if DOCS_IMPACT_PR_AUTHOR=example-contributor DOCS_IMPACT_COMMIT_AUTHOR=example-contributor \
  DOCS_IMPACT_APPROVED_REVIEWS="another-reviewer|$contributor_head" \
  "$repo/scripts/check-doc-impact-approvals.sh" "$approval_base" "$contributor_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "untrusted PR author self-approved a documentation exemption"
fi
assert_contains "$TEMP_DIR/stderr" \
  "PR author @example-contributor cannot approve Docs-Impact: none"

git -C "$repo" switch -q --detach "$approval_base"
printf '%s\n' '@second-maintainer' >>"$repo/.github/maintainers.txt"
git -C "$repo" add .github/maintainers.txt
git -C "$repo" commit -qm "chore: add second maintainer"
multi_maintainer_base=$(git -C "$repo" rev-parse HEAD)
printf '%s\n' '# multi-maintainer fixture' >"$repo/multi-maintainer.txt"
git -C "$repo" add multi-maintainer.txt
git -C "$repo" commit -qm "refactor: add multi-maintainer fixture" \
  -m "Docs-Impact: none
Docs-Impact-Reason: no documented behavior changed
Docs-Impact-Approved-By: @example-reviewer"
multi_maintainer_head=$(git -C "$repo" rev-parse HEAD)

if DOCS_IMPACT_PR_AUTHOR=example-reviewer DOCS_IMPACT_COMMIT_AUTHOR=example-reviewer \
  DOCS_IMPACT_APPROVED_REVIEWS="another-reviewer|$multi_maintainer_head" \
  "$repo/scripts/check-doc-impact-approvals.sh" \
  "$multi_maintainer_base" "$multi_maintainer_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "maintainer self-approved while another maintainer was available"
fi
assert_contains "$TEMP_DIR/stderr" "PR author @example-reviewer cannot approve Docs-Impact: none"
git -C "$repo" switch -q --detach "$approval_head"

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

coverage_repo="$TEMP_DIR/coverage-repo"
mkdir -p "$coverage_repo/scripts/lib" "$coverage_repo/docs"
cp "$ROOT/.docs-impact.yml" "$coverage_repo/.docs-impact.yml"
cp "$ROOT/.policy-files" "$coverage_repo/.policy-files"
cp "$ROOT/scripts/check-doc-impact.sh" "$coverage_repo/scripts/"
cp "$ROOT/scripts/lib/commit-message.sh" "$coverage_repo/scripts/lib/"
printf '%s\n' '0.00' >"$coverage_repo/.coverage-baseline"
printf '%s\n' '1' >"$coverage_repo/.coverage-metric-version"
printf '%s\n' '# Development' >"$coverage_repo/docs/development.md"
printf '%s\n' '# Changelog' >"$coverage_repo/CHANGELOG.md"
git -C "$coverage_repo" init -q
git -C "$coverage_repo" config user.name Tests
git -C "$coverage_repo" config user.email tests@example.invalid
git -C "$coverage_repo" add .
git -C "$coverage_repo" commit -qm base
coverage_base=$(git -C "$coverage_repo" rev-parse HEAD)
printf '%s\n' '2' >"$coverage_repo/.coverage-metric-version"
git -C "$coverage_repo" add .coverage-metric-version
git -C "$coverage_repo" commit -qm "ci: change coverage metric" -m "Docs-Impact: updated"
coverage_head=$(git -C "$coverage_repo" rev-parse HEAD)

if "$coverage_repo/scripts/check-doc-impact.sh" --range "$coverage_base" "$coverage_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "coverage metric change passed without development documentation and changelog updates"
fi
assert_contains "$TEMP_DIR/stderr" "docs/development.md"
assert_contains "$TEMP_DIR/stderr" "CHANGELOG.md"

git -C "$coverage_repo" switch -q --detach "$coverage_base"
printf '%s\n' '1.00' >"$coverage_repo/.coverage-baseline"
git -C "$coverage_repo" add .coverage-baseline
git -C "$coverage_repo" commit -qm "ci: change coverage baseline" -m "Docs-Impact: updated"
baseline_head=$(git -C "$coverage_repo" rev-parse HEAD)
if "$coverage_repo/scripts/check-doc-impact.sh" --range "$coverage_base" "$baseline_head" \
  >"$TEMP_DIR/stdout" 2>"$TEMP_DIR/stderr"; then
  fail "coverage baseline change passed without development documentation"
fi
assert_contains "$TEMP_DIR/stderr" "docs/development.md"

echo "Documentation impact tests passed."
