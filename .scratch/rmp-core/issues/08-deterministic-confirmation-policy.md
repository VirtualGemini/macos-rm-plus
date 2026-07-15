# 08 — Execute deterministic confirmation policy

**What to build:** Give interactive users and automation a complete, deterministic confirmation experience across smart, never, once, and each modes without weakening Protected Path or root safety.

**Blocked by:** 04 — Provide the complete compatible command-line interface; 07 — Move one Trash Input safely through the system Trash.

**Status:** resolved

- [x] Smart confirmation proceeds without a prompt for one ordinary file and requests one confirmation for multiple top-level inputs or any directory input.
- [x] Never, once, and each modes prompt or proceed exactly as specified, and per-item rejection continues to later inputs unless stop-on-error is active.
- [x] Compatibility options `-f`, `-i`, and `-I` produce their documented confirmation and missing-path behavior after left-to-right precedence is applied.
- [x] Non-interactive mode and non-TTY stdin never block; an operation that still requires confirmation fails with a recognizable diagnostic and exit code 1.
- [x] Negative, invalid, and interrupted confirmation responses never initiate an unapproved Trash call.
- [x] Confirmation summaries count only top-level inputs and directories and never recursively scan contents or calculate directory sizes.
- [x] Protected Path and root refusals occur independently of confirmation and remain exit code 3 under every confirmation option.
- [x] Tests exercise the confirmation matrix through executable-level input/output seams with fake prompts and Trash capabilities.

## Comments

Implemented deterministic confirmation through an injected `ConfirmationPrompt` boundary and the
production standard-input adapter. Core behavior tests cover the complete mode, response, TTY,
compatibility-precedence, summary, and safety matrix with fake prompt and Trash capabilities.
`make check` passed with 120 pure tests and 95.39% production line coverage; no real Trash API call
was executed.
