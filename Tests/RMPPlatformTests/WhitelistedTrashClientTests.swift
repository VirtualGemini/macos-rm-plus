// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import rmp_test

// The ticket and PRD define this safety-boundary name.
// swiftlint:disable inclusive_language
@Suite("Whitelisted system Trash capability", .serialized)
struct WhitelistedTrashClientTests {
  @Test("passes an authorized Test Fixture to the system capability after revalidation")
  func trashesAuthorizedFixture() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let returnedURL = URL(fileURLWithPath: "/Trash/\(target.lastPathComponent)")
    let spy = TrashSpy(returnedURL: returnedURL)
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )

    let evidence = try trash(client: client, target: target)

    #expect(spy.receivedURLs == [target])
    #expect(evidence.returnedURL == returnedURL)
    #expect(FileManager.default.fileExists(atPath: target.path))
  }

  @Test("authorizes planning without invoking the system Trash capability")
  func authorizesPlanningWithoutTrashCall() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let spy = TrashSpy()
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )

    _ = try client.authorizeForPlanning(targetURL: target)

    #expect(spy.receivedURLs.isEmpty)
  }

  @Test(
    "rejects whitelist and fixture-name violations without a system Trash call",
    arguments: AuthorizationRejectionCase.pathCases
  )
  func rejectsUnsafePaths(testCase: AuthorizationRejectionCase) throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let spy = TrashSpy()
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )
    let target = try testCase.target(context: context, fixture: fixture)
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic { _ = try trash(client: client, target: target) }

    #expect(diagnostic?.code == testCase.expectedCode)
    #expect(spy.receivedURLs.isEmpty)
    #expect(try fixture.snapshot() == before)
  }

  @Test("permits a final symlink entry but rejects an intermediate symlink escape")
  func enforcesSymlinkBoundary() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let outside = fixture.homeURL.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    let prefix = fixturePrefix(context)
    let finalSymlink = context.runDirectoryURL.appendingPathComponent("\(prefix)final-link")
    try FileManager.default.createSymbolicLink(at: finalSymlink, withDestinationURL: outside)
    let intermediate = context.runDirectoryURL.appendingPathComponent("link", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: intermediate, withDestinationURL: outside)
    let escapedTarget = intermediate.appendingPathComponent("\(prefix)escaped")
    try Data().write(to: outside.appendingPathComponent("\(prefix)escaped"))
    let volumeSpy = VolumeInspectionSpy()
    let spy = TrashSpy(
      returnedURL: URL(fileURLWithPath: "/Trash/\(finalSymlink.lastPathComponent)")
    )
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: TrashAuthorizationOperations(
        inspectVolume: volumeSpy.inspect,
        deviceMatchesRun: { $0 == $1 },
        resourceIdentifier: { _ in nil }
      ),
      systemTrash: spy.call
    )
    let before = try fixture.snapshot()

    _ = try trash(client: client, target: finalSymlink)
    let diagnostic = captureDiagnostic { _ = try trash(client: client, target: escapedTarget) }

    #expect(spy.receivedURLs.map(\.path) == [finalSymlink.path])
    #expect(volumeSpy.receivedURLs == [context.runDirectoryURL, context.runDirectoryURL])
    #expect(diagnostic?.code == .trashIntermediateSymlink)
    #expect(try fixture.snapshot() == before)
  }

  @Test(
    "rejects unsafe volume classes without a system Trash call",
    arguments: AuthorizationRejectionCase.volumeCases
  )
  func rejectsUnsafeVolumes(testCase: AuthorizationRejectionCase) throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let spy = TrashSpy()
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: testCase.authorization,
      systemTrash: spy.call
    )
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic { _ = try trash(client: client, target: target) }

    #expect(diagnostic?.code == testCase.expectedCode)
    #expect(spy.receivedURLs.isEmpty)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rechecks marker, directory identity, and permissions before every system call")
  func revalidatesContextImmediatelyBeforeSystemTrash() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let spy = TrashSpy()
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )
    let authorizedTarget = try client.authorizeForPlanning(targetURL: target)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: fixture.authorizedRootURL.path
    )
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic { _ = try client.trashItem(authorizedTarget) }

    #expect(diagnostic?.code == .directoryPermissions)
    #expect(spy.receivedURLs.isEmpty)
    #expect(try fixture.snapshot() == before)
  }

  @Test(
    "rechecks markers, identities, and permissions without a system Trash call",
    arguments: ContextRevalidationCase.allCases
  )
  func rejectsInvalidatedContext(testCase: ContextRevalidationCase) throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let spy = TrashSpy()
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )
    let authorizedTarget = try client.authorizeForPlanning(targetURL: target)
    try testCase.invalidate(context: context, fixture: fixture)
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic { _ = try client.trashItem(authorizedTarget) }

    #expect(diagnostic?.code == testCase.expectedCode)
    #expect(spy.receivedURLs.isEmpty)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rejects a Test Fixture replaced after planning without a system Trash call")
  func rejectsTargetIdentityChangeAfterPlanning() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let spy = TrashSpy()
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )
    let authorizedTarget = try client.authorizeForPlanning(targetURL: target)
    let displaced = context.runDirectoryURL.appendingPathComponent("displaced-fixture")
    try FileManager.default.moveItem(at: target, to: displaced)
    try Data("replacement".utf8).write(to: target)

    let diagnostic = captureDiagnostic { _ = try client.trashItem(authorizedTarget) }

    #expect(diagnostic?.code == .trashPlanIdentityMismatch)
    #expect(spy.receivedURLs.isEmpty)
  }

  @Test("rejects returned Trash evidence with the wrong run prefix")
  func rejectsWrongReturnedTrashPrefix() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let spy = TrashSpy(returnedURL: URL(fileURLWithPath: "/Trash/unrelated-item"))
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )

    let diagnostic = captureDiagnostic { _ = try trash(client: client, target: target) }

    #expect(diagnostic?.code == .trashEvidenceMismatch)
    #expect(spy.receivedURLs == [target])
  }

  @Test("rejects returned Trash evidence with a different resource identifier")
  func rejectsWrongReturnedTrashIdentity() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let returnedURL = URL(fileURLWithPath: "/Trash/\(target.lastPathComponent)")
    let spy = TrashSpy(returnedURL: returnedURL)
    let authorization = TrashAuthorizationOperations(
      inspectVolume: { _ in .accepted },
      deviceMatchesRun: { $0 == $1 },
      resourceIdentifier: { url in url == target ? Data([1]) : Data([2]) }
    )
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: authorization,
      systemTrash: spy.call
    )

    let diagnostic = captureDiagnostic { _ = try trash(client: client, target: target) }

    #expect(diagnostic?.code == .trashEvidenceMismatch)
    #expect(spy.receivedURLs == [target])
  }

  @Test("maps a system Trash failure to a stable diagnostic")
  func mapsSystemTrashFailure() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try makeFixture(context: context)
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: { _ in throw InjectedSystemTrashError() }
    )

    let diagnostic = captureDiagnostic { _ = try trash(client: client, target: target) }

    #expect(diagnostic?.code == .trashSystemCallFailed)
    #expect(FileManager.default.fileExists(atPath: target.path))
  }
}
// swiftlint:enable inclusive_language

private final class TrashSpy: @unchecked Sendable {
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

private final class VolumeInspectionSpy: @unchecked Sendable {
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

private struct InjectedInspectionError: Error {}
private struct InjectedSystemTrashError: Error {}

extension TrashAuthorizationOperations {
  fileprivate static let accepting = TrashAuthorizationOperations(
    inspectVolume: { _ in .accepted },
    deviceMatchesRun: { $0 == $1 },
    resourceIdentifier: { _ in nil }
  )

  fileprivate static func replacingVolume(
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
  fileprivate static let accepted = TrashVolumeInspection(
    isLocal: true,
    isMountPoint: false,
    isFileProviderRoot: false
  )
}

private func makeFixture(context: TestSafetyContext) throws -> URL {
  let target = context.runDirectoryURL.appendingPathComponent("\(fixturePrefix(context))item")
  try Data("fixture".utf8).write(to: target)
  return target
}

private func fixturePrefix(_ context: TestSafetyContext) -> String {
  "rmp-test-\(context.runID.uuidString.lowercased())-"
}

private func trash(
  client: WhitelistedTrashClient,
  target: URL
) throws -> TrashVerificationEvidence {
  try client.trashItem(client.authorizeForPlanning(targetURL: target))
}
