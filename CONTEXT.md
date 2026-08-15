# rmp

rmp provides a recoverable command-line alternative to permanent file removal on macOS. Its language distinguishes user intent, safety policy, planned work, and system trash outcomes.

## Language

**Trash Operation**:
One complete rmp invocation and its aggregate outcome.
_Avoid_: Delete operation, removal job

**Trash Plan**:
The immutable, input-ordered description of the top-level work rmp intends to perform before any
item is moved. It retains ready inputs plus missing and inaccessible planning outcomes so execution
can produce exactly one Trash Result for every supplied path.
_Avoid_: Removal plan, delete plan

**Trash Input**:
One top-level path supplied by the user for consideration in a Trash Operation. It retains the
user-supplied path text and records the inspected kind of that directory entry without recursively
describing directory contents.
_Avoid_: Delete target, removal target

**Protected Path**:
A path that safety policy forbids rmp from moving to Trash regardless of confirmation or force options.
_Avoid_: Dangerous path, blocked file

**Confirmation Prompt**:
The injected terminal boundary that reports whether stdin is a TTY, writes one confirmation question
to stderr, and returns an answer or interruption without deciding whether a Trash Input is approved.
_Avoid_: Confirmation dialog, terminal reader

**Compatibility Option**:
A historical command-line option accepted to preserve familiar invocation forms even when it has no native Trash meaning.
Compatibility help classifies each one as accepted with no effect, accepted with a warning, or
unsupported. Compatibility diagnostics remain in the CLI result envelope; Compatibility Options
never become execution-facing Trash Operation requests or Trash Plan fields.
_Avoid_: Legacy flag, ignored flag

**Exit Status Compatibility**:
The contract that an invocation expressible using supported macOS `rm` options other than `-W` and
path operands produces the same numeric exit status under equivalent filesystem and confirmation
outcomes. Native rmp extensions are outside command-for-command comparison, but their usage failures
use the macOS usage status; `-W` remains explicitly unsupported because whiteout undeletion is not a
Trash Operation.
Exit Status Compatibility standardizes numeric meanings only; it does not require rmp to reproduce
macOS `rm` deletion behavior, confirmation flow, option effects, diagnostics, or output.
The public values are `0` for success, `1` for operational or safety failure, and `64` for usage
failure.
_Avoid_: Exit code mapping, approximate compatibility

**Trash Result**:
The planned, moved, failed, or skipped outcome for one Trash Input.
Pre-capability validation failures use `rejected`; they do not claim that a post-call filesystem
identity check occurred.
Operation-scope rejections carry stable codes and identify every affected top-level source path.
An ignored missing input is skipped without an error or nonzero exit-status effect. With
stop-on-error, every input after the first failure is skipped without reaching confirmation or the
Trash capability.
Under per-input `-i` confirmation, a declined, unrecognized, or end-of-file response does not by
itself cause a nonzero Exit Status.
Trash execution distinguishes `not_moved`, used only when the original directory entry's kind
and filesystem identity can be confirmed unchanged after a system Trash failure, from
`state_uncertain`, used whenever the final source state cannot be established reliably. A moved
result records the exact destination path from the Finder Trash boundary's returned item URL.
Finder Automation consent, denial, timeout, and availability failures remain failed Trash Results
with stable codes; they never imply that another Trash API was attempted as a fallback.
_Avoid_: Delete result, removal response

**JSON Trash Operation Result**:
The schema-version-1 machine representation of one Trash Operation. It contains aggregate success
and counts plus one input-ordered item for every top-level Trash Input. JSON maps internal
`rejected`, `not_moved`, and `state_uncertain` outcomes to the external `failed` state while retaining
the stable rmp error code and human-readable message. Sources are absolute and moved destinations are
the exact system-returned paths. Platform error domains and numeric codes are not part of this
contract. Planning errors use the same typed classification in human and JSON rendering; an encoding
failure leaves stdout empty instead of exposing a partial document.
_Avoid_: JSON response, platform error result

**Trash Finalizer**:
An rmp-owned, UUID-named broken symbolic link used only after a user symbolic link enters Trash. A
successful Foundation Trash call on the finalizer activates Put Back for the preceding user item;
the exact returned finalizer is then restored, identity-checked, and removed outside Trash.
_Avoid_: Temporary file, dummy file

**Trash Warning**:
A stable diagnostic attached to a moved Trash Result when the destination is known but either Put
Back could not be guaranteed, a failed Finalizer call left its source state uncertain, or an
already-activated Trash Finalizer could not be cleaned up.
A Trash Warning does not change an otherwise successful Exit Status because the user's source entry
was confirmed moved and an exact Trash receipt exists.
_Avoid_: Trash failure, state-uncertain error

**Trash Finalizer Cleanup Failure**:
A stable failed Trash Result used when the user item has no moved receipt and one or more prepared
Trash Finalizers could not be identity-verified and removed. Its `not_moved` or `state_uncertain`
status describes the user item, while the diagnostic describes the internal cleanup failure.
_Avoid_: Trash Warning, ignored cleanup error

## Testing Language

**Test Safety Context**:
The validated identity and authorization boundary for one real-filesystem test run.
_Avoid_: Sandbox, test environment

**Test Fixture**:
Data created specifically for a test inside its authorized Run Directory.
_Avoid_: Test file, dummy data

**Run Directory**:
The unique authorized directory assigned to one real-filesystem test run.
_Avoid_: Temp directory, sandbox directory
