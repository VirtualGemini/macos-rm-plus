// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

extension TestSafetyContext {
  func createFixtureFile(suffix: String, contents: Data) throws -> URL {
    try revalidate()
    guard !suffix.isEmpty, !suffix.contains("/"), !suffix.contains("\0") else {
      throw TestSafetyDiagnostic(
        code: .fixtureNameInvalid,
        message: "A Test Fixture suffix must be one non-empty path component."
      )
    }

    let name = "rmp-test-\(runID.uuidString.lowercased())-\(suffix)"
    let parentDescriptor = try duplicateRunDirectoryDescriptor()
    defer { close(parentDescriptor) }
    let descriptor = openat(
      parentDescriptor,
      name,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      0o600
    )
    guard descriptor >= 0 else {
      throw posixDiagnostic(code: .fixtureCreateFailed, operation: "create the Test Fixture")
    }

    do {
      guard fchmod(descriptor, 0o600) == 0 else {
        throw posixDiagnostic(code: .fixtureCreateFailed, operation: "secure the Test Fixture")
      }
      try writeFixtureContents(contents, descriptor: descriptor)
      close(descriptor)
      return runDirectoryURL.appendingPathComponent(name, isDirectory: false)
    } catch let operationError {
      close(descriptor)
      do {
        try removeEntryIfPresent(
          parentDescriptor: parentDescriptor,
          name: name,
          flags: 0,
          operation: "roll back the Test Fixture"
        )
      } catch let rollbackError {
        throw rollbackError
      }
      throw operationError
    }
  }
}

private func writeFixtureContents(_ contents: Data, descriptor: Int32) throws {
  try contents.withUnsafeBytes { bytes in
    guard let baseAddress = bytes.baseAddress else { return }
    var offset = 0
    while offset < bytes.count {
      let written = Darwin.write(
        descriptor,
        baseAddress.advanced(by: offset),
        bytes.count - offset
      )
      if written < 0, errno == EINTR { continue }
      guard written > 0 else {
        throw posixDiagnostic(code: .fixtureWriteFailed, operation: "write the Test Fixture")
      }
      offset += written
    }
  }
}
