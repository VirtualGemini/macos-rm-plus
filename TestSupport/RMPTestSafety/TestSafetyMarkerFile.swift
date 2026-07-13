// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

private let maximumMarkerBytes = 16_384

func markerPreparation(
  name: String,
  marker: @escaping (DirectoryHandle) -> TestSafetyMarker
) -> DirectoryPreparation {
  DirectoryPreparation(
    apply: { handle in
      try createMarkerExclusive(parent: handle, name: name, marker: marker(handle))
    },
    rollback: { handle in
      try removeEntryIfPresent(
        parentDescriptor: handle.fileDescriptor,
        name: name,
        flags: 0,
        operation: "remove a staged safety marker"
      )
    }
  )
}

func createMarkerExclusive(
  parent: DirectoryHandle,
  name: String,
  marker: TestSafetyMarker,
  operations: MarkerFileOperations = .system
) throws {
  let descriptor = operations.create(parent.fileDescriptor, name)
  guard descriptor >= 0 else {
    if errno == EEXIST {
      throw TestSafetyDiagnostic(
        code: .markerExists,
        message: "A required safety marker already exists."
      )
    }
    throw posixDiagnostic(
      code: .markerCreateFailed,
      operation: "create a safety marker"
    )
  }
  do {
    guard fchmod(descriptor, 0o600) == 0 else {
      throw posixDiagnostic(
        code: .markerCreateFailed,
        operation: "secure a safety marker"
      )
    }
    var data = try markerEncoder.encode(marker)
    data.append(0x0A)
    try writeAll(data, to: descriptor, write: operations.write)
    try syncMarker(descriptor)
    close(descriptor)
  } catch {
    let originalError = error
    close(descriptor)
    try removeEntryIfPresent(
      parentDescriptor: parent.fileDescriptor,
      name: name,
      flags: 0,
      operation: "remove an incomplete safety marker"
    )
    throw originalError
  }
}

func validateExistingMarker(
  parent: DirectoryHandle,
  name: String,
  expected: TestSafetyMarker,
  owner: uid_t,
  operations: MarkerFileOperations = .system
) throws {
  var status = stat()
  guard fstatat(parent.fileDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
    throw TestSafetyDiagnostic(
      code: .markerMissing,
      message: "A required safety marker is missing."
    )
  }
  try validateMarkerStatus(status, owner: owner)
  let descriptor = operations.open(parent.fileDescriptor, name)
  guard descriptor >= 0 else {
    throw TestSafetyDiagnostic(
      code: .markerOpenFailed,
      message: "A required safety marker could not be opened without following symbolic links."
    )
  }
  defer { close(descriptor) }
  var openedStatus = stat()
  guard operations.identify(descriptor, &openedStatus) == 0 else {
    throw TestSafetyDiagnostic(
      code: .markerIdentityMismatch,
      message: "A required safety marker changed identity during validation."
    )
  }
  try validateMarkerStatus(openedStatus, owner: owner)
  guard FileIdentity(status: openedStatus) == FileIdentity(status: status) else {
    throw TestSafetyDiagnostic(
      code: .markerIdentityMismatch,
      message: "A required safety marker changed identity during validation."
    )
  }
  guard openedStatus.st_size >= 0, openedStatus.st_size <= off_t(maximumMarkerBytes) else {
    throw markerTooLarge()
  }
  let data = try readAll(
    from: descriptor,
    maximumBytes: maximumMarkerBytes,
    read: operations.read
  )
  guard let marker = try? JSONDecoder().decode(TestSafetyMarker.self, from: data),
    marker == expected
  else {
    throw TestSafetyDiagnostic(
      code: .markerInvalid,
      message: "A required safety marker has invalid or mismatched contents."
    )
  }
}

private func validateMarkerStatus(_ status: stat, owner: uid_t) throws {
  guard status.st_mode & S_IFMT == S_IFREG else {
    throw TestSafetyDiagnostic(
      code: .markerWrongType,
      message: "A required safety marker is not a regular file."
    )
  }
  guard status.st_uid == owner else {
    throw TestSafetyDiagnostic(
      code: .markerOwnerMismatch,
      message: "A required safety marker is not owned by the effective user."
    )
  }
  guard status.st_mode & 0o7777 == 0o600 else {
    throw TestSafetyDiagnostic(
      code: .markerPermissions,
      message: "A required safety marker must have permissions 0600."
    )
  }
}

private var markerEncoder: JSONEncoder {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return encoder
}

private func writeAll(
  _ data: Data,
  to descriptor: Int32,
  write: (Int32, UnsafeRawPointer, Int) -> Int
) throws {
  try data.withUnsafeBytes { buffer in
    guard let baseAddress = buffer.baseAddress else { return }
    var written = 0
    while written < buffer.count {
      let count = write(descriptor, baseAddress.advanced(by: written), buffer.count - written)
      if count < 0, errno == EINTR { continue }
      guard count > 0 else {
        throw posixDiagnostic(
          code: .markerWriteFailed,
          operation: "write a safety marker"
        )
      }
      written += count
    }
  }
}

private func readAll(
  from descriptor: Int32,
  maximumBytes: Int,
  read: (Int32, UnsafeMutableRawPointer, Int) -> Int
) throws -> Data {
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while true {
    let allowedCount = min(buffer.count, maximumBytes - data.count + 1)
    let count = buffer.withUnsafeMutableBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return 0 }
      return read(descriptor, baseAddress, allowedCount)
    }
    if count == 0 { return data }
    if count < 0, errno == EINTR { continue }
    guard count > 0 else {
      throw posixDiagnostic(
        code: .markerReadFailed,
        operation: "read a safety marker"
      )
    }
    data.append(buffer, count: count)
    if data.count > maximumBytes { throw markerTooLarge() }
  }
}

private func syncMarker(_ descriptor: Int32) throws {
  while fsync(descriptor) != 0 {
    if errno == EINTR { continue }
    throw posixDiagnostic(
      code: .markerWriteFailed,
      operation: "sync a safety marker"
    )
  }
}

struct MarkerFileOperations: Sendable {
  let create: @Sendable (Int32, String) -> Int32
  let open: @Sendable (Int32, String) -> Int32
  let identify: @Sendable (Int32, UnsafeMutablePointer<stat>) -> Int32
  let read: @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int
  let write: @Sendable (Int32, UnsafeRawPointer, Int) -> Int

  static let system = MarkerFileOperations(
    create: { parentDescriptor, name in
      openat(
        parentDescriptor,
        name,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        mode_t(0o600)
      )
    },
    open: { parentDescriptor, name in
      openat(parentDescriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    },
    identify: { fstat($0, $1) },
    read: { Darwin.read($0, $1, $2) },
    write: { Darwin.write($0, $1, $2) }
  )
}

private func markerTooLarge() -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(
    code: .markerTooLarge,
    message: "A required safety marker exceeds the maximum supported size."
  )
}
