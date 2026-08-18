// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import TrashCore
import TrashPlatform

final class AuthorizedBatchTrashClient: TrashClient, @unchecked Sendable {
  typealias TrashOperation = @Sendable () throws -> TrashVerificationEvidence

  private let operations: [String: TrashOperation]
  private(set) var receivedPaths: [String] = []
  private(set) var receipts: [String: TrashMoveReceipt] = [:]

  init(operations: [String: TrashOperation]) {
    self.operations = operations
  }

  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    receivedPaths.append(path)
    guard let operation = operations[path] else {
      throw TrashCapabilityError(code: .systemTrashFailed)
    }
    let evidence = try operation()
    let receipt = TrashMoveReceipt(destinationPath: evidence.returnedURL.path)
    receipts[path] = receipt
    return receipt
  }
}

struct OrderedBatchAcceptanceReport: Sendable {
  let runDirectoryURL: URL
  let result: CommandResult
  let fixtures: OrderedBatchFixtures
  let receipts: [String: TrashMoveReceipt]

  func renderSummary() -> String {
    var output = "ordered-batch acceptance=passed\n"
    output += "run-directory=\(renderAcceptancePath(runDirectoryURL.path))\n"
    for sourceURL in fixtures.movedURLs {
      guard let receipt = receipts[sourceURL.path] else { continue }
      output +=
        "moved-source=\(renderAcceptancePath(sourceURL.path)) "
        + "destination=\(renderAcceptancePath(receipt.destinationPath))\n"
    }
    output += "expected-missing=\(renderAcceptancePath(fixtures.missingURL.path))\n"
    output +=
      "expected-permission-failure=\(renderAcceptancePath(fixtures.permissionDeniedURL.path))\n"
    return output
  }
}

struct OrderedBatchFixtures: Sendable {
  let fileURL: URL
  let permissionDeniedParentURL: URL
  let permissionDeniedURL: URL
  let emptyDirectoryURL: URL
  let deepDirectoryURL: URL
  let specialNameURL: URL
  let missingURL: URL

  var orderedURLs: [URL] {
    [
      fileURL,
      permissionDeniedURL,
      emptyDirectoryURL,
      deepDirectoryURL,
      specialNameURL,
      missingURL,
    ]
  }

  var movedURLs: [URL] {
    [fileURL, emptyDirectoryURL, deepDirectoryURL, specialNameURL]
  }

  var authorizedURLs: [URL] {
    [fileURL, permissionDeniedURL, emptyDirectoryURL, deepDirectoryURL, specialNameURL]
  }
}

struct OrderedBatchAcceptanceEvidence: Sendable {
  let result: CommandResult
  let fixtures: OrderedBatchFixtures
  let receivedPaths: [String]
  let receipts: [String: TrashMoveReceipt]
  let sourceExistence: [String: Bool]
}

enum OrderedBatchAcceptance {
  static func run(context: TestSafetyContext) throws -> OrderedBatchAcceptanceReport {
    let fixtures = try prepareFixtures(context: context)
    let authorizedTrash = WhitelistedTrashClient(context: context, backend: .finder)
    var operations: [String: AuthorizedBatchTrashClient.TrashOperation] = [:]
    for sourceURL in fixtures.authorizedURLs {
      let target = try authorizedTrash.authorizeForPlanning(targetURL: sourceURL)
      operations[sourceURL.path] = {
        try authorizedTrash.trashItem(target)
      }
    }
    let client = AuthorizedBatchTrashClient(operations: operations)
    let permissionParentDescriptor = try openFixtureDirectory(
      context: context,
      url: fixtures.permissionDeniedParentURL
    )
    defer { close(permissionParentDescriptor) }

    try setMode(0o500, descriptor: permissionParentDescriptor, role: "permission fixture")
    defer { _ = fchmod(permissionParentDescriptor, 0o700) }
    let result = CLIApplication(
      makeFileSystem: { FoundationTrashPlanningFileSystem() },
      makeTrashClient: { client },
      effectiveUserID: { geteuid() }
    ).run(
      arguments: ["--confirm=never", "--verbose"] + fixtures.orderedURLs.map(\.path)
    )
    try setMode(0o700, descriptor: permissionParentDescriptor, role: "permission fixture")

    let evidence = OrderedBatchAcceptanceEvidence(
      result: result,
      fixtures: fixtures,
      receivedPaths: client.receivedPaths,
      receipts: client.receipts,
      sourceExistence: Dictionary(
        uniqueKeysWithValues: fixtures.orderedURLs.map { ($0.path, entryExists(at: $0)) }
      )
    )
    try validate(evidence)
    return OrderedBatchAcceptanceReport(
      runDirectoryURL: context.runDirectoryURL,
      result: result,
      fixtures: fixtures,
      receipts: client.receipts
    )
  }

  static func validate(_ evidence: OrderedBatchAcceptanceEvidence) throws {
    try validateOrderAndCounts(evidence)
    try validateOutput(evidence)
    try validateSourceStates(evidence)
  }

