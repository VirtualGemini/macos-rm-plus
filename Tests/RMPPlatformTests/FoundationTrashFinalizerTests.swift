// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@testable import rmp_test

@Suite("Foundation Trash finalizer", .serialized)
struct FoundationTrashFinalizerTests {
  @Test("trashes, restores, verifies, and removes one owned symbolic-link finalizer")
  func removesOnlyTheVerifiedFinalizer() throws {
    let harness = try FoundationFinalizerHarness()
    defer { harness.remove() }
    let finalizer = harness.makeFinalizer()

    let evidence = try finalizer.finalize(suffix: "foundation-finalizer")

    #expect(evidence.sourceURL.lastPathComponent.hasSuffix("foundation-finalizer"))
    #expect(evidence.trashURL.lastPathComponent == evidence.sourceURL.lastPathComponent)
    #expect(!entryExists(at: evidence.sourceURL))
    #expect(!entryExists(at: evidence.trashURL))
    #expect(try FileManager.default.contentsOfDirectory(atPath: harness.trashURL.path).isEmpty)
  }

  @Test("leaves the exact finalizer in Trash when restore fails")
  func leavesTrashEvidenceOnRestoreFailure() throws {
    let harness = try FoundationFinalizerHarness()
    defer { harness.remove() }
    let operations = FoundationTrashFinalizerOperations(
      restoreItem: { _, _ in throw InjectedFinalizerError() },
      resourceIdentifier: testSafetyResourceIdentifier,
      removeRestoredLink: { _, _, _ in
        Issue.record("cleanup must not run after a restore failure")
      }
    )
    let finalizer = harness.makeFinalizer(operations: operations)

    let diagnostic = captureDiagnostic {
      _ = try finalizer.finalize(suffix: "restore-failure-finalizer")
    }
    let expectedTrashURL = harness.trashURL.appendingPathComponent(
      try harness.context.fixtureName(suffix: "restore-failure-finalizer")
    )

    #expect(diagnostic?.code == .finalizerRestoreFailed)
    #expect(entryExists(at: expectedTrashURL))
  }

  @Test("does not restore over a source path occupied after Trash")
  func rejectsOccupiedSourceBeforeRestore() throws {
    let harness = try FoundationFinalizerHarness(occupySourceAfterTrash: true)
    defer { harness.remove() }
    var restoreCalls = 0
    let operations = FoundationTrashFinalizerOperations(
      restoreItem: { _, _ in restoreCalls += 1 },
      resourceIdentifier: testSafetyResourceIdentifier,
      removeRestoredLink: { _, _, _ in
        Issue.record("cleanup must not run for an occupied source")
      }
    )
    let finalizer = harness.makeFinalizer(operations: operations)

    let diagnostic = captureDiagnostic {
      _ = try finalizer.finalize(suffix: "occupied-source-finalizer")
    }

    #expect(diagnostic?.code == .finalizerSourceOccupied)
    #expect(restoreCalls == 0)
  }

  @Test("does not remove a restored entry whose filesystem identity changed")
  func rejectsChangedRestoredIdentity() throws {
    let harness = try FoundationFinalizerHarness()
    defer { harness.remove() }
    var cleanupCalls = 0
    let operations = FoundationTrashFinalizerOperations(
      restoreItem: { trashURL, sourceURL in
        let displacedURL = sourceURL.appendingPathExtension("displaced")
        try FileManager.default.moveItem(at: trashURL, to: displacedURL)
        try FileManager.default.createSymbolicLink(
          at: sourceURL,
          withDestinationURL: URL(fileURLWithPath: "replacement-target")
        )
      },
      resourceIdentifier: testSafetyResourceIdentifier,
      removeRestoredLink: { _, _, _ in cleanupCalls += 1 }
    )
    let finalizer = harness.makeFinalizer(operations: operations)

    let diagnostic = captureDiagnostic {
      _ = try finalizer.finalize(suffix: "changed-identity-finalizer")
    }

    #expect(diagnostic?.code == .finalizerEvidenceMismatch)
    #expect(cleanupCalls == 0)
  }
}

private struct FoundationFinalizerHarness {
  let fixture: SafetyHomeFixture
  let context: TestSafetyContext
  let trashURL: URL
  let trashClient: WhitelistedTrashClient

  init(occupySourceAfterTrash: Bool = false) throws {
    fixture = try SafetyHomeFixture()
    context = try fixture.establishContext()
    trashURL = fixture.homeURL.appendingPathComponent("Trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: false)
    let returnedTrashDirectory = trashURL
    trashClient = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: TrashAuthorizationOperations(
        inspectVolume: { _ in
          TrashVolumeInspection(isLocal: true, isMountPoint: false, isFileProviderRoot: false)
        },
        deviceMatchesRun: { $0 == $1 },
        resourceIdentifier: testSafetyResourceIdentifier
      ),
      systemTrash: { sourceURL in
        let returnedURL = returnedTrashDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
        if occupySourceAfterTrash {
          try FileManager.default.createSymbolicLink(
            at: sourceURL,
            withDestinationURL: URL(fileURLWithPath: "occupied-target")
          )
        }
        return returnedURL
      }
    )
  }

  func makeFinalizer(
    operations: FoundationTrashFinalizerOperations = .system
  ) -> FoundationTrashFinalizer {
    FoundationTrashFinalizer(
      context: context,
      trashClient: trashClient,
      operations: operations
    )
  }

  func remove() {
    fixture.remove()
  }
}

private struct InjectedFinalizerError: Error {}

private func entryExists(at url: URL) -> Bool {
  var status = stat()
  return lstat(url.path, &status) == 0
}
