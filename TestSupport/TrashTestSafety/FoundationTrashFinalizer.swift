// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

struct FoundationTrashFinalizerEvidence: Equatable, Sendable {
  let sourceURL: URL
  let trashURL: URL
}

struct FoundationTrashFinalizerOperations {
  let restoreItem: (_ trashURL: URL, _ sourceURL: URL) throws -> Void
  let resourceIdentifier: (URL) throws -> Data?
  let removeRestoredLink:
    (_ context: TestSafetyContext, _ sourceName: String, _ expectedIdentity: FileIdentity) throws ->
      Void

  static var system: FoundationTrashFinalizerOperations {
    FoundationTrashFinalizerOperations(
      restoreItem: { trashURL, sourceURL in
        try FileManager.default.moveItem(at: trashURL, to: sourceURL)
      },
      resourceIdentifier: testSafetyResourceIdentifier,
      removeRestoredLink: removeVerifiedFinalizerLink
    )
  }
}

/// Issues one successful Foundation Trash call after the real symbolic-link deletion, then removes
/// only that owned finalizer after moving it back into the authorized Run Directory and proving its
/// original filesystem identity. This is test-only issue 12 investigation support.
final class FoundationTrashFinalizer {
  private let context: TestSafetyContext
  private let trashClient: WhitelistedTrashClient
  private let operations: FoundationTrashFinalizerOperations

  convenience init(context: TestSafetyContext) {
    self.init(
      context: context,
      trashClient: WhitelistedTrashClient(context: context, backend: .foundationSymlink),
      operations: .system
    )
  }

  init(
    context: TestSafetyContext,
    trashClient: WhitelistedTrashClient,
    operations: FoundationTrashFinalizerOperations
  ) {
    self.context = context
    self.trashClient = trashClient
    self.operations = operations
  }

  func finalize(suffix: String) throws -> FoundationTrashFinalizerEvidence {
    let prepared = try prepareFinalizer(suffix: suffix)
    let trashEvidence = try trashClient.trashItem(prepared.authorizedTarget)

    try context.revalidate()
    guard try inspectSourceEntry(name: prepared.sourceName) == nil else {
      throw finalizerDiagnostic(
        .finalizerSourceOccupied,
        "The Foundation finalizer source path became occupied after Trash."
      )
    }
    try verifyResourceIdentifier(
      at: trashEvidence.returnedURL,
      expected: trashEvidence.resourceIdentifier,
      message: "The Foundation finalizer changed in Trash before restore."
    )

    do {
      try operations.restoreItem(trashEvidence.returnedURL, prepared.sourceURL)
    } catch {
      throw finalizerDiagnostic(
        .finalizerRestoreFailed,
        "The Foundation finalizer could not be restored to the Run Directory."
      )
    }

    try context.revalidate()
    guard
      let restoredEntry = try inspectSourceEntry(name: prepared.sourceName),
      restoredEntry.isSymbolicLink,
      restoredEntry.identity == prepared.plannedEntry.identity
    else {
      throw finalizerDiagnostic(
        .finalizerEvidenceMismatch,
        "The restored Foundation finalizer does not match its planned filesystem identity."
      )
    }
    try verifyResourceIdentifier(
      at: prepared.sourceURL,
      expected: trashEvidence.resourceIdentifier,
      message: "The restored Foundation finalizer does not match the Trash evidence."
    )

    try cleanupFinalizer(prepared)

    return FoundationTrashFinalizerEvidence(
      sourceURL: prepared.sourceURL,
      trashURL: trashEvidence.returnedURL
    )
  }

  private func prepareFinalizer(suffix: String) throws -> PreparedFoundationFinalizer {
    try context.revalidate()
    let absentTarget = try context.fixtureName(suffix: "\(suffix)-absent-target")
    let sourceURL = try context.createFixtureSymbolicLink(suffix: suffix, target: absentTarget)
    let sourceName = sourceURL.lastPathComponent
    let plannedEntry = try inspectSourceEntry(name: sourceName)
    guard let plannedEntry, plannedEntry.isSymbolicLink else {
      throw finalizerDiagnostic(
        .finalizerEvidenceMismatch,
        "The Foundation finalizer was not created as the expected symbolic link."
      )
    }
    return try PreparedFoundationFinalizer(
      sourceURL: sourceURL,
      sourceName: sourceName,
      plannedEntry: plannedEntry,
      authorizedTarget: trashClient.authorizeForPlanning(targetURL: sourceURL)
    )
  }

  private func cleanupFinalizer(_ prepared: PreparedFoundationFinalizer) throws {
    do {
      try operations.removeRestoredLink(
        context,
        prepared.sourceName,
        prepared.plannedEntry.identity
      )
    } catch let diagnostic as TestSafetyDiagnostic {
      throw diagnostic
    } catch {
      throw finalizerDiagnostic(
        .finalizerCleanupFailed,
        "The restored Foundation finalizer could not be removed."
      )
    }
    guard try inspectSourceEntry(name: prepared.sourceName) == nil else {
      throw finalizerDiagnostic(
        .finalizerCleanupFailed,
        "The restored Foundation finalizer remains after cleanup."
      )
    }
  }

  private func inspectSourceEntry(name: String) throws -> FinalizerSourceEntry? {
    let descriptor = try context.duplicateRunDirectoryDescriptor()
    defer { close(descriptor) }
    var status = stat()
    if fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 {
      return FinalizerSourceEntry(
        identity: FileIdentity(status: status),
        isSymbolicLink: status.st_mode & S_IFMT == S_IFLNK
      )
    }
    guard errno == ENOENT else {
      throw finalizerDiagnostic(
        .finalizerEvidenceMismatch,
        "The Foundation finalizer source path could not be inspected."
      )
    }
    return nil
  }

  private func verifyResourceIdentifier(at url: URL, expected: Data?, message: String) throws {
    guard let expected else { return }
    let current: Data?
    do {
      current = try operations.resourceIdentifier(url)
    } catch {
      throw finalizerDiagnostic(.finalizerEvidenceMismatch, message)
    }
    guard current == expected else {
      throw finalizerDiagnostic(.finalizerEvidenceMismatch, message)
    }
  }
}

private struct FinalizerSourceEntry: Equatable {
  let identity: FileIdentity
  let isSymbolicLink: Bool
}

private struct PreparedFoundationFinalizer {
  let sourceURL: URL
  let sourceName: String
  let plannedEntry: FinalizerSourceEntry
  let authorizedTarget: AuthorizedTrashTarget
}

private func removeVerifiedFinalizerLink(
  context: TestSafetyContext,
  sourceName: String,
  expectedIdentity: FileIdentity
) throws {
  try context.revalidate()
  let descriptor = try context.duplicateRunDirectoryDescriptor()
  defer { close(descriptor) }
  var status = stat()
  guard
    fstatat(descriptor, sourceName, &status, AT_SYMLINK_NOFOLLOW) == 0,
    status.st_mode & S_IFMT == S_IFLNK,
    FileIdentity(status: status) == expectedIdentity
  else {
    throw finalizerDiagnostic(
      .finalizerEvidenceMismatch,
      "The Foundation finalizer changed immediately before cleanup."
    )
  }
  guard unlinkat(descriptor, sourceName, 0) == 0 else {
    throw finalizerDiagnostic(
      .finalizerCleanupFailed,
      "The restored Foundation finalizer could not be removed."
    )
  }
}

private func finalizerDiagnostic(
  _ code: TestSafetyDiagnosticCode,
  _ message: String
) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(code: code, message: message)
}
