# tc-test product identity acceptance report

- Date: `2026-08-18`
- Tested commit: `43d396e01b18162037f2e620cd9967ffce08dd4c`
- Test executable identity: `tc-test build=TC_TESTING`
- Release test binary: `REPO_ROOT/.build/release/tc-test`
- Debug test binary: `REPO_ROOT/.build/debug/tc-test`
- Swift: `Apple Swift 6.3.3`
- macOS SDK: `26.5`

`TEST_CONTAINER` denotes the trusted user's canonical `tc-test` safety container. `HOME_TRASH`
denotes that user's home Trash. The report intentionally does not persist the checkout path or user
home path.

## Results

| Acceptance | Run ID | System Trash | Human action | Result |
| --- | --- | --- | --- | --- |
| Guarded integration | `666629a8-1d0e-4024-a31c-56cae74a8ee4` | Not requested | None | Pass |
| Ordered batch | `7744e082-3528-4371-9778-f5c50a52fc53` | Finder | None (authorized host) | Pass |
| Duplicate Trash name | `5026aac7-e026-4962-a648-31b3c794055c` | Finder | None (authorized host) | Pass |
| Manual Put Back race | `de458165-7389-40ea-aa80-2b45b86112f6` | Finder | Exact Finder Put Back | Pass |
| Production symbolic-link Finalizer | `683156a4-be47-4f26-92dd-f62269e7292c` | Finder control and Foundation symbolic link | Exact Finder Put Back | Pass |

## Evidence

- [Guarded integration](integration.log) established the renamed Test Safety Context, printed the
  canonical executable identity, invoked no Trash capability, and removed its empty Run Directory.
- [Ordered batch](ordered-batch.log) preserved input order, four exact Finder receipts, the expected
  missing input, and the expected permission failure.
- [Duplicate Trash name](duplicate-trash-name.log) reused one exact source basename and received two
  distinct Finder receipts with `renamed=true`.
- [Manual Put Back race](put-back-race-manual.log) observed the maintainer's exact Finder Put Back and
  completed the zero-delay second Finder Trash call.
- [Production symbolic-link Finalizer](put-back-symlink-production-manual.log) observed the exact
  control Put Back, ran the production symbolic-link path, and reported
  `foundation-finalizer=production-cleaned` with `trash-warning=none`.
- [Metadata](metadata.txt) records repository-relative binaries, hashes, toolchain, path
  normalization, capability use, and the human-approval boundary.

No test process enumerated or searched Trash, and no automated Trash cleanup was performed. The retained
Run Directories, Finder-created metadata, and system-returned Trash receipts remain maintainer-owned
evidence under the existing Test Safety rules.
