// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import RMPCore

public struct FoundationTrashPlanningFileSystem: TrashPlanningFileSystem {
  public let currentDirectoryPath: String
  public let homeDirectoryPath: String

  public init(fileManager: FileManager = .default) {
    currentDirectoryPath = fileManager.currentDirectoryPath
    homeDirectoryPath = fileManager.homeDirectoryForCurrentUser.path
  }

  public func inspectEntry(at path: String) -> FileSystemEntryInspection {
    var metadata = stat()
    let result = path.withCString { pointer in
      lstat(pointer, &metadata)
    }

    guard result == 0 else {
      if errno == ENOENT || errno == ENOTDIR {
        return .missing
      }
      return .inaccessible
    }

    return .entry(
      FileSystemEntry(
        kind: entryKind(path: path, mode: metadata.st_mode),
        identity: identity(metadata)
      )
    )
  }

  public func directoryIdentity(at path: String) -> FileSystemIdentity? {
    var metadata = stat()
    let result = path.withCString { pointer in
      fstatat(AT_FDCWD, pointer, &metadata, 0)
    }
    guard result == 0 else {
      return nil
    }
    return identity(metadata)
  }

  private func entryKind(path: String, mode: mode_t) -> TrashInputKind {
    switch mode & S_IFMT {
    case S_IFREG:
      return .file
    case S_IFDIR:
      return .directory
    case S_IFLNK:
      return symbolicLinkKind(path: path)
    default:
      return .other
    }
  }

  private func symbolicLinkKind(path: String) -> TrashInputKind {
    var destinationMetadata = stat()
    let result = path.withCString { pointer in
      fstatat(AT_FDCWD, pointer, &destinationMetadata, 0)
    }
    if result == 0 || (errno != ENOENT && errno != ENOTDIR) {
      return .symbolicLink
    }
    return .brokenSymbolicLink
  }

  private func identity(_ metadata: stat) -> FileSystemIdentity {
    FileSystemIdentity(
      device: UInt64(truncatingIfNeeded: metadata.st_dev),
      inode: UInt64(truncatingIfNeeded: metadata.st_ino)
    )
  }
}
