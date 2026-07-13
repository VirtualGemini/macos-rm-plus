// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@testable import rmp_test

@Suite("Test Safety Context system failures", .serialized)
struct TestSafetySystemFailureTests {
  @Test("missing system account records produce a stable diagnostic")
  func accountLookupFailureIsStable() {
    let diagnostic = captureDiagnostic {
      _ = try TrustedUserAccount.current(effectiveUserID: uid_t.max)
    }

    #expect(diagnostic?.code == .accountLookupFailed)
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

    #expect(diagnostic?.code == .directoryCreateFailed)
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

    #expect(diagnostic?.code == .markerExists)
    #expect(try fixture.snapshot() == before)
  }

  @Test("oversized safety markers are rejected before unbounded reads")
  func oversizedMarkerIsRejected() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    try fixture.createDirectory(at: fixture.containerURL, permissions: 0o700)
    let container = try DirectoryHandle.createOrValidate(
      path: fixture.containerURL.path,
      owner: fixture.trustedUser.userID,
      role: .container
    ).handle
    #expect(FileManager.default.createFile(atPath: fixture.containerMarkerURL.path, contents: nil))
    let markerHandle = try FileHandle(forWritingTo: fixture.containerMarkerURL)
    try markerHandle.truncate(atOffset: 16_385)
    try markerHandle.close()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fixture.containerMarkerURL.path
    )

    let diagnostic = captureDiagnostic {
      try validateExistingMarker(
        parent: container,
        name: ".rmp-test-container",
        expected: TestSafetyMarker(role: .container, directoryIdentity: container.identity),
        owner: fixture.trustedUser.userID
      )
    }

    #expect(diagnostic?.code == .markerTooLarge)
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

    #expect(result.diagnostic?.code == .unexpectedError)
  }

  @Test("failed fixed container preparation leaves no published directory or staging residue")
  func fixedContainerPreparationFailureLeavesNoResidue() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic {
      _ = try DirectoryHandle.createOrValidate(
        path: fixture.containerURL.path,
        owner: fixture.trustedUser.userID,
        role: .container,
        preparation: DirectoryPreparation(
          apply: { handle in
            try createMarkerExclusive(
              parent: handle,
              name: ".rmp-test-container",
              marker: TestSafetyMarker(
                role: .container,
                directoryIdentity: handle.identity
              )
            )
            throw TestSafetyDiagnostic(
              code: .directoryCreateFailed,
              message: "Injected preparation failure."
            )
          },
          rollback: { handle in
            _ = unlinkat(handle.fileDescriptor, ".rmp-test-container", 0)
          }
        )
      )
    }

    #expect(diagnostic?.code == .directoryCreateFailed)
    #expect(try fixture.snapshot() == before)
  }

  @Test("failed staged-directory rollback reports that residue may remain")
  func failedStagedDirectoryRollbackIsReported() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }

    let diagnostic = captureDiagnostic {
      _ = try DirectoryHandle.createOrValidate(
        path: fixture.containerURL.path,
        owner: fixture.trustedUser.userID,
        role: .container,
        preparation: DirectoryPreparation(
          apply: { handle in
            let descriptor = openat(
              handle.fileDescriptor,
              "residue",
              O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
              mode_t(0o600)
            )
            #expect(descriptor >= 0)
            if descriptor >= 0 { close(descriptor) }
            throw TestSafetyDiagnostic(
              code: .markerWriteFailed,
              message: "Injected preparation failure."
            )
          },
          rollback: { _ in }
        )
      )
    }

    let residue = try #require(
      fixture.snapshot().keys.first { $0.contains(".rmp-create-") }
    )
    let residueName = try #require(
      residue.split(separator: "/").first { $0.contains(".rmp-create-") }
    )
    #expect(diagnostic?.code == .rollbackFailed)
    #expect(diagnostic?.message.contains(residueName) == true)
  }

  @Test("marker unlink failure reports the staged directory residue")
  func markerRollbackFailureReportsStagingEntry() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }

    let diagnostic = captureDiagnostic {
      _ = try DirectoryHandle.createOrValidate(
        path: fixture.containerURL.path,
        owner: fixture.trustedUser.userID,
        role: .container,
        preparation: DirectoryPreparation(
          apply: { handle in
            try createMarkerExclusive(
              parent: handle,
              name: ".rmp-test-container",
              marker: TestSafetyMarker(role: .container, directoryIdentity: handle.identity)
            )
            throw InjectedFailure()
          },
          rollback: { _ in
            throw TestSafetyDiagnostic(
              code: .rollbackFailed,
              message: "Injected marker unlink failure."
            )
          }
        )
      )
    }

    let residue = try #require(
      fixture.snapshot().keys.first { $0.contains(".rmp-create-") }
    )
    let stagingName = try #require(
      residue.split(separator: "/").first { $0.contains(".rmp-create-") }
    )
    #expect(diagnostic?.code == .rollbackFailed)
    #expect(diagnostic?.message.contains(stagingName) == true)
  }

  @Test("staged rmdir failure is reported and EINTR is retried")
  func stagedDirectoryRemovalFailuresAreStable() throws {
    let failedFixture = try SafetyHomeFixture()
    defer { failedFixture.remove() }
    let failedDiagnostic = captureDiagnostic {
      _ = try DirectoryHandle.createOrValidate(
        path: failedFixture.containerURL.path,
        owner: failedFixture.trustedUser.userID,
        role: .container,
        preparation: DirectoryPreparation(
          apply: { _ in throw InjectedFailure() },
          removeStagedDirectory: { _, _, _ in
            errno = EPERM
            return -1
          }
        )
      )
    }
    #expect(failedDiagnostic?.code == .rollbackFailed)
    #expect(try failedFixture.snapshot().keys.contains { $0.contains(".rmp-create-") })

    let interruptedFixture = try SafetyHomeFixture()
    defer { interruptedFixture.remove() }
    let before = try interruptedFixture.snapshot()
    var removalAttempts = 0
    let interruptedDiagnostic = captureDiagnostic {
      _ = try DirectoryHandle.createOrValidate(
        path: interruptedFixture.containerURL.path,
        owner: interruptedFixture.trustedUser.userID,
        role: .container,
        preparation: DirectoryPreparation(
          apply: { _ in
            throw TestSafetyDiagnostic(
              code: .markerWriteFailed,
              message: "Injected preparation failure."
            )
          },
          removeStagedDirectory: { descriptor, name, flags in
            removalAttempts += 1
            if removalAttempts == 1 {
              errno = EINTR
              return -1
            }
            return unlinkat(descriptor, name, flags)
          }
        )
      )
    }

    #expect(interruptedDiagnostic?.code == .markerWriteFailed)
    #expect(removalAttempts == 2)
    #expect(try interruptedFixture.snapshot() == before)
  }
}

private struct InjectedFailure: Error {}
