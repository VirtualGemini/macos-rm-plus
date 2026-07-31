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

@Suite("Manual Put Back race pacing", .serialized)
struct ManualPutBackRacePacingTests {
  @Test("reports the remaining window every five seconds and each of the final five")
  func reportsCountdownWindow() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var elapsed: TimeInterval = 0
    var restored = false
    var reported: [Int] = []
    let advanceOneSecond = {
      elapsed += 1
      if elapsed >= 9 { restored = true }
    }

    _ = try harness.makeWaiter(
      heartbeat: { reported.append($0) },
      timeout: 12,
      entryProbe: { _ in restored },
      changeResponses: Array(repeating: advanceOneSecond, count: 9),
      now: { elapsed }
    ).putBack(harness.firstTrashEvidence, to: harness.sourceURL)

    #expect(reported == [10, 5, 4])
  }

  @Test("applies the declared re-trash delay between the restore and the second Trash")
  func appliesDeclaredSettleDelay() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var events: [String] = []
    var restored = false
    var trashEvidence = [
      harness.firstTrashEvidence,
      TrashVerificationEvidence(
        returnedURL: URL(fileURLWithPath: "/Trash/second-put-back-race"),
        resourceIdentifier: harness.resourceIdentifier
      ),
    ]
    let observePutBack = { restored = true }
    let waiter = harness.makeWaiter(
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
      putBack: waiter.putBack,
      settle: { seconds in events.append("settle:\(seconds)") },
      settleSeconds: 1.5
    )

    let report = try PutBackRaceAcceptance.run(context: harness.context, operations: operations)

    #expect(
      events == ["trash:first-put-back-race", "settle:1.5", "trash:second-put-back-race"]
    )
    #expect(report.settleSeconds == 1.5)
  }

  @Test("performs no wait at all when no delay bucket is declared")
  func performsNoWaitByDefault() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var settleCalls: [TimeInterval] = []
    var restored = false
    var trashEvidence = [harness.firstTrashEvidence, harness.firstTrashEvidence]
    let waiter = harness.makeWaiter(
      entryProbe: { _ in restored },
      changeResponses: [{ restored = true }]
    )

    let report = try PutBackRaceAcceptance.run(
      context: harness.context,
      operations: PutBackRaceOperations(
        prepare: { _ in
          PutBackRaceTrashSession(sourceURL: harness.sourceURL) { trashEvidence.removeFirst() }
        },
        putBack: waiter.putBack,
        settle: { settleCalls.append($0) }
      )
    )

    #expect(settleCalls == [0])
    #expect(report.settleSeconds == 0)
  }
}

@Suite("Manual Put Back differential cycles", .serialized)
struct ManualPutBackDifferentialTests {
  @Test("numbers each cycle's fixture so one Run Directory holds the whole differential")
  func numbersEachCycleFixture() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }
    var requested: [(Int, String)] = []

    let reports = try PutBackRaceAcceptance.runManualCycles(
      context: harness.context,
      cycles: 3,
      announce: { _, _ in },
      runCycle: { cycle, suffix in
        requested.append((cycle, suffix))
        return harness.report(suffix: suffix)
      }
    )

    #expect(requested.map(\.0) == [1, 2, 3])
    #expect(
      requested.map(\.1) == [
        "put-back-race-01",
        "put-back-race-02",
        "put-back-race-03",
      ]
    )
    #expect(reports.count == 3)
  }

  @Test("preserves completed cycle evidence when a later cycle fails")
  func preservesEvidenceOnLateFailure() throws {
    let harness = try ManualHarness()
    defer { harness.remove() }

    var thrown: PutBackRaceCycleFailure?
    do {
      _ = try PutBackRaceAcceptance.runManualCycles(
        context: harness.context,
        cycles: 4,
        announce: { _, _ in },
        runCycle: { cycle, suffix in
          guard cycle < 3 else {
            throw TestSafetyDiagnostic(
              code: .putBackManualTimeout,
              message: "cycle \(cycle) gave up"
            )
          }
          return harness.report(suffix: suffix)
        }
      )
    } catch let failure as PutBackRaceCycleFailure {
      thrown = failure
    }

    #expect(thrown?.cycle == 3)
    #expect(thrown?.completedReports.count == 2)
    #expect(
      (thrown?.underlying as? TestSafetyDiagnostic)?.code == .putBackManualTimeout
    )
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

  func report(suffix: String) -> PutBackRaceReport {
    let url = context.runDirectoryURL.appendingPathComponent(
      "rmp-test-\(context.runID.uuidString.lowercased())-\(suffix)"
    )
    return PutBackRaceReport(
      sourceURL: url,
      firstTrashURL: url,
      restoredURL: url,
      secondTrashURL: url,
      settleSeconds: 0
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
    heartbeat: @escaping (Int) -> Void = { _ in },
    timeout: TimeInterval = ManualPutBackWaiter.defaultTimeout,
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
      heartbeat: heartbeat,
      timeout: timeout,
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
