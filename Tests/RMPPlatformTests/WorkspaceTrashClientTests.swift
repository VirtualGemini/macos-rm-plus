// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

// swift-format and SwiftLint disagree on testable-import ordering for the lowercase module name.
// swiftlint:disable sorted_imports
@testable import RMPCore
@testable import RMPPlatform
@testable import rmp_test

// swiftlint:enable sorted_imports

@Test("Workspace Trash client preserves the exact system destination")
func workspaceTrashClientPreservesSystemDestination() throws {
  let returnedURL = URL(fileURLWithPath: "/Users/test/.Trash/link 2")
  let spy = WorkspaceTrashSpy(result: .success(returnedURL))
  let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)

  let receipt = try client.trashItem(atPath: "/work/link")

  #expect(spy.receivedURLBatches.map { $0.map(\.path) } == [["/work/link"]])
  #expect(receipt.destinationPath == "/Users/test/.Trash/link 2")
}

@Test("Workspace Trash client waits for the system completion")
func workspaceTrashClientWaitsForSystemCompletion() throws {
  let returnedURL = URL(fileURLWithPath: "/Users/test/.Trash/report")
  let spy = WorkspaceTrashSpy(result: .success(returnedURL), deliversAsynchronously: true)
  let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)

  let receipt = try client.trashItem(atPath: "/work/report")

  #expect(receipt.destinationPath == "/Users/test/.Trash/report")
}

@Test("Workspace Trash failure leaves an authorized Test Fixture unchanged")
func workspaceTrashFailureHasNoDestructiveFallback() throws {
  let fixture = try SafetyHomeFixture()
  defer { fixture.remove() }
  let context = try fixture.establishContext()
  let target = context.runDirectoryURL.appendingPathComponent(
    "rmp-test-\(context.runID.uuidString.lowercased())-failure"
  )
  try Data("fixture".utf8).write(to: target)
  let before = try fixture.snapshot()
  let spy = WorkspaceTrashSpy(result: .failure(InjectedWorkspaceTrashFailure()))
  let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)

  do {
    _ = try client.trashItem(atPath: target.path)
    Issue.record("Expected the injected system Trash failure to be reported")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .systemTrashFailed)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }

  #expect(spy.receivedURLBatches.map { $0.map(\.path) } == [[target.path]])
  #expect(try fixture.snapshot() == before)
  #expect(FileManager.default.fileExists(atPath: target.path))
}

@Test("Workspace Trash completion without a destination reports failure")
func workspaceTrashCompletionRequiresDestination() {
  let spy = WorkspaceTrashSpy(result: .missingDestination)
  let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)

  do {
    _ = try client.trashItem(atPath: "/work/report")
    Issue.record("Expected a missing system destination to be reported")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .systemTrashFailed)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }

  #expect(spy.receivedURLBatches.map { $0.map(\.path) } == [["/work/report"]])
}

@Test("Workspace Trash client rejects a destination mapped from another source")
func workspaceTrashClientRequiresSourceSpecificDestination() {
  let spy = WorkspaceTrashSpy(
    result: .unrelatedDestination(
      source: URL(fileURLWithPath: "/work/other"),
      destination: URL(fileURLWithPath: "/Users/test/.Trash/other")
    )
  )
  let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)

  do {
    _ = try client.trashItem(atPath: "/work/report")
    Issue.record("Expected an unrelated system destination to be rejected")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .systemTrashFailed)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }
}

