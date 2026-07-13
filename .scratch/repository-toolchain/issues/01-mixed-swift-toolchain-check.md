# 01 — Fail fast on mixed Swift toolchains

**Status:** resolved

- [x] Bootstrap, Debug and Release builds, and unit tests run a compatibility probe first.
- [x] The probe exercises `import Testing` using the active compiler, SDK, and developer frameworks.
- [x] Failures explain which toolchain was selected and how to recover.
- [x] Policy tests cover both incompatible and compatible probe results.
