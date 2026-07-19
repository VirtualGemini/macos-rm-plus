# 12 — Put Back entry lost when re-trashing a same-named item soon after Put Back

**Status:** needs-triage

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

## Remediation options (maintainer decision required)

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

## Comments

2026-07-18 — The investigation initially recorded this in the manual-testing
notes as an environment/system-boundary pattern. The maintainer reclassified
it as a product defect: the failure is user-visible in the product's core
promise (recoverable deletion), not merely a test-environment artifact. The
manual-testing document intentionally carries no copy of this record; this
ticket is the single source of truth.
