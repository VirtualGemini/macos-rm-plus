# Development Guide

This document is the single source of truth for developing, testing, reviewing, committing, and
releasing rmp. Pull requests must update it when they change the development workflow.

## 1. Toolchain

- Language mode: Swift 6.
- Package manifest: `swift-tools-version: 6.0`.
- Latest upstream toolchain verification: Swift 6.3.3.
- macOS integration builds use the Apple Swift toolchain bundled with the selected Xcode or Command
  Line Tools installation.
- Minimum deployment target: macOS 13.
- Package manager: Swift Package Manager.
- Test framework: Swift Testing only.
- Runtime dependencies: none in v0.1.

Pinned development-tool versions are recorded in `.tool-versions.lock`:

- SwiftLint 0.65.0 from the official `realm/SwiftLint` repository;
- ShellCheck 0.11.0;
- actionlint 1.7.12;
- `actions/checkout` pinned to its full reviewed commit SHA.

`swift-format` comes from the active Swift toolchain so that its SwiftSyntax version remains aligned
with the compiler.

`.tool-versions.lock` is the authoritative source for development-tool versions and checksums.
Shell tooling reads it through `scripts/lib/tool-versions.sh`; the consistency gate verifies the
SwiftLint version duplicated by necessity in the SwiftPM manifest.

The unit-test command explicitly supplies the active developer directory's Testing framework and
interop-library paths at compile and runtime. This keeps Swift Testing discoverable in both full
Xcode and Command Line Tools installations without adding a third-party testing dependency.

## 2. Dependency policy

- Third-party runtime dependencies are prohibited in v0.1.
- Development dependencies must use an exact version.
- `Package.resolved` is committed.
- Branch, floating `latest`, and unpublished commit dependencies are prohibited.
- A new dependency proposal must state its purpose, license, maintenance status, alternatives, and
  removal cost.
- New runtime dependencies require maintainer approval before implementation starts.
- Dependency upgrades use a dedicated pull request and are never mixed with feature work.
- Automated dependency tools may open pull requests but may not merge them.
- CI rejects uncommitted resolution-file changes.

## 3. Project structure

```text
Sources/
├── RMPCore/          Pure parsing, planning, safety policy, and output models
├── RMPPlatform/      macOS Foundation adapters
└── rmp/              Production command-line entrypoint

TestSupport/
├── RMPTestKit/       Fakes, spies, and test safety support
└── rmp-test/         Compile-time-isolated real-filesystem test entrypoint

Tests/
├── RMPCoreTests/
└── RMPPlatformTests/
```

The architectural decision is recorded in
[`docs/adr/0001-separate-core-platform-and-cli.md`](adr/0001-separate-core-platform-and-cli.md).

`RMPCore` must not invoke the filesystem, terminal, clock, environment, or Foundation Trash API
directly. Those capabilities cross explicit interfaces implemented in `RMPPlatform`.

Trash Plan previews follow the same boundary: `RMPCore` receives only injected top-level entry and
directory-identity inspection capabilities, while `RMPPlatform` supplies the read-only Foundation
adapter. The production dry-run path has no Trash, move, overwrite, or deletion capability.

## 4. Canonical language

- Code identifiers, code comments, commit messages, pull-request titles, CLI text, JSON contracts,
  ADRs, and development documentation use English.
- Chinese documentation may be provided as a supplementary translation.
- The current PRD may remain in Chinese; implementation tickets use English.
- Canonical domain terms are defined in `CONTEXT.md`.

## 5. Coding standards

### 5.1 Formatting and linting

- `swift-format` is the only Swift formatter.
- SwiftLint supplies a small safety-focused semantic rule set.
- The lint wrapper executes SwiftLint's resolved binary artifact without `--fix` and supplies both
  Xcode and Command Line Tools SourceKit framework locations so it works with either active developer
  directory.
- CI checks formatting and never rewrites source files.
- Developers run `make format` explicitly.
- Swift source, shell scripts, and other source-like files carry an Apache-2.0 SPDX identifier where
  the format supports comments.

### 5.2 Swift design

- Default to `internal`; expose only deliberate module interfaces.
- Prefer `struct`, `enum`, immutable `let`, and value semantics.
- Use `final class` only when reference semantics are required.
- Global mutable state and business singletons are prohibited.
- Inject dependencies through initializers.
- Keep system time, filesystem, terminal, environment, and Trash access behind explicit interfaces.
- A function has one nameable responsibility. Mechanical line limits do not replace design review.
- Introduce an abstraction only when it has two real consumers or establishes a deliberate safety
  boundary.
