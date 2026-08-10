# Preserve symbolic-link Put Back with Foundation finalizers

Status: Accepted

Date: 2026-08-10

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

Before moving a user symbolic link, the client runs a complete finalizer preflight beside the source
in the same directory and volume: exclusive UUID link creation, Foundation Trash, returned-identity
verification, exact restore, restored-identity verification, and descriptor-relative unlink. The
target is not moved unless this preflight succeeds. Two additional UUID finalizer links are then
prepared before the target moves.

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

## Consequences

The normal symbolic-link path is user-transparent and leaves only the requested item in Trash. It
costs one preflight round trip plus one target and one finalizer Trash call. Hidden finalizer links
exist briefly beside the source. A crash, volume removal, or concurrent replacement can still leave
an owned hidden link in the source directory or Trash; no finite sequence can guarantee that macOS
or the process will never fail. The ordering makes every predictable setup failure occur before the
target moves, prepares a retry before the irreversible point, and never sacrifices exact outcome
reporting after the target has moved.

The production manual acceptance uses `put-back-symlink-production-manual`. Its first Trash call is
the Foundation control used for the maintainer's real Finder Put Back. Only after that restore is
observed and revalidated does the second Trash use the production `MacOSTrashClient`. Every internal
preflight, target, and finalizer Foundation call passes through the Test Safety Context whitelist.

## Rejected alternatives

- Waiting before or after Trash was rejected because the same final-call behavior occurred at both
  tested delay endpoints.
- Finder deletion for symbolic links was rejected because Finder refuses the operation.
- A failed Foundation call, a new `FileManager`, and autorelease-pool drainage were rejected because
  none activated Put Back.
- Direct permanent deletion of the finalizer inside Trash was rejected because it expands the
  destructive capability and is unnecessary.
- Silently ignoring activation failure was rejected because it would claim recoverability that was
  not established.
