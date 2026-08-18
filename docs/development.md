# Development Guide

This document is the single source of truth for developing, testing, reviewing, committing, and
releasing tc. Pull requests must update it when they change the development workflow.

## 1. Toolchain

- Language mode: Swift 6.
- Package manifest: `swift-tools-version: 6.0`.
- Latest upstream toolchain verification: Swift 6.3.3.
- macOS integration builds use the Apple Swift toolchain bundled with the selected Xcode or Command
  Line Tools installation.
- Minimum deployment target: macOS 13.
- Package manager: Swift Package Manager.
- Test framework: Swift Testing only.
- Third-party runtime dependencies: none in v0.1. Real Trash Operations require macOS Finder and
  user-approved Automation access from the responsible terminal or `tc` process.

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
Before builds or tests, a compatibility probe type-checks a minimal `import Testing` program against
the active compiler, macOS SDK, and developer-framework directory. Mixed or partially updated Xcode
Command Line Tools therefore fail immediately with an actionable diagnostic instead of surfacing as
unrelated test compilation errors.

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
├── TrashCore/          Pure parsing, planning, safety policy, and output models
├── TrashPlatform/      macOS system-framework adapters
└── tc/              Production command-line entrypoint

TestSupport/
├── TrashTestKit/       Fakes, spies, and pure test support
├── TrashTestSafety/    Safety logic compiled only into the test executable
└── tc-test/         Compile-time-isolated real-filesystem test entrypoint

Tests/
├── TrashCoreTests/
└── TrashPlatformTests/
```

The architectural decision is recorded in
[`docs/adr/0001-separate-core-platform-and-cli.md`](adr/0001-separate-core-platform-and-cli.md).

`TrashCore` must not invoke the filesystem, terminal, clock, environment, or system Trash API
directly. Those capabilities cross explicit interfaces implemented in `TrashPlatform`.

Interactive confirmation crosses the `ConfirmationPrompt` Interface. TrashCore decides whether a
prompt is required and interprets raw answers; `TrashPlatform.StandardInputConfirmationPrompt` only
checks stdin TTY state, writes the question to stderr, and reads one line. Non-interactive and
non-TTY paths are rejected before the adapter reads stdin.

Trash Plan previews follow the same boundary: `TrashCore` receives only injected top-level entry and
directory-identity inspection capabilities, while `TrashPlatform` supplies the read-only Foundation
adapter. The production dry-run path has no Trash, move, overwrite, or deletion capability.

CLI arguments have one authoritative parser. Information commands complete before an explicit
platform-adapter factory is invoked; operation commands create their adapter only after parsing and
global validation. Compatibility diagnostics stay in the CLI result envelope and never enter the
native Trash Operation request passed to planning or execution modules. The module responsibilities
and Interfaces are recorded in ADR-0001.

Exit Status Compatibility changes numeric CLI results and adds one rm-compatible empty-invocation
rule: a short `-f` that remains effective with no paths is a successful no-op. Successful Trash
moves, including moved results with Trash Warnings, use `0`; operational and safety failures use
`1`; parser and usage failures use macOS `EX_USAGE` value `64`. Moved warnings do not trigger
stop-on-error. The no-op rule follows independent confirmation and missing-path precedence, so a
later confirmation option alone does not clear force-derived ignore-missing. It does not otherwise
change tc's Trash behavior, confirmation policy, output schema, or safety boundary; `-W` remains
explicitly unsupported. JSON mode still renders the no-op as a complete empty result document.

Non-dry-run planning retains one ordered entry for every supplied top-level path. Missing and
inaccessible entries become pre-capability Trash Results, while Protected Path and unavailable
safety-identity failures still reject the operation before any Trash capability call. Execution is
synchronous and serial, continues after item failures by default, and records all later entries as
skipped after stop-on-error or interrupted per-input confirmation. Human output is rendered once
from the complete ordered result set so standard, verbose, and quiet modes cannot change execution.
JSON output is rendered from the same plan or result set as one deterministic schema-version-1
document. It converts sources to absolute paths, retains exact moved destinations, and maps internal
failure classifications to the stable external `failed` state without exposing Foundation error
domains or numeric codes.

Confirmation tests run through the public `CLIApplication` input/output seam with fake filesystem,
prompt, and Trash capabilities. Platform prompt tests inject TTY, writer, and line-reader functions;
the pure suite never reads its real stdin and never invokes the real Trash API.
JSON contract tests use that same public seam and fixed document snapshots. They parse stdout as one
complete document while independently asserting stderr diagnostics and exit codes; the renderer does
not retain or upload the absolute paths it emits.

## 4. Canonical language

- Code identifiers, code comments, commit messages, pull-request titles, canonical CLI text, JSON
  contracts, ADRs, and development documentation use English.
- Product-specified localized help surfaces may supplement the canonical English CLI text; Chinese
  documentation may also be provided as a supplementary translation.
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
- `TrashCore` uses typed errors.
- Foundation `NSError` values remain inside `TrashPlatform` and are mapped to stable core error codes.
- Finder Automation failures are classified with the SDK's named Apple Event and OSStatus constants;
  localized error-message text never controls program flow.
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
- `MacOSTrashClient` processes approved top-level inputs synchronously. Its ordinary-entry branch
  performs one finite-timeout Finder Apple Event; its symbolic-link branch performs serial local
  Foundation and finalizer operations. TrashCore never overlaps Trash Inputs.

## 6. Testing standards

### 6.1 Framework and coverage

- Swift Testing is the only test framework.
- The safe pure-test command currently runs the complete suite with `--no-parallel`, guaranteeing
  platform-test serialization. Parallel core-only execution may be introduced later through a
  separate command that cannot include platform or real-filesystem suites.
- Every `FR-SAFE-*` and `FR-TEST-*` requirement has at least one corresponding test.
- Every pre-capability safety rejection proves the expected error, no unauthorized or partially
  prepared filesystem change, and zero TrashClient calls. A complete fixed safety boundary that was
  atomically published before a later setup failure remains in place under FR-TEST-027.
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
- The v1 production coverage baseline is `97.48%`, ratcheted upward with platform Trash adapter,
  deterministic confirmation, Finalizer failure classification, ordered batch and stable JSON
  result handling, Exit Status Compatibility, and review-remediation coverage without changing the
  coverage metric definition.
- `.coverage-metric-version` identifies the measurement definition. Changing which binaries or
  source classes count requires incrementing it and establishes a new reviewed baseline; subsequent
  PRs are compared only within that metric version.
- Documentation-impact checks require every baseline or coverage-report change to update this guide.
  A metric-version change must update both this guide and `CHANGELOG.md` because it changes the
  interpretation of reported coverage.
- Coverage includes production executables as additional `llvm-cov` objects; test-only coverage
  cannot hide newly added untested CLI code.
- SafetyPolicy, option parsing, and test-whitelist branches may not remain untested.
- Protected Path planning tests use fake filesystem identities. They must not launch `tc` with a
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
~/tc-test                         Never a tc target
~/tc-test/test                    Never a tc target
~/tc-test/test/<run-uuid>         Never a tc target
~/tc-test/test/<run-uuid>/...     The only authorized fixture area
```

