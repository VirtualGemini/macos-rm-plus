// SPDX-License-Identifier: Apache-2.0

import Foundation

struct PutBackVerificationEvidence: Equatable, Sendable {
  let returnedURL: URL
  let resourceIdentifier: Data?
}

struct PutBackRaceTrashSession {
  let sourceURL: URL
  let trash: () throws -> TrashVerificationEvidence
  var retrash: (() throws -> TrashVerificationEvidence)?
}

/// Keeps the human-operated Put Back control independent from the symbolic-link behavior under
/// test. Finder owns the ordinary-file control; only the second Trash call enters the production
/// symbolic-link algorithm.
enum PutBackRaceProductionProtocol {
  static let controlKind = PutBackRaceFixtureKind.file
  static let controlBackend = TestSystemTrashBackend.finder

  static func makeSession(
    control: PutBackRaceTrashSession,
    targetSourceURL: URL,
    targetTrash: @escaping (URL) throws -> TrashVerificationEvidence
  ) -> PutBackRaceTrashSession {
    PutBackRaceTrashSession(
      sourceURL: control.sourceURL,
      trash: control.trash,
      retrash: { try targetTrash(targetSourceURL) }
    )
  }
}

struct PutBackRaceOperations {
  let prepare: (TestSafetyContext) throws -> PutBackRaceTrashSession
  let putBack:
    (
      _ evidence: TrashVerificationEvidence,
      _ expectedSourceURL: URL
    ) throws -> PutBackVerificationEvidence
  /// The ticket's declared re-trash delay bucket, applied between the observed restore and the
  /// second Trash call. The default performs no wait at all.
  var settle: (TimeInterval) throws -> Void = { _ in }
  var settleSeconds: TimeInterval = 0
  var finalize: () throws -> Void = {}
}

struct PutBackRaceReport: Equatable, Sendable {
  let sourceURL: URL
  let firstTrashURL: URL
  let restoredURL: URL
  let secondTrashURL: URL
  let settleSeconds: TimeInterval
}

/// Issue 12's platform acceptance set. The metadata race is a property of the Trash entry, so the
/// shape of the deleted item is an independent dimension that the file-only differential leaves
/// untested.
enum PutBackRaceFixtureKind: String, CaseIterable, Sendable {
  case file
  case directory
  case symbolicLink = "symbolic-link"
  case brokenSymbolicLink = "broken-symbolic-link"
  case quotedName = "quoted-name"
  case newlineName = "newline-name"

  /// The suffix appended after the run prefix. The awkward cases deliberately embed characters
  /// that would break any implementation that interpolated paths into AppleScript source.
  func suffix(cycle: String) -> String {
    switch self {
    case .file, .directory, .symbolicLink, .brokenSymbolicLink:
      return "\(cycle)-\(rawValue)"
    case .quotedName:
      return "\(cycle)-name with \"double\" and 'single' quotes"
    case .newlineName:
      return "\(cycle)-name with\na newline"
    }
  }
}

/// Carries the evidence of already-completed cycles out of a failing differential so a late
/// failure never discards the rounds the maintainer already performed.
struct PutBackRaceCycleFailure: Error {
  let completedReports: [PutBackRaceReport]
  let cycle: Int
  let underlying: Error
}

enum PutBackRaceAcceptance {
  static func run(context: TestSafetyContext) throws -> PutBackRaceReport {
    let putBackClient = WhitelistedPutBackClient(context: context)
    let operations = PutBackRaceOperations(
      prepare: makePrepare(context: context, suffix: "put-back-race"),
      putBack: putBackClient.putBack
    )
    return try run(context: context, operations: operations)
  }

  /// Restores through the maintainer's real Finder Put Back command instead of scripting the
  /// move. This variant carries no Finder Put Back capability and needs no Full Disk Access.
  static func runManual(
    context: TestSafetyContext,
    suffix: String = "put-back-race",
    kind: PutBackRaceFixtureKind = .file,
    trashBackend: TestSystemTrashBackend = .finder,
    settleSeconds: TimeInterval = 0,
    finalizeWithFoundation: Bool = false,
    retrashWithProductionFinalizer: Bool = false,
    productionFinalizerFault: ProductionFinalizerFault = .none,
    announce: @escaping (String) -> Void,
    heartbeat: @escaping (Int) -> Void = { _ in }
  ) throws -> PutBackRaceReport {
    let waiter = ManualPutBackWaiter(
      context: context,
      announce: announce,
      heartbeat: heartbeat,
      postRestoreInstruction: retrashWithProductionFinalizer
        ? "After Put Back is observed, rmp-test immediately trashes the production symbolic-link "
          + "target. Check that target in Trash immediately; do not wait."
        : nil
    )
    let finalizer = finalizeWithFoundation ? FoundationTrashFinalizer(context: context) : nil
    let prepare =
      retrashWithProductionFinalizer
      ? makeProductionPrepare(
        context: context,
        suffix: suffix,
        kind: kind,
        fault: productionFinalizerFault
      )
      : makePrepare(
        context: context,
        suffix: suffix,
        kind: kind,
        trashBackend: trashBackend
      )
    let operations = PutBackRaceOperations(
      prepare: prepare,
      putBack: waiter.putBack,
      settle: { seconds in
        guard seconds > 0 else { return }
        Thread.sleep(forTimeInterval: seconds)
      },
      settleSeconds: settleSeconds,
      finalize: {
        guard let finalizer else { return }
        _ = try finalizer.finalize(suffix: "\(suffix)-foundation-finalizer")
      }
    )
    return try run(context: context, operations: operations)
  }

