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
```

Dry-run mode inspects only the supplied top-level entries, reports each entry kind in input order,
and never moves or deletes anything. Filesystem root, the current working directory, and the current
user's home directory are Protected Paths; explicit parent-directory expressions such as `..` are
also rejected. Safety rejections return exit code 3.

The parser accepts native confirmation, missing-path, output, automation, and batch-control options.
Familiar `-r`, `-R`, `-d`, and `-x` Compatibility Options are accepted with no effect because
directories are moved as top-level items. `-P` warns that no secure overwrite occurs, `-W` is
rejected, and `--strict-options` rejects all no-effect Compatibility Options. Run `rmp --help` for
concise native help, `rmp --help -a` for the compatibility matrix, and add `-zh` for Chinese help.
Help and version commands complete without constructing the platform filesystem adapter or inspecting
Trash Inputs.

Smart confirmation moves one ordinary file or link without prompting and asks once for multiple
top-level inputs or any directory. `never` never prompts, `once` asks once, and `each` asks before
each input. Prompts are written to stderr; only `y` or `yes`, ignoring case and surrounding
whitespace, approves a move. A declined, invalid, interrupted, non-interactive, or non-TTY
confirmation exits with code 1 and never authorizes the affected Trash call.

All inputs are planned before confirmation, so root execution and Protected Paths still fail with
exit code 3 before any prompt or Trash capability. Approved inputs are passed as top-level entries to
the macOS Foundation Trash API in input order, without recursive traversal, and each success reports
the exact system-returned destination path. A system Trash failure never falls back to permanent
deletion or direct Trash-directory manipulation, and reports `not_moved` only when the original
entry identity can be confirmed unchanged; otherwise it reports `state_uncertain`.

## Project status

- Product requirements: [`.scratch/rmp-core/spec.md`](.scratch/rmp-core/spec.md)
- Development guide: [`docs/development.md`](docs/development.md)
- Contribution guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Security policy: [`SECURITY.md`](SECURITY.md)

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