Real-filesystem tests:

- use the compile-time `TC_TESTING` executable `tc-test`;
- require `--test-run-id <uuid>`;
- use `0700` directories, `0600` marker files, device/inode identity checks, and retained directory
  descriptors;
- reject symbolic-link escapes, mount points, cross-volume paths, network volumes, and File Provider
  roots;
- prefix fixture basenames with `tc-test-<run-uuid>-`;
- run serially;
- never receive `/`, a real home directory, the working directory, or system directories;
- never clean the user's Trash by name or with a permanent-delete API.

Assertions should expose mistakes early, but every assertion has a non-optional `guard` or typed
error enforcing the same boundary in optimized builds.

The compile-time-isolated `tc-test` target fails compilation unless `TC_TESTING` is enabled and is
the only package product and module containing the real Test Safety Context implementation. The
separate `TrashTestKit` module exposes no real safety entry for an unflagged target to call or forge
with a matching runtime symbol. The driver establishes the Test Safety Context before
exposing path arguments to downstream test work. It derives the loaded executable path from macOS rather than
trusting `argv[0]`, obtains the effective user's home from the system account database, rejects root or the wrong executable identity,
exclusively creates UUID Run Directories, and retains open
descriptors for all three safety directories. Versioned JSON markers record their directory role and
device/inode identity; the run marker additionally records the UUID and all three directory
identities. Existing directories and markers are validated without following symbolic links and are
never repaired automatically.

