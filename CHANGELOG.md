# Changelog

All notable user-visible changes to this project will be documented in this file.

The format is based on Keep a Changelog, and the project follows Semantic Versioning.

## Unreleased

### Added

- Initial SwiftPM, development-policy, test-safety, and CI scaffold.
- Harden documentation and breaking-change approvals against pull-request self-modification, and add
  complete target builds, serialized platform tests, dependency-drift checks, and coverage reporting.
- Compare PR documentation from the merge base, require fresh review commits, reject deleted test
  evidence, enforce a trusted coverage baseline, and use native Git trailer parsing.
- Execute policy from the trusted target branch, ratchet production-only coverage, recognize the
  standard `BREAKING CHANGE` footer, and validate policy ownership structurally.
- Require final-state policy approval, cover every CI executor in the policy registry, isolate
  coverage metric migrations, and harden CODEOWNERS and quoted Action reference validation.
