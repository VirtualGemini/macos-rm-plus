// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@_spi(RMPTestingEntrypoint) @testable import RMPTestKit

@Suite("Test Safety Context", .serialized)
struct TestSafetyContextTests {
  @Test("trusted account lookup ignores a caller-controlled HOME value")
  func trustedAccountLookupIgnoresEnvironmentHome() throws {
    let originalHome = getenv("HOME").map { String(cString: $0) }
    defer {
      if let originalHome {
        setenv("HOME", originalHome, 1)
      } else {
        unsetenv("HOME")
      }
    }
    setenv("HOME", "/caller-controlled-home", 1)

    let account = try TrustedUserAccount.current()

    #expect(account.homeDirectory != "/caller-controlled-home")
  }

  @Test("establishes a fresh context with fixed markers and retained directory handles")
  func establishesFreshContext() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let runID = UUID()

    let context = try TestSafetyContext.establish(
      runID: runID,
      trustedUser: fixture.trustedUser,
      effectiveUserID: fixture.trustedUser.userID
    )

    #expect(context.runID == runID)
    #expect(context.containerIdentity != context.authorizedRootIdentity)
    #expect(context.authorizedRootIdentity != context.runDirectoryIdentity)
    #expect(fileMode(at: fixture.containerURL) == 0o700)
    #expect(fileMode(at: fixture.authorizedRootURL) == 0o700)
    #expect(fileMode(at: context.runDirectoryURL) == 0o700)
    #expect(fileMode(at: fixture.containerMarkerURL) == 0o600)
    #expect(fileMode(at: fixture.rootMarkerURL) == 0o600)
    #expect(fileMode(at: context.runMarkerURL) == 0o600)

    let marker = try decodeMarker(at: context.runMarkerURL)
    #expect(marker.formatVersion == 1)
    #expect(marker.role == .run)
    #expect(marker.runID == runID)
    #expect(marker.containerIdentity == context.containerIdentity)
    #expect(marker.authorizedRootIdentity == context.authorizedRootIdentity)
    #expect(marker.directoryIdentity == context.runDirectoryIdentity)
    try context.revalidate()
  }

  @Test("exclusive creation succeeds without residue under a restrictive caller umask")
  func creationSucceedsUnderRestrictiveUmask() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let originalMask = umask(0o777)
    defer { umask(originalMask) }

    let context = try fixture.establishContext()

    #expect(fileMode(at: fixture.containerURL) == 0o700)
    #expect(fileMode(at: fixture.authorizedRootURL) == 0o700)
    #expect(fileMode(at: context.runDirectoryURL) == 0o700)
    #expect(fileMode(at: fixture.containerMarkerURL) == 0o600)
    #expect(fileMode(at: fixture.rootMarkerURL) == 0o600)
    #expect(fileMode(at: context.runMarkerURL) == 0o600)
    #expect(try fixture.snapshot().keys.allSatisfy { !$0.contains(".rmp-create-") })
  }

  @Test(
    "rejects unsafe runtime identity before invoking downstream Trash work",
    arguments: [
      UnsafeRuntimeCase.root,
      .missingTestingBuild,
      .wrongExecutable,
      .missingRunID,
      .invalidRunID,
      .duplicateRunID,
      .missingRunIDValue,
      .accountIdentityMismatch,
    ])
  func rejectsUnsafeRuntime(testCase: UnsafeRuntimeCase) throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    var invocationCount = 0
    let before = try fixture.snapshot()

    let result = TestSafetyDriver.run(
      arguments: testCase.arguments,
      runtime: testCase.runtime(for: fixture.trustedUser),
      operation: { _, _ in
        invocationCount += 1
        return 0
      }
    )

    #expect(result.exitCode == 2)
    #expect(result.diagnostic?.code == testCase.expectedCode)
    #expect(invocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rejects an existing UUID Run Directory without invoking downstream Trash work")
  func rejectsRunDirectoryReuse() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let runID = UUID()
    let firstContext = try TestSafetyContext.establish(
      runID: runID,
      trustedUser: fixture.trustedUser,
      effectiveUserID: fixture.trustedUser.userID
    )
    var invocationCount = 0
    let before = try fixture.snapshot()

    let result = TestSafetyDriver.run(
      arguments: ["--test-run-id", runID.uuidString.lowercased(), "fixture"],
      runtime: .testing(executableName: "rmp-test", trustedUser: fixture.trustedUser),
      operation: { _, _ in
        invocationCount += 1
        return 0
      }
    )

    #expect(result.diagnostic?.code == .runDirectoryExists)
    #expect(invocationCount == 0)
    #expect(try fixture.snapshot() == before)
    _ = firstContext
  }

  @Test("passes path text downstream only after establishing the safety context")
  func invokesDownstreamWorkAfterAuthorization() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let runID = UUID()
    var receivedArguments: [String] = []

    let result = TestSafetyDriver.run(
      arguments: [
        "fixture with spaces",
        "--test-run-id",
        runID.uuidString.lowercased(),
        "-leading-option-like-path",
      ],
      runtime: .testing(executableName: "rmp-test", trustedUser: fixture.trustedUser),
      operation: { context, arguments in
        #expect(context.runID == runID)
        receivedArguments = arguments
        return 0
      }
    )

    #expect(result.exitCode == 0)
    #expect(result.diagnostic == nil)
    #expect(receivedArguments == ["fixture with spaces", "-leading-option-like-path"])
    #expect(!FileManager.default.fileExists(atPath: fixture.runDirectoryURL(for: runID).path))
  }
}

