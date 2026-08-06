# 12 — Put Back entry lost when re-trashing a same-named item soon after Put Back

**Status:** ready-for-agent

**Classification:** defect — user-visible product anomaly at the macOS Trash
integration boundary. Recoverability of `rmp` deletions is degraded relative
to Finder-native deletion; reclassified from environment noise by the
maintainer on 2026-07-18.

## Current state (2026-08-01)

The defect is reproduced, diagnosed, and fixed on
`fix/12-put-back-metadata-race`. `FinderTrashClient` delegates the delete to
Finder over a fixed Apple Event handler, making Finder the single `.DS_Store`
writer. The ticket's 30-cycle actual-menu differential passed **30/30** against
roughly 10% retention for the previous Foundation client in the same flow.

Confirmed working: ordinary files (30 cycles across all three delay buckets),
directories, and names containing quotes or newlines. **Symbolic links are the
exception** — Finder will not delete them over Apple Events at all, so they need
a separate path that reintroduces this ticket's race for that shape alone.

Outstanding before release:

- **Agent-runnable.** Extend the acceptance scenario to the platform set —
  directories, symbolic links, broken symbolic links, duplicate Trash names, and
  path text containing quotes and newlines. Every differential cycle so far used
  one ordinary small file on one local volume, so fixture shape is the largest
  untested dimension. The agent builds the fixtures and drives the sequence; only
  the final Finder menu judgment needs the maintainer.
- **Maintainer only.** The Feedback Assistant report to Apple about the
  `.DS_Store` coherence race, and the release decision itself.

Sections below are kept in chronological order as the investigation record;
earlier ones describe the state before the fix and are not current guidance.

## Symptom

Deleting a file with the production `rmp` produces a Trash item with a
working Finder "Put Back" entry on the first deletion. After restoring the
item with Put Back and deleting the same file again with `rmp`, the new Trash
item shows no Put Back entry about 90% of the time (reporting environment,
macOS 26.5.1). The item itself reaches the Trash on every run and `rmp` exits
0 with a correct destination path.

## Impact

- A Finder delete → Put Back → delete cycle keeps the Put Back entry at any
  speed (maintainer manual verification, 2026-07-18). The same cycle through
  `rmp` usually loses it, so `rmp` is observably worse than Finder for
  exactly the "delete, restore, delete again" flow.
- No data is lost — the item is in the Trash and can be moved back by hand —
  but the one-click restore affordance silently disappears, and a stale
  record variant can restore the item to an outdated location.
- Any user workflow or manual test that re-trashes a recently restored name
  is affected; this also explains historical "put back went to an old tmp
  path" observations during production CLI testing.

## Reproduction

1. `rmp <file>` — the Trash item shows Put Back.
2. Restore it with Finder Put Back.
3. Within a few seconds, run `rmp <file>` again for the same name.
4. Most of the time the new Trash item has no Put Back entry. Waiting >= 10
   seconds before step 3, using a different file name, or performing step 3
   with Finder avoids the loss.

## Investigation record (2026-07-18)

### Question

Does the second `rmp` Trash Operation omit Put Back metadata, or does another
process remove or replace metadata that `rmp` successfully caused the system
Trash API to write?

### Environment and safety boundary

- Reporting environment: macOS 26.5.1, home Trash, Finder Trash window open,
  human-driven Finder Put Back, then same-name re-trash through `rmp`.
- Instrumented environment: disposable scratch APFS disk image with a readable
  Trash folder at `/Volumes/<scratch>/.Trashes/<uid>/`.
- The home Trash `.DS_Store` was not read because TCC protects `~/.Trash`.
- Finder restores in the instrumented environment were automated through an
  AppleScript `move` through Finder's real `trash` container, the closest
  scriptable analog of the Put Back action without Accessibility UI control.
- No permanent-delete API was used. Every target was a disposable probe file on
  the scratch volume, and the volume was removed after the investigation.

### Repository test artifacts

- [Swift `PutBackMetadataScanner`](../../../TestSupport/RMPTestKit/PutBackMetadataScanner.swift)
  rewrites the former Python scanner as pure read-only test support.
- [Swift command-line probe](../../../TestSupport/RMPTestKit/PutBackMetadataProbe.swift)
  restores the former scanner's file-reading and text-output entrypoint without
  adding a Trash capability.
- [Swift scanner tests](../../../Tests/RMPPlatformTests/PutBackMetadataScannerTests.swift)
  validate `ptbL`/`ptbN` extraction from an independent synthetic byte fixture.
- The former independent `trash.swift` was not copied as a second direct
  `FileManager.trashItem` call. The repository's safety boundary permits that
  capability only in `FoundationTrashClient`; this branch reproduces the
  product path with the built `rmp` executable and keeps the independent-caller
  result from the original investigation as differential evidence.

The read-only probe can be built and run from the repository root:

