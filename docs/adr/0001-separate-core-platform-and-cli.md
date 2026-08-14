# Separate core policy, macOS adapters, and CLI entrypoints

The project separates pure command parsing, planning, safety policy, and output models into `RMPCore`; macOS system-framework integrations into `RMPPlatform`; and executable wiring into `rmp`. Test doubles and pure test support live in `RMPTestKit`.

The real Test Safety Context implementation and its process entry belong to the compile-time-isolated `rmp-test` executable module. That module is built only with `RMP_TESTING`; unflagged targets cannot import a separate safety library or invoke its real entry. This keeps test safety authorization attached to the executable that owns the eventual whitelisted Trash capability, while allowing safety behavior to be tested through internal seams with `@testable import rmp_test`.

Within `RMPCore`, command handling is layered through narrow module Interfaces:

- `CLIApplication` is the only public command Interface. It accepts raw arguments, performs global
  validation, renders information commands and CLI diagnostics, and dispatches native Trash
  Operation requests.
- `DryRunApplication` is an internal use-case module. It accepts an already parsed native request and
  returns a command result; it does not parse command-line arguments.
- `TrashOperationApplication` is the internal non-dry-run use-case module. It retains one ordered
  plan entry per supplied path, plans every top-level input before prompting, applies batch or
  per-input confirmation, delegates only approved inputs to `SingleTrashExecutor` serially, and
  records later entries as skipped when stop-on-error or interrupted confirmation ends processing.
- `SingleTrashExecutor` records the exact system-returned destination or classifies a failure as
  `not_moved` versus `state_uncertain` by re-inspecting the original entry through the filesystem
  seam. Its only mutation-capable dependency is the narrow `TrashClient` Interface.
- `TrashPlanner` is an internal domain module. It inspects top-level Trash Inputs through the injected
  filesystem seam and returns a Trash Plan without CLI compatibility concepts.

Platform adapters are supplied to `CLIApplication` through explicit `makeFileSystem`,
`makeTrashClient`, and `makeConfirmationPrompt` factories. Information commands finish without
invoking these factories. Dry-run commands invoke only the read-only filesystem factory. Actual
commands reject root before filesystem construction, plan all inputs before prompting, and construct
the Trash capability only for approved inputs. Production supplies the current directory through a
separate read-only closure so a root-rejected JSON operation can still report absolute sources
without constructing the filesystem adapter.
`RMPPlatform.StandardInputConfirmationPrompt` checks stdin TTY state, writes prompts to stderr, and
maps terminal lines or interruption into raw confirmation responses; approval remains pure RMPCore
policy. `RMPPlatform.MacOSTrashClient` owns production type dispatch and
`RMPPlatform.FinderTrashClient` contains the Finder Automation Trash call, while the
compile-time-isolated test executable reaches it only through `WhitelistedTrashClient`.
Compatibility diagnostics remain beside the parsed command in the CLI envelope rather than entering
a Trash Operation request or Trash Plan.

Human output is rendered once from the complete ordered result set. Standard mode prints one exact
escaped result for a single success or one aggregate summary for a batch; verbose prints every
top-level result, and quiet suppresses normal output without suppressing diagnostics.
JSON rendering consumes the same immutable plan or result set and writes one deterministic
schema-version-1 document to stdout. It exposes stable RMPCore error codes rather than platform error
domains or numeric codes; compatibility warnings and human diagnostics stay on stderr.

`FinderTrashClient` invokes one fixed AppleScript handler with the approved source path supplied as a
structured Apple Event argument. Finder executes `delete`, and the handler returns the deleted
Finder item's `URL` property for the existing synchronous `TrashMoveReceipt`. The adapter never
interpolates path text into script source, applies a finite Finder timeout, maps Automation consent,
denial, timeout, and availability failures to stable core codes, and never falls back to
`FileManager.trashItem`, `NSWorkspace.recycle`, or direct Trash-directory manipulation.

`MacOSTrashClient` dispatches final symbolic links to the Foundation Trash Finalizer protocol in
ADR-0002 and delegates every other supported entry to Finder. It preserves exact moved receipts and
stable post-move warnings without exposing platform details to RMPCore.

The compile-time-isolated `rmp-test` module owns one separate, test-only Finder Put Back adapter for
issue 12 acceptance. It can move only the exact UUID-prefixed URL returned by the whitelisted Trash
adapter back to the same revalidated Run Directory, verifies the available resource identifier, and
is unreachable from production wiring. The rapid acceptance orchestration and its fake adapter share
the `PutBackRaceAcceptance` Interface; ordinary unit tests never invoke Finder.

The same Interface serves a second restore variant that carries no Finder capability at all.
`ManualPutBackWaiter` observes the authorized Run Directory through a kqueue-backed dispatch source
and waits for the maintainer's real Finder Put Back command before the sequence fires its second
Trash call. Keeping both variants behind one orchestration Interface proves the sequence contract
once, while the scripted restore's Full Disk Access requirement stays confined to the only variant
that reads the home Trash.

Issue 12 demonstrated that Finder can overwrite Put Back metadata written by both Foundation and
Workspace callers during a rapid same-name re-trash. The maintainer accepted the first-use macOS
Automation authorization cost so Finder can be the writer for ordinary Trash Operations. The
ticket's maintainer-run Automation and Put Back differentials are complete on the reporting host;
the recorded evidence and remaining release decision live in issue 12.
