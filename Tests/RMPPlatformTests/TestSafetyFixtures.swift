// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@_spi(RMPTestingEntrypoint) @testable import RMPTestKit

enum UnsafeRuntimeCase: CaseIterable, CustomTestStringConvertible {
  case root
  case missingTestingBuild
  case wrongExecutable
  case missingRunID
  case invalidRunID
  case duplicateRunID
  case missingRunIDValue
  case accountIdentityMismatch

  var testDescription: String { expectedCode.rawValue }

  private var configuration: UnsafeRuntimeConfiguration {
    switch self {
    case .root:
      UnsafeRuntimeConfiguration(
        arguments: validArguments,
        expectedCode: .rootExecution,
        runtimeKind: .root
      )
    case .missingTestingBuild:
      UnsafeRuntimeConfiguration(
        arguments: validArguments,
        expectedCode: .testingBuildRequired,
        runtimeKind: .missingTestingBuild
      )
    case .wrongExecutable:
      UnsafeRuntimeConfiguration(
        arguments: validArguments,
        expectedCode: .wrongExecutable,
        runtimeKind: .wrongExecutable
      )
    case .missingRunID:
      UnsafeRuntimeConfiguration(
        arguments: ["fixture"],
        expectedCode: .missingRunID,
        runtimeKind: .standard
      )
    case .invalidRunID:
      UnsafeRuntimeConfiguration(
        arguments: ["--test-run-id", "not-a-uuid", "fixture"],
        expectedCode: .invalidRunID,
        runtimeKind: .standard
      )
    case .duplicateRunID:
      UnsafeRuntimeConfiguration(
        arguments: [
          "--test-run-id", UUID().uuidString.lowercased(),
          "--test-run-id", UUID().uuidString.lowercased(),
        ],
        expectedCode: .duplicateRunID,
        runtimeKind: .standard
      )
    case .missingRunIDValue:
      UnsafeRuntimeConfiguration(
        arguments: ["fixture", "--test-run-id"],
        expectedCode: .missingRunID,
        runtimeKind: .standard
      )
    case .accountIdentityMismatch:
      UnsafeRuntimeConfiguration(
        arguments: validArguments,
        expectedCode: .accountIdentityMismatch,
        runtimeKind: .accountIdentityMismatch
      )
    }
  }

  var arguments: [String] { configuration.arguments }

  var expectedCode: TestSafetyDiagnosticCode { configuration.expectedCode }

  func runtime(for trustedUser: TrustedUserAccount) -> TestSafetyRuntime {
    configuration.runtimeKind.runtime(for: trustedUser)
  }

  private var validArguments: [String] {
    ["--test-run-id", UUID().uuidString.lowercased(), "fixture"]
  }
}

private struct UnsafeRuntimeConfiguration {
  let arguments: [String]
  let expectedCode: TestSafetyDiagnosticCode
  let runtimeKind: UnsafeRuntimeKind
}

private enum UnsafeRuntimeKind {
  case standard
  case root
  case missingTestingBuild
  case wrongExecutable
  case accountIdentityMismatch

  func runtime(for trustedUser: TrustedUserAccount) -> TestSafetyRuntime {
    switch self {
    case .standard:
      .testing(executableName: "rmp-test", trustedUser: trustedUser)
    case .root:
      TestSafetyRuntime(
        effectiveUserID: 0,
        trustedUser: TrustedUserAccount(userID: 0, homeDirectory: trustedUser.homeDirectory),
        executableName: "rmp-test",
        testingBuildEnabled: true
      )
    case .missingTestingBuild:
      TestSafetyRuntime(
        effectiveUserID: trustedUser.userID,
        trustedUser: trustedUser,
        executableName: "rmp-test",
        testingBuildEnabled: false
      )
    case .wrongExecutable:
      TestSafetyRuntime(
        effectiveUserID: trustedUser.userID,
        trustedUser: trustedUser,
        executableName: "rmp",
        testingBuildEnabled: true
      )
    case .accountIdentityMismatch:
      TestSafetyRuntime(
        effectiveUserID: trustedUser.userID + 1,
        trustedUser: trustedUser,
        executableName: "rmp-test",
        testingBuildEnabled: true
      )
    }
  }
}

final class SafetyHomeFixture {
  let homeURL: URL
  let trustedUser: TrustedUserAccount
  var downstreamInvocationCount = 0

