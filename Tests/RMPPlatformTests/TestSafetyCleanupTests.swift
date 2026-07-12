// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@_spi(RMPTestingEntrypoint) @testable import RMPTestKit

@Suite("Test Safety Context cleanup", .serialized)
struct TestSafetyCleanupTests {
  @Test("cleanup refuses a replaced Run Directory identity")
  func cleanupRejectsReplacedRunDirectory() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let movedURL = context.runDirectoryURL.appendingPathExtension("moved")
    try FileManager.default.moveItem(at: context.runDirectoryURL, to: movedURL)
    try fixture.createDirectory(at: context.runDirectoryURL, permissions: 0o700)

    let diagnostic = captureDiagnostic { try context.cleanupRunDirectory() }

    #expect(diagnostic?.code == .directoryIdentityMismatch)
    #expect(FileManager.default.fileExists(atPath: movedURL.path))
    #expect(FileManager.default.fileExists(atPath: context.runDirectoryURL.path))
  }

  @Test("cleanup refuses a mismatched run marker and preserves the Run Directory")
  func cleanupRejectsMismatchedRunMarker() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    try changeRunID(in: context.runMarkerURL)

    let diagnostic = captureDiagnostic { try context.cleanupRunDirectory() }

    #expect(diagnostic?.code == .markerInvalid)
    #expect(FileManager.default.fileExists(atPath: context.runMarkerURL.path))
    #expect(FileManager.default.fileExists(atPath: context.runDirectoryURL.path))
  }

  @Test("cleanup removes only an empty revalidated Run Directory")
  func cleanupRemovesOnlyEmptyRunDirectory() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()

    try context.cleanupRunDirectory()

    #expect(!FileManager.default.fileExists(atPath: context.runDirectoryURL.path))
    #expect(FileManager.default.fileExists(atPath: fixture.containerURL.path))
    #expect(FileManager.default.fileExists(atPath: fixture.authorizedRootURL.path))
    #expect(FileManager.default.fileExists(atPath: fixture.containerMarkerURL.path))
    #expect(FileManager.default.fileExists(atPath: fixture.rootMarkerURL.path))
  }

  @Test("cleanup preserves a non-empty Run Directory and its marker")
  func cleanupPreservesNonEmptyRunDirectory() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let fixtureURL = context.runDirectoryURL.appendingPathComponent("fixture", isDirectory: false)
    try Data("fixture".utf8).write(to: fixtureURL)

    let diagnostic = captureDiagnostic { try context.cleanupRunDirectory() }

    #expect(diagnostic?.code == .runDirectoryNotEmpty)
    #expect(FileManager.default.fileExists(atPath: fixtureURL.path))
    #expect(FileManager.default.fileExists(atPath: context.runMarkerURL.path))
    #expect(FileManager.default.fileExists(atPath: context.runDirectoryURL.path))
  }
}
