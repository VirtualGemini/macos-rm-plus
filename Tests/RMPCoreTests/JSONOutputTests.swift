// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import RMPCore

@Test("JSON dry-run emits one versioned document with a planned absolute source")
func jsonDryRunEmitsVersionedDocument() {
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: [
      "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 10)))
    ]
  )

  let result = CLIApplication(makeFileSystem: { fileSystem }).run(
    arguments: ["--json", "--dry-run", "report.txt"]
  )
  let expected =
    #"{"dryRun":true,"failed":0,"items":["#
    + #"{"destination":null,"error":null,"kind":"file","#
    + #""source":"/work/report.txt","status":"planned"}"#
    + #"],"moved":0,"operation":"trash","schemaVersion":1,"skipped":0,"success":true}"#
    + "\n"

  #expect(result.exitCode == 0)
  #expect(result.standardError.isEmpty)
  #expect(result.standardOutput == expected)
}

@Test("JSON dry-run preserves every inspected kind and an inaccessible failure")
func jsonDryRunPreservesKinds() throws {
  let entries: [String: FileSystemEntryInspection] = [
    "directory": .entry(.init(kind: .directory, identity: .init(device: 1, inode: 10))),
    "link": .entry(.init(kind: .symbolicLink, identity: .init(device: 1, inode: 11))),
    "broken": .entry(.init(kind: .brokenSymbolicLink, identity: .init(device: 1, inode: 12))),
    "other": .entry(.init(kind: .other, identity: .init(device: 1, inode: 13))),
    "unknown": .entry(.init(kind: .unknown, identity: .init(device: 1, inode: 14))),
    "inaccessible": .inaccessible,
  ]
  let result = CLIApplication(
    makeFileSystem: { FakeTrashPlanningFileSystem(entries: entries) }
  ).run(
    arguments: [
      "--json", "--dry-run", "directory", "link", "broken", "other", "unknown",
      "inaccessible",
    ]
  )
  let document = try jsonObject(result.standardOutput)
  let items = try #require(document["items"] as? [[String: Any]])

  #expect(result.exitCode == 1)
  #expect(document["failed"] as? Int == 1)
  #expect(
    items.map { $0["kind"] as? String } == [
      "directory", "symbolic-link", "broken-symbolic-link", "other", "unknown", "unknown",
    ])
  #expect(
    items.map { $0["status"] as? String } == [
      "planned", "planned", "planned", "planned", "planned", "failed",
    ])
  #expect(result.standardError.contains("inaccessible_input"))
}