  private static func validateOrderAndCounts(_ evidence: OrderedBatchAcceptanceEvidence) throws {
    let fixtures = evidence.fixtures
    let expectedAttempts = fixtures.authorizedURLs.map(\.path)
    try requireEvidence(
      evidence.receivedPaths == expectedAttempts,
      "The ordered batch did not call Trash serially in top-level input order."
    )
    try requireEvidence(
      evidence.result.exitCode == 1,
      "The expected partial-success batch did not return operational exit code 1."
    )
    try requireEvidence(
      evidence.receipts.count == fixtures.movedURLs.count,
      "The ordered batch did not retain exactly one receipt for every successful input."
    )
    try requireEvidence(
      evidence.receipts[fixtures.permissionDeniedURL.path] == nil,
      "The permission-denied input unexpectedly produced a moved receipt."
    )
  }

  private static func validateOutput(_ evidence: OrderedBatchAcceptanceEvidence) throws {
    let fixtures = evidence.fixtures
    var expectedOutput = ""
    for sourceURL in fixtures.movedURLs {
      guard let receipt = evidence.receipts[sourceURL.path] else {
        throw evidenceFailure("A successful ordered-batch input lost its exact Trash receipt.")
      }
      expectedOutput +=
        "Moved \(renderAcceptancePath(sourceURL.path)) to Trash at "
        + "\(renderAcceptancePath(receipt.destinationPath)).\n"
    }
    try requireEvidence(
      evidence.result.standardOutput == expectedOutput,
      "Verbose ordered-batch output did not preserve the successful top-level result contract."
    )
    try requireEvidence(
      evidence.result.standardError.contains(TrashErrorCode.systemTrashFailed.rawValue)
        && evidence.result.standardError.contains(
          renderAcceptancePath(fixtures.permissionDeniedURL.path)
        ),
      "The real permission failure was not reported with its stable code and source path."
    )
    try requireEvidence(
      evidence.result.standardError.contains(TrashErrorCode.missingInput.rawValue)
        && evidence.result.standardError.contains(renderAcceptancePath(fixtures.missingURL.path)),
      "The missing input was not reported with its stable code and source path."
    )
    try requireEvidence(
      evidence.result.standardError.filter { $0 == "\n" }.count == 2,
      "The partial-success batch did not emit exactly one error record per failed input."
    )
  }

  private static func validateSourceStates(_ evidence: OrderedBatchAcceptanceEvidence) throws {
    let fixtures = evidence.fixtures
    for movedURL in fixtures.movedURLs {
      try requireEvidence(
        evidence.sourceExistence[movedURL.path] == false,
        "A successful Test Fixture still exists at its original source path."
      )
    }
    try requireEvidence(
      evidence.sourceExistence[fixtures.permissionDeniedURL.path] == true,
      "The permission-denied Test Fixture was not confirmed unchanged."
    )
    try requireEvidence(
      evidence.sourceExistence[fixtures.missingURL.path] == false,
      "The deliberately missing Test Fixture unexpectedly exists."
    )
  }

  private static func prepareFixtures(context: TestSafetyContext) throws -> OrderedBatchFixtures {
    let body = Data("ordered batch \(context.runID.uuidString.lowercased())\n".utf8)
    let fileURL = try context.createFixtureFile(suffix: "batch-file", contents: body)
    let emptyDirectoryURL = try context.createFixtureDirectory(suffix: "batch-empty-directory")
    let deepDirectoryURL = try createDeepDirectoryFixture(context: context, contents: body)
    let specialNameURL = try context.createFixtureFile(
      suffix: "batch name with \"quotes\" and\na newline",
      contents: body
    )
    let permissionFixture = try createPermissionDeniedFixture(context: context, contents: body)
    let missingName = try context.fixtureName(suffix: "batch-missing")
    let missingURL = context.runDirectoryURL.appendingPathComponent(missingName)
    return OrderedBatchFixtures(
      fileURL: fileURL,
      permissionDeniedParentURL: permissionFixture.parentURL,
      permissionDeniedURL: permissionFixture.targetURL,
      emptyDirectoryURL: emptyDirectoryURL,
      deepDirectoryURL: deepDirectoryURL,
      specialNameURL: specialNameURL,
      missingURL: missingURL
    )
  }
}

private func createDeepDirectoryFixture(
  context: TestSafetyContext,
  contents: Data
) throws -> URL {
  let rootURL = try context.createFixtureDirectory(suffix: "batch-deep-directory")
  let rootDescriptor = try openFixtureDirectory(context: context, url: rootURL)
  defer { close(rootDescriptor) }
  let firstDescriptor = try createAndOpenDirectory(name: "level-one", parent: rootDescriptor)
  defer { close(firstDescriptor) }
  let secondDescriptor = try createAndOpenDirectory(name: "level-two", parent: firstDescriptor)
  defer { close(secondDescriptor) }
  try createFile(name: "contents.txt", contents: contents, parent: secondDescriptor)
  return rootURL
}

