# Adopt macos-trash-cli and tc as the sole product identity

Status: Accepted

Date: 2026-08-17

The project adopts `macos-trash-cli` as its sole product and package identity and `tc` as its sole
production command before v0.1.0. The migration deliberately favors one coherent identity over a
compatibility alias or dual-brand transition, and it covers internal modules, test infrastructure,
repository policy, documentation, and generated evidence as well as the public executable.

## Audited legacy-name mapping

This section and the matching section in issue 13 are the only post-migration locations allowed to
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
| `RMP*`, `rmp-*`, and `.rmp-*` product-specific variants | Context-appropriate `TC*`, `Trash*`, `tc-*`, and `.tc-*` variants |
| `.scratch/rmp-core/` | `.scratch/macos-trash-cli/` |

Standalone references to macOS `rm`, `/bin/rm`, compatibility behavior, and shell cleanup commands
remain because they describe external concepts rather than the product identity.

## Consequences

No legacy executable, module, alias, wrapper, or generated artifact is retained. The migration is a
breaking but pre-release change, so the version remains v0.1.0 and `tc --version` reports
`tc 0.1.0`. Git history is not rewritten. The maintainer has already renamed the GitHub repository;
updating the local `origin` and checkout directory remains a maintainer-owned step after active-tree
validation.