```sh
xcrun swiftc -warnings-as-errors -D RMP_PUT_BACK_METADATA_PROBE \
  TestSupport/RMPTestKit/PutBackMetadataScanner.swift \
  TestSupport/RMPTestKit/PutBackMetadataProbe.swift \
  -o /tmp/rmp-put-back-metadata-probe

/tmp/rmp-put-back-metadata-probe \
  "/Volumes/<scratch>/.Trashes/$(id -u)/.DS_Store"
```

No executable disposable-volume Trash runner is checked in. The current test
safety contract requires real test Trash Operations to use `rmp-test` inside
`~/rmp-test/test/<run-uuid>/` and explicitly rejects mount points and
cross-volume targets. Automating this APFS-volume lab inside the repository
would therefore require a separately reviewed safety design, not an exception
hidden in this defect ticket. This branch records the maintainer-authorized lab
snapshots below while keeping the repository capability boundary intact.

### This-branch verification snapshots

| Round | Action and delay | Swift probe result |
| --- | --- | --- |
| `rmp-put-back-race-12` | First production `rmp` Trash Operation on `/source/` | Immediately showed `ptbL=/source/` and `ptbN=rmp-put-back-race-12`. |
| `-12-b` | Finder exact-path move back; observed through 10 seconds | Records remained through the 10-second snapshot. |
| `-12-c` | Finder `trash`-container move back; snapshots immediately and after 2 seconds | Records were present immediately and absent after approximately 2 seconds. |
| `-12-d` | Finder `trash`-container restore, 1 second wait, production `rmp` re-trash | Fresh `ptbL`/`ptbN` records were still present at 2 and 4 seconds. |
| `-12-e` | Finder reveal, 1.5 second restore/re-trash timing | Fresh records were still present at the 3-second snapshot. |

Together with the earlier four-cycle differential result (one total-loss cycle
at a 1.5-second delay) from the independent minimal Foundation caller, these
rounds locate a delayed disappearance window and show that the race is
nondeterministic rather than inevitable on every fast re-trash.

### Evidence matrix

| ID | Question | Method | Observation | Inference |
| --- | --- | --- | --- | --- |
| E1 | Does `rmp` write Put Back metadata on every call? | Run six same-name trash/restore cycles on the scratch volume and scan `.DS_Store` after each Trash Operation. Repeat from a different original directory. | Every Trash Operation produced one current `ptbL`/`ptbN` record; changing the source directory changed the stored original location. | The first and repeated `rmp` paths do not differ at metadata-write time. |
| E2 | When does the consumed record disappear after restore? | Scan immediately after restore and at subsequent second-scale intervals. | The old record remained briefly, then was absent after approximately 2–4 seconds. | The timing is consistent with deferred Finder metadata cleanup rather than synchronous cleanup during restore. |
| E3 | Can a new same-name Trash Operation overlap that window? | Restore, re-trash the same name near the observed disappearance window, and scan after each step. | Two bad outcomes occurred nondeterministically: the fresh record later disappeared entirely, or its original path later matched the stale previous path. The Trash item itself remained present. | A later Finder-associated metadata persistence can erase or overwrite metadata written for the new Trash item. |
| E4 | Is the conflict caused by `rmp` code outside the system API call? | Replace `rmp` with the archived minimal Swift caller, which invokes only `FileManager.trashItem`. Run four cycles with a 1.5-second delay. | One of four cycles lost the fresh Put Back record completely. | The failure reproduces for an independent caller of the same Foundation API and is not specific to `rmp` parsing, planning, or execution code. |
| E5 | Does Finder avoid the problem when it performs every step? | Manually run Finder delete → Put Back → Finder delete cycles at varying speeds. | Put Back remained available in every maintainer-observed cycle, including immediate re-delete attempts. | A single Finder writer avoids the cross-process metadata race and establishes the expected product behavior. |
| E6 | Does the user-visible report match the metadata failure? | Run production `rmp` → Finder Put Back → production `rmp` for the same name in the home Trash. | The second Trash item lacked Put Back about 90% of the time, while `rmp` exited 0 and returned a valid Trash destination. | Loss of `ptbL`/`ptbN`, rather than failure to move the item, explains the reported symptom. |

### Evidence assessment

- **Directly observed:** current records were present after each completed
  Trash call; the consumed record remained immediately after a Finder restore
  and was absent in later snapshots; re-trash near that window produced both
  total record loss and stale-path replacement; the independent caller
  reproduced total loss; Finder-only control cycles retained Put Back.
- **Inferred mechanism:** Finder holds or reconstructs an older `.DS_Store`
  state after Put Back and later persists it with last-writer-wins behavior,
  clobbering a non-Finder caller's newer record. The timing, the Finder restore
  boundary, and both observed failure modes support this inference; the private
  `.DS_Store` implementation prevents source-level confirmation.
