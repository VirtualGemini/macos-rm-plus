# 13 — Migrate the complete product identity to macos-trash-cli and tc

Status: ready-for-agent

Breaking change: yes

Approval: approved

Approved by: @VirtualGemini

Approved at: 2026-08-17

Migration plan: Replace every active product identity with macos-trash-cli/tc, retain only audited legacy-name mappings in this issue and ADR-0003, remove old artifacts without compatibility aliases, then rebuild and revalidate the complete repository.

## Outcome

Make `macos-trash-cli` the sole product, package, repository-documentation, and distribution
identity, with `tc` as its sole production command. Complete the migration before the first v0.1.0
release without changing Trash behavior, safety policy, supported options, or brand-neutral machine
contracts.

This is an exhaustive identity migration, not a search-and-replace limited to an initial list.
Implementation must inventory and migrate every active occurrence in content and paths, including
composed, case-converted, generated, and test-only variants.

## Audited legacy-name mapping

This section and the matching ADR-0003 section are the only post-migration locations allowed to
retain exact legacy product names.

| Legacy identity | Canonical identity |
| --- | --- |
| `macos-rm-plus` | `macos-trash-cli` |
| `macos_rm_plus` | `macos_trash_cli` |
| `rmp` | `tc` |
| `rmp-test` | `tc-test` |
| `rmp_test` | `tc_test` |
| `RMPCore` | `TrashCore` |
| `RMPPlatform` | `TrashPlatform` |
| `RMPTestKit` | `TrashTestKit` |
| `RMPTestSafety` | `TrashTestSafety` |
| `RMPCoreTests` | `TrashCoreTests` |
| `RMPPlatformTests` | `TrashPlatformTests` |
| `RMP_TESTING` | `TC_TESTING` |
| `RMP_PUT_BACK_METADATA_PROBE` | `TC_PUT_BACK_METADATA_PROBE` |
| `RMP*` product-specific symbols | Context-appropriate `TC*` or `Trash*` symbols |
| `rmp-*` and `.rmp-*` product-specific paths or prefixes | Corresponding `tc-*` and `.tc-*` paths or prefixes |
| `.scratch/rmp-core/` | `.scratch/macos-trash-cli/` |

The standalone macOS `rm` command, `/bin/rm`, compatibility comparisons, and shell cleanup commands
are external concepts and are not legacy product identities.

## Scope

### Package and build graph

- Rename the Swift package, executable products, targets, target dependencies, paths, imported
  modules, generated package-test identity, compiler conditions, and conditional probe identity.
- Rename the production and compile-time-isolated test entrypoint directories and every
  product-specific source, test, and support module directory or file.
- Rename product-specific Swift types, methods, functions, constants, variables, comments, test
  suites, test descriptions, and helper symbols. Do not stop at the explicit mapping table.
- Update Package.swift, Package.resolved when resolution metadata changes, formatter/linter inputs,
  coverage object discovery, Debug and Release build commands, and all package-product invocations.

### Runtime and machine-visible identity

- Produce only `tc` and `tc-test`; do not ship, build, install, alias, symlink, or silently accept a
  compatibility command under the legacy identity.
- Make `tc --version` print exactly `tc 0.1.0` and make all canonical English and supplementary
  Chinese help examples use `tc`.
- Rename brand-bearing diagnostic prefixes, Automation guidance, fixture names, finalizer names,
  temporary paths, test reports, and executable-identity checks.
- Preserve brand-neutral JSON schema-version-1 fields, error-code meanings, exit statuses, Trash
  behavior, confirmation policy, safety boundaries, and macOS `rm` compatibility semantics. If a
  stable value contains a legacy product identity, migrate that value explicitly and cover the
  breaking contract with tests.

### Test Safety Context

- Rename the test executable, compiler guard, module import, fixed safety container, long-lived and
  per-run markers, fixture prefixes, rollback staging prefix, finalizer prefix, diagnostics, and
  every fake repository used by policy tests.
- Make the new test executable reject the legacy executable identity and ensure the new fixed safety
  hierarchy cannot authorize paths from the legacy hierarchy.