@Test("Workspace Trash client preserves protected and broken symlink entry URLs")
func workspaceTrashClientDoesNotResolveSymlinkDestinations() throws {
  let fixture = try SafetyHomeFixture()
  defer { fixture.remove() }
  let context = try fixture.establishContext()
  let prefix = "rmp-test-\(context.runID.uuidString.lowercased())-"
  let protectedLink = context.runDirectoryURL.appendingPathComponent("\(prefix)root-link")
  let brokenLink = context.runDirectoryURL.appendingPathComponent("\(prefix)broken-link")
  try FileManager.default.createSymbolicLink(
    at: protectedLink,
    withDestinationURL: URL(fileURLWithPath: "/", isDirectory: true)
  )
  try FileManager.default.createSymbolicLink(
    at: brokenLink,
    withDestinationURL: context.runDirectoryURL.appendingPathComponent("missing-destination")
  )
  let before = try fixture.snapshot()
  let spy = WorkspaceTrashSpy(
    result: .success(context.runDirectoryURL.appendingPathComponent("trashed-link"))
  )
  let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)

  _ = try client.trashItem(atPath: protectedLink.path)
  _ = try client.trashItem(atPath: brokenLink.path)

  #expect(
    spy.receivedURLBatches.map { $0.map(\.path) }
      == [[protectedLink.path], [brokenLink.path]]
  )
  #expect(try fixture.snapshot() == before)
  #expect(FileManager.default.fileExists(atPath: "/"))
}

@Test("Protected and broken symlink destinations never replace the top-level Trash entry")
func symlinkDestinationsAreNeverExecuted() throws {
  let fixture = try SafetyHomeFixture()
  defer { fixture.remove() }
  let context = try fixture.establishContext()
  let prefix = "rmp-test-\(context.runID.uuidString.lowercased())-"
  let protectedLink = context.runDirectoryURL.appendingPathComponent("\(prefix)root-link")
  let brokenLink = context.runDirectoryURL.appendingPathComponent("\(prefix)broken-link")
  try FileManager.default.createSymbolicLink(
    at: protectedLink,
    withDestinationURL: URL(fileURLWithPath: "/", isDirectory: true)
  )
  try FileManager.default.createSymbolicLink(
    at: brokenLink,
    withDestinationURL: context.runDirectoryURL.appendingPathComponent("missing-destination")
  )
  let before = try fixture.snapshot()
  let spy = CoreTrashClientSpy()
  let application = CLIApplication(
    makeFileSystem: { FoundationTrashPlanningFileSystem() },
    makeTrashClient: { spy },
    effectiveUserID: { 501 }
  )

  #expect(application.run(arguments: [protectedLink.path]).exitCode == 0)
  #expect(application.run(arguments: [brokenLink.path]).exitCode == 0)

  #expect(spy.receivedPaths == [protectedLink.path, brokenLink.path])
  #expect(try fixture.snapshot() == before)
  #expect(FileManager.default.fileExists(atPath: "/"))
}

private final class WorkspaceTrashSpy: @unchecked Sendable {
  private(set) var receivedURLBatches: [[URL]] = []
  private let result: WorkspaceTrashSpyResult
  private let deliversAsynchronously: Bool

  init(result: WorkspaceTrashSpyResult, deliversAsynchronously: Bool = false) {
    self.result = result
    self.deliversAsynchronously = deliversAsynchronously
  }

  func call(
    _ urls: [URL],
    _ completion: @escaping @Sendable ([URL: URL], (any Error)?) -> Void
  ) {
    receivedURLBatches.append(urls)
    let deliver: @Sendable () -> Void = { [result] in
      switch result {
      case let .success(returnedURL):
        completion(Dictionary(uniqueKeysWithValues: urls.map { ($0, returnedURL) }), nil)
      case let .failure(error):
        completion([:], error)
      case .missingDestination:
        completion([:], nil)
      case let .unrelatedDestination(source, destination):
        completion([source: destination], nil)
      }
    }
    if deliversAsynchronously {
      DispatchQueue.global().async(execute: deliver)
    } else {
      deliver()
    }
  }
}

private enum WorkspaceTrashSpyResult: @unchecked Sendable {
  case success(URL)
  case failure(any Error)
  case missingDestination
  case unrelatedDestination(source: URL, destination: URL)
}

private struct InjectedWorkspaceTrashFailure: Error {}

private final class CoreTrashClientSpy: TrashClient, @unchecked Sendable {
  private(set) var receivedPaths: [String] = []

  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    receivedPaths.append(path)
    return TrashMoveReceipt(
      destinationPath: "/Trash/\(URL(fileURLWithPath: path).lastPathComponent)"
    )
  }
}
