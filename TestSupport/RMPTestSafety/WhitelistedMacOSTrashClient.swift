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

  convenience init(
    context: TestSafetyContext,
    fault: ProductionFinalizerFault = .none,
    finalizerName: ProductionFinalizerName = .hidden,
    preflight: ProductionFinalizerPreflight = .disabled
  ) {
    self.init(
      context: context,
      foundationTrashClient: WhitelistedTrashClient(
        context: context,
        backend: .foundationSymlink
      ),
      resourceIdentifier: testSafetyResourceIdentifier,
      fault: fault,
      finalizerName: finalizerName,
      preflight: preflight
    )
  }

  init(
    context: TestSafetyContext,
    foundationTrashClient: WhitelistedTrashClient,
    resourceIdentifier: @escaping ResourceIdentifier,
    restoreItem: @escaping @Sendable (URL, URL) throws -> Void = { trashURL, sourceURL in
      try FileManager.default.moveItem(at: trashURL, to: sourceURL)
    },
    fault: ProductionFinalizerFault = .none,
    finalizerName: ProductionFinalizerName = .hidden,
    preflight: ProductionFinalizerPreflight = .disabled
  ) {
    self.context = context
    self.foundationTrashClient = foundationTrashClient
    self.resourceIdentifier = resourceIdentifier
    let runID = context.runID
    let finalizerPrefix = finalizerName.prefix(runID: runID)
    let faultInjector = ProductionFinalizerFaultInjector(
      fault: fault,
      finalizerPrefix: finalizerPrefix
    )
    let finalizerRestorer = TestSafetyFinalizerRestorer(
      context: context,
      restoreItem: restoreItem
    )
    trashClient = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        throw TestSafetyDiagnostic(
          code: .trashSymlinkRequired,
          message: "The production finalizer acceptance accepts only symbolic links."
        )
      },
      foundationTrash: { sourceURL in
        let authorizedTarget: AuthorizedTrashTarget
        if sourceURL.lastPathComponent.hasPrefix(finalizerPrefix) {
          authorizedTarget = try foundationTrashClient.authorizeProductionFinalizerForPlanning(
            targetURL: sourceURL,
            expectedPrefix: finalizerPrefix
          )
        } else {
          authorizedTarget = try foundationTrashClient.authorizeForPlanning(targetURL: sourceURL)
        }
        return try faultInjector.trash(sourceURL) {
          try foundationTrashClient.trashItem(authorizedTarget).returnedURL
        }
      },
      restoreItem: finalizerRestorer.restore,
      finalizerName: { finalizerName.makeName(runID: runID) },
      performsFinalizerPreflight: preflight.isEnabled
    )
  }

  func trashItem(_ sourceURL: URL) throws -> TrashVerificationEvidence {
    let result = try verifiedTrashItem(sourceURL)
    if let warning = result.warnings.first {
      throw degradationDiagnostic(warning)
    }
    return result.evidence
  }

  func trashItem(
    _ sourceURL: URL,
    expecting expectedWarning: TrashWarningCode
  ) throws -> TrashVerificationEvidence {
    let result = try verifiedTrashItem(sourceURL)
    guard result.warnings.map(\.code) == [expectedWarning] else {
      throw TestSafetyDiagnostic(
        code: .trashSystemCallFailed,
        message: "The production symbolic-link Trash warning did not match the expected fault."
      )
    }
    return result.evidence
  }

  private func verifiedTrashItem(_ sourceURL: URL) throws -> VerifiedProductionTrashResult {
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

    let returnedURL = URL(fileURLWithPath: receipt.destinationPath)
    let returnedIdentifier = try identifiedResource(at: returnedURL, role: "returned Trash item")
    if let sourceIdentifier, returnedIdentifier != sourceIdentifier {
      throw TestSafetyDiagnostic(
        code: .trashEvidenceMismatch,
        message: "The production Trash receipt does not identify the original symbolic link."
      )
    }
    return VerifiedProductionTrashResult(
      evidence: TrashVerificationEvidence(
        returnedURL: returnedURL,
        resourceIdentifier: returnedIdentifier
      ),
      warnings: receipt.warnings
    )
  }

  private func degradationDiagnostic(_ warning: TrashMoveWarning) -> TestSafetyDiagnostic {
    let code: TestSafetyDiagnosticCode =
      warning.code == .finalizerCleanupFailed ? .finalizerCleanupFailed : .trashSystemCallFailed
    return TestSafetyDiagnostic(
      code: code,
      message: "The production symbolic-link Trash operation moved the target but degraded: "
        + warning.code.rawValue
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

private struct VerifiedProductionTrashResult {
  let evidence: TrashVerificationEvidence
  let warnings: [TrashMoveWarning]
}

private final class TestSafetyFinalizerRestorer: @unchecked Sendable {
  private let context: TestSafetyContext
  private let restoreItem: @Sendable (URL, URL) throws -> Void

  init(
    context: TestSafetyContext,
    restoreItem: @escaping @Sendable (URL, URL) throws -> Void
  ) {
    self.context = context
    self.restoreItem = restoreItem
  }

  func restore(_ trashURL: URL, _ sourceURL: URL) throws {
    try context.revalidate()
    try restoreItem(trashURL, sourceURL)
  }
}

private final class ProductionFinalizerFaultInjector: @unchecked Sendable {
  private let fault: ProductionFinalizerFault
  private let finalizerPrefix: String
  private let lock = NSLock()
  private var targetMoved = false
  private var injected = false

  init(fault: ProductionFinalizerFault, finalizerPrefix: String) {
    self.fault = fault
    self.finalizerPrefix = finalizerPrefix
  }

  func trash(_ sourceURL: URL, operation: () throws -> URL) throws -> URL {
    lock.lock()
    defer { lock.unlock() }
    let isFinalizer = sourceURL.lastPathComponent.hasPrefix(finalizerPrefix)
    if isFinalizer, targetMoved, !injected, fault == .firstActivationNotMoved {
      injected = true
      throw InjectedProductionFinalizerFailure()
    }
    if isFinalizer, targetMoved, !injected, fault == .firstActivationMovedBeforeError {
      injected = true
      _ = try operation()
      throw InjectedProductionFinalizerFailure()
    }
    let returnedURL = try operation()
    if !isFinalizer {
      targetMoved = true
    }
    return returnedURL
  }
}

private struct InjectedProductionFinalizerFailure: Error {}
