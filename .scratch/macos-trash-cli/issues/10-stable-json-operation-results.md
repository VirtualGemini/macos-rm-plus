# 10 — Emit stable JSON Trash Operation results

**What to build:** Give scripts and agents one versioned JSON document that represents dry runs, successful moves, failures, skipped inputs, and partial success without mixing human output into stdout.

**Blocked by:** 09 — Process an ordered batch Trash Operation.

**Status:** resolved

- [x] JSON output uses schema version 1 and includes operation, dry-run state, aggregate success and counts, plus an ordered result for every top-level Trash Input.
- [x] Every item exposes an absolute source, nullable destination, item kind, status, and nullable structured error with a stable code and human-readable message.
- [x] Planned, moved, failed, and skipped states accurately represent dry-run, success, refusal, missing-path, stop-on-error, and partial-success outcomes.
- [x] Stdout contains exactly one complete JSON document with no human-readable success line in JSON mode; warnings and diagnostics do not corrupt it.
- [x] JSON-mode tests prove that an accepted `-P` still warns on stderr with TTY or non-TTY input while stdout remains exactly one complete JSON document and the warning alone does not change a successful exit code.
- [x] JSON combined with quiet is rejected as a usage error, while verbose does not alter or expand the schema.
- [x] The decision on exposing Foundation error domain and numeric code is recorded; consumers are explicitly directed to depend only on tc's stable error codes.
- [x] Snapshot or equivalent contract tests lock the schema and exercise special characters, final system Trash URLs, state-uncertain failures, and every aggregate exit category.
- [x] JSON generation does not retain or upload path history and the documentation calls out that absolute paths may contain sensitive information.
