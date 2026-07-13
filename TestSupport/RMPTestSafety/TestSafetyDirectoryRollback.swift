// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

func createStagedDirectory(
  parentDescriptor: Int32,
  role: TestSafetyDirectoryRole
) throws -> String {
  let stagingName = ".rmp-create-\(UUID().uuidString.lowercased())"
  guard mkdirat(parentDescriptor, stagingName, 0o700) == 0 else {
    throw posixDiagnostic(
      code: .directoryCreateFailed,
      operation: "create a staged \(role.rawValue) directory"
    )
  }
  return stagingName
}

struct StagedDirectoryRollback {
  let parentDescriptor: Int32
  let stagingName: String
  let role: TestSafetyDirectoryRole
}

func rollbackStagedDirectory(
  _ rollback: StagedDirectoryRollback,
  stagedHandle: DirectoryHandle?,
  preparation: DirectoryPreparation,
  originalError: Error
) throws -> Never {
  var rollbackFailed = false
  if let stagedHandle {
    do {
      try preparation.rollback(stagedHandle)
    } catch {
      rollbackFailed = true
    }
  }
  do {
    try removeEntryIfPresent(
      parentDescriptor: rollback.parentDescriptor,
      name: rollback.stagingName,
      flags: AT_REMOVEDIR,
      operation: "remove a staged \(rollback.role.rawValue) directory",
      remove: preparation.removeStagedDirectory
    )
  } catch {
    rollbackFailed = true
  }
  if rollbackFailed {
    throw TestSafetyDiagnostic(
      code: .rollbackFailed,
      message:
        "Unable to complete rollback; filesystem residue may remain at entry "
        + "\(rollback.stagingName)."
    )
  }
  throw originalError
}
