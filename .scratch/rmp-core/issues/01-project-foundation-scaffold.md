# Project foundation scaffold

Status: ready-for-agent

## Outcome

Create the non-functional SwiftPM project foundation and repository policy gates agreed for rmp.

## Acceptance criteria

- The requested source, test-support, test, documentation, script, hook, and workflow structure
  exists without implementing Trash behavior.
- Debug and Release builds succeed and the executable fails closed as an unimplemented scaffold.
- Coding, testing, review, acceptance, commit, breaking-change, dependency, security, and release
  policies are documented and enforced where automation is possible.
- Documentation impact is checked for staged commits, individual PR commits, and the aggregate PR
  diff, including deletions.
- `Docs-Impact: none` requires a reason and approval by someone other than the author.
- All non-destructive checks pass with `make check`.

## Comments

The maintainer approved implementation in the preceding design conversation.
