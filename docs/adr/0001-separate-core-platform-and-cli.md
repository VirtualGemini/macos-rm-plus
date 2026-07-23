# Separate core policy, macOS adapters, and CLI entrypoints

The project separates pure command parsing, planning, safety policy, and output models into `RMPCore`; macOS system-framework integrations into `RMPPlatform`; and executable wiring into `rmp`. Test doubles and pure test support live in `RMPTestKit`.

The real Test Safety Context implementation and its process entry belong to the compile-time-isolated `rmp-test` executable module. That module is built only with `RMP_TESTING`; unflagged targets cannot import a separate safety library or invoke its real entry. This keeps test safety authorization attached to the executable that owns the eventual whitelisted Trash capability, while allowing safety behavior to be tested through internal seams with `@testable import rmp_test`.

Within `RMPCore`, command handling is layered through narrow module Interfaces:

- `CLIApplication` is the only public command Interface. It accepts raw arguments, performs global
  validation, renders information commands and CLI diagnostics, and dispatches native Trash
  Operation requests.
- `DryRunApplication` is an internal use-case module. It accepts an already parsed native request and
  returns a command result; it does not parse command-line arguments.
- `TrashOperationApplication` is the internal non-dry-run use-case module for the current confirmation
  slice. It plans every top-level input before prompting, applies batch or per-input confirmation,
  and delegates only approved inputs to `SingleTrashExecutor` in input order.
- `SingleTrashExecutor` records the exact system-returned destination or classifies a failure as
  `not_moved` versus `state_uncertain` by re-inspecting the original entry through the filesystem
  seam. Its only mutation-capable dependency is the narrow `TrashClient` Interface.
- `TrashPlanner` is an internal domain module. It inspects top-level Trash Inputs through the injected
  filesystem seam and returns a Trash Plan without CLI compatibility concepts.

Platform adapters are supplied to `CLIApplication` through explicit `makeFileSystem`,
`makeTrashClient`, and `makeConfirmationPrompt` factories. Information commands finish without
invoking these factories. Dry-run commands invoke only the read-only filesystem factory. Actual
commands reject root and unsupported output before filesystem construction, plan all inputs before
prompting, and construct the Trash capability only for approved inputs.
`RMPPlatform.StandardInputConfirmationPrompt` checks stdin TTY state, writes prompts to stderr, and
maps terminal lines or interruption into raw confirmation responses; approval remains pure RMPCore
policy. `RMPPlatform.FinderTrashClient` contains the Finder Automation Trash call, while the
compile-time-isolated test executable reaches it only through `WhitelistedTrashClient`.
Compatibility diagnostics remain beside the parsed command in the CLI envelope rather than entering
a Trash Operation request or Trash Plan.

`FinderTrashClient` invokes one fixed AppleScript handler with the approved source path supplied as a
structured Apple Event argument. Finder executes `delete`, and the handler returns the deleted
Finder item's `URL` property for the existing synchronous `TrashMoveReceipt`. The adapter never
interpolates path text into script source, applies a finite Finder timeout, maps Automation consent,
denial, timeout, and availability failures to stable core codes, and never falls back to
`FileManager.trashItem`, `NSWorkspace.recycle`, or direct Trash-directory manipulation.

Issue 12 demonstrated that Finder can overwrite Put Back metadata written by both Foundation and
Workspace callers during a rapid same-name re-trash. The maintainer accepted the first-use macOS
Automation authorization cost so Finder can be the writer for the second Trash Operation. The
candidate still requires the ticket's maintainer-run Automation and Put Back differentials before
release.
