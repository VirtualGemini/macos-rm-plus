# 03 — Safely preview a Trash Plan

**What to build:** Let users run `rmp` in dry-run mode to preview the complete top-level Trash Plan without changing the filesystem. Basic path inputs become domain-level Trash Inputs, retain input order, report their kind, and are checked against protected-path policy before a plan is presented.

**Blocked by:** None — the completed project scaffold provides the required foundation.

**Status:** ready-for-agent

- [x] A dry run accepts one or more file, directory, symlink, broken-symlink, and other top-level path entries and presents the planned work in input order without recursively inspecting directory contents.
- [x] A dry run performs no move, deletion, overwrite, Trash call, or other filesystem mutation.
- [x] Filesystem root, the current working directory, the user's home directory, and their equivalent path expressions are rejected as Protected Paths with exit code 3.
- [x] Protected-path comparison preserves the rule that a symlink entry may be planned without treating its destination as the Trash Input.
- [x] Missing paths fail by default, while paths containing spaces, Unicode, newlines, long components, or a leading hyphen are represented without corruption.
- [x] The execution-facing Trash Plan contains only native Trash Operation policy and does not expose compatibility concepts such as recursion, one-filesystem traversal, or secure overwrite.
- [x] Core tests use fake filesystem capabilities for dangerous path expressions and prove that no real executable receives a system or user-data path.
