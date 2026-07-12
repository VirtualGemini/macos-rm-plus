# 04 — Provide the complete compatible command-line interface

**What to build:** Give users a predictable `rm`-familiar command line that parses broadly but produces only native Trash Operation policy. The interface includes information commands, compatibility explanations, strict validation, and deterministic left-to-right option precedence.

**Blocked by:** 03 — Safely preview a Trash Plan.

**Status:** ready-for-agent

- [ ] All native options in the v0.1.0 specification parse into their documented independent policy fields, including explicit confirmation, missing-path, output, dry-run, non-interactive, and stop-on-error choices.
- [ ] Combined short options and mixed short/long invocations are processed once from left to right, with tests covering `-rf`, `-Rfv`, `-fi`, `-if`, repeated options, and explicit overrides.
- [ ] `--` ends option parsing and permits leading-hyphen Trash Inputs; unknown options and invalid or conflicting option combinations return exit code 2.
- [ ] Compatibility options are accepted, warned about, or rejected exactly as specified; strict mode rejects every no-effect compatibility option.
- [ ] The primary help remains concise, compatibility help distinguishes ignored, warned, and unsupported options, and Chinese variants explain both help surfaces consistently.
- [ ] Help and version commands require no Trash Input and do not enter path safety checks or platform Trash capabilities.
- [ ] Parser and information-command tests cover the full compatibility matrix without touching the real filesystem.
