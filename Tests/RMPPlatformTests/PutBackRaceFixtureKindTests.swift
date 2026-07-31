// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@testable import rmp_test

@Suite("Put Back race platform fixture set", .serialized)
struct PutBackRaceFixtureKindTests {
  @Test("creates a directory fixture with the run prefix and 0700")
  func createsDirectoryFixture() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let originalMask = umask(0o777)
    defer { umask(originalMask) }

    let url = try context.createFixtureDirectory(suffix: "directory")

    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    #expect(fileMode(at: url) == 0o700)
    #expect(
      url.lastPathComponent == "rmp-test-\(context.runID.uuidString.lowercased())-directory"
    )
  }

  @Test("creates a symbolic link without following or resolving it")
  func createsSymbolicLinkFixture() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try context.createFixtureFile(suffix: "target", contents: Data("t".utf8))

    let url = try context.createFixtureSymbolicLink(
      suffix: "symbolic-link",
      target: target.lastPathComponent
    )

    let destination = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    #expect(destination == target.lastPathComponent)
    #expect(try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
  }

  @Test("creates a broken symbolic link that resolves to nothing")
  func createsBrokenSymbolicLinkFixture() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()

    let url = try context.createFixtureSymbolicLink(suffix: "broken", target: "absent-target")

    // The link itself exists; what it points at does not.
    var status = stat()
    #expect(lstat(url.path, &status) == 0)
    #expect(stat(url.path, &status) != 0)
  }

  @Test("refuses to overwrite an existing entry for every fixture kind")
  func refusesToOverwriteExistingEntries() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    _ = try context.createFixtureDirectory(suffix: "dup-dir")
    _ = try context.createFixtureSymbolicLink(suffix: "dup-link", target: "somewhere")
    _ = try context.createFixtureFile(suffix: "dup-file", contents: Data())

    #expect(
      captureDiagnostic { _ = try context.createFixtureDirectory(suffix: "dup-dir") }?.code
        == .fixtureCreateFailed)
    #expect(
      captureDiagnostic {
        _ = try context.createFixtureSymbolicLink(suffix: "dup-link", target: "elsewhere")
      }?.code == .fixtureCreateFailed)
    #expect(
      captureDiagnostic {
        _ = try context.createFixtureFile(suffix: "dup-file", contents: Data())
      }?.code == .fixtureCreateFailed)
  }

  @Test("rejects fixture names that are not a single path component")
  func rejectsInvalidFixtureNames() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()

    for suffix in ["", "with/slash"] {
      #expect(
        captureDiagnostic { _ = try context.fixtureName(suffix: suffix) }?.code
          == .fixtureNameInvalid)
    }
    #expect(
      captureDiagnostic {
        _ = try context.createFixtureSymbolicLink(suffix: "link", target: "")
      }?.code == .fixtureNameInvalid)
  }

  @Test("keeps quotes and newlines in fixture names so the Apple Event boundary is exercised")
  func keepsAwkwardCharactersInNames() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()

    let quoted = PutBackRaceFixtureKind.quotedName.suffix(cycle: "c01")
    let newline = PutBackRaceFixtureKind.newlineName.suffix(cycle: "c01")
    #expect(quoted.contains("\""))
    #expect(quoted.contains("'"))
    #expect(newline.contains("\n"))

    // Such names must still be creatable through the authorized path.
    let url = try context.createFixtureFile(suffix: quoted, contents: Data("q".utf8))
    #expect(url.lastPathComponent.contains("\""))
    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test("gives every platform fixture kind a distinct suffix")
  func everyKindHasDistinctSuffix() {
    let suffixes = PutBackRaceFixtureKind.allCases.map { $0.suffix(cycle: "c01") }
    #expect(Set(suffixes).count == PutBackRaceFixtureKind.allCases.count)
    #expect(PutBackRaceFixtureKind.allCases.count == 6)
  }
}