- Comments explain why a decision exists rather than narrating code.
- Tests must not force production internals to become broadly public.

### 5.3 Error handling

- Production code prohibits `try!`, forced casts, forced unwraps, implicitly unwrapped optionals, and
  unconditional `fatalError`.
- `RMPCore` uses typed errors.
- Foundation `NSError` values remain inside `RMPPlatform` and are mapped to stable core error codes.
- Human-readable error messages are separate from machine-readable codes.
- Empty `catch` blocks and print-then-continue error handling are prohibited.
- Each error is explicitly classified as ignored, item failure with continuation, operation-stopping
  failure, or safety-policy rejection.
- Program flow must not depend on parsing error-message strings.
- Assertions express programmer invariants only and never replace runtime safety checks.

### 5.4 Concurrency

- Swift 6 language mode and complete strict-concurrency checking are required.
- Swift 6 language mode enables complete strict-concurrency checking by default; do not weaken it
  with target-specific flags.
- Compiler warnings are errors in CI.
- v0.1 Trash operations are synchronous and serial.
- `Task.detached` and unconstrained parallel filesystem work are prohibited.
- Async behavior is introduced only for a measured requirement and requires design review.

## 6. Testing standards

### 6.1 Framework and coverage

- Swift Testing is the only test framework.
- The safe pure-test command currently runs the complete suite with `--no-parallel`, guaranteeing
  platform-test serialization. Parallel core-only execution may be introduced later through a
  separate command that cannot include platform or real-filesystem suites.
- Every `FR-SAFE-*` and `FR-TEST-*` requirement has at least one corresponding test.
- Every safety rejection proves the expected error, no filesystem change, and zero TrashClient calls.
- Parameter parsing uses a behavior matrix rather than isolated happy-path tests.
- Bug fixes begin with a failing regression test.
- Unit tests collect coverage and CI publishes an `llvm-cov` summary, but no global percentage
  substitutes for requirement and branch coverage. Coverage must not decrease without an approved
  explanation.
- `.coverage-baseline` records the minimum line coverage. PR CI reads that file from the trusted
  target SHA, so a PR cannot lower its own threshold. A deliberate reduction requires a separately
  reviewed baseline change on the target branch before the implementation PR. An upward ratchet is
  governed by the same policy-executor approval rules as every other policy file; the coverage gate
  independently requires the declared value to equal the measured production coverage.
- `.coverage-metric-version` identifies the measurement definition. Changing which binaries or
  source classes count requires incrementing it and establishes a new reviewed baseline; subsequent
  PRs are compared only within that metric version.
- Documentation-impact checks require every baseline or coverage-report change to update this guide.
  A metric-version change must update both this guide and `CHANGELOG.md` because it changes the
  interpretation of reported coverage.
- Coverage includes production executables as additional `llvm-cov` objects; test-only coverage
  cannot hide newly added untested CLI code.
- SafetyPolicy, option parsing, and test-whitelist branches may not remain untested.
- Protected Path planning tests use fake filesystem identities. They must not launch `rmp` with a
  system path, a real home directory, or user-data path merely to prove a safety rejection.

### 6.2 Safe default commands

```sh
make test
make test-unit
```

These commands run pure tests only. They must never invoke the real macOS Trash API.

### 6.3 Real-filesystem whitelist

The complete normative requirements are in the PRD. The essential boundary is:

```text
~/rmp-test                         Never an rmp target
~/rmp-test/test                    Never an rmp target
~/rmp-test/test/<run-uuid>         Never an rmp target
~/rmp-test/test/<run-uuid>/...     The only authorized fixture area
```

Real-filesystem tests:

- use the compile-time `RMP_TESTING` executable `rmp-test`;
- require `--test-run-id <uuid>`;
- use `0700` directories, `0600` marker files, device/inode identity checks, and retained directory
  descriptors;
- reject symbolic-link escapes, mount points, cross-volume paths, network volumes, and File Provider
  roots;
- prefix fixture basenames with `rmp-test-<run-uuid>-`;
- run serially;
- never receive `/`, a real home directory, the working directory, or system directories;
- never clean the user's Trash by name or with a permanent-delete API.

Assertions should expose mistakes early, but every assertion has a non-optional `guard` or typed
error enforcing the same boundary in optimized builds.

