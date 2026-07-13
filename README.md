# macos-rm-plus

`macos-rm-plus` is a macOS command-line tool. The core command is `rmp`.
It will move files and directories to the system Trash instead of permanently deleting them.

The current operational slice supports safe Trash Plan previews through the complete v0.1-compatible
command-line parser:

```sh
rmp -Rfv --dry-run report.txt build
rmp --dry-run -- -leading-hyphen
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
Actual Trash moves remain unavailable until the system Trash capability is implemented; non-dry-run
operations fail closed.

## Project status

- Product requirements: [`.scratch/rmp-core/spec.md`](.scratch/rmp-core/spec.md)
- Development guide: [`docs/development.md`](docs/development.md)
- Contribution guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Security policy: [`SECURITY.md`](SECURITY.md)

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