- **Confidence:** high that the defect is a cross-process Finder/Foundation
  Trash integration race; medium on the exact Finder cache and write-back
  implementation.

### Limitations and open evidence gaps

- The instrumented scratch-volume restore used AppleScript `move`, not the
  exact Finder Put Back menu action used in the reporting environment.
- TCC prevented byte-level observation of the home Trash `.DS_Store`.
- The instrumented loss rate was lower than the reported 90%; the actual Put
  Back action, home Trash, open Trash window, and human timing may widen the
  race window.
- `.DS_Store` is private. The scanner recognizes only the relevant record
  signatures and is not a complete format parser.

### Root-cause conclusion

The Put Back entry is driven by `ptbL` (original parent directory) and `ptbN`
(original name) records in the Trash folder's `.DS_Store`.
`FoundationTrashClient` invokes `FileManager.trashItem` once per approved
Trash Input, and the experiment found correct records after both first and
repeated calls. The observed timing supports a deferred Finder cleanup for the
preceding Put Back. When a same-named item is re-trashed during that window, a
later Finder-associated write can erase or replace the new records.

This is a product defect at the macOS Trash integration boundary: `rmp` cannot
currently provide Finder-equivalent recoverability for this flow even though
the immediate Trash Operation succeeds and no file data is lost.

## Why the Foundation implementation could not avoid it

Superseded by the Finder-delegated fix; retained as the reasoning that motivated
it. "Current implementation" below means the `FileManager.trashItem` client that
shipped before this branch.

The metadata loss was observed seconds after the `rmp` process exited. The
evidence attributes the later persistence to Finder activity, but cannot prove
its private implementation. The process cannot verify or repair the record
afterwards: the home Trash `.DS_Store` is TCC-protected, its format is private,
and rewriting it would race Finder again.

## Remediation options

Decided. Option 1 was selected on 2026-07-23 and is implemented on this branch;
its 30-cycle actual-menu differential passed 30/30 on 2026-08-01. Option 2's
upstream Feedback Assistant report is still open. Option 3 remains infeasible.
The costs listed under option 1 all materialized and are now documented
behaviour: the Automation prompt, the Finder runtime dependency, and the stable
denial, consent, timeout, and availability failure codes.

1. **Finder-delegated deletion mode**: send the delete to Finder over Apple
   events so Finder is the single `.DS_Store` writer, giving Finder-grade
   Put Back reliability. Costs: an Automation (TCC) permission prompt, a
   Finder runtime dependency, slower deletions, new failure modes
   (Finder not running, permission denied), and a second TrashClient
   implementation crossing the documented `FoundationTrashClient`
   single-call-site boundary — needs design review and an ADR, possibly as
   an opt-in flag rather than the default path.
2. **Document as a known limitation**: README/help known-issues entry with
   the >= 10 s / rename / Finder-delete workarounds, plus an upstream report
   to Apple (Feedback Assistant) about the `.DS_Store` coherence race.
3. **Detect-and-warn or post-write repair**: not feasible — reading or
   rewriting the home Trash `.DS_Store` is blocked by TCC and depends on a
   private format.

Options 1 and 2 are compatible: 2 can ship immediately while 1 is designed.

## Rejected Workspace candidate (maintainer decision, 2026-07-23)

Before paying the Apple Events and Automation-permission cost of option 1, test
AppKit `NSWorkspace.recycle(_:completionHandler:)`. The macOS 26.5 SDK describes
that public API as moving URLs to Trash in the same manner as Finder and returns
a source-to-destination URL mapping. It therefore preserves the existing exact
Trash Result contract without directly reading or writing Finder metadata.

The candidate branch replaces `FoundationTrashClient` with
`WorkspaceTrashClient`, bridges the asynchronous completion on a private serial
queue, and reports a stable system Trash failure when the source URL has no
returned destination. It has no `FileManager.trashItem` fallback. Pure tests
cover the callback and failure contract but cannot establish Finder metadata
coherence. The automated pre-acceptance below found no improvement over the
Foundation baseline, so the candidate is not merge-ready.

### Automated pre-acceptance differential (2026-07-23)

The Foundation baseline at `22d9140` and Workspace candidate at `340984f` were
built as separately named Release binaries and run against separate disposable
APFS volumes on macOS 26.5.1 (build 25F80), Finder 26.4. Each binary ran 30
cycles split evenly across immediate, 1.5-second, and 3-second re-trash delays.
Every cycle used one stable source path with cycle-specific content.

The harness performed the following without human intervention:

1. Trash the current probe file through the selected production `rmp` binary.
2. Verify the exact source-to-destination mapping and initial `ptbL`/`ptbN`.
3. Restore through Finder's real `trash` container and verify path and content.
4. Re-trash the same basename after the selected delay.
5. Wait 5 seconds, scan `.DS_Store`, then restore and verify the exact content
   again.

