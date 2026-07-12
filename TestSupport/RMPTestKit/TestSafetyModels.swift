// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

struct FileIdentity: Codable, Equatable, Sendable {
  let device: UInt64
  let inode: UInt64

  init(status: stat) {
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
  }
}

enum TestSafetyDirectoryRole: String, Codable, Sendable {
  case container
  case authorizedRoot = "authorized-root"
  case run
}

struct TestSafetyMarker: Codable, Equatable, Sendable {
  let formatVersion: Int
  let role: TestSafetyDirectoryRole
  let runID: UUID?
  let directoryIdentity: FileIdentity
  let containerIdentity: FileIdentity?
  let authorizedRootIdentity: FileIdentity?

  init(
    role: TestSafetyDirectoryRole,
    runID: UUID? = nil,
    directoryIdentity: FileIdentity,
    containerIdentity: FileIdentity? = nil,
    authorizedRootIdentity: FileIdentity? = nil
  ) {
    formatVersion = 1
    self.role = role
    self.runID = runID
    self.directoryIdentity = directoryIdentity
    self.containerIdentity = containerIdentity
    self.authorizedRootIdentity = authorizedRootIdentity
  }
}

struct TrustedUserAccount: Equatable, Sendable {
  let userID: uid_t
  let homeDirectory: String

  static func current(effectiveUserID: uid_t = geteuid()) throws -> TrustedUserAccount {
    let configuredSize = sysconf(_SC_GETPW_R_SIZE_MAX)
    let bufferSize = configuredSize > 0 ? Int(configuredSize) : 16_384
    var passwordEntry = passwd()
    var result: UnsafeMutablePointer<passwd>?
    var buffer = [CChar](repeating: 0, count: bufferSize)
    let status = getpwuid_r(effectiveUserID, &passwordEntry, &buffer, buffer.count, &result)

    guard status == 0, result != nil, let homePointer = passwordEntry.pw_dir else {
      throw TestSafetyDiagnostic(
        code: "test-safety.account-lookup-failed",
        message:
          "Unable to obtain the effective user's home directory from the system account database."
      )
    }
    return TrustedUserAccount(
      userID: effectiveUserID,
      homeDirectory: String(cString: homePointer)
    )
  }
}

@_spi(RMPTestingEntrypoint)
public struct TestSafetyDiagnostic: Error, Equatable, CustomStringConvertible, Sendable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }

  public var description: String { "\(code): \(message)" }
}

func validateTestUserIdentity(
  _ trustedUser: TrustedUserAccount,
  effectiveUserID: uid_t
) throws {
  guard effectiveUserID != 0 else {
    throw TestSafetyDiagnostic(
      code: "test-safety.root-execution",
      message: "rmp-test refuses to run as root."
    )
  }
  guard trustedUser.userID == effectiveUserID else {
    throw TestSafetyDiagnostic(
      code: "test-safety.account-identity-mismatch",
      message: "The trusted account record does not match the effective user."
    )
  }
}
