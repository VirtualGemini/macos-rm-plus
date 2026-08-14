# 09 — Process an ordered batch Trash Operation

**What to build:** Let users process multiple Trash Inputs serially with predictable partial-success, missing-path, stop-on-error, and human-output behavior while retaining the exact input order and avoiding directory traversal.

**Blocked by:** 08 — Execute deterministic confirmation policy.

**Status:** resolved

- [x] Multiple inputs are evaluated and moved serially in command-line order, with one Trash Result recorded for every planned, moved, failed, or skipped input.
- [x] By default, one failed input does not prevent later inputs from being processed; stop-on-error leaves later inputs skipped after the first failure.
- [x] Missing inputs fail by default, while ignore-missing suppresses their error output and prevents them from causing a nonzero exit status.
- [x] Aggregate exit code is 0 only when every required input succeeds or is an ignored missing path, 1 for operational failure or refusal, 2 for usage errors, and 3 for safety refusal.
- [x] Default mode emits one result line containing the user-provided source and exact Trash receipt destination for a single success, and one aggregate summary rather than per-item success lines for a batch; verbose reports each top-level result, while quiet suppresses normal output but never warnings or errors.
- [x] Pure CLI tests prove the single-success result is one escaped line, uses the same item format in verbose mode, and is suppressed by quiet.
- [x] In default compatibility mode, `-P` always emits its secure-overwrite warning to stderr regardless of TTY state, `--non-interactive`, quiet, or redirection; the warning alone does not change a successful exit code.
- [x] Pure CLI tests cover `-P` with TTY and non-TTY input plus quiet mode; both option orders with `--strict-options` return usage exit code 2, emit only the strict-mode error, and prove zero path-inspection, confirmation, and Trash calls.
- [x] Batch summaries and processing costs depend on the number of top-level inputs rather than directory content size, including for large input lists.
- [x] Real-filesystem coverage includes files, empty and deep directories, special-character names, missing paths, permission failures, and partial success within the authorized test boundary.

## Comments

Implemented with pure CLI and acceptance-verifier coverage. The maintainer-only real Finder command
is `make test-ordered-batch TEST_RUN_ID=<canonical-lowercase-uuid>`; it was intentionally not run by
the implementation agent, so this change created no real Trash items.