In this harness, Finder did not enumerate a new external volume through its
global `trash` container until the already populated volume was remounted. A
separate warm-up probe established that Finder volume-enumeration state before
the 30 counted cycles; warm-up results are excluded below.

| Binary | Delay | Correct first metadata | Correct second metadata after 5 s |
| --- | ---: | ---: | ---: |
| Foundation baseline | 0 s | 10/10 | 0/10 |
| Foundation baseline | 1.5 s | 10/10 | 0/10 |
| Foundation baseline | 3 s | 10/10 | 0/10 |
| Workspace candidate | 0 s | 10/10 | 0/10 |
| Workspace candidate | 1.5 s | 10/10 | 0/10 |
| Workspace candidate | 3 s | 10/10 | 0/10 |

For each binary, all 60 Trash calls returned the exact expected destination,
all 60 Finder-container restores succeeded, and every restored content hash
matched. No `rmp` error, timeout, hang, or candidate Automation prompt occurred.
The only failure was identical for both implementations: every fresh second
`ptbL`/`ptbN` pair was absent after Finder's deferred persistence window.

Binary SHA-256 values:

- Foundation baseline:
  `8c96d7b4b8b650dc097a9b49b8af911d92ecf5731ef7d0ee05c28fd1b5ba22da`
- Workspace candidate:
  `fa9e749545e21850d44b0ce0398de5796b7a7e62ec632a3d9837c75108c9e12d`
- Read-only metadata probe:
  `d5e178b9b1ef8cdc0968a3ead2e51a4714e737a9b668228a63695860544a3d23`

This is strong evidence that `NSWorkspace.recycle` does not improve the
observable metadata outcome in this Apple Event restore harness. The experiment
does not establish which process owns or persists the private records. It is
not the ticket's formal menu-level acceptance because the restore used a Finder
Apple Event rather than clicking the actual Put Back command; the current host
reported Accessibility access as disabled. The candidate therefore fails
automated pre-acceptance and must not be pushed or merged as the fix. A
maintainer must now choose whether to abandon it or authorize a Finder-delegated
design.

### Optional menu-level Workspace confirmation

The automated result already rejects the Workspace candidate. This menu-level
check is optional and exists only to investigate whether Finder's actual Put
Back command behaves differently from the Apple Event restore used above. Stop
on the first candidate loss; a full 30-cycle run is useful only if the initial
candidate cycles remain correct.

Use separately named binaries built from the unchanged Foundation baseline and
the Workspace candidate. Do not overwrite an installed `rmp` between rounds.
Run only disposable files in the existing maintainer-authorized manual-test
boundary, keep their parent directory alive, and use Finder's actual Put Back
command rather than an AppleScript move.

For each binary, run 30 cycles split evenly across immediate, 1.5-second, and
3-second re-trash delays:

1. Create the same basename at one stable original path with cycle-specific
   content.
2. Trash it with the selected binary and record the exact returned destination.
3. Use Finder Put Back and verify the content and original path.
4. Re-trash the same basename after the round's delay.
5. Wait at least 5 seconds for deferred Finder persistence, then verify that
   Finder still offers Put Back and restores the exact current item to the
   original path.

The differential is valid only if the Foundation baseline loses or stales at
least one Put Back record. One Workspace candidate loss confirms its rejection;
a non-reproducing baseline makes the experiment inconclusive.

## Selected Finder-delegated candidate (maintainer decision, 2026-07-23)

The maintainer accepts the normal macOS Automation authorization cost, including
when a shell alias or PATH shim named `rm` invokes `rmp`. Renaming or wrapping the
command does not bypass TCC; macOS authorizes the responsible sender to control
Finder. The authorization is expected to persist for the same sender-to-Finder
pair, but may be requested again after revocation, TCC reset, sender identity
change, or use from another terminal application.

Keep `fix/12-put-back-metadata-race` as the candidate branch and continue the
implementation there. `FinderTrashClient` sends a fixed AppleScript handler a
single approved source path as a structured Apple Event argument. Finder itself
executes `delete`, and the handler returns the deleted Finder item's `URL` for
the existing exact `TrashMoveReceipt` contract. The path is never interpolated
into script source.

The candidate has these fail-closed requirements:

- The first request may show the macOS Automation prompt. Permission denial,
  consent-required, Finder-unavailable, and timeout outcomes use distinct stable
  error codes and do not move the source through another API.
- No `FileManager.trashItem`, `NSWorkspace.recycle`, direct Trash-directory, or
  permanent-delete fallback is permitted.
- The fixed Finder handler has a finite timeout and returns only a file URL.
- Production and `rmp-test` reach the capability only through the existing
  reviewed `TrashClient` and Test Safety Context boundaries.

### Finder handler correction and Automation evidence (2026-07-23)

