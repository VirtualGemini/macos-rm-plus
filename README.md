# macos-rm-plus

`macos-rm-plus` is a macOS command-line tool. The core command is `rmp`.
It will move files and directories to the system Trash instead of permanently deleting them.

The first operational slice supports safe Trash Plan previews:

```sh
rmp --dry-run report.txt build
```

Dry-run mode inspects only the supplied top-level entries, reports each entry kind in input order,
and never moves or deletes anything. Filesystem root, the current working directory, and the current
user's home directory are Protected Paths; explicit parent-directory expressions such as `..` are
also rejected. Safety rejections return exit code 3. Other operational modes and the complete
compatibility interface are not implemented yet.

## Project status

- Product requirements: [`.scratch/rmp-core/spec.md`](.scratch/rmp-core/spec.md)
- Development guide: [`docs/development.md`](docs/development.md)
- Contribution guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Security policy: [`SECURITY.md`](SECURITY.md)

## License

Apache License 2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