- Never recursively clean a real Test Safety Context. Any legacy external test hierarchy must be
  inspected and removed by the maintainer only through the existing identity, ownership,
  permissions, marker, run-UUID, and empty-directory safety rules. Preserve non-empty evidence and
  report it as a cleanup blocker.

### Repository automation and policy

- Update Makefile recipes, scripts and script variables, Git hooks, GitHub Actions, CODEOWNERS,
  documentation-impact rules, policy-file declarations, dangerous-command guards, coverage tooling,
  release scaffolding, and their shell-policy tests.
- Update hard-coded source paths and synthetic repository fixtures used to prove policy gates.
- Keep all policy protections at least as strict as before the migration; a renamed path must not
  fall outside CODEOWNERS, documentation-impact, system-Trash-boundary, or coverage enforcement.

### Documentation and tracker

- Update README, help, changelog, security and contribution guidance, development documentation,
  product specification, every active issue, both existing ADRs, manual-test plans, reports, logs,
  metadata, comments, code examples, links, and canonical domain language.
- Move the product tracker to `.scratch/macos-trash-cli/`, preserve issue numbers 01–12, add this
  issue as 13, update every cross-reference, and remove the legacy tracker directory after the move.
- Record the identity decision in ADR-0003 and make `CONTEXT.md` use `macos-trash-cli` as its context
  and `tc` as the command-level subject.
- Do not rewrite git history. The maintainer has already renamed the GitHub repository and will
  update the local `origin` to its canonical URL and rename the local checkout directory after the
  active tree migration is complete. Implementation agents must not change that remote or move the
  live workspace root.

### Artifacts and installed surfaces

- Delete legacy `.build`, `.swiftpm`, coverage/profile, package-cache, `.artifacts`, binary, module,
  report, log, and manual-acceptance outputs before rebuilding from the canonical tree.
- Remove old tracked result directories rather than relabelling their evidence. Regenerate evidence
  with the canonical executables and paths.
- Make committed evidence repository-relative or explicitly normalized so the maintainer-owned local
  checkout basename is not persisted as a legacy product identity before the final directory rename.
- The maintainer removes any legacy binary, shell alias, completion, package-manager entry, local
  checkout name, or external test hierarchy outside the repository after inspecting it safely.
  Repository automation must not mutate those external locations without separate authorization.

## Implementation and review sequence

### 1. Approval documentation commit

- Commit this issue and ADR-0003 to the trusted target branch before implementation starts.
- Review the approval commit against repository standards and this decision record.
- Keep `CONTEXT.md` aligned with the implemented tree until the atomic migration commit.

### 2. Atomic identity migration commit

- Perform the complete code, path, policy, test, tracker, domain-language, and ordinary-documentation
  migration in one breaking commit so every documentation-impact rule is satisfied within the same
  commit.
- Delete stale tracked evidence in this commit; do not add newly generated evidence yet.
- Use a Conventional Commit subject with `!` and include `Signed-off-by`, `Docs-Impact: updated`,
  `BREAKING-CHANGE`, and
  `Breaking-Approval: .scratch/macos-trash-cli/issues/13-full-product-identity-migration.md`.
- Run the static, structural, safe build, unit-test, and policy acceptance applicable before real
  Trash evidence is regenerated.
- Run an independent Standards Review and Spec Review for this commit.

### 3. Canonical evidence commit

- Start from a clean generated state, run the complete required acceptance with canonical commands,
  and add only canonical manual-test results and reports.
- Use a separate commit with the required sign-off and documentation-impact trailers.
- Run an independent Standards Review and Spec Review for this commit.

Every review finding must be fixed in a new commit; do not amend or replace an already reviewed
commit. Each fix commit must independently pass commit-message, breaking-approval when applicable,
documentation-impact, relevant acceptance, and two-axis review. Before handoff, re-run review and
commit-range validation for the aggregate branch so a later fix cannot hide an earlier defect.

## Acceptance criteria

### Exhaustive legacy-identity audit

- [ ] A case-sensitive and case-insensitive content scan for every token in the audited mapping
  returns matches only inside the dedicated mapping sections of this issue and ADR-0003.
- [ ] A repository-relative descendant path scan finds no legacy product identity in any active file
  or directory name. The maintainer-owned checkout basename is outside this scan.
