# 06 — Encapsulate the whitelisted system Trash capability

**What to build:** Ensure every real-filesystem test Trash Operation passes through a single platform capability that accepts a verified Test Safety Context, revalidates authorization immediately before the system call, and cannot be constructed or bypassed accidentally by tests.

**Blocked by:** 05 — Establish a trusted Test Safety Context.

**Status:** ready-for-human

- [x] Real Foundation Trash behavior is available to tests only through a whitelist-enforcing capability constructed with a previously verified Test Safety Context.
- [x] Production and testing capabilities are separated at compile time or dependency-wiring boundaries; no environment variable can enable test behavior in the production executable.
- [x] Authorization uses path-component and directory-identity checks rather than string prefixes, rejects intermediate symlink escape, and permits a final symlink only as the directory entry being operated on.
- [x] Targets must be descendants below the Run Directory, may not be any safety directory itself, must carry the current run UUID fixture prefix, and must remain on the authorized local volume.
- [x] Mount points, cross-volume entries, network locations, and File Provider special roots are rejected before the system Trash API is invoked.
- [x] The fixed container, authorized root, and Run Directory identities are rechecked before every real Trash call, providing the second authorization check required after planning.
- [x] Spy-based tests prove that every whitelist, marker, identity, permission, volume, and symlink rejection results in zero system Trash capability calls.
- [x] Returned Trash URLs are treated as read-only verification evidence and are never searched for, permanently deleted, or used for automated local Trash cleanup.