The compile-time-isolated `rmp-test` entrypoint supplies the `RMP_TESTING` build identity; production
targets cannot enable it. The driver establishes the Test Safety Context before exposing path
arguments to downstream test work. It derives the loaded executable path from macOS rather than
trusting `argv[0]`, obtains the effective user's home from the system account database, rejects root or the wrong executable identity,
exclusively creates UUID Run Directories, and retains open
descriptors for all three safety directories. Versioned JSON markers record their directory role and
device/inode identity; the run marker additionally records the UUID and all three directory
identities. Existing directories and markers are validated without following symbolic links and are
never repaired automatically.

Test-safety failures use stable `test-safety.*` diagnostic codes. Local cleanup revalidates the full
hierarchy, removes only the matching run marker, and uses non-recursive `rmdir` semantics only when
the Run Directory has no Test Fixtures. The two fixed directories and their long-lived markers are
never removed automatically after they have been atomically published. New safety directories and
their markers are prepared under random staging names and become fixed boundaries only when an
exclusive rename publishes the complete directory. A failed preparation removes its unpublished
staging directory and marker so that a safety rejection leaves no filesystem change.

The project still contains no real Trash integration. `make test-integration` must fail closed until
the WhitelistedTrashClient ticket is complete.

## 7. Development commands

```sh
make bootstrap          Check toolchain and resolve pinned development dependencies
make hooks-install      Install the repository's versioned Git hooks
make format             Format Swift source
make format-check       Check Swift formatting
make lint               Run SwiftLint
make lint-scripts       Run ShellCheck
make lint-actions       Run actionlint
make build              Build every package target in Debug
make build-release      Build every package target in Release
make test               Run safe pure tests
make test-unit          Run safe pure tests
make coverage-report    Publish the latest unit-test coverage summary
make test-policy        Test repository policy scripts through their public interfaces
make test-integration   Run the guarded integration entrypoint
make check              Run all non-destructive local gates
make ci                 Run the CI-equivalent non-destructive gates
make clean              Clean SwiftPM build products only
```

Hooks and validation scripts never download dependencies. The explicitly invoked `make bootstrap`
command may download only the pinned, checksum-verified development tools recorded in
`.tool-versions.lock` and resolve the exact SwiftPM development dependency.

## 8. Git hooks and quality gates

Install hooks with:

```sh
make hooks-install
```

This sets `core.hooksPath` to `.githooks`. Cloning the repository never modifies Git configuration
automatically.

### pre-commit

- format check;
- SwiftLint;
- ShellCheck and actionlint;
- SPDX validation;
- dangerous real-test command scan;

### commit-msg

- Conventional Commit syntax;
- non-empty scope when parentheses are present;
- DCO `Signed-off-by` trailer;
- documentation-impact trailers;
- breaking-change approval and migration trailers.

### pre-push

- Debug and Release build;
- pure unit tests;
- no real Trash integration.

CI repeats all enforceable checks. Local hooks are convenience and may never be the only gate.
The documentation-impact checker is a POSIX shell command and uses macOS `plutil` to read the
JSON-compatible `.docs-impact.yml`; hooks do not compile helper programs on demand.

## 9. Commit convention

Allowed types:

```text
feat fix build refactor style chore test docs perf ci revert
```

Scope is optional, but empty parentheses are invalid:

```text
feat: add dry-run planning
feat(cli): add dry-run planning
feat(): invalid
```

Every commit contains:

```text
Signed-off-by: Name <email>
Docs-Impact: updated
```

When documentation is unaffected:

```text
Docs-Impact: none
Docs-Impact-Reason: internal refactor with unchanged behavior
Docs-Impact-Approved-By: @reviewer-login
```

The documentation-impact approver must be a reviewer other than the PR author. CI queries GitHub's
pull-request reviews and requires the named handle's latest review state to be `APPROVED`. Submitting
or dismissing a review reruns CI, so an author or Agent cannot create an exemption with a trailer
alone.

Breaking changes use `type!:` or `type(scope)!:` and require approval before implementation starts.
The approval ticket must already exist on the trusted target-branch base before the first breaking
implementation commit, recording approval, a handle listed in the CODEOWNED
`.github/maintainers.txt`, date, and migration plan. CI verifies that the ticket's introducing commit
is an ancestor of every breaking implementation commit, forcing the implementation branch to begin
from or rebase onto the approved history. The implementation commit also contains:

