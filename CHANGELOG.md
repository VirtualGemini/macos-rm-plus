# Changelog

All notable user-visible changes to this project will be documented in this file.

The format is based on Keep a Changelog, and the project follows Semantic Versioning.

## Unreleased

### Changed

- Route approved Trash Inputs through Finder's Apple Event `delete` command, pass path text as a
  structured argument, and preserve the returned Finder item URL for ordinary files and directories.
- Route final symbolic links through Foundation without following their targets. Prepare two
  identity-verified same-directory finalizers before moving the target, make the target the first
  Foundation Trash call, then use a successful finalizer call to activate Put Back and remove only
  the exact restored helper outside Trash. Omit the former target-before-move Trash preflight because
  repeated real Finder checks showed that it consumed the target's metadata transition.
- Preserve the exact moved destination when all finalizer activations fail, an activation may have
  moved before throwing, or post-activation cleanup fails, reporting
  `symlink_put_back_not_guaranteed`, `finalizer_state_uncertain`, or
  `finalizer_cleanup_failed` with exit code 1. Retry only when the failed finalizer's original
  identity can still be verified and removed at its source.
- Report `finalizer_cleanup_failed` instead of silently discarding a cleanup error when the user
  target has not moved and a prepared Finalizer can no longer be safely removed. Preserve a newly
  created helper whose first identity check fails rather than deleting an unverified basename.
- Resolve the AppleScript file specification outside Finder's `tell` block so approved paths reach
  Finder correctly, and add a compile-time-isolated Swift acceptance that performs first Trash,
  exact Put Back, and immediate second Trash in one process for issue 12's manual Finder check.
- Add a second maintainer-only acceptance variant that holds no Finder Put Back capability and needs
  no Full Disk Access: it waits for the real Finder Put Back command through a kqueue-backed
  dispatch source over the authorized Run Directory, then fires the second Trash from that event.
- Cover issue 12's platform acceptance set through `FIXTURE`: directories, symbolic links, broken
  symbolic links, and names containing quotes or newlines, each created exclusively against the
  retained Run Directory descriptor with an explicit mode restore that umask cannot strip.
- Run the manual acceptance for up to 30 numbered cycles in one Run Directory through `CYCLES`, so
  the issue 12 differential costs one command and one inspection pass; evidence from completed
  cycles is reported even when a later cycle fails.
- Print a live countdown while that variant waits for the maintainer's Put Back action, declare the
  pre-Trash delay bucket explicitly through `SETTLE_SECONDS`, and echo the applied bucket. Final menu
  availability is checked immediately because later probes falsified post-Trash waiting as a factor.
- Report Finder Automation consent, denial, timeout, and availability failures with stable,
  actionable codes; release remains gated on issue 12's permission and real Put Back acceptance.
- Keep Finder Automation in one reviewed adapter by rejecting direct AppleScript, Apple Event,
  `osascript`, Foundation Trash, and Workspace recycle capability elsewhere.
- Keep the maintainer-only Foundation symbolic-link delay experiment isolated in the test target. It
  measures the pre-Trash delay after Put Back without changing production dispatch or treating the
  previously observed ten-second workaround as a proven threshold.
- Document the rapid same-name restore/re-trash Put Back limitation and its wait, rename, and
  Finder-delete workarounds for existing Foundation-backed builds.
- Ratchet the production line-coverage baseline from 95.70% to 97.16% with platform-adapter and
  Finalizer failure-classification tests, without changing the coverage metric.
- Reserve `not_moved` and `state_uncertain` for post-system-call outcome classification, report
  pre-capability unsupported inputs as `rejected`, and include stable codes plus affected source
  paths when unsupported output modes fail closed.
- Prevent tests, including the Finder adapter injection suite, from constructing the production
  system Trash capability directly; injected adapter tests receive only an existential Trash client,
  so the production metatype and initializer cannot be recovered.
- Allow trusted maintainers to ratchet coverage baselines upward with implementation changes without
  creating a self-approval deadlock; untrusted authors, reductions, and metric changes remain
  protected.

### Added

