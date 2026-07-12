# Changelog

All notable user-visible changes to this project will be documented in this file.

The format is based on Keep a Changelog, and the project follows Semantic Versioning.

## Unreleased

### Changed

- Allow trusted maintainers to ratchet coverage baselines upward with implementation changes without
  creating a self-approval deadlock; untrusted authors, reductions, and metric changes remain
  protected.

### Added

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
