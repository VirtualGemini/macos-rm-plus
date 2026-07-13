# Separate core policy, macOS adapters, and CLI entrypoints

The project separates pure command parsing, planning, safety policy, and output models into `RMPCore`; macOS Foundation integrations into `RMPPlatform`; and executable wiring into `rmp`. Test doubles and pure test support live in `RMPTestKit`.

The real Test Safety Context implementation and its process entry belong to the compile-time-isolated `rmp-test` executable module. That module is built only with `RMP_TESTING`; unflagged targets cannot import a separate safety library or invoke its real entry. This keeps test safety authorization attached to the executable that owns the eventual whitelisted Trash capability, while allowing safety behavior to be tested through internal seams with `@testable import rmp_test`.
