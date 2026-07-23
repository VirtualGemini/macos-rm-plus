// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import RMPCore

public struct WorkspaceTrashClient: TrashClient {
  typealias Completion = @Sendable ([URL: URL], (any Error)?) -> Void
  typealias WorkspaceRecycle = @Sendable ([URL], @escaping Completion) -> Void

  private let workspaceRecycle: WorkspaceRecycle
  private let operationQueue: DispatchQueue

  public init() {
    workspaceRecycle = Self.recycleThroughWorkspace
    operationQueue = DispatchQueue(label: "com.macos-rm-plus.workspace-trash")
  }

  fileprivate init(workspaceRecycle: @escaping WorkspaceRecycle) {
    self.workspaceRecycle = workspaceRecycle
    operationQueue = DispatchQueue(label: "com.macos-rm-plus.workspace-trash.injected")
  }

  public func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    let sourceURL = URL(fileURLWithPath: path)
    let result = WorkspaceTrashResult(sourceURL: sourceURL)
    operationQueue.async {
      workspaceRecycle([sourceURL], result.finish)
    }
    guard let destinationURL = result.wait() else {
      throw TrashCapabilityError(code: .systemTrashFailed)
    }
    return TrashMoveReceipt(destinationPath: destinationURL.path)
  }

  private static func recycleThroughWorkspace(
    _ urls: [URL],
    _ completion: @escaping Completion
  ) {
    NSWorkspace.shared.recycle(urls, completionHandler: completion)
  }
}

func makeInjectedWorkspaceTrashClient(
  workspaceRecycle: @escaping WorkspaceTrashClient.WorkspaceRecycle
) -> any TrashClient {
  WorkspaceTrashClient(workspaceRecycle: workspaceRecycle)
}

private final class WorkspaceTrashResult: @unchecked Sendable {
  private let sourceURL: URL
  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)
  private var destinationURL: URL?

  init(sourceURL: URL) {
    self.sourceURL = sourceURL
  }

  func finish(newURLs: [URL: URL], error _: (any Error)?) {
    // NSWorkspace reports per-item success through this mapping; raw NSError never leaves
    // RMPPlatform.
    lock.lock()
    destinationURL = newURLs[sourceURL]
    lock.unlock()
    semaphore.signal()
  }

  func wait() -> URL? {
    semaphore.wait()
    lock.lock()
    defer { lock.unlock() }
    return destinationURL
  }
}
