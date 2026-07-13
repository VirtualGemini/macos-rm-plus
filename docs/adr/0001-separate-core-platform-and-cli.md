# Separate core policy, macOS adapters, and CLI entrypoints

The project separates pure command parsing, planning, safety policy, and output models into `RMPCore`; macOS Foundation integrations into `RMPPlatform`; and executable wiring into `rmp`. Test doubles and pure test support live in `RMPTestKit`.

The real Test Safety Context implementation and its process entry belong to the compile-time-isolated `rmp-test` executable module. That module is built only with `RMP_TESTING`; unflagged targets cannot import a separate safety library or invoke its real entry. This keeps test safety authorization attached to the executable that owns the eventual whitelisted Trash capability, while allowing safety behavior to be tested through internal seams with `@testable import rmp_test`.

Within `RMPCore`, command handling is layered through narrow module Interfaces:

- `CLIApplication` is the only public command Interface. It accepts raw arguments, performs global
  validation, renders information commands and CLI diagnostics, and dispatches native Trash
  Operation requests.
- `DryRunApplication` is an internal use-case module. It accepts an already parsed native request and
  returns a command result; it does not parse command-line arguments.
- `TrashPlanner` is an internal domain module. It inspects top-level Trash Inputs through the injected
  filesystem seam and returns a Trash Plan without CLI compatibility concepts.

Platform adapters are supplied to `CLIApplication` through an explicit `makeFileSystem` factory.
Information commands finish without invoking that factory; operation commands create the adapter only
after parsing and global validation succeed. Compatibility diagnostics remain beside the parsed
command in the CLI envelope rather than entering a Trash Operation request or Trash Plan.
