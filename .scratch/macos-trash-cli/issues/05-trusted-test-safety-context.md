# 05 — Establish a trusted Test Safety Context

**What to build:** Make the compile-time-isolated test executable establish a trustworthy identity and authorization boundary before it accepts any real-filesystem Trash Input. Test operators get deterministic diagnostics when the fixed test hierarchy, markers, run identity, ownership, permissions, or executable identity are unsafe.

**Blocked by:** None — the completed project scaffold provides the required foundation.

**Status:** resolved

- [x] The test driver obtains the real user's home directory from trusted system account information rather than caller-controlled environment variables.
- [x] The fixed outer container and authorized test root are exclusively created when absent, or validated without following symlinks when present, with the required ownership and permissions.
- [x] Long-lived markers are exclusively created with the required ownership, permissions, format version, directory role, and recorded directory identity; existing markers are validated but never rewritten or silently repaired.
- [x] Every run exclusively creates a fresh UUID-named Run Directory and matching run marker, records all three directory identities, and refuses reuse or mismatch.
- [x] The driver rejects root execution, a missing testing build flag, the wrong executable identity, an absent or invalid test run ID, or unsafe directory state before parsing path arguments.
- [x] The Test Safety Context retains open directory handles for the fixed container, authorized root, and Run Directory for the duration of the run where the platform permits it.
- [x] Failure tests cover symlinks, wrong object types, unsafe permissions, ownership mismatch, corrupt markers, identity mismatch, and UUID reuse without performing a Trash capability call.
- [x] Cleanup can remove only a revalidated run marker and an already-empty Run Directory; it never recursively cleans or removes either fixed safety directory or its long-lived marker.
