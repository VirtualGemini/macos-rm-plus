// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import rmp_test

@Suite("Manual Put Back race acceptance", .serialized)
struct ManualPutBackRaceAcceptanceTests {
  @Test("refuses to wait when the first Trash left the original path occupied")
  func refusesOccupiedOriginalPath() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var announcements: [String] = []

    let diagnostic = captureDiagnostic {
      _ = try harness.makeWaiter(
        announce: { announcements.append($0) },
        entryProbe: { _ in true },
        changeResponses: []
      ).putBack(harness.firstTrashEvidence, to: harness.sourceURL)
    }

    #expect(diagnostic?.code == .putBackSourceOccupied)
    #expect(announcements.isEmpty)
  }

  @Test("announces the manual instruction once before waiting for the restore")
  func announcesOnceBeforeWaiting() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var events: [String] = []
    var restored = false
    let observePutBack = {
      restored = true
      events.append("finder-put-back")
    }

    let restoredEvidence = try harness.makeWaiter(
      announce: { message in
        events.append(message.contains("Put Back") ? "announce" : "announce-unexpected")
      },
      entryProbe: { _ in
        events.append("probe")
        return restored
      },
      changeResponses: [observePutBack]
    ).putBack(harness.firstTrashEvidence, to: harness.sourceURL)

    #expect(events == ["probe", "announce", "finder-put-back", "probe"])
    #expect(restoredEvidence.returnedURL == harness.sourceURL)
    #expect(restoredEvidence.resourceIdentifier == harness.resourceIdentifier)
  }

  @Test("keeps waiting across change events until the exact entry returns")
  func waitsAcrossUnrelatedChangeEvents() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var restored = false
    var waits = 0

    let restoredEvidence = try harness.makeWaiter(
      entryProbe: { _ in restored },
      changeResponses: [
        { waits += 1 },
        { waits += 1 },
        {
          waits += 1
          restored = true
        },
      ]
    ).putBack(harness.firstTrashEvidence, to: harness.sourceURL)

    #expect(waits == 3)
    #expect(restoredEvidence.returnedURL == harness.sourceURL)
  }

  @Test("fails closed when Put Back is not observed before the deadline")
  func failsClosedOnTimeout() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var elapsed: TimeInterval = 0

    let diagnostic = captureDiagnostic {
      _ = try harness.makeWaiter(
        entryProbe: { _ in false },
        changeResponses: [{ elapsed += 90 }, { elapsed += 90 }, { elapsed += 90 }],
        now: { elapsed }
      ).putBack(harness.firstTrashEvidence, to: harness.sourceURL)
    }

    #expect(diagnostic?.code == .putBackManualTimeout)
  }

  @Test("rejects a restored entry whose resource identity does not match the Trash item")
  func rejectsRestoredIdentityMismatch() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var restored = false

    let diagnostic = captureDiagnostic {
      _ = try harness.makeWaiter(
        resourceIdentifier: { _ in Data("replaced-identity".utf8) },
        entryProbe: { _ in restored },
        changeResponses: [{ restored = true }]
      ).putBack(harness.firstTrashEvidence, to: harness.sourceURL)
    }

    #expect(diagnostic?.code == .putBackEvidenceMismatch)
  }

  @Test("rejects a restore target outside the authorized Test Fixture identity")
  func rejectsUnauthorizedRestoreTarget() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var probes = 0

    let diagnostic = captureDiagnostic {
      _ = try harness.makeWaiter(
        entryProbe: { _ in
          probes += 1
          return false
        },
        changeResponses: []
      ).putBack(
        harness.firstTrashEvidence,
        to: harness.context.runDirectoryURL.appendingPathComponent("unauthorized-name")
      )
    }

    #expect(diagnostic?.code == .putBackEvidenceMismatch)
    #expect(probes == 0)
  }

  @Test("revalidates the context before accepting the restored entry")
  func revalidatesBeforeAcceptingRestore() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var restored = false
    let corruptAuthorizedRoot = {
      restored = true
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: harness.fixture.authorizedRootURL.path
      )
    }

    let diagnostic = captureDiagnostic {
      _ = try harness.makeWaiter(
        entryProbe: { _ in restored },
        changeResponses: [corruptAuthorizedRoot]
      ).putBack(harness.firstTrashEvidence, to: harness.sourceURL)
    }

    #expect(diagnostic?.code == .directoryPermissions)
  }

  @Test("re-trashes immediately after the observed manual restore")
  func reTrashesImmediatelyAfterManualRestore() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var events: [String] = []
    var restored = false
    let secondTrashURL = URL(fileURLWithPath: "/Trash/second-put-back-race")
    var trashEvidence = [
      harness.firstTrashEvidence,
      TrashVerificationEvidence(
        returnedURL: secondTrashURL,
        resourceIdentifier: harness.resourceIdentifier
      ),
    ]
    let observePutBack = {
      restored = true
      events.append("finder-put-back")
    }
    let waiter = harness.makeWaiter(
      announce: { _ in events.append("announce") },
      entryProbe: { _ in restored },
      changeResponses: [observePutBack]
    )
    let operations = PutBackRaceOperations(
      prepare: { _ in
        PutBackRaceTrashSession(sourceURL: harness.sourceURL) {
          let evidence = trashEvidence.removeFirst()
          events.append("trash:\(evidence.returnedURL.lastPathComponent)")
          return evidence
        }
      },
      putBack: waiter.putBack
    )

    let report = try PutBackRaceAcceptance.run(context: harness.context, operations: operations)

    #expect(
      events
        == [
          "trash:first-put-back-race",
          "announce",
          "finder-put-back",
          "trash:second-put-back-race",
        ]
    )
    #expect(report.secondTrashURL == secondTrashURL)
    #expect(report.restoredURL == harness.sourceURL)
  }
}

/// Builds an authorized context whose Test Fixture has already been moved away, mirroring the
/// state right after the first real Trash call.
private struct ManualHarness {
  let fixture: SafetyHomeFixture
  let context: TestSafetyContext
  let sourceURL: URL
  let resourceIdentifier = Data("fixture-identity".utf8)

  init() throws {
    fixture = try SafetyHomeFixture()
    context = try fixture.establishContext()
    sourceURL = context.runDirectoryURL.appendingPathComponent(
      "rmp-test-\(context.runID.uuidString.lowercased())-put-back-race"
    )
  }

  var firstTrashEvidence: TrashVerificationEvidence {
    TrashVerificationEvidence(
      returnedURL: URL(fileURLWithPath: "/Trash/first-put-back-race"),
      resourceIdentifier: resourceIdentifier
    )
  }

  func remove() {
    fixture.remove()
  }

  func makeWaiter(
    announce: @escaping (String) -> Void = { _ in },
    resourceIdentifier: ((URL) throws -> Data?)? = nil,
    entryProbe: @escaping (String) throws -> Bool,
    changeResponses: [() -> Void],
    now: @escaping () -> TimeInterval = { 0 }
  ) -> ManualPutBackWaiter {
    var pending = changeResponses
    let identity = self.resourceIdentifier
    return ManualPutBackWaiter(
      context: context,
      announce: announce,
      resourceIdentifier: resourceIdentifier ?? { _ in identity },
      entryProbe: entryProbe,
      makeWatch: {
        DirectoryChangeWatch(
          waitForChange: { _ in
            guard !pending.isEmpty else { return false }
            pending.removeFirst()()
            return true
          },
          close: {}
        )
      },
      now: now
    )
  }
}
