// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import tc_test

@Suite("Duplicate Trash name acceptance")
struct DuplicateTrashNameAcceptanceTests {
  @Test("uses two exact system receipts when duplicate Trash names are renamed")
  func usesExactSystemReceipts() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = context.runDirectoryURL.appendingPathComponent("same-name")
    let firstTrashURL = URL(fileURLWithPath: "/Trash/same-name")
    let secondTrashURL = URL(fileURLWithPath: "/Trash/same-name 2")
    var events: [String] = []
    let report = try PutBackRaceAcceptance.runDuplicateTrashName(
      context: context,
      operations: DuplicateTrashNameOperations(
        create: { receivedContext in
          #expect(receivedContext === context)
          events.append("create")
          return sourceURL
        },
        trash: { receivedSourceURL in
          #expect(receivedSourceURL == sourceURL)
          let url = events.count == 1 ? firstTrashURL : secondTrashURL
          events.append("trash:\(url.lastPathComponent)")
          return TrashVerificationEvidence(returnedURL: url, resourceIdentifier: nil)
        }
      )
    )

    #expect(events == ["create", "trash:same-name", "create", "trash:same-name 2"])
    #expect(
      report
        == DuplicateTrashNameReport(
          sourceURL: sourceURL,
          firstTrashURL: firstTrashURL,
          secondTrashURL: secondTrashURL
        )
    )
  }

  @Test("rejects duplicate-name evidence when macOS returns the same Trash URL")
  func rejectsSameReturnedURL() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let sourceURL = context.runDirectoryURL.appendingPathComponent("same-name")
    let trashURL = URL(fileURLWithPath: "/Trash/same-name")

    let diagnostic = captureDiagnostic {
      _ = try PutBackRaceAcceptance.runDuplicateTrashName(
        context: context,
        operations: DuplicateTrashNameOperations(
          create: { _ in sourceURL },
          trash: { _ in
            TrashVerificationEvidence(returnedURL: trashURL, resourceIdentifier: nil)
          }
        )
      )
    }

    #expect(diagnostic?.code == .trashEvidenceMismatch)
  }

  @Test("rejects a duplicate-name fixture that changes its source path")
  func rejectsDifferentSourcePaths() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let firstSourceURL = context.runDirectoryURL.appendingPathComponent("same-name")
    let secondSourceURL = context.runDirectoryURL.appendingPathComponent("different-name")
    let trashURL = URL(fileURLWithPath: "/Trash/same-name")
    var createCount = 0

    let diagnostic = captureDiagnostic {
      _ = try PutBackRaceAcceptance.runDuplicateTrashName(
        context: context,
        operations: DuplicateTrashNameOperations(
          create: { _ in
            createCount += 1
            return createCount == 1 ? firstSourceURL : secondSourceURL
          },
          trash: { _ in
            TrashVerificationEvidence(returnedURL: trashURL, resourceIdentifier: nil)
          }
        )
      )
    }

    #expect(diagnostic?.code == .unexpectedError)
  }
}
