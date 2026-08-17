// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

extension TestSafetyContext {
  /// Builds the authorized fixture name for `suffix`, rejecting anything that is not a single
  /// path component. Quotes and newlines are deliberately permitted: issue 12's acceptance set
  /// requires proving that such names survive the Apple Event boundary without being interpreted.
  func fixtureName(suffix: String) throws -> String {
    guard !suffix.isEmpty, !suffix.contains("/"), !suffix.contains("\0") else {
      throw TestSafetyDiagnostic(
        code: .fixtureNameInvalid,
        message: "A Test Fixture suffix must be one non-empty path component."
      )
    }
    return "tc-test-\(runID.uuidString.lowercased())-\(suffix)"
  }

  /// Creates a `0700` directory fixture. The mode is applied through a descriptor opened with
  /// `O_NOFOLLOW` rather than by path, so umask cannot loosen it and no symlink can be followed.
  func createFixtureDirectory(suffix: String) throws -> URL {
    try revalidate()
    let name = try fixtureName(suffix: suffix)
    let parentDescriptor = try duplicateRunDirectoryDescriptor()
    defer { close(parentDescriptor) }
    guard mkdirat(parentDescriptor, name, 0o700) == 0 else {
      throw posixDiagnostic(
        code: .fixtureCreateFailed,
        operation: "create the Test Fixture directory"
      )
    }
    // `mkdirat` applies the process umask, which can strip the requested mode entirely and leave
    // a directory that cannot even be opened. Restore the mode relative to the retained parent
    // descriptor; `mkdirat` succeeded exclusively, so the entry is still the directory just made.
    guard fchmodat(parentDescriptor, name, 0o700, 0) == 0 else {
      try? removeEntryIfPresent(
        parentDescriptor: parentDescriptor,
        name: name,
        flags: AT_REMOVEDIR,
        operation: "roll back the Test Fixture directory"
      )
      throw posixDiagnostic(
        code: .fixtureCreateFailed,
        operation: "secure the Test Fixture directory"
      )
    }
    return runDirectoryURL.appendingPathComponent(name, isDirectory: true)
  }

  /// Creates a symbolic-link fixture pointing at `target`. A target that does not exist yields the
  /// broken-link case; nothing here resolves or follows the link.
  func createFixtureSymbolicLink(suffix: String, target: String) throws -> URL {
    try revalidate()
    guard !target.isEmpty, !target.contains("\0") else {
      throw TestSafetyDiagnostic(
        code: .fixtureNameInvalid,
        message: "A Test Fixture symbolic-link target must be non-empty."
      )
    }
    let name = try fixtureName(suffix: suffix)
    let parentDescriptor = try duplicateRunDirectoryDescriptor()
    defer { close(parentDescriptor) }
    guard symlinkat(target, parentDescriptor, name) == 0 else {
      throw posixDiagnostic(
        code: .fixtureCreateFailed,
        operation: "create the Test Fixture symbolic link"
      )
    }
    return runDirectoryURL.appendingPathComponent(name, isDirectory: false)
  }

  func createFixtureFile(suffix: String, contents: Data) throws -> URL {
    try revalidate()
    let name = try fixtureName(suffix: suffix)
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
