# 11 — Complete v0.1.0 release acceptance

**What to build:** Turn the implemented command into an auditable v0.1.0 release candidate by completing the specified safety matrix, Finder recovery check, documentation alignment, architecture builds, and distribution decisions.

**Blocked by:** 04 — Provide the complete compatible command-line interface; 06 — Encapsulate the whitelisted system Trash capability; 07 — Move one Trash Input safely through the system Trash; 08 — Execute deterministic confirmation policy; 09 — Process an ordered batch Trash Operation; 10 — Emit stable JSON Trash Operation results.

**Status:** ready-for-human

- [ ] Automated acceptance demonstrates that every successful move passes through the system Trash API and that no production or test path provides permanent-delete fallback or direct Trash-directory manipulation.
- [ ] The compatibility, Protected Path, root, symlink, dry-run, batch, JSON, test-envelope, identity-change, mount, volume, and File Provider rejection matrices pass with rejected cases proving zero Trash calls.
- [ ] Local integration tests use only compile-time-isolated test artifacts and authorized run fixtures, execute serially, never recursively clean, and leave any non-empty Run Directory intact for inspection.
- [ ] A human verifies the exact system-returned URL for a dedicated local-volume fixture in Finder and records whether “Put Back” restores it, without claiming universal restore capability.
- [ ] External volume, network volume, and File Provider observations are recorded as a compatibility matrix rather than treated as universally supported behavior.
- [ ] Primary help, compatibility help, README, security guidance, changelog, and release notes agree on Trash-only semantics, ignored options, warnings, unsupported operations, disk-space implications, and recovery limitations.
- [ ] Debug and release builds cover all targets, and release artifacts are validated for both Apple Silicon and Intel architectures.
- [ ] The minimum macOS target and initial Homebrew source-build or prebuilt-bottle strategy are explicitly decided and documented.
- [ ] Signing, notarization, GitHub Release, and Homebrew steps either succeed with maintainer credentials or are captured as clearly owned release blockers.
- [ ] The final two-axis review passes against repository standards and the v0.1.0 specification before the release commit is created.
