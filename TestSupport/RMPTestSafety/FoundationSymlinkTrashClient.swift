// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

/// Test-only system Trash capability for measuring issue 12's symbolic-link delay threshold.
/// The production executable cannot import this target, and this adapter refuses every entry kind
/// except a final symbolic link before reaching Foundation.
struct FoundationSymlinkTrashClient {
  typealias SystemTrash = @Sendable (URL) throws -> URL

  private let systemTrash: SystemTrash

  init() {
    systemTrash = Self.liveSystemTrash
  }

  init(systemTrash: @escaping SystemTrash) {
    self.systemTrash = systemTrash
  }

  func trashItem(_ sourceURL: URL) throws -> URL {
    var status = stat()
    guard lstat(sourceURL.path, &status) == 0 else {
      throw TestSafetyDiagnostic(
        code: .trashPathInspectionFailed,
        message: "The Foundation symbolic-link Trash target could not be inspected."
      )
    }
    guard status.st_mode & S_IFMT == S_IFLNK else {
      throw TestSafetyDiagnostic(
        code: .trashSymlinkRequired,
        message: "The Foundation Trash experiment accepts only a symbolic link."
      )
    }
    return try systemTrash(sourceURL)
  }

  private static func liveSystemTrash(_ sourceURL: URL) throws -> URL {
    var resultingURL: NSURL?
    try FileManager.default.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
    guard let resultingURL else {
      throw TestSafetyDiagnostic(
        code: .trashEvidenceMismatch,
        message: "Foundation did not return the symbolic link's Trash URL."
      )
    }
    return resultingURL as URL
  }
}