```text
BREAKING-CHANGE: Describe the user-visible break and migration.
Breaking-Approval: .scratch/<feature>/issues/<ticket>.md
```

Breaking commits may not use `Docs-Impact: none`.
CI reads the approval ticket from the base SHA rather than the pull-request head, preventing a change
author from creating or editing their own approval as part of the implementation.

Temporary `fixup!` and `squash!` commits, debug artifacts, and unexplained binaries may not be pushed
for review.

## 10. Branches and pull requests

- `main` is the only long-lived branch and remains releasable.
- One branch represents one ticket.
- Branch names use `type/ticket-number-kebab-case`, for example `feat/01-cli-parser`.
- Branches start from current `main` and are deleted after merge.
- Pull-request titles follow Conventional Commits.
- Pull requests use squash merge, producing one main-branch commit per ticket.
- Ordinary pull requests require at least one approval.
- Safety-sensitive paths require maintainer CODEOWNER approval.
- An author or Agent may not approve its own change.

## 11. Breaking-change gate

An Agent or contributor must identify a possible breaking change before modifying code. Until the
maintainer approves the ticket, only read-only investigation and proposal work is allowed. It is a
process failure to disclose a breaking change only after implementation or at commit time.

## 12. Code review

Every pull request receives two independent conclusions:

1. **Standards Review**: coding, module boundaries, error handling, tests, dependencies, commits, and
   documentation impact.
2. **Spec Review**: PRD, ticket acceptance criteria, behavior, and safety invariants.

Agent review does not replace human approval for SafetyPolicy, WhitelistedTrashClient,
FoundationTrashClient, `rmp-test`, Git hooks, workflows, release configuration, or development
standards.

Unresolved critical or high-risk findings block merge. Medium-risk findings are fixed or explicitly
accepted with a written maintainer rationale.

## 13. Definition of Done

A ticket or pull request is complete only when:

- every acceptance criterion has evidence;
- Debug and Release builds pass;
- formatting, SwiftLint, shell, workflow, SPDX, and compiler-warning checks pass;
- pure tests pass;
- applicable whitelist integration tests pass;
- applicable human safety review passes;
- documentation, PRD, glossary, ADR, help, and changelog are synchronized;
- no unresolved critical, high, or medium review findings remain without accepted rationale;
- no unrelated TODO, skipped test, or lint disable was introduced;
- the pull request lists executed commands and whether a real Trash API call occurred;
- any breaking change was approved before implementation;
- required main-branch CI checks remain green after merge.

## 14. Documentation impact

Documentation must change with the behavior or process it describes. `.docs-impact.yml` maps changed
paths to documents that must be reviewed or updated. The `commit-msg` hook checks staged changes, and
CI checks the complete pull-request diff.

The staged checker reads the committed `HEAD` matrix, commit checks read the parent matrix, and PR
range checks read the base SHA matrix. A change therefore cannot weaken or delete the rules used to
judge itself. Documentation-policy files cannot use `Docs-Impact: none`.

If that trusted `HEAD`, parent, or base SHA does not contain `.docs-impact.yml`, the check is a policy
initialization check and no documentation matrix is applied. The checker must not fall back to an
uncommitted working-tree matrix or the pull-request head matrix, because neither is trusted yet. The
new matrix takes effect for subsequent commits and pull requests whose trusted reference contains it.

Examples:

- CLI flags, output, and exit codes affect README, help, PRD, and changelog.
- safety behavior affects the PRD, tests, and changelog.
- TestSupport, hooks, Makefile, and workflows affect this guide.
- module boundaries affect this guide and an ADR.
- toolchain and dependency changes affect this guide and resolution files.
- release or installation changes affect README, this guide, and the changelog.
- domain terminology affects `CONTEXT.md`.

`Docs-Impact: none` requires a reason and an independently named reviewer. Breaking changes can
never claim no documentation impact, whether declared with `!` or a `BREAKING-CHANGE:` trailer. CI
validates additions, copies, modifications, renames, and deletions in every commit, then validates
the aggregate base-to-head pull-request diff so documentation may be synchronized anywhere in the
same pull request without falling behind the resulting code version.

