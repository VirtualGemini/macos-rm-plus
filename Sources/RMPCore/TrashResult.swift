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
  let suppressesFailureExit: Bool

  init(
    sourcePath: String,
    destinationPath: String?,
    kind: TrashInputKind,
    status: TrashResultStatus,
    skipReason: TrashSkipReason?,
    warnings: [TrashMoveWarning],
    error: TrashFailure?,
    suppressesFailureExit: Bool = false
  ) {
    self.sourcePath = sourcePath
    self.destinationPath = destinationPath
    self.kind = kind
    self.status = status
    self.skipReason = skipReason
    self.warnings = warnings
    self.error = error
    self.suppressesFailureExit = suppressesFailureExit
  }

  var requiresFailureExit: Bool {
    !suppressesFailureExit && status.isFailure
  }

  var preventsAggregateSuccess: Bool {
    status.isFailure || !warnings.isEmpty
  }

  var triggersStopOnError: Bool {
    status.isFailure
  }
}

enum TrashSkipReason: Equatable, Sendable {
  case confirmationInterrupted
  case ignoredMissing
  case stoppedAfterFailure
}

private extension TrashResultStatus {
  var isFailure: Bool {
    switch self {
    case .moved, .skipped: false
    case .rejected, .notMoved, .stateUncertain: true
    }
  }
}