  private static func makeProductionPrepare(
    context: TestSafetyContext,
    suffix: String,
    kind: PutBackRaceFixtureKind,
    fault: ProductionFinalizerFault
  ) -> (TestSafetyContext) throws -> PutBackRaceTrashSession {
    let productionClient = WhitelistedMacOSTrashClient(
      context: context,
      fault: fault
    )
    let controlPrepare = makePrepare(
      context: context,
      suffix: "\(suffix)-finder-control",
      kind: PutBackRaceProductionProtocol.controlKind,
      trashBackend: PutBackRaceProductionProtocol.controlBackend
    )
    return { receivedContext in
      let control = try controlPrepare(receivedContext)
      let targetSourceURL = try makeFixture(
        context: receivedContext,
        suffix: suffix,
        kind: kind
      )
      return PutBackRaceProductionProtocol.makeSession(
        control: control,
        targetSourceURL: targetSourceURL,
        targetTrash: { sourceURL in
          if let expectedWarning = fault.expectedWarning {
            return try productionClient.trashItem(sourceURL, expecting: expectedWarning)
          }
          return try productionClient.trashItem(sourceURL)
        }
      )
    }
  }

  /// Runs the manual scenario repeatedly inside one Run Directory so the maintainer can perform a
  /// differential without a separate process, prompt, and inspection per cycle. Each cycle owns a
  /// distinct fixture name, and every completed cycle's evidence survives a later cycle's failure.
  /// `runCycle` exists so pure tests can exercise the numbering and failure-carrying contract
  /// without reaching the real Finder capability that the default cycle wires up.
  static func runManualCycles(
    context: TestSafetyContext,
    cycles: Int,
    kind: PutBackRaceFixtureKind = .file,
    trashBackend: TestSystemTrashBackend = .finder,
    settleSeconds: TimeInterval = 0,
    finalizeWithFoundation: Bool = false,
    retrashWithProductionFinalizer: Bool = false,
    announce: @escaping (Int, String) -> Void,
    heartbeat: @escaping (Int) -> Void = { _ in },
    runCycle: ((Int, String) throws -> PutBackRaceReport)? = nil
  ) throws -> [PutBackRaceReport] {
    let cycleOperation =
      runCycle
      ?? { cycle, suffix in
        try runManual(
          context: context,
          suffix: suffix,
          kind: kind,
          trashBackend: trashBackend,
          settleSeconds: settleSeconds,
          finalizeWithFoundation: finalizeWithFoundation,
          retrashWithProductionFinalizer: retrashWithProductionFinalizer,
          announce: { announce(cycle, $0) },
          heartbeat: heartbeat
        )
      }
    var reports: [PutBackRaceReport] = []
    for cycle in 1...cycles {
      do {
        reports.append(
          try cycleOperation(cycle, kind.suffix(cycle: String(format: "put-back-race-%02d", cycle)))
        )
      } catch {
        throw PutBackRaceCycleFailure(completedReports: reports, cycle: cycle, underlying: error)
      }
    }
    return reports
  }

  private static func makePrepare(
    context: TestSafetyContext,
    suffix: String,
    kind: PutBackRaceFixtureKind = .file,
    trashBackend: TestSystemTrashBackend = .finder
  ) -> (TestSafetyContext) throws -> PutBackRaceTrashSession {
    let trashClient = WhitelistedTrashClient(context: context, backend: trashBackend)
    return { receivedContext in
      guard receivedContext === context else {
        throw TestSafetyDiagnostic(
          code: .unexpectedError,
          message: "The Put Back acceptance context changed unexpectedly."
        )
      }
      let sourceURL = try makeFixture(context: receivedContext, suffix: suffix, kind: kind)
      let authorizedTarget = try trashClient.authorizeForPlanning(targetURL: sourceURL)
      return PutBackRaceTrashSession(sourceURL: sourceURL) {
        try trashClient.trashItem(authorizedTarget)
      }
    }
  }

  private static func makeFixture(
    context: TestSafetyContext,
    suffix: String,
    kind: PutBackRaceFixtureKind
  ) throws -> URL {
    let body = Data("rmp Put Back race \(context.runID.uuidString.lowercased()) \(suffix)\n".utf8)
    switch kind {
    case .file, .quotedName, .newlineName:
      return try context.createFixtureFile(suffix: suffix, contents: body)
    case .directory:
      let directoryURL = try context.createFixtureDirectory(suffix: suffix)
      try body.write(to: directoryURL.appendingPathComponent("contents.txt"))
      return directoryURL
    case .symbolicLink:
      // Point at a real sibling so the link resolves; Finder must still move the link itself.
      let targetURL = try context.createFixtureFile(
        suffix: "\(suffix)-link-target",
        contents: body
      )
      return try context.createFixtureSymbolicLink(
        suffix: suffix,
        target: targetURL.lastPathComponent
      )
    case .brokenSymbolicLink:
      return try context.createFixtureSymbolicLink(
        suffix: suffix,
        target: "rmp-test-\(context.runID.uuidString.lowercased())-absent-target"
      )
    }
  }

  static func run(
    context: TestSafetyContext,
    operations: PutBackRaceOperations
  ) throws -> PutBackRaceReport {
    let session = try operations.prepare(context)
    let firstTrash = try session.trash()
    let restored = try operations.putBack(firstTrash, session.sourceURL)
    try operations.settle(operations.settleSeconds)
    let secondTrash = try session.retrash?() ?? session.trash()
    try operations.finalize()
    return PutBackRaceReport(
      sourceURL: session.sourceURL,
      firstTrashURL: firstTrash.returnedURL,
      restoredURL: restored.returnedURL,
      secondTrashURL: secondTrash.returnedURL,
      settleSeconds: operations.settleSeconds
    )
  }
}