The first real candidate invocation failed closed with
`trash_system_call_failed (not_moved)`. A diagnostic run exposed Apple Event
error `-1728`: Finder could not resolve `POSIX file sourcePath`. The fixed
handler now creates the AppleScript file specification before entering Finder's
`tell` block, then passes that structured object to Finder `delete`. This keeps
path text out of script source and preserves broken-symbolic-link semantics.

The corrected candidate was exercised from the intended Ghostty host:

- A reset denial round returned `finder_automation_denied (not_moved)` for
  `/tmp/rmp-finder-automation.kMh4lh/automation-deny-probe`; the source remained
  present with device `16777231`, inode `10049588`, and size `0`.
- In the approval round macOS named `Ghostty` as the sender controlling Finder.
  `automation-approve-first` and `automation-approve-reuse` both moved to their
  exact home Trash URLs, the second call did not prompt again, and Finder Put
  Back restored both source entries. This establishes the intended
  sender-to-Finder approval reuse for this host, but is not the 30-cycle race
  differential.

An attempted temporary one-shot harness split the restore into an `osascript`
process and failed with Finder error `-5000`. That failure was initially
attributed to the second Automation sender; the 2026-07-26 live run recorded
below disproves that attribution. The authoritative race scenario is a single
compile-time-isolated Swift process under `rmp-test`, in two restore variants:

```sh
make test-put-back-race TEST_RUN_ID=<canonical-lowercase-uuid>
make test-put-back-race-manual TEST_RUN_ID=<canonical-lowercase-uuid> SETTLE_SECONDS=0
```

`SETTLE_SECONDS` declares this ticket's 0 / 1.5 / 3 second re-trash bucket between the
observed restore and the second Trash call, and the applied value is echoed as
`settle-seconds=` beside each result. Judge Put Back only after waiting at least
5 seconds past the second Trash: Finder's deferred write-back window is roughly
2-4 seconds, so an earlier check can report a record that has not been clobbered
yet.

Both variants exclusive-create one UUID-prefixed Test Fixture, perform the
first whitelisted Finder Trash call, and immediately reuse the original planned
identity for the second Trash call. Neither has a sleep, shell harness,
`osascript` subprocess, or Trash name search. They differ only in the restore
step: `put-back-race` moves the exact returned URL through
`WhitelistedPutBackClient`, while `put-back-race-manual` carries no Finder Put
Back capability and instead waits for the maintainer's real Put Back command,
observing the authorized Run Directory through a kqueue-backed dispatch source.
Each command prints the exact second Trash URL and preserves the validated Run
Directory for the maintainer's final Finder menu check.

### Home Trash TCC constraint (2026-07-26)

A live `make test-put-back-race` run from the approved Ghostty host completed
the first Finder Trash call and then failed closed with
`test-safety.put-back-system-call-failed` and Apple Event error `-5000`.

The cause is the home Trash TCC boundary, not the Automation sender:

- `ls ~/.Trash` and a read of `~/Library/Application Support/com.apple.TCC/TCC.db`
  both returned `Operation not permitted` for the invoking process.
- The same sender's Finder Apple Event `move` between two unprotected
  directories succeeded and returned the moved item's POSIX path.
- `/Applications/Ghostty.app` is listed for Full Disk Access, but the running
  process had been alive for 45 days and predates the grant. Full Disk Access
  applies only to processes started after the entry is enabled.

This invalidates the earlier "different Automation sender" inference for
`-5000`. Production `rmp` is unaffected: it only asks Finder to `delete`, which
needs Automation but not Full Disk Access. Only the scripted restore in the
test harness reads from `~/.Trash`.

Consequences for acceptance:

- `put-back-race` requires the invoking terminal to hold Full Disk Access and
  to have been restarted after the grant.
- `put-back-race-manual` requires no additional permission and exercises the
  actual Finder Put Back command, closing the evidence gap recorded under
  "Limitations and open evidence gaps" above.

### Real Put Back menu acceptance (2026-07-31)

First successful end-to-end run of the authoritative scenario. The maintainer
performed the actual Finder "Put Back" command; `rmp-test` detected the restore
through the kqueue-backed dispatch source and re-trashed from that event. Put
Back availability was judged at least 10 seconds after the second Trash call,
outside Finder's 2-4 second deferred write-back window. Home Trash was emptied
first, so the only item present was the run's own fixture.

| Round | `SETTLE_SECONDS` | Run ID prefix | Restore verified to exact original path | Put Back on second Trash item |
| --- | ---: | --- | --- | --- |
| 1B | 0 | `93101e0b` | yes | **present** |
| 2 | 1.5 | `b3fc266c` | yes | **present** |
| 3 | 3 | `b5a39cfd` | yes | **present** |

All rounds exited 0 with `status=complete` and
`restore-method=maintainer-finder-put-back-command`. In every round the adapter
independently verified, before printing any result, that Put Back returned the
fixture to the exact Run Directory path and that the file resource identifier
was unchanged across trash, restore, and re-trash; a mismatch would have failed
closed instead.

