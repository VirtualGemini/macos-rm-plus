// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@testable import rmp_test

@Suite("Test Safety Context failure matrix", .serialized)
struct TestSafetyFailureMatrixTests {
  @Test(
    "pre-capability filesystem failures preserve the hierarchy and skip downstream work",
    arguments: PreCapabilityFailureCase.allCases
  )
  func preCapabilityFailuresSkipDownstream(testCase: PreCapabilityFailureCase) throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let before = try fixture.snapshot()
    var downstreamInvocationCount = 0

    let result = TestSafetyDriver.run(
      arguments: ["--test-run-id", UUID().uuidString.lowercased(), "fixture"],
      runtime: .testing(executableName: "rmp-test", trustedUser: fixture.trustedUser),
      establishContext: { _, _, _ in
        throw TestSafetyDiagnostic(
          code: testCase.code,
          message: "Injected pre-capability failure."
        )
      },
      operation: { _, _ in
        downstreamInvocationCount += 1
        return 0
      }
    )

    #expect(result.diagnostic?.code == testCase.code)
    #expect(try fixture.snapshot() == before)
    #expect(downstreamInvocationCount == 0)
  }

  @Test("directory descriptor failures map to stable diagnostics")
  func directoryDescriptorFailuresAreStable() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    try fixture.createDirectory(at: fixture.containerURL, permissions: 0o700)
    var status = stat()
    try #require(lstat(fixture.containerURL.path, &status) == 0)
    let expectation = DirectoryExpectation(
      status: status,
      owner: fixture.trustedUser.userID,
      role: .container
    )

    let openDiagnostic = captureDiagnostic {
      _ = try DirectoryHandle.finishOpening(-1, expectation: expectation)
    }

    let descriptor = open(fixture.containerURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    try #require(descriptor >= 0)
    let identityDiagnostic = captureDiagnostic {
      _ = try DirectoryHandle.finishOpening(
        descriptor,
        expectation: expectation,
        identify: { _, _ in
          errno = EIO
          return -1
        }
      )
    }

    #expect(openDiagnostic?.code == .directoryOpenFailed)
    #expect(identityDiagnostic?.code == .directoryIdentityUnavailable)
  }

  @Test("directory enumeration failure maps to a stable diagnostic")
  func directoryReadFailureIsStable() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let runDirectory = try DirectoryHandle.createOrValidate(
      path: context.runDirectoryURL.path,
      owner: fixture.trustedUser.userID,
      role: .run
    ).handle
    let before = try fixture.snapshot()

    let diagnostic = captureDiagnostic {
      _ = try runDirectory.entryNames(duplicate: { _ in
        errno = EMFILE
        return -1
      })
    }

    #expect(diagnostic?.code == .directoryReadFailed)
    #expect(try fixture.snapshot() == before)
  }

  @Test("marker descriptor failures map to stable diagnostics without changing the marker")
  func markerDescriptorFailuresAreStable() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let runDirectory = try DirectoryHandle.createOrValidate(
      path: context.runDirectoryURL.path,
      owner: fixture.trustedUser.userID,
      role: .run
    ).handle
    let before = try fixture.snapshot()
    let expected = try decodeMarker(at: context.runMarkerURL)

    let identityDiagnostic = captureDiagnostic {
      try validateExistingMarker(
        parent: runDirectory,
        name: ".rmp-test-run",
        expected: expected,
        owner: fixture.trustedUser.userID,
        operations: .failingIdentity
      )
    }
    let readDiagnostic = captureDiagnostic {
      try validateExistingMarker(
        parent: runDirectory,
        name: ".rmp-test-run",
        expected: expected,
        owner: fixture.trustedUser.userID,
        operations: .failingRead
      )
    }

    #expect(identityDiagnostic?.code == .markerIdentityMismatch)
    #expect(readDiagnostic?.code == .markerReadFailed)
    #expect(try fixture.snapshot() == before)
  }

  @Test("marker create, open, and write failures map to stable diagnostics")
  func markerMutationFailuresAreStable() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    try fixture.createDirectory(at: fixture.containerURL, permissions: 0o700)
    let container = try DirectoryHandle.createOrValidate(
      path: fixture.containerURL.path,
      owner: fixture.trustedUser.userID,
      role: .container
    ).handle
    let marker = TestSafetyMarker(role: .container, directoryIdentity: container.identity)

    let createDiagnostic = captureDiagnostic {
      try createMarkerExclusive(
        parent: container,
        name: ".rmp-test-container",
        marker: marker,
        operations: .failingCreate
      )
    }
    try createMarkerExclusive(parent: container, name: ".rmp-test-container", marker: marker)
    let before = try fixture.snapshot()
    let openDiagnostic = captureDiagnostic {
      try validateExistingMarker(
        parent: container,
        name: ".rmp-test-container",
        expected: marker,
        owner: fixture.trustedUser.userID,
        operations: .failingOpen
      )
    }
    let writeDiagnostic = captureDiagnostic {
      try createMarkerExclusive(
        parent: container,
        name: ".incomplete-marker",
        marker: marker,
        operations: .failingWrite
      )
    }

    #expect(createDiagnostic?.code == .markerCreateFailed)
    #expect(openDiagnostic?.code == .markerOpenFailed)
    #expect(writeDiagnostic?.code == .markerWriteFailed)
    #expect(try fixture.snapshot() == before)
  }
}

enum PreCapabilityFailureCase: CaseIterable, CustomTestStringConvertible {
  case directoryIdentityUnavailable
  case directoryOpenFailed
  case markerCreateFailed
  case markerIdentityMismatch
  case markerOpenFailed
  case markerReadFailed
  case markerWriteFailed

  var testDescription: String { code.rawValue }

  var code: TestSafetyDiagnosticCode {
    switch self {
    case .directoryIdentityUnavailable: .directoryIdentityUnavailable
    case .directoryOpenFailed: .directoryOpenFailed
    case .markerCreateFailed: .markerCreateFailed
    case .markerIdentityMismatch: .markerIdentityMismatch
    case .markerOpenFailed: .markerOpenFailed
    case .markerReadFailed: .markerReadFailed
    case .markerWriteFailed: .markerWriteFailed
    }
  }
}

extension MarkerFileOperations {
  fileprivate static let failingCreate = replacing(create: { _, _ in
    errno = EACCES
    return -1
  })

  fileprivate static let failingOpen = replacing(open: { _, _ in
    errno = EMFILE
    return -1
  })

  fileprivate static let failingIdentity = replacing(identify: { _, _ in
    errno = EIO
    return -1
  })

  fileprivate static let failingRead = replacing(read: { _, _, _ in
    errno = EIO
    return -1
  })

  fileprivate static let failingWrite = replacing(write: { _, _, _ in
    errno = EIO
    return -1
  })

  private static func replacing(
    create: (@Sendable (Int32, String) -> Int32)? = nil,
    open: (@Sendable (Int32, String) -> Int32)? = nil,
    identify: (@Sendable (Int32, UnsafeMutablePointer<stat>) -> Int32)? = nil,
    read: (@Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int)? = nil,
    write: (@Sendable (Int32, UnsafeRawPointer, Int) -> Int)? = nil
  ) -> MarkerFileOperations {
    MarkerFileOperations(
      create: create ?? system.create,
      open: open ?? system.open,
      identify: identify ?? system.identify,
      read: read ?? system.read,
      write: write ?? system.write
    )
  }
}