Directory validation packages the expected device/inode identity, owner, and directory role into one
expectation value so path and descriptor checks apply the same invariant. Stable `test-safety.*`
identifiers are defined as typed diagnostic codes while preserving their documented raw strings.

Test-safety failures use stable `test-safety.*` diagnostic codes. Local cleanup revalidates the full
hierarchy, removes only the matching run marker, and uses non-recursive `rmdir` semantics only when
the Run Directory has no Test Fixtures. The two fixed directories and their long-lived markers are
never removed automatically after they have been atomically published. New safety directories and
their markers are prepared under random staging names and become fixed boundaries only when an
exclusive rename publishes the complete directory. A failed preparation removes its unpublished
staging directory and marker so that a safety rejection normally leaves no filesystem change. If a
filesystem error prevents that rollback, the operation fails with `test-safety.rollback-failed`,
reports the random `.tc-create-*` staging entry that may remain, and never silently claims cleanup
succeeded.

`TrashPlatform.MacOSTrashClient` is the production Trash capability. It dispatches ordinary files and
directories to `FinderTrashClient`, whose fixed AppleScript handler receives path text as a
structured Apple Event argument and returns the Finder item URL. Final symbolic links use the
Foundation and Trash Finalizer protocol accepted in ADR-0002; Finder failure never triggers that
branch. The failed AppKit `NSWorkspace.recycle(_:completionHandler:)` candidate and direct
Trash-directory mutation remain prohibited. The production execution path constructs the composite
adapter only after parsing, root policy, output-mode, Trash Plan, and confirmation checks succeed,
and only for an individual Trash Input approved for execution.
Automation consent, denial, timeout, unavailable Finder, or missing file URL is reported without a
fallback Trash API. The compile-time-isolated `tc-test` target reaches the production symbolic-link
algorithm only through `WhitelistedMacOSTrashClient` and `WhitelistedTrashClient`, which accept
opaque targets produced by their planning authorization passes,
revalidates the complete Test Safety Context and target immediately before the system call, and
returns read-only verification evidence. Pure tests inject Trash spies and never invoke the real
capability. The integration runner remains separately guarded and cannot be enabled through an
environment switch in the production executable.

`make test-integration` builds the Release `tc-test` executable and invokes it without fixture
paths under a fresh Test Safety Context run UUID. This proves the canonical executable identity,
fixed hierarchy validation, empty Run Directory cleanup, and compile-time `TC_TESTING` boundary
without constructing or calling a system Trash capability. `TC_TEST_BINARY` is an integration-runner
test seam that accepts only an absolute executable path whose basename is exactly `tc-test`; it is
never read by the production executable. Its policy test asserts the runner's exact validation
diagnostic for relative paths, directories, non-executable files, and noncanonical basenames so an
operating-system execution failure cannot masquerade as whitelist enforcement.

`tc-test ordered-batch` is the maintainer-only real-filesystem acceptance for ordered execution. It
creates a file, empty directory, deep directory, quoted/newline filename, missing path, and nested
permission-denied fixture inside one authorized Run Directory. Existing fixtures are converted to
opaque whitelist authorizations before CLI execution; the adapter revalidates each target and the
complete Test Safety Context immediately before its Finder call. The command requires partial
success, exact ordered receipts, stable missing and permission diagnostics, and verified final
source states. It restores the permission fixture directory to `0700`, preserves the Run Directory
and Trash receipts for inspection, and is excluded from default tests and CI.

The compile-time-isolated `tc-test` target has a separate capability for reproducing issue 12's
symbolic-link behavior. `FoundationSymlinkTrashClient` uses
`FileManager.trashItem(at:resultingItemURL:)`, but refuses every entry that `lstat` does not identify
as a final symbolic link. It remains behind `WhitelistedTrashClient`, so the complete Test Safety
Context, planned link identity, local-volume policy, UUID prefix, and returned Trash evidence are
revalidated exactly as they are for Finder. Production cannot import this test adapter; its separate
Foundation call site is confined to `MacOSTrashClient`, Finder failures never fall back to it, and
ordinary tests inject fake system calls.

