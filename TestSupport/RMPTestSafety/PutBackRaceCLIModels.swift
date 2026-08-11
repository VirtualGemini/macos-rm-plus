// SPDX-License-Identifier: Apache-2.0

import Foundation
import RMPCore

enum ProductionFinalizerFault: String, CaseIterable, Sendable {
  case none
  case firstActivationNotMoved = "not-moved-before-error"
  case firstActivationMovedBeforeError = "moved-before-error"

  var expectedWarning: TrashWarningCode? {
    switch self {
    case .none, .firstActivationNotMoved: nil
    case .firstActivationMovedBeforeError: .finalizerStateUncertain
    }
  }

  var finalizerDescription: String {
    switch self {
    case .none: "production-cleaned"
    case .firstActivationNotMoved: "backup-recovered"
    case .firstActivationMovedBeforeError: "state-uncertain"
    }
  }
}

enum PutBackRaceRestore {
  case finderScript
  case manualFinderMenu
  case manualFoundationSymlinkDelay
  case manualFoundationSymlinkFinalizer
  case manualProductionSymlinkFinalizer

  var scenarioName: String {
    switch self {
    case .finderScript: "put-back-race"
    case .manualFinderMenu: "put-back-race-manual"
    case .manualFoundationSymlinkDelay: "put-back-symlink-delay-manual"
    case .manualFoundationSymlinkFinalizer: "put-back-symlink-finalizer-manual"
    case .manualProductionSymlinkFinalizer: "put-back-symlink-production-manual"
    }
  }

  var restoreDescription: String {
    switch self {
    case .finderScript: "finder-apple-event-move"
    case .manualFinderMenu, .manualFoundationSymlinkDelay,
      .manualFoundationSymlinkFinalizer, .manualProductionSymlinkFinalizer:
      "maintainer-finder-put-back-command"
    }
  }

  var trashBackend: TestSystemTrashBackend {
    switch self {
    case .finderScript, .manualFinderMenu: .finder
    case .manualFoundationSymlinkDelay, .manualFoundationSymlinkFinalizer,
      .manualProductionSymlinkFinalizer:
      .foundationSymlink
    }
  }

  var defaultFixtureKind: PutBackRaceFixtureKind {
    switch self {
    case .finderScript, .manualFinderMenu: .file
    case .manualFoundationSymlinkDelay, .manualFoundationSymlinkFinalizer,
      .manualProductionSymlinkFinalizer:
      .symbolicLink
    }
  }

  var supportsCycles: Bool {
    switch self {
    case .finderScript: false
    case .manualFinderMenu, .manualFoundationSymlinkDelay,
      .manualFoundationSymlinkFinalizer, .manualProductionSymlinkFinalizer:
      true
    }
  }

  var usesFoundationFinalizer: Bool {
    self == .manualFoundationSymlinkFinalizer
  }

  var usesProductionFinalizer: Bool {
    self == .manualProductionSymlinkFinalizer
  }

  var requiresZeroSettle: Bool {
    usesFoundationFinalizer || usesProductionFinalizer
  }

  func finalizerDescription(fault: ProductionFinalizerFault = .none) -> String {
    if usesFoundationFinalizer { return "test-only-cleaned" }
    if usesProductionFinalizer { return fault.finalizerDescription }
    return "disabled"
  }
}

struct RaceOptions {
  let settleSeconds: TimeInterval
  let cycles: Int
  let kind: PutBackRaceFixtureKind
  let finalizerFault: ProductionFinalizerFault
  let driverArguments: [String]
}

func extractProductionFinalizerFault(
  _ arguments: [String]
) throws -> (ProductionFinalizerFault, [String]) {
  var fault = ProductionFinalizerFault.none
  var remaining: [String] = []
  var index = arguments.startIndex
  while index < arguments.endIndex {
    guard arguments[index] == "--finalizer-fault" else {
      remaining.append(arguments[index])
      index = arguments.index(after: index)
      continue
    }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex,
      let parsed = ProductionFinalizerFault(rawValue: arguments[valueIndex])
    else {
      let known = ProductionFinalizerFault.allCases.map(\.rawValue).joined(separator: ", ")
      throw TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "--finalizer-fault requires one of: \(known)."
      )
    }
    fault = parsed
    index = arguments.index(after: valueIndex)
  }
  return (fault, remaining)
}
