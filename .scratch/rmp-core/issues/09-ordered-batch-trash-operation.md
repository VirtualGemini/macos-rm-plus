# 09 — Process an ordered batch Trash Operation

**What to build:** Let users process multiple Trash Inputs serially with predictable partial-success, missing-path, stop-on-error, and human-output behavior while retaining the exact input order and avoiding directory traversal.

**Blocked by:** 08 — Execute deterministic confirmation policy.

**Status:** ready-for-agent

- [ ] Multiple inputs are evaluated and moved serially in command-line order, with one Trash Result recorded for every planned, moved, failed, or skipped input.
- [ ] By default, one failed input does not prevent later inputs from being processed; stop-on-error leaves later inputs skipped after the first failure.
- [ ] Missing inputs fail by default, while ignore-missing suppresses their error output and prevents them from causing a nonzero exit status.
- [ ] Aggregate exit code is 0 only when every required input succeeds or is an ignored missing path, 1 for operational failure or refusal, 2 for usage errors, and 3 for safety refusal.
- [ ] Default, verbose, and quiet modes follow the stdout/stderr contract; quiet suppresses normal output but never errors, while verbose reports each top-level result.
- [ ] The implementation decision for whether a single success is silent or summarized is recorded and remains consistent across the release.
- [ ] The implementation decision for compatibility `-P` warnings in non-TTY contexts is recorded, documented, and covered by tests.
- [ ] Batch summaries and processing costs depend on the number of top-level inputs rather than directory content size, including for large input lists.
- [ ] Real-filesystem coverage includes files, empty and deep directories, special-character names, missing paths, permission failures, and partial success within the authorized test boundary.
