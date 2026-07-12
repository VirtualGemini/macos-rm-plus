// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

final class DirectoryHandle {
  let fileDescriptor: Int32
  let identity: FileIdentity

  private init(fileDescriptor: Int32, identity: FileIdentity) {
    self.fileDescriptor = fileDescriptor
    self.identity = identity
  }

  deinit { close(fileDescriptor) }

  static func createOrValidate(
    path: String,
    owner: uid_t,
    role: TestSafetyDirectoryRole,
    preparation: DirectoryPreparation = DirectoryPreparation()
  ) throws -> DirectoryCreation {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    let parentDescriptor = open(
      url.deletingLastPathComponent().path,
      O_RDONLY | O_DIRECTORY | O_CLOEXEC
    )
    guard parentDescriptor >= 0 else {
      throw posixDiagnostic(
        code: "test-safety.directory-create-failed",
        operation: "open the parent of the \(role.rawValue) directory"
      )
    }
    defer { close(parentDescriptor) }
    return try createOrValidate(
      parentDescriptor: parentDescriptor,
      name: url.lastPathComponent,
      owner: owner,
      role: role,
      preparation: preparation
    )
  }

  static func createOrValidate(
    parent: DirectoryHandle,
    name: String,
    owner: uid_t,
    role: TestSafetyDirectoryRole,
    preparation: DirectoryPreparation = DirectoryPreparation()
  ) throws -> DirectoryCreation {
    try createOrValidate(
      parentDescriptor: parent.fileDescriptor,
      name: name,
      owner: owner,
      role: role,
      preparation: preparation
    )
  }

  static func createExclusive(
    parent: DirectoryHandle,
    name: String,
    owner: uid_t,
    preparation: DirectoryPreparation = DirectoryPreparation()
  ) throws -> DirectoryHandle {
    do {
      return try installCreatedDirectory(
        parentDescriptor: parent.fileDescriptor,
        name: name,
        owner: owner,
        role: .run,
        preparation: preparation
      )
    } catch StagedDirectoryError.destinationExists {
      throw TestSafetyDiagnostic(
        code: "test-safety.run-directory-exists",
        message: "The UUID Run Directory already exists and cannot be reused."
      )
    }
  }

