# rmp Help Contract

The supported operational forms are:

```text
rmp [OPTIONS] [--] <PATH>...
rmp [OPTIONS] --dry-run [--] <PATH>...
```

`--` permits a Trash Input whose path begins with a hyphen. A successful preview writes the complete
top-level Trash Plan to stdout in input order. Each line contains the entry kind and a quoted path;
control characters are escaped so paths containing newlines remain unambiguous. Dry-run mode never
moves, deletes, overwrites, or sends an item to Trash.

Smart confirmation proceeds without a prompt for one ordinary file or link and asks once for
multiple top-level inputs or any directory. `never` proceeds without prompting, `once` asks once for
the complete top-level summary, and `each` asks before each input. `-I` asks once when more than three
top-level inputs are supplied or a planned input is a directory. Confirmation summaries count only
top-level inputs and directories and never inspect directory contents or calculate sizes.

Prompts are written to stderr. After surrounding whitespace is ignored, only case-insensitive `y` or
`yes` approves an input. Empty, `n`, or `no` responses decline; other text is invalid; and end of
input is interrupted. These outcomes report `confirmation_declined`,
`confirmation_invalid_response`, or `confirmation_interrupted`, respectively, with exit code 1 and
no unapproved Trash call. Invalid per-input responses continue like a rejection; interrupted input
stops further prompts because no later approval can be read. `--non-interactive`, a non-TTY stdin,
or an unavailable prompt capability reports `confirmation_required` without reading input or
blocking.

All paths are planned before confirmation. Approved ordinary entries are passed to Finder serially
through a structured Apple Event. Symbolic links use Foundation directly, never as a Finder failure
fallback, and an owned finalizer preserves Put Back without following the link target. Each success
reports the system-returned exact URL. Failure never triggers permanent deletion,
`NSWorkspace.recycle`, direct Trash-directory access, or overwrite.
By default, an item failure does not prevent later inputs from being processed; `--stop-on-error`
records all later inputs as skipped. Missing inputs fail unless `--ignore-missing` is active, in
which case their error output and exit-status effect are suppressed.

One standard-mode success writes exactly one escaped line containing the user-provided source and
the exact Trash receipt destination. A standard-mode batch writes one aggregate summary instead of
per-item success lines. `--verbose` writes every top-level moved or skipped result in input order.
Quiet mode suppresses normal results but never a warning or error. Non-dry-run JSON output fails closed
until the versioned schema is implemented; it never emits human output on stdout while claiming to
be JSON.

The first real Trash Operation may show a macOS Automation prompt allowing the invoking terminal or
`rmp` to control Finder. Accepted permission is normally reused for that sender-to-Finder pair but
can be revoked, reset, or requested separately by another terminal application. Consent-required,
denied, unavailable-Finder, and timeout outcomes fail closed with stable error codes.

Finder owns the private metadata used by “Put Back.” Finder handles ordinary entries directly but
refuses symbolic links. For links, rmp prepares two same-directory finalizers before moving the
target, makes the target the first Foundation Trash call, then uses a successful Foundation
finalizer call to activate Put Back. It does not run a target-before-move Trash preflight because
that call was shown to consume the metadata transition needed by the target.
Normal completion is silent and leaves no helper behind. `symlink_put_back_not_guaranteed` or
`finalizer_cleanup_failed` reports a moved result with its exact destination on stderr and exits 1.
If a failed finalizer call no longer has its exact source identity, rmp stops without using the
backup and reports `finalizer_state_uncertain`, preserving the best available Put Back state.
If the user link has not moved but a prepared finalizer cannot be identity-verified and removed, the
operation instead fails with `finalizer_cleanup_failed`; its `not_moved` or `state_uncertain`
classification comes from the normal post-call source-identity check.

Native options set confirmation (`-f`, `-i`, `-I`, `--confirm`), missing-path
(`--ignore-missing`), output (`-v`, `--quiet`, `--json`), preview (`--dry-run`), automation
(`--non-interactive`), batch (`--stop-on-error`), and compatibility-validation
(`--strict-options`) policy independently. Arguments are parsed once from left to right, including
characters within combined short options. `--json` conflicts with `--quiet`; `--verbose` does not
change JSON output policy.

Compatibility Options `-r`, `-R`, `-d`, and `-x` are accepted with no effect. `-P` is accepted with
a stderr warning that secure overwrite is not performed. That warning is independent of TTY state,
`--non-interactive`, `--quiet`, and redirection, and does not change an otherwise successful exit
code. `-W` is unsupported. `--strict-options` rejects every no-effect Compatibility Option,
including `-P`, before filesystem inspection, confirmation, or Trash capability construction.

`rmp --help` prints concise native help, while `rmp --help -a` groups compatibility behavior into
accepted-with-no-effect, accepted-with-warning, and unsupported sections. `-zh` selects Chinese for
either help surface. `rmp --version` prints `rmp 0.1.0`. These information commands require no Trash
Input, do not construct the platform filesystem adapter, and do not inspect filesystem or Trash
capabilities.

Required missing paths and operational failures return exit code 1. Usage errors and unsupported
options return exit code 2. Protected Paths return exit code 3 without presenting a plan. Protected Paths include filesystem
root, the current working directory, the user's home directory, their identity-equivalent path
expressions, and explicit parent-directory expressions such as `..`. Effective root execution also
returns exit code 3 before planning or Trash capability construction. `-f`, `--confirm=never`, and
`--non-interactive` cannot bypass root or Protected Path policy. A failed system Trash call reports a
stable code plus `not_moved` when the original identity remains, or `state_uncertain` when the final
state cannot be established reliably.
