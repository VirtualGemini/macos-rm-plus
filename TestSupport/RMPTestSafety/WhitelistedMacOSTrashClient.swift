// SPDX-License-Identifier: Apache-2.0

import Foundation
import RMPCore
import RMPPlatform

// The ticket and PRD define this safety-boundary name.
// swiftlint:disable inclusive_language
/// Runs the production symbolic-link algorithm while requiring every real Foundation call to pass
/// through the maintainer-only Test Safety Context.
final class WhitelistedMacOSTrashClient {
  typealias ResourceIdentifier = @Sendable (URL) throws -> Data?

  private let context: TestSafetyContext
  private let foundationTrashClient: WhitelistedTrashClient
  private let resourceIdentifier: ResourceIdentifier
  private let trashClient: any TrashClient

  convenience init(context: TestSafetyContext) {
    self.init(
      context: context,
      foundationTrashClient: WhitelistedTrashClient(
        context: context,
        backend: .foundationSymlink
      ),
      resourceIdentifier: testSafetyResourceIdentifier
    )
  }

  init(
    context: TestSafetyContext,
    foundationTrashClient: WhitelistedTrashClient,
    resourceIdentifier: @escaping ResourceIdentifier,
    restoreItem: @escaping @Sendable (URL, URL) throws -> Void = { trashURL, sourceURL in
      try FileManager.default.moveItem(at: trashURL, to: sourceURL)
    }
  ) {
    self.context = context
    self.foundationTrashClient = foundationTrashClient
    self.resourceIdentifier = resourceIdentifier
    trashClient = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        throw TestSafetyDiagnostic(
          code: .trashSymlinkRequired,
          message: "The production finalizer acceptance accepts only symbolic links."
        )
      },
      foundationTrash: { sourceURL in
        let authorizedTarget =
          sourceURL.lastPathComponent.hasPrefix(".rmp-finalizer-")
          ? try foundationTrashClient.authorizeProductionFinalizerForPlanning(
            targetURL: sourceURL
          )
          : try foundationTrashClient.authorizeForPlanning(targetURL: sourceURL)
        return try foundationTrashClient.trashItem(authorizedTarget).returnedURL
      },
      restoreItem: restoreItem
    )
  }

  func trashItem(_ sourceURL: URL) throws -> TrashVerificationEvidence {
    try context.revalidate()
    _ = try foundationTrashClient.authorizeForPlanning(targetURL: sourceURL)
    let sourceIdentifier = try identifiedResource(at: sourceURL, role: "source")

    let receipt: TrashMoveReceipt
    do {
      receipt = try trashClient.trashItem(atPath: sourceURL.path)
    } catch let diagnostic as TestSafetyDiagnostic {
      throw diagnostic
    } catch {
      throw TestSafetyDiagnostic(
        code: .trashSystemCallFailed,
        message: "The production symbolic-link Trash operation failed."
      )
    }

    if let warning = receipt.warnings.first {
      let code: TestSafetyDiagnosticCode =
        warning.code == .finalizerCleanupFailed ? .finalizerCleanupFailed : .trashSystemCallFailed
      throw TestSafetyDiagnostic(
        code: code,
        message: "The production symbolic-link Trash operation moved the target but degraded: "
          + warning.code.rawValue
      )
    }

    let returnedURL = URL(fileURLWithPath: receipt.destinationPath)
    let returnedIdentifier = try identifiedResource(at: returnedURL, role: "returned Trash item")
    if let sourceIdentifier, returnedIdentifier != sourceIdentifier {
      throw TestSafetyDiagnostic(
        code: .trashEvidenceMismatch,
        message: "The production Trash receipt does not identify the original symbolic link."
      )
    }
    return TrashVerificationEvidence(
      returnedURL: returnedURL,
      resourceIdentifier: returnedIdentifier
    )
  }

  private func identifiedResource(at url: URL, role: String) throws -> Data? {
    do {
      return try resourceIdentifier(url)
    } catch {
      throw TestSafetyDiagnostic(
        code: .trashPathInspectionFailed,
        message: "The \(role) resource identity could not be inspected."
      )
    }
  }
}
// swiftlint:enable inclusive_language