Issue 12's authoritative rapid Put Back acceptance lives entirely in the compile-time-isolated test
target. `PutBackRaceAcceptance` exclusive-creates one UUID-prefixed Test Fixture, authorizes its
identity once, performs the first Finder Trash call, restores the exact returned URL through
`WhitelistedPutBackClient`, and immediately reuses the same identity for the second Finder Trash
call. The sequence contains no sleep, shell script, `osascript` subprocess, or Trash name search.
The test-only Put Back adapter revalidates the complete Test Safety Context immediately before its
Finder call and compares the run prefix plus available file resource identifier before and after
restore. Static policy permits its AppleScript bridge only in
`TestSupport/TrashTestSafety/WhitelistedPutBackClient.swift`; production cannot reference it.

The restore step has two variants sharing that one sequence. `put-back-race` scripts the move
through `WhitelistedPutBackClient`; because it reads `~/.Trash` it requires the invoking terminal to
hold Full Disk Access *and* to have been started after that grant, otherwise Finder fails closed with
Apple Event `-5000`. `put-back-race-manual` holds no Finder Put Back capability and needs no extra
permission: it confirms the original path is empty, then waits for the maintainer's real Finder Put
Back command through a kqueue-backed dispatch source over the authorized Run Directory, revalidates
the context and resource identifier, and only then fires the second Trash call. Detection is driven
by the vnode event rather than a timer; a bounded wait slice only backstops a missed notification.
The manual variant is the menu-level authority, since production `tc` needs Automation but never
Full Disk Access. While it waits it prints the remaining window to stdout once every five seconds
and for each of the final five, so a terminal shows a live countdown. The first tick reports the
full declared timeout: the remaining window is rounded up, because the clock has already advanced a
fraction by the time it is measured and rounding down would skip straight to the next multiple of
five.

`duplicate-trash-name` covers the separate case where Finder must rename the second Trash item
because an entry with the same basename already exists. It exclusively creates and trashes one
ordinary file, exclusively creates a second generation at the exact same source path, and trashes
that generation through the same whitelisted Finder boundary. The acceptance succeeds only when
the two system-returned URLs are distinct and prints both exact receipts. It never restores,
enumerates, searches, or automatically cleans the Trash; the retained items are disposable evidence.

`SETTLE_SECONDS` (0-60, default 0) declares the ticket's re-trash delay bucket between the observed
restore and the second Trash call. It is an explicit experiment parameter, not an implicit wait: the
default performs no sleep, and the value that actually applied is echoed as `settle-seconds=` beside
the result so every evidence line is traceable to its bucket. Issue 12's symbolic-link investigation
later proved that menu availability for the final Foundation Trash item changes only after another
successful Foundation Trash call, at both 0- and 15-second settle endpoints. Maintainers therefore
inspect the menu immediately after the command completes; no post-Trash observation delay is part of
the protocol.

`put-back-symlink-delay-manual` runs the same real-menu sequence with both Trash calls routed through
the test-only Foundation symbolic-link adapter. It accepts only `symbolic-link` and
`broken-symbolic-link` fixtures. Its declared settle interval is applied after the exact Put Back is
observed and before the second Foundation call; delaying only the command response after that call
would not test the proposed mitigation. The completed 0- and 15-second probes falsified delay as a
viable mitigation: every non-final item acquired Put Back after the next successful call, while the
final item did not. This command remains available as the unfinalized control and is not a production
fallback.

`put-back-symlink-finalizer-manual` adds one owned Foundation symbolic-link Trash call immediately
after the second user-visible Trash call. It then moves the exact Foundation-returned finalizer URL
back to its exact Run Directory source, revalidates the Test Safety Context, UUID prefix, resource
identifier when available, symbolic-link type, and original device/inode identity, and removes only
that restored link through the retained Run Directory descriptor. It never permanently deletes an
item inside Trash and stops closed if the source is occupied or any identity changes. The scenario
fixes the settle bucket at zero and reports `foundation-finalizer=test-only-cleaned`; it is an automated
test-only feasibility check, not production wiring.

`put-back-symlink-production-manual` uses an ordinary-file Finder Trash call only as the human
control that must offer the maintainer's real Finder Put Back. The symbolic-link target is a separate
Test Fixture that remains in the Run Directory until that exact control restore is observed and
revalidated; it is then moved by the normal or explicitly injected production `MacOSTrashClient`
scenario under test. A raw Foundation control plus a separate test Finalizer, and a fault-free
production symbolic-link control, were both rejected by real evidence because neither made the next
human control reliable. Every production target and activation Foundation call is independently
authorized immediately before execution. User fixtures retain the run UUID prefix;
internal helpers must be direct Run Directory children named exactly
`.tc-finalizer-<canonical-lowercase-uuid>` and must remain symbolic links with their planned
identity. The wrapper revalidates the complete Test Safety Context immediately before the real
Finalizer restore move; a changed directory identity or marker prevents that call. Any production
warning fails the acceptance while retaining the exact target evidence. The scenario fixes the
settle bucket at zero, performs no post-Trash wait, and reports
`foundation-finalizer=production-cleaned` on normal completion.

