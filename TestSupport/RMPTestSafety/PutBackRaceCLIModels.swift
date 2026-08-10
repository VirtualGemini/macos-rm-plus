// SPDX-License-Identifier: Apache-2.0

import Foundation

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

  var finalizerDescription: String {
    if usesFoundationFinalizer { return "test-only-cleaned" }
    if usesProductionFinalizer { return "production-cleaned" }
    return "disabled"
  }
}

struct RaceOptions {
  let settleSeconds: TimeInterval
  let cycles: Int
  let kind: PutBackRaceFixtureKind
  let driverArguments: [String]
}
