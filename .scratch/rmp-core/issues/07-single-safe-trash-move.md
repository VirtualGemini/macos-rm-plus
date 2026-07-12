# 07 — Move one Trash Input safely through the system Trash

**What to build:** Let a user move one file, directory, symlink, or broken symlink through the macOS system Trash API while preserving clear safety boundaries and honest outcome reporting. A failed operation must never trigger a destructive fallback or an unsafe compensating action.

**Blocked by:** 03 — Safely preview a Trash Plan; 06 — Encapsulate the whitelisted system Trash capability.

**Status:** ready-for-agent

- [ ] A single supported Trash Input is passed to the Foundation system Trash API as a top-level entry, without recursive traversal or direct manipulation of a Trash directory.
- [ ] Success records and reports the exact resulting URL supplied by the system so name-conflict renames are represented correctly.
- [ ] Validation failures occur before the system call and guarantee zero filesystem changes and zero Trash capability calls.
- [ ] System Trash failure never invokes permanent deletion, direct `~/.Trash` manipulation, overwrite, automatic move-back, or any other compensating filesystem mutation.
- [ ] When the original entry can be confirmed unchanged, failure is reported as `not_moved`; when the final state cannot be established reliably, it is reported as `state_uncertain` and never misrepresented as success or rollback.
- [ ] Every failure exposes a stable machine-readable error code and a clear human explanation that identifies the affected source path without requiring the user to interpret a Foundation error.
- [ ] Effective root execution is rejected with exit code 3 before an actual move, and force, non-interactive, or never-confirm options cannot bypass root or Protected Path policy.
- [ ] A symlink to a Protected Path moves only the symlink entry, including when broken, and never moves or resolves the link destination for execution.
- [ ] Tests prove that Trash API failure leaves no rmp-controlled path to permanent removal and that all real-filesystem fixtures remain inside the authorized Run Directory.
