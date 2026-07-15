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
BASE_SHA="$(git merge-base origin/main HEAD)"
./scripts/check-commits.sh "$BASE_SHA" HEAD
```

`make check` validates the checked-out source tree, but it does not validate every commit message in
the pull-request history. The explicit `check-commits.sh` range check is therefore mandatory before
declaring a branch ready for review or merge.

Work from a ticket under `.scratch/<feature>/issues/`, use one branch per ticket, and open a pull
request. Breaking changes require maintainer approval in the ticket before implementation begins.
That approval ticket must already be present on the target branch before the implementation branch
is created; approval added by the breaking-change pull request itself is invalid.

Security vulnerabilities must follow [`SECURITY.md`](SECURITY.md) instead of a public issue.
