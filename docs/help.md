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

All paths are planned before confirmation, and approved inputs are passed to the macOS Foundation
Trash API serially in input order. Each success reports its exact resulting destination path.
Failure never triggers permanent deletion, direct Trash-directory access, overwrite, or automatic
move-back. Quiet mode suppresses successful results but never an error. Non-dry-run JSON output fails
closed until the versioned schema is implemented; it never emits human output on stdout while
claiming to be JSON.

Native options set confirmation (`-f`, `-i`, `-I`, `--confirm`), missing-path
(`--ignore-missing`), output (`-v`, `--quiet`, `--json`), preview (`--dry-run`), automation
(`--non-interactive`), batch (`--stop-on-error`), and compatibility-validation
(`--strict-options`) policy independently. Arguments are parsed once from left to right, including
characters within combined short options. `--json` conflicts with `--quiet`; `--verbose` does not
change JSON output policy.

Compatibility Options `-r`, `-R`, `-d`, and `-x` are accepted with no effect. `-P` is accepted with
a stderr warning that secure overwrite is not performed. `-W` is unsupported. `--strict-options`
rejects every no-effect Compatibility Option, including `-P`.

`rmp --help` prints concise native help, while `rmp --help -a` groups compatibility behavior into
accepted-with-no-effect, accepted-with-warning, and unsupported sections. `-zh` selects Chinese for
either help surface. `rmp --version` prints `rmp 0.1.0`. These information commands require no Trash
Input, do not construct the platform filesystem adapter, and do not inspect filesystem or Trash
capabilities.

Missing paths return exit code 1; absent Trash Inputs, usage errors, and unsupported options return
exit code 2; and
Protected Paths return exit code 3 without presenting a plan. Protected Paths include filesystem
root, the current working directory, the user's home directory, their identity-equivalent path
expressions, and explicit parent-directory expressions such as `..`. Effective root execution also
returns exit code 3 before planning or Trash capability construction. `-f`, `--confirm=never`, and
`--non-interactive` cannot bypass root or Protected Path policy. A failed system Trash call reports a
stable code plus `not_moved` when the original identity remains, or `state_uncertain` when the final
state cannot be established reliably.