@Test("JSON batch contract preserves order, exact receipts, failures, and skipped inputs")
func jsonBatchContractPreservesCompleteOrderedResults() {
  let movedPath = "odd\"\nname"
  let probes = JSONTestProbes(
    results: [
      movedPath: .success(
        .init(destinationPath: "/Users/test/.Trash/final \"name\"\n")
      ),
      "uncertain": .failure(.init(code: .systemTrashFailed)),
    ]
  )
  let entries: [String: FileSystemEntryInspection] = [
    movedPath: .entry(.init(kind: .file, identity: .init(device: 1, inode: 10))),
    "uncertain": .entry(.init(kind: .file, identity: .init(device: 1, inode: 11))),
    "after": .entry(.init(kind: .file, identity: .init(device: 1, inode: 12))),
  ]
  let application = CLIApplication(
    makeFileSystem: { JSONTestFileSystem(entries: entries, probes: probes) },
    makeTrashClient: { JSONTestTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  let result = application.run(
    arguments: [
      "--json", "--confirm=never", "--stop-on-error",
      movedPath, "uncertain", "missing", "after",
    ]
  )
  let expected =
    #"{"dryRun":false,"failed":1,"items":["#
    + #"{"destination":"/Users/test/.Trash/final \"name\"\n","error":null,"kind":"file","#
    + #""source":"/work/odd\"\nname","status":"moved"},"#
    + #"{"destination":null,"error":{"code":"trash_system_call_failed","#
    + #""message":"The system Trash operation failed; "#
    + #"the source entry's final state is uncertain."},"#
    + #""kind":"file","source":"/work/uncertain","status":"failed"},"#
    + #"{"destination":null,"error":null,"kind":"unknown","#
    + #""source":"/work/missing","status":"skipped"},"#
    + #"{"destination":null,"error":null,"kind":"file","#
    + #""source":"/work/after","status":"skipped"}"#
    + #"],"moved":1,"operation":"trash","schemaVersion":1,"skipped":2,"success":false}"#
    + "\n"

  #expect(result.exitCode == 1)
  #expect(result.standardError.contains("trash_system_call_failed"))
  #expect(result.standardError.contains("state_uncertain"))
  #expect(probes.receivedTrashPaths == [movedPath, "uncertain"])
  #expect(result.standardOutput == expected)
}

@Test("JSON keeps compatibility warnings on stderr for TTY and non-TTY input")
func jsonCompatibilityWarningsStayOnStandardError() throws {
  let ttyProbes = JSONTestProbes(results: [:])
  let tty = makeJSONTestApplication(
    paths: ["report.txt"],
    probes: ttyProbes,
    prompt: JSONTestPrompt(isInputTTY: true, response: .answer("yes"))
  ).run(arguments: ["--json", "-P", "--confirm=once", "report.txt"])

  #expect(tty.exitCode == 0)
  #expect(tty.standardError.contains("warning: -P does not securely overwrite"))
  #expect(try jsonObject(tty.standardOutput)["success"] as? Bool == true)

  let nonTTYProbes = JSONTestProbes(results: [:])
  let nonTTY = makeJSONTestApplication(
    paths: ["report.txt"],
    probes: nonTTYProbes,
    prompt: JSONTestPrompt(isInputTTY: false, response: .answer("yes"))
  ).run(arguments: ["--json", "-P", "--confirm=once", "report.txt"])

  #expect(nonTTY.exitCode == 1)
  #expect(nonTTY.standardError.contains("warning: -P does not securely overwrite"))
  #expect(nonTTY.standardError.contains("confirmation_required"))
  #expect(nonTTY.standardOutput.contains("\"code\":\"confirmation_required\""))

  let nonTTYSuccessProbes = JSONTestProbes(results: [:])
  let nonTTYSuccess = makeJSONTestApplication(
    paths: ["report.txt"],
    probes: nonTTYSuccessProbes,
    prompt: JSONTestPrompt(isInputTTY: false, response: .interrupted)
  ).run(arguments: ["--json", "-P", "--confirm=never", "report.txt"])

  #expect(nonTTYSuccess.exitCode == 0)
  #expect(nonTTYSuccess.standardError.contains("warning: -P does not securely overwrite"))
  #expect(try jsonObject(nonTTYSuccess.standardOutput)["success"] as? Bool == true)
}

@Test("Verbose does not alter the JSON schema")
func verboseDoesNotAlterJSONSchema() {
  let standardProbes = JSONTestProbes(results: [:])
  let standard = makeJSONTestApplication(
    paths: ["report.txt"], probes: standardProbes
  ).run(arguments: ["--json", "--confirm=never", "report.txt"])

  let verboseProbes = JSONTestProbes(results: [:])
  let verbose = makeJSONTestApplication(
    paths: ["report.txt"], probes: verboseProbes
  ).run(arguments: ["--json", "--verbose", "--confirm=never", "report.txt"])

  #expect(standard.standardOutput == verbose.standardOutput)
  #expect(standard.standardError == verbose.standardError)
  #expect(standard.exitCode == verbose.exitCode)
}

@Test("A moved item with a Trash Warning keeps its receipt and reports aggregate failure")
func jsonMovedWarningKeepsExactDestination() throws {
  let destination = "/Users/test/.Trash/shortcut"
  let receipt = TrashMoveReceipt(
    destinationPath: destination,
    warnings: [.init(code: .finalizerStateUncertain)]
  )
  let probes = JSONTestProbes(results: ["shortcut": .success(receipt)])
  let result = makeJSONTestApplication(
    paths: ["shortcut"],
    kind: .symbolicLink,
    probes: probes
  ).run(arguments: ["--json", "--confirm=never", "shortcut"])

  let document = try jsonObject(result.standardOutput)
  let items = try #require(document["items"] as? [[String: Any]])
  let item = try #require(items.first)

  #expect(result.exitCode == 1)
  #expect(document["success"] as? Bool == false)
  #expect(document["moved"] as? Int == 1)
  #expect(document["failed"] as? Int == 0)
  #expect(item["status"] as? String == "moved")
  #expect(item["destination"] as? String == destination)
  #expect(result.standardError.contains("finalizer_state_uncertain"))
}

@Test("JSON dry-run distinguishes a missing failure from an ignored missing input")
func jsonDryRunRepresentsMissingPolicies() throws {
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: [
      "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 10)))
    ]
  )
  let application = CLIApplication(makeFileSystem: { fileSystem })

  let failed = application.run(arguments: ["--json", "--dry-run", "missing"])
  let failedDocument = try jsonObject(failed.standardOutput)
  let failedItems = try #require(failedDocument["items"] as? [[String: Any]])

  #expect(failed.exitCode == 1)
  #expect(failedDocument["failed"] as? Int == 1)
  #expect(failedItems.first?["status"] as? String == "failed")
  #expect(failedItems.first?["source"] as? String == "/work/missing")
  #expect(failed.standardError.contains("missing_input"))

  let skipped = application.run(
    arguments: ["--json", "--dry-run", "--ignore-missing", "missing"]
  )
  let skippedDocument = try jsonObject(skipped.standardOutput)
  let skippedItems = try #require(skippedDocument["items"] as? [[String: Any]])

  #expect(skipped.exitCode == 0)
  #expect(skippedDocument["success"] as? Bool == true)
  #expect(skippedDocument["skipped"] as? Int == 1)
  #expect(skippedItems.first?["status"] as? String == "skipped")
  #expect(skipped.standardError.isEmpty)

  let ordered = application.run(
    arguments: ["--json", "--dry-run", "report.txt", "missing"]
  )
  let orderedDocument = try jsonObject(ordered.standardOutput)
  let orderedItems = try #require(orderedDocument["items"] as? [[String: Any]])

  #expect(ordered.exitCode == 1)
  #expect(orderedDocument["failed"] as? Int == 1)
  #expect(orderedItems.map { $0["status"] as? String } == ["planned", "failed"])
  #expect(
    orderedItems.map { $0["source"] as? String } == [
      "/work/report.txt", "/work/missing",
    ])
}