Before a target receipt exists, a failure in preparation, diagnostic preflight, or the target Trash
call triggers identity-verified cleanup of every prepared Finalizer. If any helper cannot be safely
removed, `MacOSTrashClient` reports `finalizer_cleanup_failed` instead of discarding the cleanup
error. The normal source-identity check independently classifies the user target as `not_moved` or
`state_uncertain`. After a target receipt exists, cleanup degradation remains a moved Trash Warning
that preserves the exact destination.

`FINALIZER_FAULT` is a test-target-only fault mode for this production-algorithm acceptance. Its
default is `none`. `not-moved-before-error` injects a failure after the first activation helper is
authorized but before its Foundation call, so the prepared backup must recover and the summary
reports `foundation-finalizer=backup-recovered`. `moved-before-error` performs the first activation
through the real whitelisted Foundation boundary and then throws, so production must stop before the
backup; the acceptance succeeds only when the exact target receipt is retained with
`finalizer_state_uncertain`. It reports `foundation-finalizer=state-uncertain` and leaves the moved
helper in Trash as evidence. A fault mode requires `CYCLES=1`. Without an explicit fault, every
production warning still fails acceptance.

`put-back-symlink-production-probe` is the minimal standalone diagnosis for the production
symbolic-link path. It creates one resolving or broken symbolic-link Test Fixture and invokes one
whitelisted production `MacOSTrashClient` operation. It creates no control item, performs no Put
Back, has no settle interval or cycle mode, and prints `control=none` plus the exact target to inspect
immediately. `FINALIZER_NAME=hidden` preserves the production basename; `FINALIZER_NAME=visible`
uses a run-prefixed visible helper for the single-variable name experiment. `PREFLIGHT=disabled` is
the production default and keeps the target as the first Foundation Trash call. The explicit
`PREFLIGHT=enabled` diagnostic mode inserts the rejected target-before-move preflight while keeping
target activation, restore, cleanup, and whitelist checks unchanged. This probe established that
the preflight, rather than helper naming or elapsed time, consumed the metadata transition needed by
the target; it remains diagnostic evidence, not a replacement acceptance.

`FIXTURE` selects the deleted item's shape from issue 12's platform acceptance set: `file`
(default), `directory`, `symbolic-link`, `broken-symbolic-link`, `quoted-name`, or `newline-name`.
The metadata race is a property of the Trash entry, so shape is a dimension independent of the delay
bucket, and the awkward-name kinds are the end-to-end proof that path text crosses the Apple Event
boundary as a structured argument rather than as script source. Every result echoes `fixture=`.

Fixture creation for each shape matches the safety of the plain-file path: revalidate the context,
use only `*at` calls against the retained Run Directory descriptor, create exclusively, and roll
back on failure. Directories need an explicit mode restore after `mkdirat`, because the process
umask can strip the requested `0700` and leave a directory that cannot even be opened. Symbolic
links are never followed or resolved during creation.

`CYCLES` (1-30, default 1) runs that many cycles inside one Run Directory for the ticket's
differential. Each cycle gets its own numbered fixture, the maintainer performs one Put Back per
cycle, and the command ends with a single summary listing every second-Trash target to inspect, so a
30-cycle differential costs one command and one inspection pass rather than thirty. A cycle that
fails still prints the evidence of the cycles already completed before it reports the failure.

These Put Back acceptances are maintainer-invoked only and are excluded from `make test`, `make check`,
and CI. They intentionally preserve the validated Run Directory after the second Trash call so
Finder's final Put Back destination continues to exist during human inspection. Each command prints
that Run Directory and the exact second Trash URL; retained acceptance evidence is not recursively
cleaned.

