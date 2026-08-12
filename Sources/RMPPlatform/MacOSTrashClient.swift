// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import RMPCore

public struct MacOSTrashClient: TrashClient {
  typealias RestoreItem = @Sendable (_ trashURL: URL, _ sourceURL: URL) throws -> Void
  typealias SystemTrash = @Sendable (URL) throws -> URL
  typealias FinalizerName = @Sendable () -> String

  private var finderTrash: SystemTrash
  private var foundationTrash: SystemTrash
  private var restoreItem: RestoreItem
  private var finalizerName: FinalizerName

  public init() {
    let finderClient = FinderTrashClient()
    finderTrash = { sourceURL in
      let receipt = try finderClient.trashItem(atPath: sourceURL.path)
      return URL(fileURLWithPath: receipt.destinationPath)
    }
    foundationTrash = liveFoundationTrash
    restoreItem = liveRestoreItem
    finalizerName = liveFinalizerName
  }

  fileprivate init(
    finderTrash: @escaping SystemTrash,
    foundationTrash: @escaping SystemTrash,
    restoreItem: @escaping RestoreItem,
    finalizerName: @escaping FinalizerName
  ) {
    self.init()
    self.finderTrash = finderTrash
    self.foundationTrash = foundationTrash
    self.restoreItem = restoreItem
    self.finalizerName = finalizerName
  }

  public func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    let sourceURL = URL(fileURLWithPath: path)
    do {
      if let identity = try symbolicLinkIdentity(at: sourceURL) {
        return try trashSymbolicLink(sourceURL, identity: identity)
      }
      let destinationURL = try finderTrash(sourceURL)
      return TrashMoveReceipt(destinationPath: destinationURL.path)
    } catch let error as TrashCapabilityError {
      throw error
    } catch {
      throw TrashCapabilityError(code: .systemTrashFailed)
    }
  }

  private func trashSymbolicLink(
    _ sourceURL: URL,
    identity: PlatformFileIdentity
  ) throws -> TrashMoveReceipt {
    try runFinalizerPreflight(beside: sourceURL)
    let finalizers = try prepareFinalizers(beside: sourceURL, count: 2)
    let targetTrashURL: URL
    do {
      try verifySymbolicLink(identity: identity, at: sourceURL)
      targetTrashURL = try foundationTrash(sourceURL)
    } catch {
      for finalizer in finalizers {
        try? removeVerifiedFinalizer(finalizer)
      }
      throw error
    }
    let targetReceiptIsValid = isSymbolicLink(identity: identity, at: targetTrashURL)
    let warnings = activatePutBack(using: finalizers)
    guard targetReceiptIsValid else { throw FinalizerFailure.identityMismatch }
    return TrashMoveReceipt(destinationPath: targetTrashURL.path, warnings: warnings)
  }

  private func activatePutBack(using finalizers: [PreparedFinalizer]) -> [TrashMoveWarning] {
    for (index, finalizer) in finalizers.enumerated() {
      let finalizerTrashURL: URL
      do {
        finalizerTrashURL = try foundationTrash(finalizer.sourceURL)
      } catch {
        do {
          try removeVerifiedFinalizer(finalizer)
          continue
        } catch {
          for unusedFinalizer in finalizers.dropFirst(index + 1) {
            try? removeVerifiedFinalizer(unusedFinalizer)
          }
          return [TrashMoveWarning(code: .finalizerStateUncertain)]
        }
      }

      do {
        try verifyFinalizer(finalizer, at: finalizerTrashURL)
        try restoreItem(finalizerTrashURL, finalizer.sourceURL)
        try removeVerifiedFinalizer(finalizer)
        for unusedFinalizer in finalizers.dropFirst(index + 1) {
          try removeVerifiedFinalizer(unusedFinalizer)
        }
        return []
      } catch {
        try? removeVerifiedFinalizer(finalizer)
        for unusedFinalizer in finalizers.dropFirst(index + 1) {
          try? removeVerifiedFinalizer(unusedFinalizer)
        }
        return [TrashMoveWarning(code: .finalizerCleanupFailed)]
      }
    }
    return [TrashMoveWarning(code: .symlinkPutBackNotGuaranteed)]
  }

  private func runFinalizerPreflight(beside sourceURL: URL) throws {
    let finalizer = try prepareFinalizer(beside: sourceURL)
    do {
      let trashURL = try foundationTrash(finalizer.sourceURL)
      try verifyFinalizer(finalizer, at: trashURL)
      try restoreItem(trashURL, finalizer.sourceURL)
      try removeVerifiedFinalizer(finalizer)
    } catch {
      try? removeVerifiedFinalizer(finalizer)
      throw error
    }
  }

  private func prepareFinalizer(beside sourceURL: URL) throws -> PreparedFinalizer {
    let parentURL = sourceURL.deletingLastPathComponent()
    let name = finalizerName()
    guard
      !name.isEmpty,
      name != ".",
      name != "..",
      !name.contains("/"),
      !name.contains("\0")
    else {
      throw FinalizerFailure.createFailed
    }
    let descriptor = open(parentURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw FinalizerFailure.parentUnavailable }
    defer { close(descriptor) }
    guard symlinkat("\(name)-absent", descriptor, name) == 0 else {
      throw FinalizerFailure.createFailed
    }

    var status = stat()
    guard
      fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0,
      status.st_mode & S_IFMT == S_IFLNK
    else {
      _ = unlinkat(descriptor, name, 0)
      throw FinalizerFailure.identityMismatch
    }
    return PreparedFinalizer(
      sourceURL: parentURL.appendingPathComponent(name),
      name: name,
      identity: PlatformFileIdentity(status: status)
    )
  }

  private func prepareFinalizers(beside sourceURL: URL, count: Int) throws -> [PreparedFinalizer] {
    var finalizers: [PreparedFinalizer] = []
    do {
      for _ in 0..<count {
        finalizers.append(try prepareFinalizer(beside: sourceURL))
      }
      return finalizers
    } catch {
      for finalizer in finalizers {
        try? removeVerifiedFinalizer(finalizer)
      }
      throw error
    }
  }

  private func removeVerifiedFinalizer(_ finalizer: PreparedFinalizer) throws {
    let parentURL = finalizer.sourceURL.deletingLastPathComponent()
    let descriptor = open(parentURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw FinalizerFailure.parentUnavailable }
    defer { close(descriptor) }
    var status = stat()
    guard
      fstatat(descriptor, finalizer.name, &status, AT_SYMLINK_NOFOLLOW) == 0,
      status.st_mode & S_IFMT == S_IFLNK,
      PlatformFileIdentity(status: status) == finalizer.identity
    else {
      throw FinalizerFailure.identityMismatch
    }
    guard unlinkat(descriptor, finalizer.name, 0) == 0 else {
      throw FinalizerFailure.cleanupFailed
    }
  }

  private func verifyFinalizer(_ finalizer: PreparedFinalizer, at url: URL) throws {
    try verifySymbolicLink(identity: finalizer.identity, at: url)
  }

  private func symbolicLinkIdentity(at url: URL) throws -> PlatformFileIdentity? {
    var status = stat()
    guard lstat(url.path, &status) == 0 else {
      throw FinalizerFailure.sourceUnavailable
    }
    guard status.st_mode & S_IFMT == S_IFLNK else { return nil }
    return PlatformFileIdentity(status: status)
  }

  private func verifySymbolicLink(identity: PlatformFileIdentity, at url: URL) throws {
    guard isSymbolicLink(identity: identity, at: url) else {
      throw FinalizerFailure.identityMismatch
    }
  }

  private func isSymbolicLink(identity: PlatformFileIdentity, at url: URL) -> Bool {
    var status = stat()
    return
      lstat(url.path, &status) == 0
      && status.st_mode & S_IFMT == S_IFLNK
      && PlatformFileIdentity(status: status) == identity
  }
}