An earlier round 1 attempt at the same 0-second bucket is excluded: the
maintainer read the menu 1-2 seconds after the second Trash, inside the deferred
write-back window, so its "Put Back present" observation is a false positive by
construction. That discarded attempt did confirm the entry was functional, since
the accidental click restored the fixture correctly to its original path.

Interpretation. The matched control for this scenario is E6: production `rmp`
through the Foundation client, home Trash, real Put Back, same-name re-trash,
which lost Put Back roughly 90% of the time. Against that control, 3/3 retention
is meaningful but small-n; it is not the ticket's 30-cycle differential and does
not replace it. The rounds also share one host, one volume, and one file shape.
This result therefore clears the menu-level smoke gate and removes the last
blocker to running the full differential; it does not by itself authorize
release.

### Finder candidate actual-menu differential (2026-08-01)

The ticket's 30-cycle actual-menu differential, run as three `CYCLES=10` batches
through `make test-put-back-race-manual`. Every restore was the maintainer's
real Finder "Put Back" command; the maintainer confirmed performing ten Put Back
actions per batch. Each batch used one Run Directory with numbered fixtures, and
Put Back availability was judged for all ten targets after the batch completed,
well past Finder's 2-4 second deferred write-back window.

| Delay bucket | Cycles | Run ID prefix | Put Back retained on second Trash item |
| ---: | ---: | --- | ---: |
| 0 s | 10 | `eee49099` | **10/10** |
| 1.5 s | 10 | `29005f37` | **10/10** |
| 3 s | 10 | `9089241c` | **10/10** |
| **Total** | **30** | | **30/30** |

All three batches reported `completed-cycles=10/10` and exited 0, and every Run
Directory ended holding only its marker, confirming all thirty fixtures reached
the Trash. In each of the thirty cycles the adapter verified before proceeding
that Put Back returned the fixture to its exact original path and that the file
resource identifier was unchanged across trash, restore, and re-trash. Only a
genuine Put Back returns the same inode to that exact path, so a cycle could not
have completed without one.

Comparison with the recorded baselines for the same flow:

| Implementation | Harness | Second-item Put Back retained |
| --- | --- | ---: |
| Foundation `trashItem` | home Trash, real menu (E6) | roughly 10% |
| Foundation `trashItem` | scratch volume, Apple Event restore | 0/30 |
| `NSWorkspace.recycle` | scratch volume, Apple Event restore | 0/30 |
| **Finder `delete`** | **home Trash, real menu** | **30/30** |

This satisfies the ticket's actual-menu differential. It does not by itself
authorize release: all thirty cycles used one host, one local volume, and one
ordinary small file. The platform acceptance set below still requires
directories, symbolic links, broken symbolic links, duplicate Trash names, and
path text containing quotes and newlines.

### Platform fixture set results (2026-08-01)

Acceptance criterion 5 asks for fixture shapes beyond ordinary files. Each row
below was driven through the same sequence — first Finder Trash, the
maintainer's real Put Back, then an immediate re-trash — and Put Back
availability was judged past Finder's deferred write-back window.

| Fixture shape | Cycles verified | Deletes | Put Back survives re-trash |
| --- | ---: | --- | --- |
| Ordinary file | 30 (10 each at 0 / 1.5 / 3 s) | yes | **yes** |
| Directory | 3 | yes | **yes** |
| Name with double and single quotes | 1 | yes | **yes** |
| Name containing a newline | 1 | yes | **yes** |
| Symbolic link | 0 | **no** — see below | n/a |
| Broken symbolic link | 0 | **no** — see below | n/a |

The quoted-name and newline-name rows are the end-to-end counterpart to the pure
test for structured Apple Event arguments. Any implementation that interpolated
path text into AppleScript source would fail on them; both completed normally
and retained Put Back. The newline case is visible in the command's own output,
where `trash-item=` is split across two lines by the embedded newline.

Coverage limits worth stating plainly. The quoted-name and newline-name rows are
single cycles, not the 10-per-bucket depth used for ordinary files, and every
row ran on one host and one local volume. Duplicate Trash names — the remaining
item in acceptance criterion 5 — were **not** tested; no fixture kind exists for
placing a same-basename decoy in the Trash first.

### Symbolic links cannot be Finder-delegated (2026-08-01)

Found while extending the acceptance set beyond ordinary files. This is a
regression introduced by the Finder-delegated fix, not a pre-existing defect.

**Finder refuses to trash a symbolic link over Apple Events.** The first
acceptance cycle failed closed with `test-safety.trash-system-call-failed`,
leaving both the link and its target untouched. Four reference forms were tried
against a freshly created valid symlink in an unprotected directory:

