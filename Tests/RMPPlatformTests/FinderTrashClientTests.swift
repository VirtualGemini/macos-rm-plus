// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

// swift-format and SwiftLint disagree on testable-import ordering for the lowercase module name.
// swiftlint:disable sorted_imports
@testable import RMPCore
@testable import RMPPlatform
@testable import rmp_test

// swiftlint:enable sorted_imports

@Test("Finder Trash client preserves the exact destination returned by Finder")
func finderTrashClientPreservesFinderDestination() throws {
  let returnedURL = URL(fileURLWithPath: "/Users/test/.Trash/report 2.txt")
  let spy = FinderTrashSpy(result: .success(returnedURL))
  let client = makeInjectedFinderTrashClient(finderDelete: spy.call)

  let receipt = try client.trashItem(atPath: "/work/report.txt")

  #expect(spy.receivedURLs.map(\.path) == ["/work/report.txt"])
  #expect(receipt.destinationPath == "/Users/test/.Trash/report 2.txt")
}

@Test("Finder Automation denial reports a stable error code")
func finderTrashClientReportsAutomationDenial() {
  let client = makeInjectedFinderTrashClient { _ in
    throw FinderTrashClientFailure.automationDenied
  }

  do {
    _ = try client.trashItem(atPath: "/work/report.txt")
    Issue.record("Expected Finder Automation denial to be reported")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .finderAutomationDenied)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }
}

@Test("Unexpected Finder boundary errors map to the generic system failure")
func finderTrashClientMapsUnexpectedFailure() {
  let client = makeInjectedFinderTrashClient { _ in throw InjectedFinderTrashFailure() }

  do {
    _ = try client.trashItem(atPath: "/work/report.txt")
    Issue.record("Expected the unexpected Finder failure to be reported")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .systemTrashFailed)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }
}

@Test("Finder boundary failures retain actionable stable error codes")
func finderTrashClientReportsActionableFailures() {
  let testCases: [(FinderTrashClientFailure, TrashErrorCode)] = [
    (.automationConsentRequired, .finderAutomationConsentRequired),
    (.finderUnavailable, .finderUnavailable),
    (.timedOut, .finderAutomationTimedOut),
  ]

  for (failure, expectedCode) in testCases {
    let client = makeInjectedFinderTrashClient { _ in throw failure }

    do {
      _ = try client.trashItem(atPath: "/work/report.txt")
      Issue.record("Expected Finder boundary failure to be reported")
    } catch let error as TrashCapabilityError {
      #expect(error.code == expectedCode)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }
  }
}

@Test("Finder script bridge passes path text as a structured argument")
func finderTrashClientUsesStructuredScriptArguments() throws {
  let sourcePath = "/work/name with \"quotes\" and newline\nvalue"
  let spy = FinderScriptSpy(
    result: .success("file:///Users/test/.Trash/name%20with%20quotes")
  )
  let client = makeInjectedFinderTrashClient(scriptExecute: spy.call)

  let receipt = try client.trashItem(atPath: sourcePath)

  #expect(
    spy.invocations
      == [FinderScriptInvocation(handlerName: "trashItem", arguments: [sourcePath])]
  )
  #expect(receipt.destinationPath == "/Users/test/.Trash/name with quotes")
}

@Test("Finder script executor passes structured arguments through the local AppleScript engine")
func finderTrashClientExecutesStructuredLocalScript() throws {
  let scriptSource = """
    on trashItem(sourcePath)
      if sourcePath is not "/work/report.txt" then error number -1
      return "file:///Users/test/.Trash/report%202.txt"
    end trashItem
    """
  let client = makeInjectedFinderTrashClient(scriptSource: scriptSource)

  let receipt = try client.trashItem(atPath: "/work/report.txt")

  #expect(receipt.destinationPath == "/Users/test/.Trash/report 2.txt")
}