private func createPermissionDeniedFixture(
  context: TestSafetyContext,
  contents: Data
) throws -> (parentURL: URL, targetURL: URL) {
  let parentURL = try context.createFixtureDirectory(suffix: "batch-permission-parent")
  let parentDescriptor = try openFixtureDirectory(context: context, url: parentURL)
  defer { close(parentDescriptor) }
  let targetName = try context.fixtureName(suffix: "batch-permission-denied")
  try createFile(name: targetName, contents: contents, parent: parentDescriptor)
  return (
    parentURL,
    parentURL.appendingPathComponent(targetName, isDirectory: false)
  )
}

private func openFixtureDirectory(context: TestSafetyContext, url: URL) throws -> Int32 {
  try context.revalidate()
  let runDescriptor = try context.duplicateRunDirectoryDescriptor()
  defer { close(runDescriptor) }
  let descriptor = openat(
    runDescriptor,
    url.lastPathComponent,
    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
  )
  guard descriptor >= 0 else {
    throw TestSafetyDiagnostic(
      code: .directoryOpenFailed,
      message: "An ordered-batch Test Fixture directory could not be opened safely."
    )
  }
  return descriptor
}

private func createAndOpenDirectory(name: String, parent: Int32) throws -> Int32 {
  guard mkdirat(parent, name, 0o700) == 0 else {
    throw TestSafetyDiagnostic(
      code: .fixtureCreateFailed,
      message: "The deep-directory Test Fixture could not be created safely."
    )
  }
  guard fchmodat(parent, name, 0o700, 0) == 0 else {
    try rollbackCreatedEntry(
      parent: parent,
      name: name,
      flags: AT_REMOVEDIR,
      originalError: TestSafetyDiagnostic(
        code: .fixtureCreateFailed,
        message: "The deep-directory Test Fixture could not be secured."
      )
    )
  }
  let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
  guard descriptor >= 0 else {
    try rollbackCreatedEntry(
      parent: parent,
      name: name,
      flags: AT_REMOVEDIR,
      originalError: TestSafetyDiagnostic(
        code: .directoryOpenFailed,
        message: "The deep-directory Test Fixture could not be opened safely."
      )
    )
  }
  return descriptor
}

private func createFile(name: String, contents: Data, parent: Int32) throws {
  let descriptor = openat(
    parent,
    name,
    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
    0o600
  )
  guard descriptor >= 0 else {
    throw TestSafetyDiagnostic(
      code: .fixtureCreateFailed,
      message: "An ordered-batch Test Fixture file could not be created safely."
    )
  }
  do {
    guard fchmod(descriptor, 0o600) == 0 else {
      throw TestSafetyDiagnostic(
        code: .fixtureCreateFailed,
        message: "An ordered-batch Test Fixture file could not be secured."
      )
    }
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
          throw TestSafetyDiagnostic(
            code: .fixtureWriteFailed,
            message: "An ordered-batch Test Fixture file could not be written."
          )
        }
        offset += written
      }
    }
    close(descriptor)
  } catch {
    close(descriptor)
    try rollbackCreatedEntry(parent: parent, name: name, flags: 0, originalError: error)
  }
}

private func rollbackCreatedEntry(
  parent: Int32,
  name: String,
  flags: Int32,
  originalError: any Error
) throws -> Never {
  guard unlinkat(parent, name, flags) == 0 else {
    throw TestSafetyDiagnostic(
      code: .rollbackFailed,
      message: "An ordered-batch Test Fixture could not be rolled back after setup failed."
    )
  }
  throw originalError
}

private func setMode(_ mode: mode_t, descriptor: Int32, role: String) throws {
  guard fchmod(descriptor, mode) == 0 else {
    throw TestSafetyDiagnostic(
      code: .directoryPermissions,
      message: "The ordered-batch \(role) permissions could not be changed."
    )
  }
}

private func entryExists(at url: URL) -> Bool {
  var status = stat()
  return url.path.withCString { lstat($0, &status) == 0 }
}

private func requireEvidence(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else { throw evidenceFailure(message) }
}

private func evidenceFailure(_ message: String) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(code: .trashEvidenceMismatch, message: message)
}

private func renderAcceptancePath(_ path: String) -> String {
  var result = "\""
  for scalar in path.unicodeScalars {
    switch scalar.value {
    case 0x08: result += "\\b"
    case 0x09: result += "\\t"
    case 0x0A: result += "\\n"
    case 0x0C: result += "\\f"
    case 0x0D: result += "\\r"
    case 0x22: result += "\\\""
    case 0x5C: result += "\\\\"
    case 0x00...0x1F:
      result += String(format: "\\u%04x", scalar.value)
    default:
      result.unicodeScalars.append(scalar)
    }
  }
  result += "\""
  return result
}