| AppleScript reference form | Result |
| --- | --- |
| `POSIX file p` (production handler) | `-5000` |
| `item (POSIX file p)` | `-5000` |
| `item "name" of folder <parent>` | `-5000` |
| `alias file "name" of folder <parent>` | `-5000` |

A regular file in the same directory deleted normally in the same session, so
this is specific to symbolic links rather than to the location or the sender.
`move ... to trash` fails identically to `delete`. Finder also surfaces a modal
dialog ("无法完成此操作，因为你没有访问一些项目的许可"), which is why one round
returned `-1712` (Apple Event timeout) instead: the handler's 30-second timeout
expired while Finder waited on a human. For a user this means `rmp <symlink>`
shows a confusing Finder dialog, hangs for 30 seconds, then fails.

Mechanism: Finder resolves the POSIX symlink to its target before acting.
Asking for `name` of the link produced an error naming the *target's* path, and
`original item` of the link resolved to `document file "<target>"`. The earlier
ADR claim that the handler "preserves broken-symbolic-link semantics" is
therefore incorrect.

Unresolved variable: the invoking process lacks Full Disk Access, and at least
one Apple Developer Forums report ties Finder permission errors to FDA on the
scripting host. This cannot be separated without restarting the terminal. It
does not change the product conclusion: FDA is granted to the terminal, not to
`rmp`, and requiring every user to grant their terminal Full Disk Access is a
far larger privilege than `rmp` needs.

**Foundation handles symbolic links correctly but keeps the defect.** A
throwaway diagnostic (not checked in) trashed a symlink through
`FileManager.trashItem`: the link itself moved to the Trash and its target
stayed in place. Restoring it with the real Put Back command and immediately
re-trashing it lost the Put Back entry, judged past the deferred write-back
window. Symbolic links suffer this ticket's race exactly like regular files.

| Path | Deletes a symlink | Put Back survives a fast re-trash |
| --- | --- | --- |
| Finder delegation | no — dialog, 30 s hang, failure | n/a |
| Foundation `trashItem` | yes — link moved, target intact | **no** |

Neither path gives symbolic links Finder-grade recoverability. That is a macOS
constraint, not an implementation choice: Finder will not touch the link, and
anything that bypasses Finder re-enters the metadata race.

#### Recorded remediation direction (not implemented)

The maintainer selected dispatch-by-type on 2026-08-01, on the grounds that
"deletes, with a metadata limitation" is strictly better than "shows an
inexplicable dialog, hangs, then fails". Implementation is deliberately deferred
until the rest of the acceptance set has been measured.

- Route symbolic links through a Foundation client and everything else through
  Finder, deciding by `lstat` rather than by any resolved path.
- Confine `FileManager.trashItem` to that one new file. The static boundary
  script currently forbids it everywhere and must be narrowed rather than
  relaxed, and the new client must itself refuse any target that is not a
  symbolic link.
- A new ADR records that "Finder is the single `.DS_Store` writer" no longer
  holds for symbolic links, and why no alternative was available.
- README, `docs/help.md`, and this ticket carry the known limitation: a symbolic
  link re-trashed shortly after a Put Back can lose its Put Back entry.
- Issue 12's conclusion splits: fixed for ordinary files and directories,
  constrained by macOS for symbolic links.

### Finder candidate acceptance

1. From a reset/undetermined Automation state, run one disposable candidate
   Trash Operation from the intended terminal host. Record which sender macOS
   names, approve the prompt, verify the exact destination and Put Back, then
   verify that later calls from the same host do not repeatedly prompt.
2. In a separately reset denial round, deny Automation and verify the stable
   `finder_automation_denied` failure, unchanged source identity, and zero
   fallback Trash call.
3. Repeat the disposable-volume differential with the unchanged Foundation
   baseline and Finder candidate: 30 cycles per binary, split evenly across
   immediate, 1.5-second, and 3-second re-trash delays. One candidate metadata
   loss or stale path rejects the Finder fix.
4. Run the actual Finder Put Back menu differential for the Finder candidate.
   All 30 cycles must retain Put Back, restore the current content to the exact
   source path, return exact destination URLs, and show no unexpected UI or
   hang beyond the first accepted Automation prompt.
5. Include ordinary files, directories, symbolic links, broken symbolic links,
   duplicate Trash names, and path text containing quotes and newlines in the
   platform acceptance set.

### Human follow-up

- [x] Run and record the automated metadata differential above.
- [x] Reject the Workspace candidate and authorize a Finder-delegated design.
- [x] Retain `fix/12-put-back-metadata-race` for the Finder candidate.
- [x] Run and record the Finder Automation authorization/denial acceptance.
- [x] Run `make test-put-back-race-manual` and record whether Finder offers Put
      Back for its exact second Trash URL. Recorded 2026-07-31: 3/3 retained
      across the 0, 1.5, and 3 second buckets.
- [x] Repeat that manual scenario for the full 30 cycles (10 per bucket).
      Recorded 2026-08-01: 30/30 retained.
