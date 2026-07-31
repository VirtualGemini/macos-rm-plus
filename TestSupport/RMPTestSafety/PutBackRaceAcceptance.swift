// SPDX-License-Identifier: Apache-2.0

import Foundation

struct PutBackVerificationEvidence: Equatable, Sendable {
  let returnedURL: URL
  let resourceIdentifier: Data?
}

struct PutBackRaceTrashSession {
  let sourceURL: URL
  let trash: () throws -> TrashVerificationEvidence
}

struct PutBackRaceOperations {
  let prepare: (TestSafetyContext) throws -> PutBackRaceTrashSession
  let putBack:
    (
      _ evidence: TrashVerificationEvidence,
      _ expectedSourceURL: URL
    ) throws -> PutBackVerificationEvidence
}

struct PutBackRaceReport: Equatable, Sendable {
  let sourceURL: URL
  let firstTrashURL: URL
  let restoredURL: URL
  let secondTrashURL: URL
}

enum PutBackRaceAcceptance {
  static func run(context: TestSafetyContext) throws -> PutBackRaceReport {
    let putBackClient = WhitelistedPutBackClient(context: context)
    let operations = PutBackRaceOperations(
      prepare: makePrepare(context: context),
      putBack: putBackClient.putBack
    )
    return try run(context: context, operations: operations)
  }

  /// Restores through the maintainer's real Finder Put Back command instead of scripting the
  /// move. This variant carries no Finder Put Back capability and needs no Full Disk Access.
  static func runManual(
    context: TestSafetyContext,
    announce: @escaping (String) -> Void
  ) throws -> PutBackRaceReport {
    let waiter = ManualPutBackWaiter(context: context, announce: announce)
    let operations = PutBackRaceOperations(
      prepare: makePrepare(context: context),
      putBack: waiter.putBack
    )
    return try run(context: context, operations: operations)
  }

  private static func makePrepare(
    context: TestSafetyContext
  ) -> (TestSafetyContext) throws -> PutBackRaceTrashSession {
    let trashClient = WhitelistedTrashClient(context: context)
    return { receivedContext in
      guard receivedContext === context else {
        throw TestSafetyDiagnostic(
          code: .unexpectedError,
          message: "The Put Back acceptance context changed unexpectedly."
        )
      }
      let sourceURL = try receivedContext.createFixtureFile(
        suffix: "put-back-race",
        contents: Data(
          "rmp Put Back race \(receivedContext.runID.uuidString.lowercased())\n".utf8
        )
      )
      let authorizedTarget = try trashClient.authorizeForPlanning(targetURL: sourceURL)
      return PutBackRaceTrashSession(sourceURL: sourceURL) {
        try trashClient.trashItem(authorizedTarget)
      }
    }
  }

  static func run(
    context: TestSafetyContext,
    operations: PutBackRaceOperations
  ) throws -> PutBackRaceReport {
    let session = try operations.prepare(context)
    let firstTrash = try session.trash()
    let restored = try operations.putBack(firstTrash, session.sourceURL)
    let secondTrash = try session.trash()
    return PutBackRaceReport(
      sourceURL: session.sourceURL,
      firstTrashURL: firstTrash.returnedURL,
      restoredURL: restored.returnedURL,
      secondTrashURL: secondTrash.returnedURL
    )
  }
}
