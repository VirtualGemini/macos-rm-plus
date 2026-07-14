// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("A single Trash Input records the exact system-returned destination")
func singleTrashInputRecordsExactDestination() {
  let identity = FileSystemIdentity(device: 1, inode: 10)
  let fileSystem = ExecutionFileSystem(
    entries: ["report.txt": .entry(.init(kind: .file, identity: identity))]
  )
  let client = TrashClientSpy(
    result: .success(.init(destinationPath: "/Users/test/.Trash/report 2.txt"))
  )
  let executor = SingleTrashExecutor(fileSystem: fileSystem, makeTrashClient: { client })

  let result = executor.execute(
    TrashInput(path: "report.txt", kind: .file, plannedIdentity: identity)
  )

  #expect(client.receivedPaths == ["report.txt"])
  #expect(result.sourcePath == "report.txt")
  #expect(result.destinationPath == "/Users/test/.Trash/report 2.txt")
  #expect(result.kind == .file)
  #expect(result.status == .moved)
  #expect(result.error == nil)
}

@Test("A system Trash failure reports not_moved only when the source identity is unchanged")
func unchangedSourceAfterTrashFailureIsNotMoved() throws {
  let identity = FileSystemIdentity(device: 1, inode: 11)
  let fileSystem = ExecutionFileSystem(
    entries: ["build": .entry(.init(kind: .directory, identity: identity))]
  )
  let client = TrashClientSpy(
    result: .failure(.init(code: .systemTrashFailed))
  )
  let executor = SingleTrashExecutor(fileSystem: fileSystem, makeTrashClient: { client })

  let result = executor.execute(
    TrashInput(path: "build", kind: .directory, plannedIdentity: identity)
  )

  #expect(client.receivedPaths == ["build"])
  #expect(result.destinationPath == nil)
  #expect(result.status == .notMoved)
  #expect(result.error?.code == .systemTrashFailed)
  #expect(try #require(result.error).explanation.contains("source entry is unchanged"))
}

@Test("A system Trash failure reports state_uncertain when the source cannot be confirmed")
func missingSourceAfterTrashFailureIsStateUncertain() throws {
  let identity = FileSystemIdentity(device: 1, inode: 12)
  let client = TrashClientSpy(
    result: .failure(.init(code: .systemTrashFailed))
  )
  let executor = SingleTrashExecutor(
    fileSystem: ExecutionFileSystem(entries: [:]),
    makeTrashClient: { client }
  )

  let result = executor.execute(
    TrashInput(path: "shortcut", kind: .symbolicLink, plannedIdentity: identity)
  )

  #expect(result.status == .stateUncertain)
  #expect(result.error?.code == .systemTrashFailed)
  #expect(try #require(result.error).explanation.contains("final state is uncertain"))
}

@Test("An unsupported top-level entry is rejected before the Trash capability")
func unsupportedEntryIsRejectedBeforeTrashCapability() {
  let identity = FileSystemIdentity(device: 1, inode: 13)
  let fileSystem = ExecutionFileSystem(
    entries: ["pipe": .entry(.init(kind: .other, identity: identity))]
  )
  let client = TrashClientSpy(
    result: .success(.init(destinationPath: "/unused"))
  )
  let executor = SingleTrashExecutor(fileSystem: fileSystem, makeTrashClient: { client })

  let result = executor.execute(
    TrashInput(path: "pipe", kind: .other, plannedIdentity: identity)
  )

  #expect(client.receivedPaths.isEmpty)
  #expect(result.status == .notMoved)
  #expect(result.error?.code == .unsupportedInputKind)
}

@Test("An unexpected Trash capability error maps to the stable system failure code")
func unexpectedTrashCapabilityErrorIsStable() {
  let identity = FileSystemIdentity(device: 1, inode: 14)
  let fileSystem = ExecutionFileSystem(
    entries: ["report.txt": .entry(.init(kind: .file, identity: identity))]
  )
  let executor = SingleTrashExecutor(
    fileSystem: fileSystem,
    makeTrashClient: { UnexpectedTrashClient() }
  )

  let result = executor.execute(
    TrashInput(path: "report.txt", kind: .file, plannedIdentity: identity)
  )

  #expect(result.status == .notMoved)
  #expect(result.error?.code == .systemTrashFailed)
}

private struct ExecutionFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/test"
  let entries: [String: FileSystemEntryInspection]

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    entries[path] ?? .missing
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    guard case let .entry(entry) = entries[path] else { return nil }
    return entry.identity
  }
}

private final class TrashClientSpy: TrashClient, @unchecked Sendable {
  private(set) var receivedPaths: [String] = []
  private let result: Result<TrashMoveReceipt, TrashCapabilityError>

  init(result: Result<TrashMoveReceipt, TrashCapabilityError>) {
    self.result = result
  }

  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    receivedPaths.append(path)
    return try result.get()
  }
}

private struct UnexpectedTrashClient: TrashClient {
  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    throw UnexpectedTrashError()
  }
}

private struct UnexpectedTrashError: Error {}
