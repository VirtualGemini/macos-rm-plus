# Preserve symbolic-link Put Back with Foundation finalizers

Status: Accepted

Date: 2026-08-10

Revised: 2026-08-13

## Context

Finder deletion preserves Put Back reliably for ordinary files and directories, but Finder's Apple
Event `delete` command refuses symbolic links. Foundation moves symbolic links correctly without
following their targets, but issue 12 found that the final Foundation Trash call in a process does
not immediately expose Put Back. Across 0- and 15-second tests, a later successful Foundation Trash
call made the preceding item recoverable while the new final item remained without Put Back.

Delay, a failed follow-up call, a fresh `FileManager`, and an explicit autorelease pool did not
change that result. A successful Foundation call on an owned symbolic link, followed by restoring
and removing that link, did preserve Put Back for the preceding user item.

## Decision

`MacOSTrashClient` dispatches by the final directory-entry type:

- ordinary files and directories use `FinderTrashClient`;
- symbolic links and broken symbolic links use Foundation Trash with an owned finalizer lifecycle.

Before moving a user symbolic link, the client prepares two exclusive UUID finalizer links beside the
source in the same directory and volume and records their device/inode identities. It does not Trash
a preflight finalizer: resolving-link runs `0516390e-686b-4d0d-ba62-cc5b40d22064` and
`0a34c398-056b-4a45-9892-0f3d7fed7614`, plus broken-link run
`a6a43b18-bba2-4d8b-b681-0c12d83569ca`, all offered Put Back when only the preflight was disabled.
The otherwise equivalent standalone run with preflight enabled did not. The production Foundation
sequence must therefore begin with the user target, followed by an activation finalizer.

After Foundation returns the target's Trash URL, the prepared finalizers are tried serially. The
first successful Foundation finalizer call establishes the Put Back guarantee for the target. The
client verifies that the returned target is the original symbolic-link identity before reporting
its destination. It still performs the finalizer call before rejecting a mismatched target receipt,
so a bad receipt does not unnecessarily forfeit the actual moved item's Put Back opportunity. The
client verifies the returned finalizer by symbolic-link type and device/inode before restoring the
exact URL, verifies it again at the source, and unlinks only that restored entry. It never
permanently deletes an item inside Trash and never searches Trash by name.

If an activation throws, the client retries only after proving that the exact finalizer remains at
its source and removing it there. If the source is missing or changed, the call may have moved the
finalizer before throwing; retrying would shift the next-call metadata again, so processing stops
with `finalizer_state_uncertain`. If every definitely-not-moved activation fails, the exact target
receipt is retained with `symlink_put_back_not_guaranteed`. If activation succeeds but restore or
cleanup fails, the receipt
uses `finalizer_cleanup_failed`; Put Back remains classified as activated. All three warnings keep
the item status `moved`, write a stable diagnostic to stderr, and produce exit code 1.

Preparation, the optional diagnostic preflight, and the target Trash call can also fail before a
moved target receipt exists. Cleanup of every already prepared Finalizer is then mandatory and
identity-checked. If any such cleanup cannot be completed, the original failure is replaced by the
stable `finalizer_cleanup_failed` capability error so the residue is never silently hidden. The
ordinary post-call identity check still determines whether the user target is `not_moved` or
`state_uncertain`. If a newly created Finalizer cannot pass its first identity check, the client
does not unlink that basename because concurrent replacement cannot be excluded; it preserves the
entry as evidence and reports the same stable cleanup failure.

## Consequences

The normal symbolic-link path is user-transparent and leaves only the requested item in Trash. It
costs one target and one finalizer Trash call. Hidden finalizer links exist briefly beside the source.
A crash, volume removal, or concurrent replacement can still leave an owned hidden link in the
source directory or Trash; no finite sequence can guarantee that macOS or the process will never
fail. Both activation candidates are created and identity-checked before the irreversible point,
while any failure after the target moves preserves exact outcome reporting.

The production manual acceptance uses `put-back-symlink-production-manual`. Its first Trash call
moves a separate ordinary-file control through Finder, which establishes a reliable item for the
maintainer's real Finder Put Back. Only after that exact restore is observed and revalidated does a
production client Trash the symbolic-link target under the normal or injected scenario. Every
internal target and finalizer Foundation call passes through the Test Safety Context
whitelist, and its restore wrapper revalidates that context immediately before the real move. The
test executable can inject a single first-activation failure either before the
Foundation call or after the real whitelisted call has moved the Finalizer. These modes verify backup
recovery and the moved-before-error stop rule without exposing fault controls in production `rmp`.

## Rejected alternatives

- Waiting before or after Trash was rejected because the same final-call behavior occurred at both
  tested delay endpoints.
- Finder deletion for symbolic links was rejected because Finder refuses the operation.
- A failed Foundation call, a new `FileManager`, and autorelease-pool drainage were rejected because
  none activated Put Back.
- A target-before-move Foundation finalizer preflight was rejected because isolated runs with that
  single extra operation lacked Put Back, while two resolving-link runs and one broken-link run with
  the preflight disabled all offered it immediately.
- Direct permanent deletion of the finalizer inside Trash was rejected because it expands the
  destructive capability and is unnecessary.
- Silently ignoring activation failure was rejected because it would claim recoverability that was
  not established.
