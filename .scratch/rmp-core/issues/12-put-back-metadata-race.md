# 12 — Put Back entry lost when re-trashing a same-named item soon after Put Back

**Status:** ready-for-human

**Classification:** defect — user-visible product anomaly at the macOS Trash
integration boundary. Recoverability of `rmp` deletions is degraded relative
to Finder-native deletion; reclassified from environment noise by the
maintainer on 2026-07-18.

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

## Why the current implementation cannot avoid it

The metadata loss was observed seconds after the `rmp` process exited. The
evidence attributes the later persistence to Finder activity, but cannot prove
its private implementation. The process cannot verify or repair the record
afterwards: the home Trash `.DS_Store` is TCC-protected, its format is private,
and rewriting it would race Finder again.

## Remediation options

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
- [ ] Run and record the Finder Automation authorization/denial acceptance.
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
