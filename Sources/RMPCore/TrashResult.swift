// SPDX-License-Identifier: Apache-2.0

enum TrashResultStatus: String, Equatable, Sendable {
  case moved
  case rejected
  case skipped
  case notMoved = "not_moved"
  case stateUncertain = "state_uncertain"
}

struct TrashFailure: Equatable, Sendable {
  let code: TrashErrorCode
  let explanation: String
}

struct TrashResult: Equatable, Sendable {
  let sourcePath: String
  let destinationPath: String?
  let kind: TrashInputKind
  let status: TrashResultStatus
  let skipReason: TrashSkipReason?
  let warnings: [TrashMoveWarning]
  let error: TrashFailure?
  let failureExitSuppressed: Bool

  init(
    sourcePath: String,
    destinationPath: String?,
    kind: TrashInputKind,
    status: TrashResultStatus,
    skipReason: TrashSkipReason?,
    warnings: [TrashMoveWarning],
    error: TrashFailure?,
    failureExitSuppressed: Bool = false
  ) {
    self.sourcePath = sourcePath
    self.destinationPath = destinationPath
    self.kind = kind
    self.status = status
    self.skipReason = skipReason
    self.warnings = warnings
    self.error = error
    self.failureExitSuppressed = failureExitSuppressed
  }

  var requiresFailureExit: Bool {
    if failureExitSuppressed { return false }
    switch status {
    case .moved: return false
    case .skipped: return false
    case .rejected, .notMoved, .stateUncertain: return true
    }
  }

  var representsOperationFailure: Bool {
    switch status {
    case .moved: !warnings.isEmpty
    case .skipped: false
    case .rejected, .notMoved, .stateUncertain: true
    }
  }
}

enum TrashSkipReason: Equatable, Sendable {
  case confirmationInterrupted
  case ignoredMissing
  case stoppedAfterFailure
}
