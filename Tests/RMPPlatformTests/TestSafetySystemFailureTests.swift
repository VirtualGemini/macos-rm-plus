// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@_spi(RMPTestingEntrypoint) @testable import RMPTestKit

@Suite("Test Safety Context system failures", .serialized)
struct TestSafetySystemFailureTests {
  @Test("missing system account records produce a stable diagnostic")
  func accountLookupFailureIsStable() {
    let diagnostic = captureDiagnostic {
      _ = try TrustedUserAccount.current(effectiveUserID: uid_t.max)
    }

    #expect(diagnostic?.code == "test-safety.account-lookup-failed")
  }

  @Test("directory creation failure is stable and leaves the trusted home unchanged")
  func directoryCreationFailureIsStable() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let nonDirectoryHome = fixture.homeURL.appendingPathComponent("not-a-home")
    try Data("file".utf8).write(to: nonDirectoryHome)
    let trustedUser = TrustedUserAccount(
      userID: fixture.trustedUser.userID,
      homeDirectory: nonDirectoryHome.path
    )
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic {
      _ = try TestSafetyContext.establish(
        runID: UUID(),
        trustedUser: trustedUser,
        effectiveUserID: trustedUser.userID
      )
    }

    #expect(diagnostic?.code == "test-safety.directory-create-failed")
    #expect(try fixture.snapshot() == before)
  }

  @Test("exclusive marker creation rejects an existing object without rewriting it")
  func markerCreationFailureIsStable() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    try fixture.createDirectory(at: fixture.containerURL, permissions: 0o700)
    let container = try DirectoryHandle.createOrValidate(
      path: fixture.containerURL.path,
      owner: fixture.trustedUser.userID,
      role: .container
    ).handle
    let marker = TestSafetyMarker(role: .container, directoryIdentity: container.identity)
    try createMarkerExclusive(parent: container, name: ".rmp-test-container", marker: marker)
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic {
      try createMarkerExclusive(parent: container, name: ".rmp-test-container", marker: marker)
    }

    #expect(diagnostic?.code == "test-safety.marker-exists")
    #expect(try fixture.snapshot() == before)
  }

  @Test("unexpected downstream errors map to a stable driver diagnostic")
  func unexpectedDriverFailureIsStable() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }

    let result = TestSafetyDriver.run(
      arguments: ["--test-run-id", UUID().uuidString.lowercased(), "fixture"],
      runtime: .testing(executableName: "rmp-test", trustedUser: fixture.trustedUser),
      operation: { _, _ in throw InjectedFailure() }
    )

    #expect(result.diagnostic?.code == "test-safety.unexpected-error")
  }
}

private struct InjectedFailure: Error {}
