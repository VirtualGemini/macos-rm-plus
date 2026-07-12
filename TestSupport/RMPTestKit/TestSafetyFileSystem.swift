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
        code: .directoryCreateFailed,
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
        code: .runDirectoryExists,
        message: "The UUID Run Directory already exists and cannot be reused."
      )
    }
  }

  func entryNames() throws -> [String] {
    let copiedDescriptor = dup(fileDescriptor)
    guard copiedDescriptor >= 0, let directory = fdopendir(copiedDescriptor) else {
      if copiedDescriptor >= 0 { close(copiedDescriptor) }
      throw posixDiagnostic(
        code: .directoryReadFailed,
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
        code: .directoryReadFailed,
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
    let expectation = DirectoryExpectation(status: status, owner: owner, role: role)
    try expectation.validate(status)
    let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    return try finishOpening(descriptor, expectation: expectation)
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
        code: .directoryCreateFailed,
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
        code: .directoryCreateFailed,
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
        code: .directoryCreateFailed,
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
        code: .directoryCreateFailed,
        operation: "install the \(role.rawValue) directory"
      )
    }
    stagingInstalled = false
    try validateDirectoryEntry(
      parentDescriptor: parentDescriptor,
      name: name,
      expectation: DirectoryExpectation(identity: handle.identity, owner: owner, role: role)
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
    let expectation = DirectoryExpectation(status: status, owner: owner, role: role)
    try expectation.validate(status)
    let descriptor = openat(
      parentDescriptor,
      name,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    return try finishOpening(descriptor, expectation: expectation)
  }

  private static func finishOpening(
    _ descriptor: Int32,
    expectation: DirectoryExpectation
  ) throws -> DirectoryHandle {
    guard descriptor >= 0 else {
      throw TestSafetyDiagnostic(
        code: .directoryOpenFailed,
        message:
          "The \(expectation.role.rawValue) directory could not be opened "
          + "without following symbolic links."
      )
    }
    var openedStatus = stat()
    guard fstat(descriptor, &openedStatus) == 0 else {
      close(descriptor)
      throw posixDiagnostic(
        code: .directoryIdentityUnavailable,
        operation: "identify the \(expectation.role.rawValue) directory"
      )
    }
    do {
      try expectation.validate(openedStatus)
    } catch {
      close(descriptor)
      throw error
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

struct DirectoryExpectation {
  let identity: FileIdentity
  let owner: uid_t
  let role: TestSafetyDirectoryRole

  init(identity: FileIdentity, owner: uid_t, role: TestSafetyDirectoryRole) {
    self.identity = identity
    self.owner = owner
    self.role = role
  }

  init(status: stat, owner: uid_t, role: TestSafetyDirectoryRole) {
    self.init(identity: FileIdentity(status: status), owner: owner, role: role)
  }

  func validate(_ status: stat) throws {
    try validateDirectoryStatus(status, owner: owner, role: role)
    guard FileIdentity(status: status) == identity else { throw identityMismatch(role) }
  }
}

func validateDirectoryPath(
  _ path: String,
  expectation: DirectoryExpectation
) throws {
  var status = stat()
  guard lstat(path, &status) == 0 else { throw missingDirectory(expectation.role) }
  try expectation.validate(status)
}

func validateDirectoryEntry(
  parent: DirectoryHandle,
  name: String,
  expectation: DirectoryExpectation
) throws {
  try validateDirectoryEntry(
    parentDescriptor: parent.fileDescriptor,
    name: name,
    expectation: expectation
  )
}

private func validateDirectoryEntry(
  parentDescriptor: Int32,
  name: String,
  expectation: DirectoryExpectation
) throws {
  var status = stat()
  guard fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
    throw missingDirectory(expectation.role)
  }
  try expectation.validate(status)
}

func posixDiagnostic(code: TestSafetyDiagnosticCode, operation: String) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(code: code, message: "Unable to \(operation) (errno \(errno)).")
}

private func validateDirectoryStatus(
  _ status: stat,
  owner: uid_t,
  role: TestSafetyDirectoryRole
) throws {
  guard status.st_mode & S_IFMT == S_IFDIR else {
    let code: TestSafetyDiagnosticCode =
      status.st_mode & S_IFMT == S_IFLNK
      ? .directorySymlink
      : .directoryWrongType
    throw TestSafetyDiagnostic(
      code: code, message: "The \(role.rawValue) path is not a real directory.")
  }
  guard status.st_uid == owner else {
    throw TestSafetyDiagnostic(
      code: .directoryOwnerMismatch,
      message: "The \(role.rawValue) directory is not owned by the effective user."
    )
  }
  guard status.st_mode & 0o7777 == 0o700 else {
    throw TestSafetyDiagnostic(
      code: .directoryPermissions,
      message: "The \(role.rawValue) directory must have permissions 0700."
    )
  }
}

private func missingDirectory(_ role: TestSafetyDirectoryRole) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(
    code: .directoryMissing,
    message: "The \(role.rawValue) directory is missing."
  )
}

private func identityMismatch(_ role: TestSafetyDirectoryRole) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(
    code: .directoryIdentityMismatch,
    message: "The \(role.rawValue) directory identity does not match its recorded identity."
  )
}
