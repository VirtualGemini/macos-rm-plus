// SPDX-License-Identifier: Apache-2.0

import Foundation
import RMPCore

public struct FoundationTrashClient: TrashClient {
  typealias SystemTrash = @Sendable (URL) throws -> URL

  private let systemTrash: SystemTrash

  public init() {
    systemTrash = Self.moveThroughSystemTrash
  }

  init(systemTrash: @escaping SystemTrash) {
    self.systemTrash = systemTrash
  }

  public func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    do {
      let resultingURL = try systemTrash(URL(fileURLWithPath: path))
      return TrashMoveReceipt(destinationPath: resultingURL.path)
    } catch {
      throw TrashCapabilityError(code: .systemTrashFailed)
    }
  }

  private static func moveThroughSystemTrash(_ sourceURL: URL) throws -> URL {
    var resultingURL: NSURL?
    try FileManager.default.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
    guard let resultingURL else {
      throw TrashCapabilityError(code: .systemTrashFailed)
    }
    return resultingURL as URL
  }
}
