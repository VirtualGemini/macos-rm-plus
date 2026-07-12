# 08 — Execute deterministic confirmation policy

**What to build:** Give interactive users and automation a complete, deterministic confirmation experience across smart, never, once, and each modes without weakening Protected Path or root safety.

**Blocked by:** 04 — Provide the complete compatible command-line interface; 07 — Move one Trash Input safely through the system Trash.

**Status:** ready-for-agent

- [ ] Smart confirmation proceeds without a prompt for one ordinary file and requests one confirmation for multiple top-level inputs or any directory input.
- [ ] Never, once, and each modes prompt or proceed exactly as specified, and per-item rejection continues to later inputs unless stop-on-error is active.
- [ ] Compatibility options `-f`, `-i`, and `-I` produce their documented confirmation and missing-path behavior after left-to-right precedence is applied.
- [ ] Non-interactive mode and non-TTY stdin never block; an operation that still requires confirmation fails with a recognizable diagnostic and exit code 1.
- [ ] Negative, invalid, and interrupted confirmation responses never initiate an unapproved Trash call.
- [ ] Confirmation summaries count only top-level inputs and directories and never recursively scan contents or calculate directory sizes.
- [ ] Protected Path and root refusals occur independently of confirmation and remain exit code 3 under every confirmation option.
- [ ] Tests exercise the confirmation matrix through executable-level input/output seams with fake prompts and Trash capabilities.
