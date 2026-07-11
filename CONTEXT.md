# rmp

rmp provides a recoverable command-line alternative to permanent file removal on macOS. Its language distinguishes user intent, safety policy, planned work, and system trash outcomes.

## Language

**Trash Operation**:
One complete rmp invocation and its aggregate outcome.
_Avoid_: Delete operation, removal job

**Trash Plan**:
The immutable description of the top-level work rmp intends to perform before any item is moved.
_Avoid_: Removal plan, delete plan

**Trash Input**:
One top-level path supplied by the user for consideration in a Trash Operation.
_Avoid_: Delete target, removal target

**Protected Path**:
A path that safety policy forbids rmp from moving to Trash regardless of confirmation or force options.
_Avoid_: Dangerous path, blocked file

**Compatibility Option**:
A historical command-line option accepted to preserve familiar invocation forms even when it has no native Trash meaning.
_Avoid_: Legacy flag, ignored flag

**Trash Result**:
The planned, moved, failed, or skipped outcome for one Trash Input.
_Avoid_: Delete result, removal response

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
