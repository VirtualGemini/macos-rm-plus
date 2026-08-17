# tc production CLI exit-status test report

- Run ID: `20260817T114304Z`
- Commit: `dbb6b85b50edcd98caa587180aed5c0ec2557025`
- Binary SHA-256: `82b2981db21c3585205392e6693749d39f5a54658352b6ecada4929f77d7d339`
- Test script SHA-256: `cd16600d19b3c58f32201c39cc910630ff8140585e40277680df0ea66d4a6655`
- Version result: `tc 0.1.0` (exit `0`)
- Started: `2026-08-17T11:43:04Z`
- Finished: `2026-08-17T11:43:05Z`
- System Trash API: not requested by this suite

## Summary

| Total | Passed | Failed | Script exit |
|---:|---:|---:|---:|
| 86 | 86 | 0 | 0 |

## Cases

| Case | Expected | Actual | Result | Command |
|---|---:|---:|---|---|
| `ES-0-01` | `0` | `0` | `PASS` | `tc <--help>` |
| `ES-0-02` | `0` | `0` | `PASS` | `tc <--help> <-a>` |
| `ES-0-03` | `0` | `0` | `PASS` | `tc <--help> <-zh>` |
| `ES-0-04` | `0` | `0` | `PASS` | `tc <--help> <-a> <-zh>` |
| `ES-0-05` | `0` | `0` | `PASS` | `tc <--version>` |
| `ES-0-06` | `0` | `0` | `PASS` | `tc <--help> <missing-information-path>` |
| `ES-0-07` | `0` | `0` | `PASS` | `tc <--version> <missing-information-path>` |
| `ES-0-08` | `0` | `0` | `PASS` | `tc <--help> <-P>` |
| `ES-0-09` | `0` | `0` | `PASS` | `tc <--version> <-P>` |
| `ES-0-10` | `0` | `0` | `PASS` | `tc <--dry-run> <present-file>` |
| `ES-0-11` | `0` | `0` | `PASS` | `tc <--dry-run> <directory>` |
| `ES-0-12` | `0` | `0` | `PASS` | `tc <--dry-run> <symbolic-link>` |
| `ES-0-13` | `0` | `0` | `PASS` | `tc <--dry-run> <broken-symbolic-link>` |
| `ES-0-14` | `0` | `0` | `PASS` | `tc <--dry-run> <fifo-input>` |
| `ES-0-15` | `0` | `0` | `PASS` | `tc <--dry-run> <first-file> <directory> <second-file>` |
| `ES-0-16` | `0` | `0` | `PASS` | `tc <--quiet> <--dry-run> <present-file>` |
| `ES-0-17` | `0` | `0` | `PASS` | `tc <--json> <--dry-run> <present-file>` |
| `ES-0-18` | `0` | `0` | `PASS` | `tc <--json> <--verbose> <--dry-run> <present-file>` |
| `ES-0-19` | `0` | `0` | `PASS` | `tc <--verbose> <--json> <--dry-run> <present-file>` |
| `ES-0-20` | `0` | `0` | `PASS` | `tc <-P> <--dry-run> <present-file>` |
| `ES-0-21` | `0` | `0` | `PASS` | `tc <-rRdx> <--dry-run> <directory>` |
| `ES-0-22` | `0` | `0` | `PASS` | `tc <--dry-run> <--ignore-missing> <missing-input>` |
| `ES-0-23` | `0` | `0` | `PASS` | `tc <--dry-run> <--ignore-missing> <missing-input> <present-file>` |
| `ES-0-24` | `0` | `0` | `PASS` | `tc <--json> <--dry-run> <--ignore-missing> <missing-input>` |
| `ES-0-25` | `0` | `0` | `PASS` | `tc <-f> <missing-input>` |
| `ES-0-26` | `0` | `0` | `PASS` | `tc <--force> <missing-input>` |
| `ES-0-27` | `0` | `0` | `PASS` | `tc <--ignore-missing> <missing-input>` |
| `ES-0-28` | `0` | `0` | `PASS` | `tc <-f> <--ignore-missing> <-i> <missing-input>` |
| `ES-0-29` | `0` | `0` | `PASS` | `tc <-f> <--confirm=each> <missing-input>` |
| `ES-0-30` | `0` | `0` | `PASS` | `tc <-f>` |
| `ES-0-31` | `0` | `0` | `PASS` | `tc <-if>` |
| `ES-0-32` | `0` | `0` | `PASS` | `tc <-i> <-f>` |
| `ES-0-33` | `0` | `0` | `PASS` | `tc <-f> <--confirm=never>` |
| `ES-0-34` | `0` | `0` | `PASS` | `tc <-f> <--confirm=each>` |
| `ES-0-35` | `0` | `0` | `PASS` | `tc <-f> <--ignore-missing>` |
| `ES-0-36` | `0` | `0` | `PASS` | `tc <-fI>` |
| `ES-0-37` | `0` | `0` | `PASS` | `tc <-If>` |
| `ES-0-38` | `0` | `0` | `PASS` | `tc <--force> <-f>` |
| `ES-0-39` | `0` | `0` | `PASS` | `tc <-f> <--json>` |
| `ES-1-01` | `1` | `1` | `PASS` | `tc <missing-input>` |
| `ES-1-02` | `1` | `1` | `PASS` | `tc <>` |
| `ES-1-03` | `1` | `1` | `PASS` | `tc <--dry-run> <missing-input>` |
| `ES-1-04` | `1` | `1` | `PASS` | `tc <--json> <--dry-run> <missing-input>` |
| `ES-1-05` | `1` | `1` | `PASS` | `tc <--dry-run> <present-file> <missing-input>` |
| `ES-1-06` | `1` | `1` | `PASS` | `tc <-fi> <missing-input>` |
| `ES-1-07` | `1` | `1` | `PASS` | `tc <--force> <--interactive> <missing-input>` |
| `ES-1-08` | `1` | `1` | `PASS` | `tc <--ignore-missing> <-f> <-i> <missing-input>` |
| `ES-1-09` | `1` | `1` | `PASS` | `tc <--confirm=never> <fifo-input>` |
| `ES-1-10` | `1` | `1` | `PASS` | `tc <--non-interactive> <directory>` |
| `ES-1-11` | `1` | `1` | `PASS` | `tc <--non-interactive> <first-file> <second-file>` |
| `ES-1-12` | `1` | `1` | `PASS` | `tc <--json> <--non-interactive> <directory>` |
| `ES-1-13` | `1` | `1` | `PASS` | `tc <--quiet> <missing-input>` |
| `ES-1-14` | `1` | `1` | `PASS` | `tc <-P> <missing-input>` |
| `ES-64-01` | `64` | `64` | `PASS` | `tc` |
| `ES-64-02` | `64` | `64` | `PASS` | `tc <--dry-run>` |
| `ES-64-03` | `64` | `64` | `PASS` | `tc <-->` |
| `ES-64-04` | `64` | `64` | `PASS` | `tc <--force>` |
| `ES-64-05` | `64` | `64` | `PASS` | `tc <-fi>` |
| `ES-64-06` | `64` | `64` | `PASS` | `tc <-f> <-i>` |
| `ES-64-07` | `64` | `64` | `PASS` | `tc <-f> <--ignore-missing> <--confirm=each>` |
| `ES-64-08` | `64` | `64` | `PASS` | `tc <-f> <--force>` |
| `ES-64-09` | `64` | `64` | `PASS` | `tc <--unknown> <present-file>` |
| `ES-64-10` | `64` | `64` | `PASS` | `tc <-z> <present-file>` |
| `ES-64-11` | `64` | `64` | `PASS` | `tc <-fz> <present-file>` |
| `ES-64-12` | `64` | `64` | `PASS` | `tc <--confirm=sometimes> <present-file>` |
| `ES-64-13` | `64` | `64` | `PASS` | `tc <--confirm=> <present-file>` |
| `ES-64-14` | `64` | `64` | `PASS` | `tc <--confirm> <present-file>` |
| `ES-64-15` | `64` | `64` | `PASS` | `tc <--confirm=conditionalOnce> <present-file>` |
| `ES-64-16` | `64` | `64` | `PASS` | `tc <--json> <--quiet> <present-file>` |
| `ES-64-17` | `64` | `64` | `PASS` | `tc <--quiet> <--json> <present-file>` |
| `ES-64-18` | `64` | `64` | `PASS` | `tc <-W> <present-file>` |
| `ES-64-19` | `64` | `64` | `PASS` | `tc <-P> <-W> <present-file>` |
| `ES-64-20` | `64` | `64` | `PASS` | `tc <--strict-options> <-r> <present-file>` |
| `ES-64-21` | `64` | `64` | `PASS` | `tc <-r> <--strict-options> <present-file>` |
| `ES-64-22` | `64` | `64` | `PASS` | `tc <--strict-options> <-R> <present-file>` |
| `ES-64-23` | `64` | `64` | `PASS` | `tc <--strict-options> <-d> <present-file>` |
| `ES-64-24` | `64` | `64` | `PASS` | `tc <--strict-options> <-x> <present-file>` |
| `ES-64-25` | `64` | `64` | `PASS` | `tc <--strict-options> <-P> <present-file>` |
| `ES-64-26` | `64` | `64` | `PASS` | `tc <--strict-options> <-W> <present-file>` |
| `ES-64-27` | `64` | `64` | `PASS` | `tc <-a>` |
| `ES-64-28` | `64` | `64` | `PASS` | `tc <-zh>` |
| `ES-64-29` | `64` | `64` | `PASS` | `tc <--help> <--version>` |
| `ES-64-30` | `64` | `64` | `PASS` | `tc <--version> <--help>` |
| `ES-64-31` | `64` | `64` | `PASS` | `tc <--version> <-a>` |
| `ES-64-32` | `64` | `64` | `PASS` | `tc <--version> <-zh>` |
| `ES-64-33` | `64` | `64` | `PASS` | `tc <--help> <--json> <--quiet>` |

Detailed stdout/stderr responses: [`responses.log`](responses.log).
Machine-readable results: [`cases.tsv`](cases.tsv).
Run metadata: [`metadata.txt`](metadata.txt).
