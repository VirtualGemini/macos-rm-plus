// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import tc_test

final class TrashSpy: @unchecked Sendable {
  private(set) var receivedURLs: [URL] = []
  private let returnedURL: URL

  init(returnedURL: URL = URL(fileURLWithPath: "/unused-trash-evidence")) {
    self.returnedURL = returnedURL
  }

  func call(_ url: URL) throws -> URL {
    receivedURLs.append(url)
    return returnedURL
  }
}

final class VolumeInspectionSpy: @unchecked Sendable {
  private(set) var receivedURLs: [URL] = []

  func inspect(_ url: URL) throws -> TrashVolumeInspection {
    receivedURLs.append(url)
    return .accepted
  }
}

enum AuthorizationRejectionCase: CaseIterable, CustomTestStringConvertible {
  case outside
  case runDirectory
  case wrongFixturePrefix
  case missingTarget
  case intermediateFile
  case mountPoint
  case networkVolume
  case fileProviderRoot
  case crossVolume
  case inspectionFailure

  static let pathCases: [AuthorizationRejectionCase] = [
    .outside, .runDirectory, .wrongFixturePrefix, .missingTarget, .intermediateFile,
  ]
  static let volumeCases: [AuthorizationRejectionCase] = [
    .mountPoint, .networkVolume, .fileProviderRoot, .crossVolume, .inspectionFailure,
  ]

  var testDescription: String { expectedCode.rawValue }

  var expectedCode: TestSafetyDiagnosticCode {
    switch self {
    case .outside: .trashOutsideRunDirectory
    case .runDirectory: .trashSafetyDirectory
    case .wrongFixturePrefix: .trashFixtureName
    case .missingTarget, .intermediateFile: .trashPathInspectionFailed
    case .mountPoint: .trashMountPoint
    case .networkVolume: .trashNetworkVolume
    case .fileProviderRoot: .trashFileProviderRoot
    case .crossVolume: .trashVolumeMismatch
    case .inspectionFailure: .trashPathInspectionFailed
    }
  }

  var authorization: TrashAuthorizationOperations {
    switch self {
    case .mountPoint:
      .replacingVolume(
        TrashVolumeInspection(isLocal: true, isMountPoint: true, isFileProviderRoot: false)
      )
    case .networkVolume:
      .replacingVolume(
        TrashVolumeInspection(isLocal: false, isMountPoint: false, isFileProviderRoot: false)
      )
    case .fileProviderRoot:
      .replacingVolume(
        TrashVolumeInspection(isLocal: true, isMountPoint: false, isFileProviderRoot: true)
      )
    case .crossVolume:
      TrashAuthorizationOperations(
        inspectVolume: { _ in .accepted },
        deviceMatchesRun: { _, _ in false },
        resourceIdentifier: { _ in nil }
      )
    case .inspectionFailure:
      TrashAuthorizationOperations(
        inspectVolume: { _ in throw InjectedInspectionError() },
        deviceMatchesRun: { $0 == $1 },
        resourceIdentifier: { _ in nil }
      )
    default: .accepting
    }
  }

  func target(context: TestSafetyContext, fixture: SafetyHomeFixture) throws -> URL {
    switch self {
    case .outside:
      let target = fixture.homeURL.appendingPathComponent("\(fixturePrefix(context))outside")
      try Data().write(to: target)
      return target
    case .runDirectory:
      return context.runDirectoryURL
    case .wrongFixturePrefix:
      let target = context.runDirectoryURL.appendingPathComponent("fixture")
      try Data().write(to: target)
      return target
    case .missingTarget:
      return context.runDirectoryURL.appendingPathComponent("\(fixturePrefix(context))missing")
    case .intermediateFile:
      let intermediate = context.runDirectoryURL.appendingPathComponent("intermediate")
      try Data().write(to: intermediate)
      return intermediate.appendingPathComponent("\(fixturePrefix(context))nested")
    default:
      return try makeFixture(context: context)
    }
  }
}

struct InjectedInspectionError: Error {}
struct InjectedSystemTrashError: Error {}

extension TrashAuthorizationOperations {
  static let accepting = TrashAuthorizationOperations(
    inspectVolume: { _ in .accepted },
    deviceMatchesRun: { $0 == $1 },
    resourceIdentifier: { _ in nil }
  )

  static func replacingVolume(
    _ inspection: TrashVolumeInspection
  ) -> TrashAuthorizationOperations {
    TrashAuthorizationOperations(
      inspectVolume: { _ in inspection },
      deviceMatchesRun: { $0 == $1 },
      resourceIdentifier: { _ in nil }
    )
  }
}

extension TrashVolumeInspection {
  static let accepted = TrashVolumeInspection(
    isLocal: true,
    isMountPoint: false,
    isFileProviderRoot: false
  )
}

func makeFixture(context: TestSafetyContext) throws -> URL {
  let target = context.runDirectoryURL.appendingPathComponent("\(fixturePrefix(context))item")
  try Data("fixture".utf8).write(to: target)
  return target
}

func fixturePrefix(_ context: TestSafetyContext) -> String {
  "tc-test-\(context.runID.uuidString.lowercased())-"
}

func trash(
  client: WhitelistedTrashClient,
  target: URL
) throws -> TrashVerificationEvidence {
  try client.trashItem(client.authorizeForPlanning(targetURL: target))
}
