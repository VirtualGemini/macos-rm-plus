# Changelog

All notable user-visible changes to this project will be documented in this file.

The format is based on Keep a Changelog, and the project follows Semantic Versioning.

## Unreleased

### Changed

- Reserve `not_moved` and `state_uncertain` for post-system-call outcome classification, report
  pre-capability unsupported inputs as `rejected`, and include stable codes plus affected source
  paths when unsupported output modes or input counts fail closed.
- Prevent tests, including the Foundation adapter injection suite, from constructing the production
  system Trash capability directly; injected adapter tests receive only an existential Trash client,
  so the production metatype and initializer cannot be recovered.
- Allow trusted maintainers to ratchet coverage baselines upward with implementation changes without
  creating a self-approval deadlock; untrusted authors, reductions, and metric changes remain
  protected.

### Added

- Add deterministic `smart`, `never`, `once`, and `each` confirmation with top-level-only summaries,
  `-f`/`-i`/`-I` precedence, non-interactive and non-TTY fail-closed behavior, stable declined,
  invalid, and interrupted diagnostics, and zero unapproved Trash calls.
- Add one-item system Trash execution for files, directories, symbolic links, and broken symbolic
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
