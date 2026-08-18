// SPDX-License-Identifier: Apache-2.0

import Foundation
import TrashCore

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

enum ProductionFinalizerName: String, CaseIterable, Sendable {
  case hidden
  case visible

  func prefix(runID: UUID) -> String {
    switch self {
    case .hidden: ".tc-finalizer-"
    case .visible: "tc-test-\(runID.uuidString.lowercased())-visible-finalizer-"
    }
  }

  func makeName(runID: UUID) -> String {
    "\(prefix(runID: runID))\(UUID().uuidString.lowercased())"
  }
}

enum ProductionFinalizerPreflight: String, CaseIterable, Sendable {
  case enabled
  case disabled

  var isEnabled: Bool { self == .enabled }
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

struct ProductionProbeOptions {
  let kind: PutBackRaceFixtureKind
  let finalizerName: ProductionFinalizerName
  let preflight: ProductionFinalizerPreflight
  let driverArguments: [String]
}

func extractProductionProbeOptions(_ arguments: [String]) throws -> ProductionProbeOptions {
  let unsupported = ["--cycles", "--settle-seconds", "--finalizer-fault"]
  guard !arguments.contains(where: unsupported.contains) else {
    throw TestSafetyDiagnostic(
      code: .invalidCommandArguments,
      message: "put-back-symlink-production-probe accepts only --fixture."
    )
  }
  let (finalizerName, afterName) = try extractProductionFinalizerName(arguments)
  let (preflight, afterPreflight) = try extractProductionFinalizerPreflight(afterName)
  let (kind, driverArguments) = try extractFixtureKind(afterPreflight, defaultKind: .symbolicLink)
  return ProductionProbeOptions(
    kind: kind,
    finalizerName: finalizerName,
    preflight: preflight,
    driverArguments: driverArguments
  )
}

func extractProductionFinalizerPreflight(
  _ arguments: [String]
) throws -> (ProductionFinalizerPreflight, [String]) {
  var preflight = ProductionFinalizerPreflight.disabled
  var remaining: [String] = []
  var index = arguments.startIndex
  while index < arguments.endIndex {
    guard arguments[index] == "--preflight" else {
      remaining.append(arguments[index])
      index = arguments.index(after: index)
      continue
    }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex,
      let parsed = ProductionFinalizerPreflight(rawValue: arguments[valueIndex])
    else {
      throw TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "--preflight requires one of: enabled, disabled."
      )
    }
    preflight = parsed
    index = arguments.index(after: valueIndex)
  }
  return (preflight, remaining)
}

func extractProductionFinalizerName(
  _ arguments: [String]
) throws -> (ProductionFinalizerName, [String]) {
  var name = ProductionFinalizerName.hidden
  var remaining: [String] = []
  var index = arguments.startIndex
  while index < arguments.endIndex {
    guard arguments[index] == "--finalizer-name" else {
      remaining.append(arguments[index])
      index = arguments.index(after: index)
      continue
    }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex,
      let parsed = ProductionFinalizerName(rawValue: arguments[valueIndex])
    else {
      throw TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "--finalizer-name requires one of: hidden, visible."
      )
    }
    name = parsed
    index = arguments.index(after: valueIndex)
  }
  return (name, remaining)
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