@Test("JSON operation exit categories keep usage and safety semantics")
func jsonOperationExitCategoriesRemainStable() throws {
  let usage = CLIApplication(
    makeFileSystem: { FakeTrashPlanningFileSystem(entries: [:]) }
  ).run(arguments: ["--json", "--quiet", "report.txt"])

  #expect(usage.exitCode == 2)
  #expect(usage.standardOutput.isEmpty)
  #expect(usage.standardError.contains("conflicting options"))

  let root = CLIApplication(
    makeFileSystem: { FakeTrashPlanningFileSystem(entries: [:]) },
    makeTrashClient: { JSONTestTrashClient(probes: JSONTestProbes(results: [:])) },
    effectiveUserID: { 0 },
    currentDirectoryPath: { "/work" }
  ).run(arguments: ["--json", "report.txt"])
  let rootDocument = try jsonObject(root.standardOutput)
  let rootItems = try #require(rootDocument["items"] as? [[String: Any]])

  #expect(root.exitCode == 3)
  #expect(rootDocument["success"] as? Bool == false)
  #expect(rootItems.first?["source"] as? String == "/work/report.txt")
  #expect(
    rootItems.first?["error"] as? [String: String] == [
      "code": "root_execution",
      "message": "Trash Operations cannot run as root.",
    ])
  #expect(root.standardError.contains("root_execution"))
}

@Test("JSON planning failures keep a complete document on stdout")
func jsonPlanningFailuresKeepStandardOutputValid() throws {
  let homeEntry = FileSystemEntryInspection.entry(
    .init(kind: .directory, identity: .init(device: 1, inode: 3))
  )
  let protected = CLIApplication(
    makeFileSystem: {
      FakeTrashPlanningFileSystem(entries: ["home-alias": homeEntry])
    }
  ).run(arguments: ["--json", "--dry-run", "home-alias"])
  let protectedDocument = try jsonObject(protected.standardOutput)
  let protectedItems = try #require(protectedDocument["items"] as? [[String: Any]])

  #expect(protected.exitCode == 3)
  #expect(protectedItems.first?["status"] as? String == "failed")
  #expect(
    protectedItems.first?["error"] as? [String: String] == [
      "code": "protected_path",
      "message": "Protected Path rejected: home-directory.",
    ])
  #expect(protected.standardError.contains("protected_path"))

  let unavailable = CLIApplication(
    makeFileSystem: { JSONSafetyIdentityUnavailableFileSystem() }
  ).run(arguments: ["--json", "--dry-run", "report.txt"])
  let unavailableDocument = try jsonObject(unavailable.standardOutput)
  let unavailableItems = try #require(unavailableDocument["items"] as? [[String: Any]])

  #expect(unavailable.exitCode == 3)
  #expect(
    unavailableItems.first?["error"] as? [String: String] == [
      "code": "safety_identity_unavailable",
      "message": "Safety identity unavailable: home-directory.",
    ])
  #expect(unavailable.standardError.contains("safety_identity_unavailable"))
}

