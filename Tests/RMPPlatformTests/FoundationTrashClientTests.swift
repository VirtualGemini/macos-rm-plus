// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

// swift-format and SwiftLint disagree on testable-import ordering for the lowercase module name.
// swiftlint:disable sorted_imports
@testable import RMPCore
@testable import RMPPlatform
@testable import rmp_test

// swiftlint:enable sorted_imports

@Test("Foundation Trash client passes one top-level URL and preserves the returned path")
func foundationTrashClientPreservesSystemDestination() throws {
  let returnedURL = URL(fileURLWithPath: "/Users/test/.Trash/link 2")
  let spy = FoundationTrashSpy(result: .success(returnedURL))
  let client = FoundationTrashClient(systemTrash: spy.call)

  let receipt = try client.trashItem(atPath: "/work/link")

  #expect(spy.receivedURLs.map(\.path) == ["/work/link"])
  #expect(receipt.destinationPath == "/Users/test/.Trash/link 2")
}

@Test("Production Foundation Trash client construction performs no filesystem operation")
func productionFoundationTrashClientConstructionIsInert() {
  _ = FoundationTrashClient()
}

@Test("Foundation Trash failure leaves an authorized Test Fixture unchanged")
func foundationTrashFailureHasNoDestructiveFallback() throws {
  let fixture = try SafetyHomeFixture()
  defer { fixture.remove() }
  let context = try fixture.establishContext()
  let target = context.runDirectoryURL.appendingPathComponent(
    "rmp-test-\(context.runID.uuidString.lowercased())-failure"
  )
  try Data("fixture".utf8).write(to: target)
  let before = try fixture.snapshot()
  let spy = FoundationTrashSpy(result: .failure(InjectedFoundationTrashFailure()))
  let client = FoundationTrashClient(systemTrash: spy.call)

  do {
    _ = try client.trashItem(atPath: target.path)
    Issue.record("Expected the injected system Trash failure to be reported")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .systemTrashFailed)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }

  #expect(spy.receivedURLs.map(\.path) == [target.path])
  #expect(try fixture.snapshot() == before)
  #expect(FileManager.default.fileExists(atPath: target.path))
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

private final class FoundationTrashSpy: @unchecked Sendable {
  private(set) var receivedURLs: [URL] = []
  private let result: Result<URL, InjectedFoundationTrashFailure>

  init(result: Result<URL, InjectedFoundationTrashFailure>) {
    self.result = result
  }

  func call(_ url: URL) throws -> URL {
    receivedURLs.append(url)
    return try result.get()
  }
}

private struct InjectedFoundationTrashFailure: Error {}

private final class CoreTrashClientSpy: TrashClient, @unchecked Sendable {
  private(set) var receivedPaths: [String] = []

  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    receivedPaths.append(path)
    return TrashMoveReceipt(
      destinationPath: "/Trash/\(URL(fileURLWithPath: path).lastPathComponent)")
  }
}