@Suite("Test Safety Context validation", .serialized)
struct TestSafetyValidationTests {
  @Test("rejects a symbolic-link fixed container before downstream Trash work")
  func rejectsSymbolicLinkContainer() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let destination = fixture.homeURL.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(
      at: fixture.containerURL, withDestinationURL: destination)
    let before = try fixture.snapshot()

    let result = fixture.runDriver()

    #expect(result.diagnostic?.code == .directorySymlink)
    #expect(fixture.downstreamInvocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rejects a non-directory fixed container before downstream Trash work")
  func rejectsWrongContainerType() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    try Data("not a directory".utf8).write(to: fixture.containerURL)
    let before = try fixture.snapshot()

    let result = fixture.runDriver()

    #expect(result.diagnostic?.code == .directoryWrongType)
    #expect(fixture.downstreamInvocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rejects unsafe fixed-directory permissions before downstream Trash work")
  func rejectsUnsafeDirectoryPermissions() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    try context.cleanupRunDirectory()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: fixture.authorizedRootURL.path
    )
    let before = try fixture.snapshot()

    let result = fixture.runDriver()

    #expect(result.diagnostic?.code == .directoryPermissions)
    #expect(fixture.downstreamInvocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rejects fixed-directory ownership mismatch before downstream Trash work")
  func rejectsDirectoryOwnershipMismatch() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    try fixture.createDirectory(at: fixture.containerURL, permissions: 0o700)
    let mismatchedUser = TrustedUserAccount(
      userID: fixture.trustedUser.userID + 1,
      homeDirectory: fixture.homeURL.path
    )
    let before = try fixture.snapshot()

    let result = TestSafetyDriver.run(
      arguments: ["--test-run-id", UUID().uuidString.lowercased(), "fixture"],
      runtime: .testing(executableName: "rmp-test", trustedUser: mismatchedUser),
      operation: { _, _ in
        Issue.record("Downstream Trash work must not be invoked")
        return 0
      }
    )

    #expect(result.diagnostic?.code == .directoryOwnerMismatch)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rejects a corrupt existing marker without rewriting it or invoking downstream Trash work")
  func rejectsCorruptMarkerWithoutRepair() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    try fixture.createDirectory(at: fixture.containerURL, permissions: 0o700)
    let corruptData = Data("corrupt marker\n".utf8)
    try corruptData.write(to: fixture.containerMarkerURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fixture.containerMarkerURL.path
    )
    let before = try fixture.snapshot()

    let result = fixture.runDriver()

    #expect(result.diagnostic?.code == .markerInvalid)
    #expect(try Data(contentsOf: fixture.containerMarkerURL) == corruptData)
    #expect(fixture.downstreamInvocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rejects an unsafe marker object and marker permissions before downstream Trash work")
  func rejectsUnsafeMarkerState() throws {
    let symlinkFixture = try SafetyHomeFixture()
    defer { symlinkFixture.remove() }
    try symlinkFixture.createDirectory(at: symlinkFixture.containerURL, permissions: 0o700)
    let target = symlinkFixture.homeURL.appendingPathComponent("marker-target")
    try Data().write(to: target)
    try FileManager.default.createSymbolicLink(
      at: symlinkFixture.containerMarkerURL,
      withDestinationURL: target
    )
    let symlinkBefore = try symlinkFixture.snapshot()

    let symlinkResult = symlinkFixture.runDriver()

    #expect(symlinkResult.diagnostic?.code == .markerWrongType)
    #expect(symlinkFixture.downstreamInvocationCount == 0)
    #expect(try symlinkFixture.snapshot() == symlinkBefore)

    let permissionFixture = try SafetyHomeFixture()
    defer { permissionFixture.remove() }
    let context = try TestSafetyContext.establish(
      runID: UUID(),
      trustedUser: permissionFixture.trustedUser,
      effectiveUserID: permissionFixture.trustedUser.userID
    )
    try context.cleanupRunDirectory()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: permissionFixture.rootMarkerURL.path
    )
    let permissionBefore = try permissionFixture.snapshot()

    let permissionResult = permissionFixture.runDriver()

    #expect(permissionResult.diagnostic?.code == .markerPermissions)
    #expect(permissionFixture.downstreamInvocationCount == 0)
    #expect(try permissionFixture.snapshot() == permissionBefore)
  }

  @Test("rejects recorded directory identity mismatch before downstream Trash work")
  func rejectsRecordedDirectoryIdentityMismatch() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try TestSafetyContext.establish(
      runID: UUID(),
      trustedUser: fixture.trustedUser,
      effectiveUserID: fixture.trustedUser.userID
    )
    try context.cleanupRunDirectory()
    try changeRecordedInode(in: fixture.rootMarkerURL)
    let before = try fixture.snapshot()

    let result = fixture.runDriver()

    #expect(result.diagnostic?.code == .markerInvalid)
    #expect(fixture.downstreamInvocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }

  @Test("rejects a missing long-lived marker without repairing it or invoking downstream work")
  func rejectsMissingMarkerWithoutRepair() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    try context.cleanupRunDirectory()
    try FileManager.default.removeItem(at: fixture.rootMarkerURL)
    let before = try fixture.snapshot()

    let result = fixture.runDriver()

    #expect(result.diagnostic?.code == .markerMissing)
    #expect(fixture.downstreamInvocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }

  @Test("run marker mismatch prevents a revalidated downstream Trash call")
  func runMarkerMismatchPreventsDownstreamWork() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    try changeRunID(in: context.runMarkerURL)
    let before = try fixture.snapshot()
    var invocationCount = 0

    let diagnostic = captureDiagnostic {
      try invokeAfterRevalidation(context: context) {
        invocationCount += 1
      }
    }

    #expect(diagnostic?.code == .markerInvalid)
    #expect(invocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }

  @Test("marker ownership mismatch is rejected without changing the hierarchy")
  func rejectsMarkerOwnershipMismatch() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    try context.cleanupRunDirectory()
    let container = try DirectoryHandle.createOrValidate(
      path: fixture.containerURL.path,
      owner: fixture.trustedUser.userID,
      role: .container
    ).handle
    let root = try DirectoryHandle.createOrValidate(
      parent: container,
      name: "test",
      owner: fixture.trustedUser.userID,
      role: .authorizedRoot
    ).handle
    let marker = try decodeMarker(at: fixture.rootMarkerURL)
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic {
      try validateExistingMarker(
        parent: root,
        name: ".rmp-test-root",
        expected: marker,
        owner: fixture.trustedUser.userID + 1
      )
    }

    #expect(diagnostic?.code == .markerOwnerMismatch)
    #expect(try fixture.snapshot() == before)
  }

  @Test("a missing fixed directory prevents revalidated downstream work")
  func missingFixedDirectoryPreventsDownstreamWork() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let movedRoot = fixture.authorizedRootURL.appendingPathExtension("moved")
    try FileManager.default.moveItem(at: fixture.authorizedRootURL, to: movedRoot)
    let before = try fixture.snapshot()
    var invocationCount = 0

    let diagnostic = captureDiagnostic {
      try invokeAfterRevalidation(context: context) {
        invocationCount += 1
      }
    }

    #expect(diagnostic?.code == .directoryMissing)
    #expect(invocationCount == 0)
    #expect(try fixture.snapshot() == before)
  }
}
