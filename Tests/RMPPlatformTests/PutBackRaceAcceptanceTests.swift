// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@testable import rmp_test

@Suite("Put Back race acceptance safety", .serialized)
struct PutBackRaceAcceptanceSafetyTests {
  @Test("preserves the validated Run Directory for manual Finder inspection")
  func preservesRunDirectoryForManualInspection() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let runID = UUID()

    let result = TestSafetyDriver.run(
      arguments: ["--test-run-id", runID.uuidString.lowercased()],
      runtime: .testing(executableName: "rmp-test", trustedUser: fixture.trustedUser),
      cleanupPolicy: .preserveRunDirectory,
      operation: { _, _ in 0 }
    )

    let runDirectory = fixture.runDirectoryURL(for: runID)
    #expect(result.exitCode == 0)
    #expect(result.diagnostic == nil)
    #expect(FileManager.default.fileExists(atPath: runDirectory.path))
    #expect(
      FileManager.default.fileExists(
        atPath: runDirectory.appendingPathComponent(".rmp-test-run").path))
  }

  @Test("creates the race fixture exclusively with the required run prefix and permissions")
  func createsAuthorizedRaceFixture() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let originalMask = umask(0o777)
    defer { umask(originalMask) }

    let fixtureURL = try context.createFixtureFile(
      suffix: "put-back-race",
      contents: Data("current-race-content".utf8)
    )

    #expect(
      fixtureURL.lastPathComponent
        == "rmp-test-\(context.runID.uuidString.lowercased())-put-back-race"
    )
    #expect(fixtureURL.deletingLastPathComponent() == context.runDirectoryURL)
    #expect(fileMode(at: fixtureURL) == 0o600)
    #expect(try Data(contentsOf: fixtureURL) == Data("current-race-content".utf8))
  }

  @Test("puts back only the exact returned Trash item after revalidating the context")
  func putsBackExactTrashEvidence() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = try context.createFixtureFile(
      suffix: "put-back-race",
      contents: Data("current-race-content".utf8)
    )
    let fakeTrashDirectory = fixture.homeURL.appendingPathComponent("Trash", isDirectory: true)
    try FileManager.default.createDirectory(
      at: fakeTrashDirectory,
      withIntermediateDirectories: false
    )
    let trashURL = fakeTrashDirectory.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: trashURL)
    let resourceIdentifier = Data("fixture-identity".utf8)
    let spy = PutBackSpy(returnedURL: sourceURL)
    let client = WhitelistedPutBackClient(
      context: context,
      resourceIdentifier: { _ in resourceIdentifier },
      systemPutBack: spy.call
    )

    let restored = try client.putBack(
      TrashVerificationEvidence(
        returnedURL: trashURL,
        resourceIdentifier: resourceIdentifier
      ),
      to: sourceURL
    )

    #expect(
      spy.receivedMoves == [PutBackMove(sourceURL: trashURL, destination: context.runDirectoryURL)])
    #expect(
      restored
        == PutBackVerificationEvidence(
          returnedURL: sourceURL,
          resourceIdentifier: resourceIdentifier
        )
    )
  }

  @Test("revalidates the complete context immediately before Finder Put Back")
  func revalidatesImmediatelyBeforePutBack() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = try context.createFixtureFile(
      suffix: "put-back-race",
      contents: Data("current-race-content".utf8)
    )
    let fakeTrashDirectory = fixture.homeURL.appendingPathComponent("Trash", isDirectory: true)
    try FileManager.default.createDirectory(
      at: fakeTrashDirectory,
      withIntermediateDirectories: false
    )
    let trashURL = fakeTrashDirectory.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: trashURL)
    let resourceIdentifier = Data("fixture-identity".utf8)
    let spy = PutBackSpy(returnedURL: sourceURL)
    var inspectionCount = 0
    let client = WhitelistedPutBackClient(
      context: context,
      resourceIdentifier: { _ in
        inspectionCount += 1
        if inspectionCount == 1 {
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fixture.authorizedRootURL.path
          )
        }
        return resourceIdentifier
      },
      systemPutBack: spy.call
    )

    let diagnostic = captureDiagnostic {
      _ = try client.putBack(
        TrashVerificationEvidence(
          returnedURL: trashURL,
          resourceIdentifier: resourceIdentifier
        ),
        to: sourceURL
      )
    }

    #expect(diagnostic?.code == .directoryPermissions)
    #expect(spy.receivedMoves.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
    #expect(FileManager.default.fileExists(atPath: trashURL.path))
  }

  @Test("rejects an occupied restore path without a Finder Put Back call")
  func rejectsOccupiedRestorePath() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = try context.createFixtureFile(
      suffix: "put-back-race",
      contents: Data("occupied".utf8)
    )
    let trashURL = URL(fileURLWithPath: "/Trash/\(sourceURL.lastPathComponent)")
    let resourceIdentifier = Data("fixture-identity".utf8)
    let spy = PutBackSpy(returnedURL: sourceURL)
    let client = WhitelistedPutBackClient(
      context: context,
      resourceIdentifier: { _ in resourceIdentifier },
      systemPutBack: spy.call
    )

    let diagnostic = captureDiagnostic {
      _ = try client.putBack(
        TrashVerificationEvidence(
          returnedURL: trashURL,
          resourceIdentifier: resourceIdentifier
        ),
        to: sourceURL
      )
    }

    #expect(diagnostic?.code == .putBackSourceOccupied)
    #expect(spy.receivedMoves.isEmpty)
    #expect(try Data(contentsOf: sourceURL) == Data("occupied".utf8))
  }

  @Test("rejects changed Trash evidence without a Finder Put Back call")
  func rejectsChangedTrashEvidence() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = context.runDirectoryURL.appendingPathComponent(
      "rmp-test-\(context.runID.uuidString.lowercased())-put-back-race"
    )
    let trashURL = URL(fileURLWithPath: "/Trash/\(sourceURL.lastPathComponent)")
    let spy = PutBackSpy(returnedURL: sourceURL)
    let client = WhitelistedPutBackClient(
      context: context,
      resourceIdentifier: { _ in Data("changed-identity".utf8) },
      systemPutBack: spy.call
    )

    let diagnostic = captureDiagnostic {
      _ = try client.putBack(
        TrashVerificationEvidence(
          returnedURL: trashURL,
          resourceIdentifier: Data("planned-identity".utf8)
        ),
        to: sourceURL
      )
    }

    #expect(diagnostic?.code == .putBackEvidenceMismatch)
    #expect(spy.receivedMoves.isEmpty)
  }
}