`TrashTestKit.PutBackMetadataScanner` and its conditionally compiled command-line probe are read-only
investigation support. They parse caller-supplied Trash `.DS_Store` data for Finder `ptbL`/`ptbN`
records and never call the system Trash API or rewrite metadata. The scanner has Swift Testing
coverage over synthetic bytes. Maintainers may compile the probe from its two `TrashTestKit` source
files with `TC_PUT_BACK_METADATA_PROBE` enabled for a disposable-volume investigation; automating
the cross-volume Trash workflow remains outside the current Test Safety Context, which intentionally
rejects mount points and cross-volume Trash Inputs.

## 7. Development commands

```sh
make bootstrap          Check toolchain and resolve pinned development dependencies
make hooks-install      Install the repository's versioned Git hooks
make format             Format Swift source
make format-check       Check Swift formatting
make lint               Run SwiftLint
make lint-scripts       Run ShellCheck
make lint-actions       Run actionlint
make check-swift-toolchain Verify compiler, SDK, and Testing.framework compatibility
make build              Build every package target in Debug
make build-release      Build every package target in Release
make test               Run safe pure tests
make test-unit          Run safe pure tests
make test-ordered-batch TEST_RUN_ID=<uuid> Run the maintainer-only ordered batch acceptance
make test-put-back-race TEST_RUN_ID=<uuid> Run the maintainer-only issue 12 Swift acceptance
make test-put-back-race-manual TEST_RUN_ID=<uuid> [SETTLE_SECONDS=] [CYCLES=] [FIXTURE=] Put Back
make test-put-back-symlink-delay-manual TEST_RUN_ID=<uuid> [SETTLE_SECONDS=] [CYCLES=]
                                         [SYMLINK_FIXTURE=]
make test-put-back-symlink-finalizer-manual TEST_RUN_ID=<uuid> [CYCLES=] [SYMLINK_FIXTURE=]
make test-put-back-symlink-production-manual TEST_RUN_ID=<uuid> [CYCLES=] [SYMLINK_FIXTURE=]
                                                [FINALIZER_FAULT=]
make test-put-back-symlink-production-probe TEST_RUN_ID=<uuid> [SYMLINK_FIXTURE=]
                                                [FINALIZER_NAME=hidden|visible]
                                                [PREFLIGHT=enabled|disabled]
make test-duplicate-trash-name TEST_RUN_ID=<uuid> Run the duplicate Trash basename acceptance
make coverage-report    Publish the latest unit-test coverage summary
make test-policy        Test repository policy scripts through their public interfaces
make test-integration   Run the guarded integration entrypoint
make check              Run all non-destructive local gates
make ci                 Run the CI-equivalent non-destructive gates
make clean              Clean SwiftPM build products only
TC_BINARY=/absolute/path/to/tc TC_RESULTS_DIR=/absolute/results/path \
  ./scripts/run-production-cli-exit-status-tests.sh Run the non-Trash production CLI exit-status suite
```

The exit-status runner normalizes the repository root plus both the logical and filesystem-canonical
forms of its temporary fixture root to `REPO_ROOT` and `TEST_ROOT` in persisted evidence. Committed
reports therefore identify canonical commands and repository-relative source binaries without
recording the maintainer-owned checkout path or host-specific temporary-directory aliases.
`Tests/PolicyTests/evidence-path-normalization-tests.sh` fixes a symbolic-link fixture across those
two path forms and verifies that neither host path survives normalization.

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

### Mandatory commit-history validation

`make check` and `make ci` validate the checked-out source tree. They do **not** replace validation
of every commit that the pull request makes reachable. CI validates the complete commit range, so a
later revert or corrective commit does not excuse an earlier commit with an invalid message or
documentation-impact declaration.

Immediately after creating a commit, validate that commit before continuing:

```sh
./scripts/check-commits.sh "$(git rev-parse HEAD^)" HEAD
```

Before pushing, opening a pull request, or declaring a pull request ready, validate the complete
range against the target branch:

```sh
BASE_SHA="$(git merge-base origin/main HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
./scripts/check-commits.sh "$BASE_SHA" "$HEAD_SHA"
```

This range check is a blocking release criterion. Do not rely on CI to discover missing
`Signed-off-by`, `Docs-Impact`, breaking-change, or documentation-coverage metadata. If any reachable
commit fails, stop and repair the branch history; adding a later valid commit or revert leaves the
invalid commit in the range and does not fix the failure. Coordinate any published-history rewrite
and protect the remote update with an exact `--force-with-lease` expectation so unknown remote work
cannot be overwritten.

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

