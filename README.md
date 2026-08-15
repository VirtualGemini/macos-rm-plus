# macos-rm-plus

`macos-rm-plus` is a macOS command-line tool. The core command is `rmp`.
It will move files and directories to the system Trash instead of permanently deleting them.

The current operational slice supports safe Trash Plan previews, deterministic confirmation, and
approved top-level Trash moves through the complete v0.1-compatible command-line parser:

```sh
rmp -Rfv --dry-run report.txt build
rmp --dry-run -- -leading-hyphen
rmp report.txt
rmp --confirm=once build report.txt
rmp --json --non-interactive --confirm=never report.txt build
```

Dry-run mode inspects only the supplied top-level entries, reports each entry kind in input order,
and never moves or deletes anything. Filesystem root, the current working directory, and the current
user's home directory are Protected Paths; explicit parent-directory expressions such as `..` are
also rejected. Safety rejections return exit code 1.

The parser accepts native confirmation, missing-path, output, automation, and batch-control options.
Familiar `-r`, `-R`, `-d`, and `-x` Compatibility Options are accepted with no effect because
directories are moved as top-level items. `-P` warns that no secure overwrite occurs, `-W` is
rejected, and `--strict-options` rejects all no-effect Compatibility Options. Run `rmp --help` for
concise native help, `rmp --help -a` for the compatibility matrix, and add `-zh` for Chinese help.
Help and version commands complete without constructing the platform filesystem adapter or inspecting
Trash Inputs.

Trash Inputs are processed serially in command-line order. By default, a missing or failed input is
reported and later inputs continue; `--stop-on-error` records every later input as skipped instead.
`--ignore-missing` keeps an absent input in the ordered result set but suppresses its diagnostic and
does not make the operation fail. A single standard-mode success prints its escaped source and exact
system-returned Trash destination on one line. A batch prints one aggregate summary, `--verbose`
prints every top-level result, and `--quiet` suppresses normal output without hiding warnings or
errors.

`--json` writes exactly one schema-version-1 document to stdout for a preview or real Trash
Operation. It includes aggregate success and counts plus one ordered `planned`, `moved`, `failed`, or
`skipped` item for every top-level input. Each item carries an absolute source, its inspected kind,
the exact system-returned destination when moved, and a nullable error containing an rmp stable code
and human-readable message. Compatibility warnings and operational diagnostics remain on stderr;
`--verbose` does not change the JSON schema, and `--quiet` conflicts with `--json`. Machine consumers
must depend only on rmp error codes, not message text or Foundation error details. JSON output can
contain sensitive absolute paths; rmp neither retains nor uploads path history.

Smart confirmation moves one ordinary file or link without prompting and asks once for multiple
top-level inputs or any directory. `never` never prompts, `once` asks once, and `each` asks before
each input. Prompts are written to stderr; only `y` or `yes`, ignoring case and surrounding
whitespace, approves a move. A declined, invalid, or interrupted per-input confirmation does not
change the successful exit code; non-interactive or non-TTY confirmation that is required exits with
code 1 and never authorizes the affected Trash call.

The `-P` Compatibility Option always warns on stderr that secure overwrite is not performed,
including with non-TTY input, `--non-interactive`, `--quiet`, or redirected output. The warning alone
does not change a successful exit code. With `--strict-options`, `-P` is a usage error and parsing
stops before filesystem inspection, confirmation, or Trash capability construction.

All inputs are planned before confirmation, so root execution and Protected Paths still fail with
exit code 1 before any prompt or Trash capability. Approved ordinary files and directories are
passed to Finder in input order through a structured Apple Event. Symbolic links use Foundation
without following their targets, plus an identity-verified finalizer that preserves Finder Put Back.
Every success reports the system-returned exact URL. A Finder failure never falls back to Foundation,
and no failure falls back to permanent deletion, `NSWorkspace.recycle`, or direct Trash-directory
manipulation. Failures report `not_moved` only when the original entry identity is confirmed
unchanged; otherwise they report `state_uncertain`.

The first real Trash Operation may show a macOS Automation prompt allowing the invoking terminal or
`rmp` to control Finder. An accepted permission is normally reused for that sender-to-Finder pair.
If permission is required, denied, reset, or used from another terminal host, `rmp` fails closed with
an actionable stable error instead of silently using a less reliable Trash API.

Finder owns the private metadata behind “Put Back.” Ordinary entries therefore use Finder directly.
Finder refuses symbolic links, so rmp prepares two owned hidden symbolic-link finalizers, moves the
user link through Foundation as the first Foundation Trash call, then performs one successful
Foundation finalizer call and cleans up the exact identity outside Trash. Normal success leaves no
finalizer residue. A target-before-move Trash preflight is deliberately omitted because real Finder
checks showed that it consumes the metadata transition needed by the following user link. If every
prepared activation fails, or an activated finalizer cannot be cleaned up, rmp preserves the target
destination and emits a stable warning without changing the successful exit code. A failed finalizer call is retried only when
the exact helper is still verified at its source; if it moved before throwing, rmp stops with
`finalizer_state_uncertain` instead of shifting the metadata again. If the target has not moved but
a prepared helper can no longer be safely cleaned up, rmp reports `finalizer_cleanup_failed` as a
failed Trash Result and classifies the source from its verified post-call identity. The evidence and
release acceptance remain tracked in
[issue 12](.scratch/rmp-core/issues/12-put-back-metadata-race.md).

Exit Status Compatibility changes only numeric results and does not change rmp's Trash behavior:
`0` means success, `1` means an operational or safety failure, and `64` means command-line usage
failure. `-W` remains explicitly unsupported.

## Project status

- Product requirements: [`.scratch/rmp-core/spec.md`](.scratch/rmp-core/spec.md)
- Development guide: [`docs/development.md`](docs/development.md)
- Contribution guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Security policy: [`SECURITY.md`](SECURITY.md)

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
