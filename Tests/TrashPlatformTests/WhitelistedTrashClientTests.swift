// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import tc_test

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

  @Test("authorizes only an exact production finalizer symbolic link")
  func authorizesExactProductionFinalizer() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let finalizer = context.runDirectoryURL.appendingPathComponent(
      ".tc-finalizer-\(UUID().uuidString.lowercased())"
    )
    try FileManager.default.createSymbolicLink(
      at: finalizer,
      withDestinationURL: URL(fileURLWithPath: "absent-finalizer-target")
    )
    let returnedURL = URL(fileURLWithPath: "/Trash/\(finalizer.lastPathComponent)")
    let spy = TrashSpy(returnedURL: returnedURL)
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )

    let authorized = try client.authorizeProductionFinalizerForPlanning(targetURL: finalizer)
    let evidence = try client.trashItem(authorized)

    #expect(spy.receivedURLs == [finalizer])
    #expect(evidence.returnedURL == returnedURL)
  }

  @Test("rejects malformed, non-link, and nested production finalizers before system Trash")
  func rejectsInvalidProductionFinalizers() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let nestedDirectory = try context.createFixtureDirectory(suffix: "nested-finalizer")
    let candidates = [
      context.runDirectoryURL.appendingPathComponent(".tc-finalizer-not-a-uuid"),
      context.runDirectoryURL.appendingPathComponent(
        ".tc-finalizer-\(UUID().uuidString.lowercased())"
      ),
      nestedDirectory.appendingPathComponent(
        ".tc-finalizer-\(UUID().uuidString.lowercased())"
      ),
    ]
    try FileManager.default.createSymbolicLink(
      at: candidates[0],
      withDestinationURL: URL(fileURLWithPath: "absent")
    )
    try Data("not a link".utf8).write(to: candidates[1])
    try FileManager.default.createSymbolicLink(
      at: candidates[2],
      withDestinationURL: URL(fileURLWithPath: "absent")
    )
    let spy = TrashSpy()
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: .accepting,
      systemTrash: spy.call
    )

    for candidate in candidates {
      let diagnostic = captureDiagnostic {
        _ = try client.authorizeProductionFinalizerForPlanning(targetURL: candidate)
      }
      #expect(diagnostic?.code == .trashFixtureName)
    }

    #expect(spy.receivedURLs.isEmpty)
  }
}

extension WhitelistedTrashClientTests {
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

  @Test("verifies the same symbolic link after its relative target becomes broken in Trash")
  func verifiesMovedSymbolicLinkIdentity() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try context.createFixtureFile(
      suffix: "identity-target",
      contents: Data("target".utf8)
    )
    let link = try context.createFixtureSymbolicLink(
      suffix: "identity-link",
      target: target.lastPathComponent
    )
    let fakeTrashDirectory = fixture.homeURL.appendingPathComponent("Trash", isDirectory: true)
    try FileManager.default.createDirectory(
      at: fakeTrashDirectory,
      withIntermediateDirectories: false
    )
    let returnedURL = fakeTrashDirectory.appendingPathComponent(link.lastPathComponent)
    let client = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: TrashAuthorizationOperations(
        inspectVolume: { _ in .accepted },
        deviceMatchesRun: { $0 == $1 },
        resourceIdentifier: testSafetyResourceIdentifier
      ),
      systemTrash: { sourceURL in
        try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
        return returnedURL
      }
    )

    let evidence = try trash(client: client, target: link)

    #expect(evidence.returnedURL == returnedURL)
    #expect(evidence.resourceIdentifier != nil)
    #expect(FileManager.default.fileExists(atPath: target.path))
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
