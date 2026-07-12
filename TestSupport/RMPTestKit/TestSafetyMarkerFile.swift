// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

func validateOrCreateMarker(
  parent: DirectoryHandle,
  name: String,
  expected: TestSafetyMarker,
  owner: uid_t,
  directoryWasCreated: Bool
) throws {
  if directoryWasCreated {
    try createMarkerExclusive(parent: parent, name: name, marker: expected)
  } else {
    try validateExistingMarker(parent: parent, name: name, expected: expected, owner: owner)
  }
}

func createMarkerExclusive(
  parent: DirectoryHandle,
  name: String,
  marker: TestSafetyMarker
) throws {
  let descriptor = openat(
    parent.fileDescriptor,
    name,
    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
    mode_t(0o600)
  )
  guard descriptor >= 0 else {
    if errno == EEXIST {
      throw TestSafetyDiagnostic(
        code: "test-safety.marker-exists",
        message: "A required safety marker already exists."
      )
    }
    throw posixDiagnostic(
      code: "test-safety.marker-create-failed",
      operation: "create a safety marker"
    )
  }
  defer { close(descriptor) }
  guard fchmod(descriptor, 0o600) == 0 else {
    throw posixDiagnostic(
      code: "test-safety.marker-create-failed",
      operation: "secure a safety marker"
    )
  }
  var data = try markerEncoder.encode(marker)
  data.append(0x0A)
  try writeAll(data, to: descriptor)
  guard fsync(descriptor) == 0 else {
    throw posixDiagnostic(
      code: "test-safety.marker-write-failed",
      operation: "sync a safety marker"
    )
  }
}

func validateExistingMarker(
  parent: DirectoryHandle,
  name: String,
  expected: TestSafetyMarker,
  owner: uid_t
) throws {
  var status = stat()
  guard fstatat(parent.fileDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
    throw TestSafetyDiagnostic(
      code: "test-safety.marker-missing",
      message: "A required safety marker is missing."
    )
  }
  guard status.st_mode & S_IFMT == S_IFREG else {
    throw TestSafetyDiagnostic(
      code: "test-safety.marker-wrong-type",
      message: "A required safety marker is not a regular file."
    )
  }
  guard status.st_uid == owner else {
    throw TestSafetyDiagnostic(
      code: "test-safety.marker-owner-mismatch",
      message: "A required safety marker is not owned by the effective user."
    )
  }
  guard status.st_mode & 0o7777 == 0o600 else {
    throw TestSafetyDiagnostic(
      code: "test-safety.marker-permissions",
      message: "A required safety marker must have permissions 0600."
    )
  }
  let descriptor = openat(parent.fileDescriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
  guard descriptor >= 0 else {
    throw TestSafetyDiagnostic(
      code: "test-safety.marker-open-failed",
      message: "A required safety marker could not be opened without following symbolic links."
    )
  }
  defer { close(descriptor) }
  var openedStatus = stat()
  guard fstat(descriptor, &openedStatus) == 0,
    FileIdentity(status: openedStatus) == FileIdentity(status: status)
  else {
    throw TestSafetyDiagnostic(
      code: "test-safety.marker-identity-mismatch",
      message: "A required safety marker changed identity during validation."
    )
  }
  let data = try readAll(from: descriptor)
  guard let marker = try? JSONDecoder().decode(TestSafetyMarker.self, from: data),
    marker == expected
  else {
    throw TestSafetyDiagnostic(
      code: "test-safety.marker-invalid",
      message: "A required safety marker has invalid or mismatched contents."
    )
  }
}

private var markerEncoder: JSONEncoder {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return encoder
}

private func writeAll(_ data: Data, to descriptor: Int32) throws {
  try data.withUnsafeBytes { buffer in
    guard let baseAddress = buffer.baseAddress else { return }
    var written = 0
    while written < buffer.count {
      let count = Darwin.write(
        descriptor, baseAddress.advanced(by: written), buffer.count - written)
      guard count > 0 else {
        throw posixDiagnostic(
          code: "test-safety.marker-write-failed",
          operation: "write a safety marker"
        )
      }
      written += count
    }
  }
}

private func readAll(from descriptor: Int32) throws -> Data {
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while true {
    let count = Darwin.read(descriptor, &buffer, buffer.count)
    if count == 0 { return data }
    guard count > 0 else {
      throw posixDiagnostic(
        code: "test-safety.marker-read-failed",
        operation: "read a safety marker"
      )
    }
    data.append(buffer, count: count)
  }
}
