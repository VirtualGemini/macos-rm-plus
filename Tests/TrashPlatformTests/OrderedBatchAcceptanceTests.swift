// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import TrashCore

@testable import tc_test

@Test("Authorized batch Trash adapter preserves order and exact receipts")
func authorizedBatchTrashAdapterPreservesOrderAndReceipts() throws {
  let firstPath = "/authorized/first"
  let secondPath = "/authorized/second"
  let client = AuthorizedBatchTrashClient(
    operations: [
      firstPath: {
        TrashVerificationEvidence(
          returnedURL: URL(fileURLWithPath: "/Trash/first 2"),
          resourceIdentifier: nil
        )
      },
      secondPath: {
        throw TrashCapabilityError(code: .systemTrashFailed)
      },
    ]
  )

  let receipt = try client.trashItem(atPath: firstPath)

  #expect(receipt.destinationPath == "/Trash/first 2")
  #expect(throws: TrashCapabilityError(code: .systemTrashFailed)) {
    try client.trashItem(atPath: secondPath)
  }
  #expect(client.receivedPaths == [firstPath, secondPath])
  #expect(client.receipts == [firstPath: receipt])
}

@Test("Ordered batch acceptance requires complete partial-success evidence")
func orderedBatchAcceptanceValidatesPartialSuccessEvidence() throws {
  let fixtures = OrderedBatchFixtures(
    fileURL: URL(fileURLWithPath: "/run/file"),
    permissionDeniedParentURL: URL(fileURLWithPath: "/run/locked"),
    permissionDeniedURL: URL(fileURLWithPath: "/run/locked/permission"),
    emptyDirectoryURL: URL(fileURLWithPath: "/run/empty"),
    deepDirectoryURL: URL(fileURLWithPath: "/run/deep"),
    specialNameURL: URL(fileURLWithPath: "/run/special"),
    missingURL: URL(fileURLWithPath: "/run/missing")
  )
  let receipts = [
    "/run/file": TrashMoveReceipt(destinationPath: "/Trash/file"),
    "/run/empty": TrashMoveReceipt(destinationPath: "/Trash/empty"),
    "/run/deep": TrashMoveReceipt(destinationPath: "/Trash/deep"),
    "/run/special": TrashMoveReceipt(destinationPath: "/Trash/special"),
  ]
  let result = CommandResult(
    standardOutput: """
      Moved "/run/file" to Trash at "/Trash/file".
      Moved "/run/empty" to Trash at "/Trash/empty".
      Moved "/run/deep" to Trash at "/Trash/deep".
      Moved "/run/special" to Trash at "/Trash/special".

      """,
    standardError: """
      tc: trash_system_call_failed (not_moved) for "/run/locked/permission": denied
      tc: missing_input (rejected) for "/run/missing": absent

      """,
    exitCode: 1
  )
  let evidence = OrderedBatchAcceptanceEvidence(
    result: result,
    fixtures: fixtures,
    receivedPaths: [
      "/run/file", "/run/locked/permission", "/run/empty", "/run/deep", "/run/special",
    ],
    receipts: receipts,
    sourceExistence: [
      "/run/file": false,
      "/run/locked/permission": true,
      "/run/empty": false,
      "/run/deep": false,
      "/run/special": false,
      "/run/missing": false,
    ]
  )

  try OrderedBatchAcceptance.validate(evidence)

  let reordered = OrderedBatchAcceptanceEvidence(
    result: result,
    fixtures: fixtures,
    receivedPaths: evidence.receivedPaths.reversed(),
    receipts: receipts,
    sourceExistence: evidence.sourceExistence
  )
  #expect(throws: TestSafetyDiagnostic.self) {
    try OrderedBatchAcceptance.validate(reordered)
  }
}