- [ ] The scans include hidden files and exclude only `.git`. A pre-clean scan inventories stale
  generated matches; post-clean and post-rebuild scans must return no generated legacy identity.
- [ ] Standalone external `rm` references are reviewed semantically and remain only where they mean
  the macOS command, compatibility behavior, or safe shell cleanup.
- [ ] No broad allowlist, binary-file skip, case-folding gap, composed identifier, archived result,
  comment, fixture, marker, or log can hide a product-identity match.

### Structure and contracts

- [ ] `swift package describe` reports package `macos-trash-cli`, production product/target `tc`,
  test product/target `tc-test`, and the canonical core, platform, test-kit, test-safety, and test
  module names. Generated package-test identity uses `macos_trash_cli`.
- [ ] Only canonical source, support, test, tracker, and manual-result directories exist; every
  migrated legacy directory and file is absent.
- [ ] `tc --help`, both localized help surfaces, and `tc --version` use only the canonical identity;
  the version output is exactly `tc 0.1.0`.
- [ ] No executable, Swift product, target, module, alias, symlink, wrapper, script entrypoint, or
  package artifact exposes the legacy command.
- [ ] `tc-test --version`, executable-identity checks, fixed safety hierarchy, markers, fixtures,
  finalizers, and every maintained test scenario use the canonical identity.
- [ ] JSON schema version, brand-neutral stable codes, exit-status compatibility, protected-path
  policy, confirmation, serial execution, and Trash-only behavior remain unchanged.

### Repository gates

- [ ] `make format-check`
- [ ] `make lint`
- [ ] `make lint-scripts`
- [ ] `make lint-actions`
- [ ] `make check-spdx`
- [ ] `make check-dangerous`
- [ ] `make check-tool-versions`
- [ ] `make check-swift-toolchain`
- [ ] `make check-system-trash-boundary`
- [ ] `make check-policy-ownership`
- [ ] `make build`
- [ ] `make build-release`
- [ ] `make test-unit`
- [ ] `make test-policy`
- [ ] `make coverage-report`, with no unauthorized baseline decrease or metric-definition change
- [ ] `make check`

### Canonical evidence

- [ ] The guarded integration suite passes through the renamed Test Safety Context without granting
  the production executable a test-only capability.
- [ ] The full production CLI exit-status matrix is regenerated with `tc`, contains the expected 0,
  1, and 64 outcomes, and is committed under a canonical result path.
- [ ] Maintainer-only ordered-batch, duplicate-name, Put Back, and symbolic-link entrypoints resolve
  through `tc-test`; required real-Trash and Finder checks are executed under their existing safety
  and human-approval rules.
- [ ] New reports record canonical source binaries, commands, fixture paths, executable identities,
  and version output without persisting the maintainer-owned absolute checkout path. No old report
  is copied or textually relabelled.
- [ ] Ignored build and profile outputs contain no stale legacy product artifact after the final
  clean rebuild.

### Commit and review gates

- [ ] The approval issue and ADR exist on the trusted target branch before the breaking migration
  commit.
- [ ] Every commit passes the repository commit-message and per-commit documentation-impact checks.
- [ ] Every breaking or breaking-remediation commit points `Breaking-Approval` to this issue.
- [ ] Each planned or remediation commit has a completed Standards Review and Spec Review before the
  next commit begins.
- [ ] Review fixes are new commits; reviewed commits are not amended or silently replaced.
- [ ] The complete commit range and aggregate diff pass the repository gates and final two-axis
  review.

## Out of scope

- Rewriting git history.
- Changing Trash semantics, safety protections, supported options, or brand-neutral JSON contracts.
- Replacing or modifying macOS `/bin/rm`.
- Automatically renaming the live workspace root, GitHub repository, or maintainer-owned external
  installations and test evidence, or automatically changing the local `origin` URL.

## Comments

The maintainer confirmed the complete scope, canonical mapping, pre-release v0.1.0 version,
no-alias breaking migration, safe artifact cleanup, external `rm` boundary, ADR and glossary work,
tracker path, approval metadata, exhaustive acceptance, and per-commit review loop on 2026-08-17.