CI normally requires the named documentation-impact approver's latest pull-request review to be
`APPROVED`, and the approver must differ from the PR and commit authors. When the trusted target base
lists exactly one maintainer, that maintainer may instead approve their own exemption by matching the
authenticated PR author and the trailer handle. This exception never trusts commit names or email
addresses and does not grant merge permission.

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

Before the first published release, compatibility is not preserved for unpublished Interfaces of
non-product internal targets such as `TrashCore`. Removing or reshaping such an Interface still requires
explicit maintainer confirmation before implementation, but does not require a compatibility shim,
`BREAKING-CHANGE` trailer, or trusted-base migration ticket. Published executable CLI contracts and
package products remain subject to the full breaking-change gate at every stage.

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
WhitelistedPutBackClient, MacOSTrashClient, FinderTrashClient, `tc-test`, Git hooks, workflows, release
configuration, or development standards.

Repository policy also enforces the test Trash boundary statically: `NSAppleScript`, Apple Event
descriptor construction, Finder bundle targeting, and `osascript` execution may appear only in
`FinderTrashClient.swift` and the compile-time-isolated `WhitelistedPutBackClient.swift`.
Foundation `trashItem` may appear only in production `MacOSTrashClient.swift` and the
compile-time-isolated `FoundationSymlinkTrashClient.swift`; the failed Workspace `recycle` API
remains forbidden everywhere. References to the Foundation experiment adapter are confined to its file,
`WhitelistedTrashClient`, and its dedicated pure test.
`FinderTrashClient` construction is limited to `MacOSTrashClient`, the whitelist wrapper, and its
private platform implementation. `MacOSTrashClient` construction is limited to production wiring.
Adapter tests may obtain only an `any TrashClient` existential
through `makeInjectedFinderTrashClient(...)`; concrete production type references, aliases,
metatypes, and constructor references remain forbidden in all tests. The composite adapter follows
the same rule through `makeInjectedMacOSTrashClient(...)`; its package-visible injection seam is
also limited to `WhitelistedMacOSTrashClient`, which reauthorizes every real call. The test-only Put Back wrapper
may be referenced only by the authoritative acceptance module and its dedicated pure test. The
injectable `WhitelistedTrashClient.testingOnly(...)` factory may appear only in its dedicated spy
test, the Foundation finalizer safety test, and the production-finalizer whitelist safety test.
`make check-system-trash-boundary` runs
this check directly, and `make check` includes it.

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
- CLI parser tests exercise the pure `TrashCore` command boundary with fake filesystem capabilities;
  help and version tests must prove that no path inspection occurs.
- safety behavior affects the PRD, tests, and changelog.
- TestSupport, hooks, Makefile, and workflows affect this guide.
- module boundaries affect this guide and an ADR.
- toolchain and dependency changes affect this guide and resolution files.
- release or installation changes affect README, this guide, and the changelog.
- domain terminology affects `CONTEXT.md`.

`Docs-Impact: none` requires a reason and a named approver, subject to the sole-maintainer exception
in the commit convention. Breaking changes can never claim no documentation impact, whether declared
with `!` or a `BREAKING-CHANGE:` trailer. CI validates additions, copies, modifications, renames, and
deletions in every commit, then validates the aggregate base-to-head pull-request diff so
documentation may be synchronized anywhere in the same pull request without falling behind the
resulting code version.

For aggregate validation, files changed exclusively by validly approved `Docs-Impact: none` commits
do not trigger matrix rules; documents changed anywhere in the PR may satisfy rules triggered by
non-exempt commits. This preserves both a real exemption path and version-level synchronization.
The aggregate file set is calculated from the merge base to the PR head, preventing unrelated target
branch documentation changes from satisfying the PR. Renamed documents and tests count under both
their former and canonical paths so an atomic path migration can satisfy the trusted pre-migration
matrix. Deleted documents and tests never count as updated evidence. All TrashCore and TrashPlatform
changes trigger the safety evidence rule rather than relying on filenames to guess whether code is
safety-sensitive. Policy tests enforce the same rename accounting for staged changes, individual
commits, and aggregate ranges, including rules that require multiple companion documents.

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

The workflow runs on a fresh GitHub-hosted macOS runner. It has no release secrets. The guarded
integration establishes and cleans an empty `tc-test` Run Directory without accepting a fixture path
or calling the real Trash API.

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