  func entryNames() throws -> [String] {
    let copiedDescriptor = dup(fileDescriptor)
    guard copiedDescriptor >= 0, let directory = fdopendir(copiedDescriptor) else {
      if copiedDescriptor >= 0 { close(copiedDescriptor) }
      throw posixDiagnostic(
        code: "test-safety.directory-read-failed",
        operation: "read the Run Directory"
      )
    }
    defer { closedir(directory) }

    var names: [String] = []
    errno = 0
    while let entry = readdir(directory) {
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
          String(cString: $0)
        }
      }
      if name != ".", name != ".." { names.append(name) }
      errno = 0
    }
    guard errno == 0 else {
      throw posixDiagnostic(
        code: "test-safety.directory-read-failed",
        operation: "read the Run Directory"
      )
    }
    return names.sorted()
  }

  private static func openValidated(
    path: String,
    owner: uid_t,
    role: TestSafetyDirectoryRole
  ) throws -> DirectoryHandle {
    var status = stat()
    guard lstat(path, &status) == 0 else { throw missingDirectory(role) }
    try validateDirectoryStatus(status, owner: owner, role: role)
    let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    return try finishOpening(descriptor, initialStatus: status, owner: owner, role: role)
  }

  private static func createOrValidate(
    parentDescriptor: Int32,
    name: String,
    owner: uid_t,
    role: TestSafetyDirectoryRole,
    preparation: DirectoryPreparation
  ) throws -> DirectoryCreation {
    var status = stat()
    if fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 {
      return DirectoryCreation(
        handle: try openValidated(
          parentDescriptor: parentDescriptor,
          name: name,
          owner: owner,
          role: role
        ),
        created: false
      )
    }
    guard errno == ENOENT else {
      throw posixDiagnostic(
        code: "test-safety.directory-create-failed",
        operation: "inspect the \(role.rawValue) directory"
      )
    }
    do {
      return DirectoryCreation(
        handle: try installCreatedDirectory(
          parentDescriptor: parentDescriptor,
          name: name,
          owner: owner,
          role: role,
          preparation: preparation
        ),
        created: true
      )
    } catch StagedDirectoryError.destinationExists {
      return DirectoryCreation(
        handle: try openValidated(
          parentDescriptor: parentDescriptor,
          name: name,
          owner: owner,
          role: role
        ),
        created: false
      )
    }
  }

  private static func installCreatedDirectory(
    parentDescriptor: Int32,
    name: String,
    owner: uid_t,
    role: TestSafetyDirectoryRole,
    preparation: DirectoryPreparation
  ) throws -> DirectoryHandle {
    let stagingName = ".rmp-create-\(UUID().uuidString.lowercased())"
    guard mkdirat(parentDescriptor, stagingName, 0o700) == 0 else {
      throw posixDiagnostic(
        code: "test-safety.directory-create-failed",
        operation: "create a staged \(role.rawValue) directory"
      )
    }
    var stagingInstalled = true
    var stagedHandle: DirectoryHandle?
    defer {
      if stagingInstalled {
        if let stagedHandle {
          preparation.rollback(stagedHandle)
        }
        _ = unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR)
      }
    }
    guard fchmodat(parentDescriptor, stagingName, 0o700, AT_SYMLINK_NOFOLLOW) == 0 else {
      throw posixDiagnostic(
        code: "test-safety.directory-create-failed",
        operation: "secure a staged \(role.rawValue) directory"
      )
    }
    let handle = try openValidated(
      parentDescriptor: parentDescriptor,
      name: stagingName,
      owner: owner,
      role: role
    )
    stagedHandle = handle
    try preparation.apply(handle)
    guard
      renameatx_np(
        parentDescriptor,
        stagingName,
        parentDescriptor,
        name,
        UInt32(RENAME_EXCL)
      ) == 0
    else {
      if errno == EEXIST {
        throw StagedDirectoryError.destinationExists
      }
      throw posixDiagnostic(
        code: "test-safety.directory-create-failed",
        operation: "install the \(role.rawValue) directory"
      )
    }
    stagingInstalled = false
    try validateDirectoryEntry(
      parentDescriptor: parentDescriptor,
      name: name,
      expectedIdentity: handle.identity,
      owner: owner,
      role: role
    )
    return handle
  }

  private static func openValidated(
    parent: DirectoryHandle,
    name: String,
    owner: uid_t,
    role: TestSafetyDirectoryRole
  ) throws -> DirectoryHandle {
    try openValidated(
      parentDescriptor: parent.fileDescriptor,
      name: name,
      owner: owner,
      role: role
    )
  }

  private static func openValidated(
    parentDescriptor: Int32,
    name: String,
    owner: uid_t,
    role: TestSafetyDirectoryRole
  ) throws -> DirectoryHandle {
    var status = stat()
    guard fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
      throw missingDirectory(role)
    }
    try validateDirectoryStatus(status, owner: owner, role: role)
    let descriptor = openat(
      parentDescriptor,
      name,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    return try finishOpening(descriptor, initialStatus: status, owner: owner, role: role)
  }

  private static func finishOpening(
    _ descriptor: Int32,
    initialStatus: stat,
    owner: uid_t,
    role: TestSafetyDirectoryRole
  ) throws -> DirectoryHandle {
    guard descriptor >= 0 else {
      throw TestSafetyDiagnostic(
        code: "test-safety.directory-open-failed",
        message:
          "The \(role.rawValue) directory could not be opened without following symbolic links."
      )
    }
    var openedStatus = stat()
    guard fstat(descriptor, &openedStatus) == 0 else {
      close(descriptor)
      throw posixDiagnostic(
        code: "test-safety.directory-identity-unavailable",
        operation: "identify the \(role.rawValue) directory"
      )
    }
    do {
      try validateDirectoryStatus(openedStatus, owner: owner, role: role)
    } catch {
      close(descriptor)
      throw error
    }
    guard FileIdentity(status: initialStatus) == FileIdentity(status: openedStatus) else {
      close(descriptor)
      throw TestSafetyDiagnostic(
        code: "test-safety.directory-identity-mismatch",
        message: "The \(role.rawValue) directory changed identity while it was opened."
      )
    }
    return DirectoryHandle(fileDescriptor: descriptor, identity: FileIdentity(status: openedStatus))
  }
}

