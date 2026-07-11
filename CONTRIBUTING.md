# Contributing

Thank you for contributing to rmp.

Before starting work, read the complete [Development Guide](docs/development.md). It is the single
source of truth for toolchain setup, coding rules, tests, review, commits, documentation impact,
CI, and releases.

## Quick start

```sh
make bootstrap
make hooks-install
make check
```

Work from a ticket under `.scratch/<feature>/issues/`, use one branch per ticket, and open a pull
request. Breaking changes require maintainer approval in the ticket before implementation begins.

Security vulnerabilities must follow [`SECURITY.md`](SECURITY.md) instead of a public issue.