package func makeInjectedMacOSTrashClient(
  finderTrash: @escaping @Sendable (URL) throws -> URL,
  foundationTrash: @escaping @Sendable (URL) throws -> URL,
  restoreItem: @escaping @Sendable (URL, URL) throws -> Void = liveRestoreItem,
  finalizerName: @escaping @Sendable () -> String = liveFinalizerName
) -> any TrashClient {
  MacOSTrashClient(
    finderTrash: finderTrash,
    foundationTrash: foundationTrash,
    restoreItem: restoreItem,
    finalizerName: finalizerName
  )
}

private struct PreparedFinalizer {
  let sourceURL: URL
  let name: String
  let identity: PlatformFileIdentity
}

private struct PlatformFileIdentity: Equatable {
  let device: UInt64
  let inode: UInt64

  init(status: stat) {
    device = UInt64(truncatingIfNeeded: status.st_dev)
    inode = UInt64(truncatingIfNeeded: status.st_ino)
  }
}

private enum FinalizerFailure: Error {
  case cleanupFailed
  case createFailed
  case identityMismatch
  case parentUnavailable
  case sourceUnavailable
}

private func liveFoundationTrash(_ sourceURL: URL) throws -> URL {
  var resultingURL: NSURL?
  try FileManager.default.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
  guard let resultingURL else { throw FinalizerFailure.identityMismatch }
  return resultingURL as URL
}

private func liveRestoreItem(_ trashURL: URL, _ sourceURL: URL) throws {
  try FileManager.default.moveItem(at: trashURL, to: sourceURL)
}

private func liveFinalizerName() -> String {
  ".rmp-finalizer-\(UUID().uuidString.lowercased())"
}