For aggregate validation, files changed exclusively by independently approved `Docs-Impact: none`
commits do not trigger matrix rules; documents changed anywhere in the PR may satisfy rules triggered
by non-exempt commits. This preserves both a real exemption path and version-level synchronization.
The aggregate file set is calculated from the merge base to the PR head, preventing unrelated target
branch documentation changes from satisfying the PR. Deleted documents and tests never count as
updated evidence. All RMPCore and RMPPlatform changes trigger the safety evidence rule rather than
relying on filenames to guess whether code is safety-sensitive.

Commit metadata is parsed with `git interpret-trailers`; trailer-like text in the message body is not
accepted. A documentation exemption approval must target a commit that contains the exempt commit,
so approvals from an earlier PR revision cannot be reused after new exempt changes are pushed.

`Trusted Policy` runs through `pull_request_target`: it checks out and executes only target-branch
policy code, fetches the PR head as data, and never executes PR source. A PR therefore cannot disable
its required policy status by replacing its own scripts or Makefile.
Changes to any registered policy executor require a trusted maintainer's approving review on the
current PR head; approvals for earlier revisions do not authorize later policy changes.
When the trusted base lists exactly one maintainer and that maintainer authored the pull request, the
policy gate permits the change without an impossible self-review. As soon as the trusted base lists
two or more maintainers, policy-executor changes again require a current-head approval from a trusted
maintainer. Non-maintainer authors never receive this exception.

The trusted workflow obtains the author identity from the GitHub pull-request event and checks it
against the target branch's maintainer list. Coverage baseline ratchets follow the same sole-
maintainer exception and multi-maintainer review rule; the coverage gate still requires the baseline
to equal measured production line coverage. Coverage metric migrations remain dedicated pull
requests regardless of the approval exception.

The first deployment of the sole-maintainer exception cannot authorize itself because Trusted Policy
executes the target branch's previous script. The sole repository administrator must use a one-time
ruleset bypass to merge only the reviewed bootstrap change, record the bypass and passing local gates
in that pull request, and restore normal required-check enforcement immediately afterward. Once the
exception exists on the trusted base, it must not be bypassed for later sole-maintainer changes.
The repository ruleset must require the `Trusted Policy / policy` check before merge. Workflow files
cannot configure that GitHub repository setting themselves; maintainers verify it after initial setup
and whenever required-check settings change.

Coverage metric-version changes must use a dedicated PR containing only the metric, baseline,
development-guide, and changelog files. Implementation changes cannot reset their own metric.

## 15. CI workflows

### 15.1 `ci.yml`

Runs automatically for pull requests and pushes to `main`. It performs all non-destructive gates and
never invokes the real Trash API.

### 15.2 Using `integration.yml`

Use this workflow after platform-adapter, whitelist, path, symbol-link, mount, or real Trash behavior
changes, and before a release.

From GitHub:

1. Open the repository **Actions** tab.
2. Select **Integration Tests**.
3. Select **Run workflow**.
4. Choose the trusted branch and run it.

From GitHub CLI:

```sh
gh workflow run integration.yml --ref main
gh run watch
```

The workflow runs on a fresh GitHub-hosted macOS runner. It has no release secrets. Until the guarded
integration implementation is complete, it fails closed instead of calling the real Trash API.

### 15.3 Using `release.yml`

Day-to-day development does not run this workflow. To publish a release after all gates pass:

```sh
git switch main
git pull --ff-only
git tag -s v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

The signed `vX.Y.Z` tag starts `release.yml`, but the current scaffold fails closed before publication.
The future release ticket must implement tag and changelog verification, required tests, artifact
building, signing, notarization, checksums, and GitHub Release publication. Release secrets will be
available only through the protected `release` environment after maintainer approval.

## 16. Versioning and changelog

The project uses Semantic Versioning and signed `vX.Y.Z` tags.

- `fix` normally increments patch.
- non-breaking `feat` increments minor.
- breaking changes increment minor during `0.x` and major after `1.0`.
- other commit types do not independently require a release.
- maintainers choose when to release; commits do not publish automatically.
- Conventional Commits may generate a draft, but `CHANGELOG.md` is reviewed and written for users.
- Breaking changes appear under Changed or Removed with migration instructions.

## 17. Release security

- Pull requests never receive signing or notarization secrets.
- Workflows use minimum read-only permissions unless a job documents a narrower required write.
- External Actions are pinned to a full commit SHA.
- Release tags are cryptographically signed.
- The `release` GitHub Environment requires maintainer approval.
- The release workflow remains disabled until signing and notarization secrets are configured and the
  maintainer explicitly enables release publication.
