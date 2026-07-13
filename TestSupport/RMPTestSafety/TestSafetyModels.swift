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

  static func current(
    effectiveUserID: uid_t = geteuid()
  ) throws -> TrustedUserAccount {
    let configuredSize = sysconf(_SC_GETPW_R_SIZE_MAX)
    let bufferSize = configuredSize > 0 ? Int(configuredSize) : 16_384
    var passwordEntry = passwd()
    var result: UnsafeMutablePointer<passwd>?
    var buffer = [CChar](repeating: 0, count: bufferSize)
    let status = getpwuid_r(effectiveUserID, &passwordEntry, &buffer, buffer.count, &result)

    guard status == 0, result != nil, let homePointer = passwordEntry.pw_dir else {
      throw TestSafetyDiagnostic(
        code: .accountLookupFailed,
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

enum TestSafetyDiagnosticCode: String, Sendable {
  case accountIdentityMismatch = "test-safety.account-identity-mismatch"
  case accountLookupFailed = "test-safety.account-lookup-failed"
  case cleanupFailed = "test-safety.cleanup-failed"
  case directoryCreateFailed = "test-safety.directory-create-failed"
  case directoryIdentityMismatch = "test-safety.directory-identity-mismatch"
  case directoryIdentityUnavailable = "test-safety.directory-identity-unavailable"
  case directoryMissing = "test-safety.directory-missing"
  case directoryOpenFailed = "test-safety.directory-open-failed"
  case directoryOwnerMismatch = "test-safety.directory-owner-mismatch"
  case directoryPermissions = "test-safety.directory-permissions"
  case directoryReadFailed = "test-safety.directory-read-failed"
  case directorySymlink = "test-safety.directory-symlink"
  case directoryWrongType = "test-safety.directory-wrong-type"
  case duplicateRunID = "test-safety.duplicate-run-id"
  case executableIdentityUnavailable = "test-safety.executable-identity-unavailable"
  case invalidRunID = "test-safety.invalid-run-id"
  case markerCreateFailed = "test-safety.marker-create-failed"
  case markerExists = "test-safety.marker-exists"
  case markerIdentityMismatch = "test-safety.marker-identity-mismatch"
  case markerInvalid = "test-safety.marker-invalid"
  case markerMissing = "test-safety.marker-missing"
  case markerOpenFailed = "test-safety.marker-open-failed"
  case markerOwnerMismatch = "test-safety.marker-owner-mismatch"
  case markerPermissions = "test-safety.marker-permissions"
  case markerReadFailed = "test-safety.marker-read-failed"
  case markerTooLarge = "test-safety.marker-too-large"
  case markerWriteFailed = "test-safety.marker-write-failed"
  case markerWrongType = "test-safety.marker-wrong-type"
  case missingRunID = "test-safety.missing-run-id"
  case rootExecution = "test-safety.root-execution"
  case rollbackFailed = "test-safety.rollback-failed"
  case runDirectoryExists = "test-safety.run-directory-exists"
  case runDirectoryNotEmpty = "test-safety.run-directory-not-empty"
  case unexpectedError = "test-safety.unexpected-error"
  case wrongExecutable = "test-safety.wrong-executable"
  case trashFileProviderRoot = "test-safety.trash-file-provider-root"
  case trashEvidenceMismatch = "test-safety.trash-evidence-mismatch"
  case trashFixtureName = "test-safety.trash-fixture-name"
  case trashIntermediateSymlink = "test-safety.trash-intermediate-symlink"
  case trashMountPoint = "test-safety.trash-mount-point"
  case trashNetworkVolume = "test-safety.trash-network-volume"
  case trashOutsideRunDirectory = "test-safety.trash-outside-run-directory"
  case trashPathInspectionFailed = "test-safety.trash-path-inspection-failed"
  case trashPlanIdentityMismatch = "test-safety.trash-plan-identity-mismatch"
  case trashSafetyDirectory = "test-safety.trash-safety-directory"
  case trashSystemCallFailed = "test-safety.trash-system-call-failed"
  case trashVolumeMismatch = "test-safety.trash-volume-mismatch"
}

struct TestSafetyDiagnostic: Error, Equatable, CustomStringConvertible, Sendable {
  let code: TestSafetyDiagnosticCode
  let message: String

  init(code: TestSafetyDiagnosticCode, message: String) {
    self.code = code
    self.message = message
  }

  var description: String { "\(code.rawValue): \(message)" }
}

func validateTestUserIdentity(
  _ trustedUser: TrustedUserAccount,
  effectiveUserID: uid_t
) throws {
  guard effectiveUserID != 0 else {
    throw TestSafetyDiagnostic(
      code: .rootExecution,
      message: "rmp-test refuses to run as root."
    )
  }
  guard trustedUser.userID == effectiveUserID else {
    throw TestSafetyDiagnostic(
      code: .accountIdentityMismatch,
      message: "The trusted account record does not match the effective user."
    )
  }
}