@Test("JSON encoding failures do not emit a partial document")
func jsonEncodingFailuresDoNotEmitPartialOutput() {
  let encoders: [any JSONTrashEncoding] = [
    FailingJSONTrashEncoder(),
    InvalidUTF8JSONTrashEncoder(),
  ]
  let unclassifiedFailure = TrashResult(
    sourcePath: "report.txt",
    destinationPath: nil,
    kind: .file,
    status: .notMoved,
    skipReason: nil,
    warnings: [],
    error: nil
  )

  for encoder in encoders {
    let renderer = JSONTrashRenderer(encoder: encoder)
    let result = renderer.render(
      results: [unclassifiedFailure],
      dryRun: false,
      currentDirectoryPath: "/work"
    )

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("json_encoding_failed"))
  }
}

private final class JSONTestProbes: @unchecked Sendable {
  let results: [String: Result<TrashMoveReceipt, TrashCapabilityError>]
  var receivedTrashPaths: [String] = []

  init(results: [String: Result<TrashMoveReceipt, TrashCapabilityError>]) {
    self.results = results
  }
}

private struct JSONTestFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/test"
  let entries: [String: FileSystemEntryInspection]
  let probes: JSONTestProbes

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    if probes.receivedTrashPaths.contains(path) {
      return .missing
    }
    return entries[path] ?? .missing
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    switch path {
    case "/": .init(device: 1, inode: 1)
    case currentDirectoryPath: .init(device: 1, inode: 2)
    case homeDirectoryPath: .init(device: 1, inode: 3)
    default: nil
    }
  }
}

private struct JSONTestTrashClient: TrashClient {
  let probes: JSONTestProbes

  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    probes.receivedTrashPaths.append(path)
    return try probes.results[path, default: .success(.init(destinationPath: "/Trash/item"))].get()
  }
}

private struct JSONTestPrompt: ConfirmationPrompt {
  let isInputTTY: Bool
  let response: ConfirmationResponse

  func readResponse(prompt _: String) -> ConfirmationResponse {
    response
  }
}

private struct JSONSafetyIdentityUnavailableFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/test"

  func inspectEntry(at _: String) -> FileSystemEntryInspection {
    .entry(.init(kind: .file, identity: .init(device: 1, inode: 70)))
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    switch path {
    case "/": .init(device: 1, inode: 1)
    case currentDirectoryPath: .init(device: 1, inode: 2)
    case homeDirectoryPath: nil
    default: nil
    }
  }
}

private struct FailingJSONTrashEncoder: JSONTrashEncoding {
  func encode(_: JSONTrashOperation) throws -> Data {
    throw JSONTestEncodingError()
  }
}

private struct InvalidUTF8JSONTrashEncoder: JSONTrashEncoding {
  func encode(_: JSONTrashOperation) throws -> Data {
    Data([0xFF])
  }
}

private struct JSONTestEncodingError: Error {}

private func makeJSONTestApplication(
  paths: [String],
  kind: TrashInputKind = .file,
  probes: JSONTestProbes,
  prompt: JSONTestPrompt? = nil
) -> CLIApplication<JSONTestFileSystem> {
  let entries = Dictionary(
    uniqueKeysWithValues: paths.enumerated().map { element in
      let (offset, path) = element
      return (
        path,
        FileSystemEntryInspection.entry(
          .init(kind: kind, identity: .init(device: 1, inode: UInt64(offset + 10)))
        )
      )
    }
  )
  let makeFileSystem = { JSONTestFileSystem(entries: entries, probes: probes) }
  let makeTrashClient = { JSONTestTrashClient(probes: probes) }
  if let prompt {
    return CLIApplication(
      makeFileSystem: makeFileSystem,
      makeTrashClient: makeTrashClient,
      effectiveUserID: { 501 },
      makeConfirmationPrompt: { prompt }
    )
  }
  return CLIApplication(
    makeFileSystem: makeFileSystem,
    makeTrashClient: makeTrashClient,
    effectiveUserID: { 501 }
  )
}

private func jsonObject(_ output: String) throws -> [String: Any] {
  try #require(
    JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
  )
}
