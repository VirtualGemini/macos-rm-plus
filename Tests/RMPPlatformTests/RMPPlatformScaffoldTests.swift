// SPDX-License-Identifier: Apache-2.0

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
}
