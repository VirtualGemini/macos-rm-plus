# rmp Help Contract

The supported operational forms are:

```text
rmp [OPTIONS] [--] <PATH>
rmp [OPTIONS] --dry-run [--] <PATH>...
```

`--` permits a Trash Input whose path begins with a hyphen. A successful preview writes the complete
top-level Trash Plan to stdout in input order. Each line contains the entry kind and a quoted path;
control characters are escaped so paths containing newlines remain unambiguous. Dry-run mode never
moves, deletes, overwrites, or sends an item to Trash.

Non-dry-run execution currently accepts exactly one top-level file, directory, symbolic link, or
broken symbolic link. One ordinary file or link proceeds under smart confirmation; a directory must
use `--confirm=never` until interactive confirmation is available. Modes that still require a prompt
fail closed with `confirmation_required` and make no Trash call. Successful execution uses the macOS
Foundation Trash API and reports its exact resulting destination path. Failure never triggers
permanent deletion, direct Trash-directory access, overwrite, or automatic move-back.
Quiet mode suppresses a successful single-item result but never an error. Non-dry-run JSON output
fails closed until the versioned schema is implemented; it never emits human output on stdout while
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
