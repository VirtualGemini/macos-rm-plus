# rmp Help Contract

The complete help and compatibility interface has not been implemented. The currently supported
operational form is:

```text
rmp --dry-run [--] <PATH>...
```

`--` permits a Trash Input whose path begins with a hyphen. A successful preview writes the complete
top-level Trash Plan to stdout in input order. Each line contains the entry kind and a quoted path;
control characters are escaped so paths containing newlines remain unambiguous. Dry-run mode never
moves, deletes, overwrites, or sends an item to Trash.

Missing inputs return exit code 1, usage and unsupported-option errors return exit code 2, and
Protected Paths return exit code 3 without presenting a plan. Protected Paths include filesystem
root, the current working directory, the user's home directory, their identity-equivalent path
expressions, and explicit parent-directory expressions such as `..`. Commands without `--dry-run`
remain unsupported until the complete CLI ticket is implemented.

When CLI arguments, output, or exit codes are implemented or changed, this document must be updated
in the same pull request alongside the README, product specification, domain language, and changelog.
