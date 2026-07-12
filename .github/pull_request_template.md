<!-- SPDX-License-Identifier: Apache-2.0 -->

## Summary

Describe the user-visible or engineering outcome.

## Ticket

Link the tracked file under `.scratch/<feature>/issues/`.

## Standards Review

- [ ] Module boundaries and dependency rules are respected.
- [ ] Error handling and concurrency follow `docs/development.md`.
- [ ] Formatting, linting, builds, and required tests pass.
- [ ] No unresolved critical, high, or medium findings remain without accepted rationale.

## Spec Review

- [ ] The ticket and PRD acceptance criteria are satisfied.
- [ ] Safety invariants are covered by tests.
- [ ] User-visible behavior matches the documented contract.

## Documentation Impact

- Docs-Impact: `updated` / `none`
- Docs-Impact-Reason, when none:
- Docs-Impact-Approved-By GitHub handle, when none:
- Updated documents:
- [ ] The named reviewer has submitted an active approving review and is not the PR author.

## Breaking Change

- Breaking change: `yes` / `no`
- Approval ticket, when yes:
- Migration plan, when yes:

## Test Evidence

Commands executed:

```text
make check
```

- Real macOS Trash API called: `yes` / `no`
- If yes, integration run URL and run UUID:

## Checklist

- [ ] Commits follow Conventional Commits and include DCO trailers.
- [ ] `CHANGELOG.md` is updated when users are affected.
- [ ] `CONTEXT.md` or an ADR is updated when vocabulary or architecture changed.
- [ ] Documentation-impact checks pass for both individual commits and the complete PR diff.
- [ ] No release or signing secret was exposed to this pull request.
