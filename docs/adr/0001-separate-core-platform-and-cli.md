# Separate core policy, macOS adapters, and CLI entrypoints

The project separates pure command parsing, planning, safety policy, and output models into `RMPCore`; macOS Foundation integrations into `RMPPlatform`; and executable wiring into `rmp`. Test doubles and the compile-time-isolated `rmp-test` executable live outside production sources so that core behavior can be tested without system access and real trash operations can only pass through an explicit platform seam and test whitelist.