  init() throws {
    homeURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "rmp-test-safety-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: homeURL,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    trustedUser = TrustedUserAccount(userID: geteuid(), homeDirectory: homeURL.path)
  }

  var containerURL: URL { homeURL.appendingPathComponent("rmp-test", isDirectory: true) }
  var authorizedRootURL: URL { containerURL.appendingPathComponent("test", isDirectory: true) }
  var containerMarkerURL: URL { containerURL.appendingPathComponent(".rmp-test-container") }
  var rootMarkerURL: URL { authorizedRootURL.appendingPathComponent(".rmp-test-root") }

  func runDirectoryURL(for runID: UUID) -> URL {
    authorizedRootURL.appendingPathComponent(runID.uuidString.lowercased(), isDirectory: true)
  }

  func establishContext(runID: UUID = UUID()) throws -> TestSafetyContext {
    try TestSafetyContext.establish(
      runID: runID,
      trustedUser: trustedUser,
      effectiveUserID: trustedUser.userID
    )
  }

  func createDirectory(at url: URL, permissions: Int) throws {
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: permissions]
    )
  }

  func runDriver() -> TestSafetyDriverResult {
    TestSafetyDriver.run(
      arguments: ["--test-run-id", UUID().uuidString.lowercased(), "fixture"],
      runtime: .testing(executableName: "rmp-test", trustedUser: trustedUser),
      operation: { [self] _, _ in
        downstreamInvocationCount += 1
        return 0
      }
    )
  }

  func snapshot() throws -> [String: SafetySnapshotEntry] {
    var entries: [String: SafetySnapshotEntry] = [:]
    try snapshotChildren(of: homeURL, relativeTo: homeURL, entries: &entries)
    return entries
  }

  func remove() { try? FileManager.default.removeItem(at: homeURL) }
}

struct SafetySnapshotEntry: Equatable {
  let mode: mode_t
  let contents: Data?
  let symbolicLinkDestination: String?
}

func fileMode(at url: URL) -> mode_t? {
  var info = stat()
  guard lstat(url.path, &info) == 0 else { return nil }
  return info.st_mode & 0o7777
}

func decodeMarker(at url: URL) throws -> TestSafetyMarker {
  try JSONDecoder().decode(TestSafetyMarker.self, from: Data(contentsOf: url))
}

func captureDiagnostic(_ operation: () throws -> Void) -> TestSafetyDiagnostic? {
  do {
    try operation()
    return nil
  } catch let diagnostic as TestSafetyDiagnostic {
    return diagnostic
  } catch {
    Issue.record("Unexpected error: \(error)")
    return nil
  }
}

func invokeAfterRevalidation(context: TestSafetyContext, operation: () -> Void) throws {
  try context.revalidate()
  operation()
}

func changeRecordedInode(in markerURL: URL) throws {
  var object = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: markerURL)) as? [String: Any]
  )
  var identity = try #require(object["directoryIdentity"] as? [String: Any])
  identity["inode"] = UInt64.max
  object["directoryIdentity"] = identity
  try writeMarkerObject(object, to: markerURL)
}

func changeRunID(in markerURL: URL) throws {
  var object = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: markerURL)) as? [String: Any]
  )
  object["runID"] = UUID().uuidString
  try writeMarkerObject(object, to: markerURL)
}

private func writeMarkerObject(_ object: [String: Any], to markerURL: URL) throws {
  let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  try data.write(to: markerURL)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
}

private func snapshotChildren(
  of directory: URL,
  relativeTo root: URL,
  entries: inout [String: SafetySnapshotEntry]
) throws {
  for child in try FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: nil
  ) {
    var status = stat()
    try #require(lstat(child.path, &status) == 0)
    let relativePath = String(child.path.dropFirst(root.path.count + 1))
    let kind = status.st_mode & S_IFMT
    let contents = kind == S_IFREG ? try Data(contentsOf: child) : nil
    let destination =
      kind == S_IFLNK
      ? try FileManager.default.destinationOfSymbolicLink(atPath: child.path)
      : nil
    entries[relativePath] = SafetySnapshotEntry(
      mode: status.st_mode,
      contents: contents,
      symbolicLinkDestination: destination
    )
    if kind == S_IFDIR {
      try snapshotChildren(of: child, relativeTo: root, entries: &entries)
    }
  }
}
