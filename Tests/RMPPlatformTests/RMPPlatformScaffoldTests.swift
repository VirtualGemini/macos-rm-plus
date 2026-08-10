// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import RMPTestKit
import Testing

@testable import RMPPlatform

@Suite("RMPPlatform scaffold", .serialized)
struct RMPPlatformScaffoldTests {
  @Test("RMPPlatform and RMPTestKit targets are available")
  func platformTargetsAreAvailable() {
    #expect(RMPPlatformModule.name == "RMPPlatform")
    #expect(RMPTestKitModule.name == "RMPTestKit")
  }

  @Test("Foundation planning adapter performs read-only top-level inspection")
  func foundationPlanningAdapterInspectsTopLevelEntries() {
    let fileSystem = FoundationTrashPlanningFileSystem()
    let sourcePath = #filePath
    let testsDirectory = URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path

    guard case let .entry(sourceEntry) = fileSystem.inspectEntry(at: sourcePath) else {
      Issue.record("Expected the test source to be inspectable")
      return
    }
    guard case let .entry(directoryEntry) = fileSystem.inspectEntry(at: testsDirectory) else {
      Issue.record("Expected the test directory to be inspectable")
      return
    }

    #expect(sourceEntry.kind == .file)
    #expect(directoryEntry.kind == .directory)
    #expect(fileSystem.directoryIdentity(at: testsDirectory) == directoryEntry.identity)
    #expect(fileSystem.inspectEntry(at: sourcePath + ".missing") == .missing)
  }

  @Test("Foundation planning classifies links without following the top-level entry")
  func foundationPlanningAdapterClassifiesSymbolicLinks() throws {
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "rmp-planning-links-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: rootURL) }
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
    let targetURL = rootURL.appendingPathComponent("target")
    let linkURL = rootURL.appendingPathComponent("link")
    let brokenLinkURL = rootURL.appendingPathComponent("broken-link")
    try Data("target\n".utf8).write(to: targetURL)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
    try FileManager.default.createSymbolicLink(
      at: brokenLinkURL,
      withDestinationURL: rootURL.appendingPathComponent("missing")
    )
    let fileSystem = FoundationTrashPlanningFileSystem()

    guard case let .entry(linkEntry) = fileSystem.inspectEntry(at: linkURL.path) else {
      Issue.record("Expected the resolving symbolic link to be inspectable")
      return
    }
    guard case let .entry(brokenLinkEntry) = fileSystem.inspectEntry(at: brokenLinkURL.path) else {
      Issue.record("Expected the broken symbolic link to be inspectable")
      return
    }

    #expect(linkEntry.kind == .symbolicLink)
    #expect(brokenLinkEntry.kind == .brokenSymbolicLink)
    #expect(linkEntry.identity != brokenLinkEntry.identity)
  }

  @Test("Foundation planning classifies special entries and missing directory identities")
  func foundationPlanningAdapterClassifiesSpecialAndMissingEntries() throws {
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "rmp-planning-special-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: rootURL) }
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
    let fifoURL = rootURL.appendingPathComponent("fifo")
    guard mkfifo(fifoURL.path, 0o600) == 0 else {
      Issue.record("Expected the FIFO fixture to be created")
      return
    }
    let fileSystem = FoundationTrashPlanningFileSystem()

    guard case let .entry(entry) = fileSystem.inspectEntry(at: fifoURL.path) else {
      Issue.record("Expected the FIFO to be inspectable")
      return
    }

    #expect(entry.kind == .other)
    #expect(fileSystem.directoryIdentity(at: rootURL.appendingPathComponent("missing").path) == nil)
  }
}