private enum StagedDirectoryError: Error {
  case destinationExists
}

struct DirectoryPreparation {
  let apply: (DirectoryHandle) throws -> Void
  let rollback: (DirectoryHandle) -> Void

  init(
    apply: @escaping (DirectoryHandle) throws -> Void = { _ in },
    rollback: @escaping (DirectoryHandle) -> Void = { _ in }
  ) {
    self.apply = apply
    self.rollback = rollback
  }
}

struct DirectoryCreation {
  let handle: DirectoryHandle
  let created: Bool
}

func validateDirectoryPath(
  _ path: String,
  expectedIdentity: FileIdentity,
  owner: uid_t,
  role: TestSafetyDirectoryRole
) throws {
  var status = stat()
  guard lstat(path, &status) == 0 else { throw missingDirectory(role) }
  try validateDirectoryStatus(status, owner: owner, role: role)
  guard FileIdentity(status: status) == expectedIdentity else { throw identityMismatch(role) }
}

func validateDirectoryEntry(
  parent: DirectoryHandle,
  name: String,
  expectedIdentity: FileIdentity,
  owner: uid_t,
  role: TestSafetyDirectoryRole
) throws {
  try validateDirectoryEntry(
    parentDescriptor: parent.fileDescriptor,
    name: name,
    expectedIdentity: expectedIdentity,
    owner: owner,
    role: role
  )
}

private func validateDirectoryEntry(
  parentDescriptor: Int32,
  name: String,
  expectedIdentity: FileIdentity,
  owner: uid_t,
  role: TestSafetyDirectoryRole
) throws {
  var status = stat()
  guard fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
    throw missingDirectory(role)
  }
  try validateDirectoryStatus(status, owner: owner, role: role)
  guard FileIdentity(status: status) == expectedIdentity else { throw identityMismatch(role) }
}

func posixDiagnostic(code: String, operation: String) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(code: code, message: "Unable to \(operation) (errno \(errno)).")
}

private func validateDirectoryStatus(
  _ status: stat,
  owner: uid_t,
  role: TestSafetyDirectoryRole
) throws {
  guard status.st_mode & S_IFMT == S_IFDIR else {
    let code =
      status.st_mode & S_IFMT == S_IFLNK
      ? "test-safety.directory-symlink"
      : "test-safety.directory-wrong-type"
    throw TestSafetyDiagnostic(
      code: code, message: "The \(role.rawValue) path is not a real directory.")
  }
  guard status.st_uid == owner else {
    throw TestSafetyDiagnostic(
      code: "test-safety.directory-owner-mismatch",
      message: "The \(role.rawValue) directory is not owned by the effective user."
    )
  }
  guard status.st_mode & 0o7777 == 0o700 else {
    throw TestSafetyDiagnostic(
      code: "test-safety.directory-permissions",
      message: "The \(role.rawValue) directory must have permissions 0700."
    )
  }
}

private func missingDirectory(_ role: TestSafetyDirectoryRole) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(
    code: "test-safety.directory-missing",
    message: "The \(role.rawValue) directory is missing."
  )
}

private func identityMismatch(_ role: TestSafetyDirectoryRole) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(
    code: "test-safety.directory-identity-mismatch",
    message: "The \(role.rawValue) directory identity does not match its recorded identity."
  )
}