- [x] Extend the differential to the platform acceptance set. Recorded
      2026-08-01: directories, quoted names, and newline names all retain Put
      Back; symbolic links and broken symbolic links cannot be deleted through
      Finder at all.
- [ ] Implement dispatch-by-type so symbolic links delete through Foundation,
      with the boundary, ADR, and known-limitation documentation it requires.
      Direction recorded below; deliberately not implemented yet.
- [ ] Test duplicate Trash names, the one shape in acceptance criterion 5 with
      no fixture kind yet. It needs a same-basename decoy already in the Trash,
      which the current single-Run-Directory scenario cannot produce.
- [ ] Decide whether the quoted-name and newline-name rows need the same
      10-cycle depth as ordinary files, or whether one cycle each is enough
      given that they probe argument passing rather than the metadata race.
- [ ] Grant the invoking terminal Full Disk Access, restart it, then run
      `make test-put-back-race` and record the same outcome for the scripted
      restore. A differing result between the two variants would isolate an
      Apple Event versus menu discrepancy.
- [ ] Run and record the Finder candidate automated metadata differential.
- [ ] Run and record the Finder candidate actual-menu differential.
- [ ] If the maintainer wants to investigate a possible Apple Event versus menu
      discrepancy, run the actual Put Back differential above.
- [ ] Submit the Foundation/Finder metadata-coherence evidence through Feedback
      Assistant and record the Feedback ID here. No upstream report was sent by
      the implementation agent.

## Comments

2026-07-18 — The investigation initially recorded this in the manual-testing
notes as an environment/system-boundary pattern. The maintainer reclassified
it as a product defect: the failure is user-visible in the product's core
promise (recoverable deletion), not merely a test-environment artifact. The
manual-testing document intentionally carries no copy of this record; this
ticket is the single source of truth.

2026-07-23 — The maintainer approved an isolated
`fix/12-put-back-metadata-race` candidate branch, local commits only, with no
push or merge to local `main`. Agent-runnable work is complete when pure tests,
policy gates, documentation, and review pass.

2026-07-23 — Automated pre-acceptance produced a valid Foundation baseline but
the Workspace candidate matched its failure in all 30 cycles. The candidate is
not merge-ready; status returned to `needs-triage` for a maintainer decision on
abandoning the candidate versus designing Finder-delegated deletion.

2026-07-23 — The maintainer accepted the first-use Automation authorization
tradeoff, retained the existing candidate branch, rejected Workspace recycling,
and authorized continued implementation of Finder-delegated deletion. The
ticket is `ready-for-human` until the Automation and real Put Back acceptance
rounds above are recorded.

2026-08-01 — Status moved from `ready-for-human` to `ready-for-agent`. The
condition the 2026-07-23 comment set for leaving `ready-for-human` (recording the
Automation and real Put Back acceptance rounds) is met. The largest remaining gap
is fixture shape, and extending the scenario to directories, symbolic links,
broken symbolic links, duplicate names, and awkward path text is agent work; only
the final menu judgment and the upstream report need the maintainer.

2026-08-01 — The 30-cycle actual-menu differential passed 30/30 across the 0,
1.5, and 3 second buckets. Against the roughly 10% retention recorded for the
Foundation client in the same flow, and 0/30 for both Foundation and Workspace
in the instrumented harness, Finder-delegated deletion is established as the fix
for this defect. The ticket stays `ready-for-human`: the differential covered
only ordinary small files on one local volume, so the platform acceptance set
and the Feedback Assistant report remain open.

2026-07-31 — The authoritative scenario ran end to end for the first time with
the maintainer's real Finder Put Back command. Put Back survived on the second
Trash item in all three delay buckets, judged outside the deferred write-back
window. Against E6's roughly 90% loss rate for the Foundation client in the same
flow, this is the first direct evidence that Finder-delegated deletion fixes the
reported defect. The ticket stays `ready-for-human`: the 30-cycle differential
and the Feedback Assistant report remain open.

2026-07-26 — A live scripted-restore run failed with Apple Event `-5000`. The
recorded cause is the home Trash TCC boundary rather than a second Automation
sender, correcting the earlier inference; see the constraint section above. A
second maintainer-invoked variant, `put-back-race-manual`, was added. It holds
no Finder Put Back capability, needs no Full Disk Access, and waits for the
real Put Back command through a kqueue-backed dispatch source before firing the
second Trash call.

2026-07-26 — The real handler's `POSIX file` scope defect was corrected after a
live `-1728` failure. Ghostty denial, approval, and same-host authorization reuse
were recorded. The temporary shell/`osascript` race attempt was rejected because
it introduced a second Automation sender; the checked-in authority is now the
single-process Swift `rmp-test put-back-race` scenario. The 30-cycle metadata and
actual-menu differentials remain human release gates.