@Suite("Put Back race acceptance sequence", .serialized)
struct PutBackRaceAcceptanceSequenceTests {
  @Test("passes the exact Trash URL and Run Directory as structured script arguments")
  func usesStructuredFinderPutBackArguments() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = context.runDirectoryURL.appendingPathComponent(
      "rmp-test-\(context.runID.uuidString.lowercased())-name with \"quotes\" and newline\nvalue"
    )
    let trashURL = URL(
      fileURLWithPath: "/Trash/\(sourceURL.lastPathComponent)"
    )
    let resourceIdentifier = Data("fixture-identity".utf8)
    let scriptSpy = PutBackScriptSpy(result: .success(sourceURL.absoluteString))
    let client = WhitelistedPutBackClient(
      context: context,
      resourceIdentifier: { _ in resourceIdentifier },
      scriptExecute: scriptSpy.call
    )

    _ = try client.putBack(
      TrashVerificationEvidence(
        returnedURL: trashURL,
        resourceIdentifier: resourceIdentifier
      ),
      to: sourceURL
    )

    let expectedInvocation = FinderPutBackScriptInvocation(
      handlerName: "putBackItem",
      arguments: [trashURL.path, context.runDirectoryURL.path]
    )
    #expect(scriptSpy.invocations == [expectedInvocation])
  }

  @Test("executes both Put Back paths through the local structured AppleScript bridge")
  func executesStructuredLocalPutBackScript() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = context.runDirectoryURL.appendingPathComponent(
      "rmp-test-\(context.runID.uuidString.lowercased())-put-back-race"
    )
    let trashURL = URL(fileURLWithPath: "/Trash/\(sourceURL.lastPathComponent)")
    let resourceIdentifier = Data("fixture-identity".utf8)
    let scriptSource = """
      on putBackItem(trashedPath, destinationPath)
        if trashedPath is not "\(trashURL.path)" then error number -1
        if destinationPath is not "\(context.runDirectoryURL.path)" then error number -2
        return "\(sourceURL.absoluteString)"
      end putBackItem
      """
    let client = WhitelistedPutBackClient(
      context: context,
      resourceIdentifier: { _ in resourceIdentifier },
      scriptSource: scriptSource
    )

    let restored = try client.putBack(
      TrashVerificationEvidence(
        returnedURL: trashURL,
        resourceIdentifier: resourceIdentifier
      ),
      to: sourceURL
    )

    #expect(restored.returnedURL == sourceURL)
  }

  @Test("trashes, restores the exact item, and immediately trashes it again")
  func performsOneSynchronousRaceSequence() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = context.runDirectoryURL.appendingPathComponent(
      "rmp-test-\(context.runID.uuidString.lowercased())-put-back-race"
    )
    let firstTrashURL = URL(fileURLWithPath: "/Trash/first-put-back-race")
    let secondTrashURL = URL(fileURLWithPath: "/Trash/second-put-back-race")
    let resourceIdentifier = Data("fixture-identity".utf8)
    var events: [String] = []
    var trashEvidence = makeTrashEvidence(
      firstURL: firstTrashURL,
      secondURL: secondTrashURL,
      resourceIdentifier: resourceIdentifier
    )
    let operations = PutBackRaceOperations(
      prepare: { receivedContext in
        #expect(receivedContext === context)
        events.append("prepare")
        return PutBackRaceTrashSession(sourceURL: sourceURL) {
          let evidence = trashEvidence.removeFirst()
          events.append("trash:\(evidence.returnedURL.lastPathComponent)")
          return evidence
        }
      },
      putBack: { evidence, expectedSourceURL in
        #expect(evidence.returnedURL == firstTrashURL)
        #expect(expectedSourceURL == sourceURL)
        events.append("put-back:\(evidence.returnedURL.lastPathComponent)")
        return PutBackVerificationEvidence(
          returnedURL: sourceURL,
          resourceIdentifier: resourceIdentifier
        )
      },
      finalize: { events.append("finalize") }
    )

    let report = try PutBackRaceAcceptance.run(context: context, operations: operations)

    #expect(
      events
        == [
          "prepare",
          "trash:first-put-back-race",
          "put-back:first-put-back-race",
          "trash:second-put-back-race",
          "finalize",
        ]
    )
    #expect(
      report
        == PutBackRaceReport(
          sourceURL: sourceURL,
          firstTrashURL: firstTrashURL,
          restoredURL: sourceURL,
          secondTrashURL: secondTrashURL,
          settleSeconds: 0
        )
    )
  }

  @Test("uses a dedicated production retrash operation only after Put Back")
  func usesDedicatedProductionRetrash() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = context.runDirectoryURL.appendingPathComponent("production-retrash")
    let firstTrashURL = URL(fileURLWithPath: "/Trash/first")
    let secondTrashURL = URL(fileURLWithPath: "/Trash/second")
    var events: [String] = []
    let operations = PutBackRaceOperations(
      prepare: { _ in
        PutBackRaceTrashSession(
          sourceURL: sourceURL,
          trash: {
            events.append("foundation-control")
            return TrashVerificationEvidence(returnedURL: firstTrashURL, resourceIdentifier: nil)
          },
          retrash: {
            events.append("production-finalizer")
            return TrashVerificationEvidence(returnedURL: secondTrashURL, resourceIdentifier: nil)
          }
        )
      },
      putBack: { _, _ in
        events.append("put-back")
        return PutBackVerificationEvidence(returnedURL: sourceURL, resourceIdentifier: nil)
      }
    )

    let report = try PutBackRaceAcceptance.run(context: context, operations: operations)

    #expect(events == ["foundation-control", "put-back", "production-finalizer"])
    #expect(report.firstTrashURL == firstTrashURL)
    #expect(report.secondTrashURL == secondTrashURL)
  }
}

private func makeTrashEvidence(
  firstURL: URL,
  secondURL: URL,
  resourceIdentifier: Data
) -> [TrashVerificationEvidence] {
  [firstURL, secondURL].map {
    TrashVerificationEvidence(returnedURL: $0, resourceIdentifier: resourceIdentifier)
  }
}

private struct PutBackMove: Equatable {
  let sourceURL: URL
  let destination: URL
}

private final class PutBackSpy {
  private(set) var receivedMoves: [PutBackMove] = []
  private let returnedURL: URL

  init(returnedURL: URL) {
    self.returnedURL = returnedURL
  }

  func call(sourceURL: URL, destination: URL) throws -> URL {
    receivedMoves.append(PutBackMove(sourceURL: sourceURL, destination: destination))
    try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
    return returnedURL
  }
}

private final class PutBackScriptSpy {
  private(set) var invocations: [FinderPutBackScriptInvocation] = []
  private let result: FinderPutBackScriptResult

  init(result: FinderPutBackScriptResult) {
    self.result = result
  }

  func call(_ invocation: FinderPutBackScriptInvocation) -> FinderPutBackScriptResult {
    invocations.append(invocation)
    return result
  }
}