- Add schema-version-1 JSON Trash Operation results for dry runs and real ordered batches, including
  aggregate success and counts, absolute sources, exact moved destinations, stable structured errors,
  skipped and partial-success outcomes, deterministic contract snapshots, and stderr-only warnings.
  Platform error domains and numeric codes remain private, and rmp does not retain or upload the
  potentially sensitive absolute paths it emits. Human and JSON output share one planning-error
  classification, and JSON encoding failures never emit partial stdout.
- Add ordered serial batch Trash Operations with default continuation, stop-on-error skipped
  results, missing-path and ignore-missing outcomes, aggregate exit codes, one-line single-success
  output, batch summaries, ordered verbose results, and quiet output that preserves diagnostics.
- Add a maintainer-only `rmp-test ordered-batch` acceptance inside the Test Safety Context. It covers
  a file, empty and deep directories, a quoted/newline name, a missing path, a real permission
  failure, and partial success through pre-authorized whitelist targets without entering default
  tests or CI.
- Make the accepted `-P` secure-overwrite warning unconditional across TTY, non-interactive, quiet,
  and redirected output while keeping successful exit status unchanged; strict mode rejects it in
  either argument order before any capability boundary.

- Add a maintainer-only production-finalizer acceptance that uses a separate Finder ordinary-file
  control for the maintainer's real Put Back, then runs the symbolic-link target through a normal or
  fault-injected `MacOSTrashClient`; every internal Foundation call is independently reauthorized by
  the Test Safety Context whitelist, and the exact Finalizer restore revalidates that context before
  its real move.
- Add test-only single-cycle Finalizer fault modes that verify backup recovery after a definitely
  not-moved failure and preserve `finalizer_state_uncertain` without invoking the backup when the
  first Finalizer moved before the injected error.
- Add a maintainer-only standalone production probe that trashes one symbolic-link target without a
  control item or manual Put Back, isolating production Finalizer behavior from prior Trash state;
  its explicit visible-name and preflight modes test those production sequence variables separately.
- Add a maintainer-only duplicate-Trash-name acceptance that sends two exclusively created files
  from the exact same source path through Finder and records both distinct system-returned URLs
  without searching or cleaning the Trash by name.

- Add deterministic `smart`, `never`, `once`, and `each` confirmation with top-level-only summaries,
  `-f`/`-i`/`-I` precedence, non-interactive and non-TTY fail-closed behavior, stable declined,
  invalid, and interrupted diagnostics, and zero unapproved Trash calls.
- Add per-input system Trash execution for files, directories, symbolic links, and broken symbolic
  links with root and Protected Path refusal, exact system-returned destinations, stable failure
  codes, and honest `not_moved` versus `state_uncertain` reporting without destructive fallback.
- Add the complete v0.1 command-line parser with deterministic left-to-right precedence, combined
  short options, strict compatibility validation, concise and compatibility help in English and
  Chinese, filesystem-independent help/version commands, one authoritative parsing path, and
  CLI-only compatibility diagnostics. Explicit missing-path policy remains independent of `-i`, and
  internal confirmation policies cannot be selected through undocumented long-option values.
- Add `rmp --dry-run` for ordered, kind-aware top-level Trash Plan previews with missing-path and
  Protected Path safety failures, without exposing any filesystem mutation capability.
- Initial SwiftPM, development-policy, test-safety, and CI scaffold.
- Harden documentation and breaking-change approvals against pull-request self-modification, and add
  complete target builds, serialized platform tests, dependency-drift checks, and coverage reporting.
- Compare PR documentation from the merge base, require fresh review commits, reject deleted test
  evidence, enforce a trusted coverage baseline, and use native Git trailer parsing.
- Execute policy from the trusted target branch, ratchet production-only coverage, recognize the
  standard `BREAKING CHANGE` footer, and validate policy ownership structurally.
- Require final-state policy approval, cover every CI executor in the policy registry, isolate
  coverage metric migrations, and harden CODEOWNERS and quoted Action reference validation.
- Require coverage baseline and metric-definition changes to update their governing documentation.