@Test("Finder script executor maps local compile and execution failures")
func finderTrashClientMapsLocalScriptFailures() {
  let testCases: [(String, TrashErrorCode)] = [
    ("on", .systemTrashFailed),
    (
      """
      on trashItem(sourcePath)
        error number -1743
      end trashItem
      """,
      .finderAutomationDenied
    ),
    (
      """
      on trashItem(sourcePath)
        return missing value
      end trashItem
      """,
      .systemTrashFailed
    ),
  ]

  for (scriptSource, expectedCode) in testCases {
    let client = makeInjectedFinderTrashClient(scriptSource: scriptSource)

    do {
      _ = try client.trashItem(atPath: "/work/report.txt")
      Issue.record("Expected the local Finder script failure to be reported")
    } catch let error as TrashCapabilityError {
      #expect(error.code == expectedCode)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }
  }
}

@Test("Finder Trash reports an unavailable AppleScript engine as a system failure")
func finderTrashClientReportsUnavailableScriptEngine() {
  let client = makeInjectedFinderTrashClient(
    scriptSource: "return 1",
    makeScript: { _ in nil }
  )

  do {
    _ = try client.trashItem(atPath: "/work/report.txt")
    Issue.record("Expected the unavailable AppleScript engine to be reported")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .systemTrashFailed)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }
}

@Test("Finder Apple Event status numbers map to stable Trash errors")
func finderTrashClientMapsAppleEventErrors() {
  let testCases: [(Int?, TrashErrorCode)] = [
    (-1744, .finderAutomationConsentRequired),
    (-1743, .finderAutomationDenied),
    (-1712, .finderAutomationTimedOut),
    (-600, .finderUnavailable),
    (-1, .systemTrashFailed),
    (nil, .systemTrashFailed),
  ]

  for (errorNumber, expectedCode) in testCases {
    let client = makeInjectedFinderTrashClient { _ in
      .failure(errorNumber: errorNumber)
    }

    do {
      _ = try client.trashItem(atPath: "/work/report.txt")
      Issue.record("Expected Finder Apple Event failure to be reported")
    } catch let error as TrashCapabilityError {
      #expect(error.code == expectedCode)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }
  }
}

@Test("Finder Trash rejects a non-file destination")
func finderTrashClientRequiresFileDestination() {
  let client = makeInjectedFinderTrashClient { _ in .success("not a file URL") }

  do {
    _ = try client.trashItem(atPath: "/work/report.txt")
    Issue.record("Expected an invalid Finder destination to be reported")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .systemTrashFailed)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }
}

@Test("Finder Trash failure leaves an authorized Test Fixture unchanged")
func finderTrashFailureHasNoDestructiveFallback() throws {
  let fixture = try SafetyHomeFixture()
  defer { fixture.remove() }
  let context = try fixture.establishContext()
  let target = context.runDirectoryURL.appendingPathComponent(
    "rmp-test-\(context.runID.uuidString.lowercased())-failure"
  )
  try Data("fixture".utf8).write(to: target)
  let before = try fixture.snapshot()
  let client = makeInjectedFinderTrashClient { _ in
    throw FinderTrashClientFailure.automationDenied
  }

  do {
    _ = try client.trashItem(atPath: target.path)
    Issue.record("Expected Finder Trash failure to be reported")
  } catch let error as TrashCapabilityError {
    #expect(error.code == .finderAutomationDenied)
  } catch {
    Issue.record("Expected a stable TrashCapabilityError")
  }

  #expect(try fixture.snapshot() == before)
  #expect(FileManager.default.fileExists(atPath: target.path))
}

@Test("Finder Trash preserves protected and broken symlink entry paths")
func finderTrashClientDoesNotResolveSymlinkDestinations() throws {
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
  let spy = FinderTrashSpy(
    result: .success(context.runDirectoryURL.appendingPathComponent("trashed-link"))
  )
  let client = makeInjectedFinderTrashClient(finderDelete: spy.call)

  _ = try client.trashItem(atPath: protectedLink.path)
  _ = try client.trashItem(atPath: brokenLink.path)

  #expect(spy.receivedURLs.map(\.path) == [protectedLink.path, brokenLink.path])
  #expect(try fixture.snapshot() == before)
  #expect(FileManager.default.fileExists(atPath: "/"))
}

private final class FinderTrashSpy: @unchecked Sendable {
  private(set) var receivedURLs: [URL] = []
  private let result: Result<URL, any Error>

  init(result: Result<URL, any Error>) {
    self.result = result
  }

  func call(_ sourceURL: URL) throws -> URL {
    receivedURLs.append(sourceURL)
    return try result.get()
  }
}

private final class FinderScriptSpy: @unchecked Sendable {
  private(set) var invocations: [FinderScriptInvocation] = []
  private let result: FinderScriptResult

  init(result: FinderScriptResult) {
    self.result = result
  }

  func call(_ invocation: FinderScriptInvocation) -> FinderScriptResult {
    invocations.append(invocation)
    return result
  }
}

private struct InjectedFinderTrashFailure: Error {}
