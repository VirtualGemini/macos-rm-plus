// SPDX-License-Identifier: Apache-2.0

public enum TrashWarningCode: String, Equatable, Sendable {
  case finalizerCleanupFailed = "finalizer_cleanup_failed"
  case finalizerStateUncertain = "finalizer_state_uncertain"
  case symlinkPutBackNotGuaranteed = "symlink_put_back_not_guaranteed"
}

public struct TrashMoveWarning: Equatable, Sendable {
  public let code: TrashWarningCode

  public init(code: TrashWarningCode) {
    self.code = code
  }
}

public struct TrashMoveReceipt: Equatable, Sendable {
  public let destinationPath: String
  public let warnings: [TrashMoveWarning]

  public init(destinationPath: String, warnings: [TrashMoveWarning] = []) {
    self.destinationPath = destinationPath
    self.warnings = warnings
  }
}

public enum TrashErrorCode: String, Equatable, Sendable {
  case confirmationDeclined = "confirmation_declined"
  case confirmationInterrupted = "confirmation_interrupted"
  case confirmationInvalidResponse = "confirmation_invalid_response"
  case confirmationRequired = "confirmation_required"
  case finderAutomationConsentRequired = "finder_automation_consent_required"
  case finderAutomationDenied = "finder_automation_denied"
  case finderAutomationTimedOut = "finder_automation_timed_out"
  case finderUnavailable = "finder_unavailable"
  case finalizerCleanupFailed = "finalizer_cleanup_failed"
  case inaccessibleInput = "inaccessible_input"
  case jsonEncodingFailed = "json_encoding_failed"
  case missingInput = "missing_input"
  case noInputs = "no_inputs"
  case protectedPath = "protected_path"
  case rootExecution = "root_execution"
  case safetyIdentityUnavailable = "safety_identity_unavailable"
  case systemTrashFailed = "trash_system_call_failed"
  case unsupportedInputKind = "unsupported_input_kind"
  case unsupportedOutputMode = "unsupported_output_mode"
}

public struct TrashCapabilityError: Error, Equatable, Sendable {
  public let code: TrashErrorCode

  public init(code: TrashErrorCode) {
    self.code = code
  }
}

public protocol TrashClient: Sendable {
  func trashItem(atPath path: String) throws -> TrashMoveReceipt
}

public enum ConfirmationResponse: Equatable, Sendable {
  case answer(String)
  case interrupted
}

public protocol ConfirmationPrompt: Sendable {
  var isInputTTY: Bool { get }

  func readResponse(prompt: String) -> ConfirmationResponse
}

struct SingleTrashExecutor<FileSystem: TrashPlanningFileSystem> {
  private let fileSystem: FileSystem
  private let makeTrashClient: () -> any TrashClient

  init(
    fileSystem: FileSystem,
    makeTrashClient: @escaping () -> any TrashClient
  ) {
    self.fileSystem = fileSystem
    self.makeTrashClient = makeTrashClient
  }

  func execute(_ input: TrashInput) -> TrashResult {
    guard input.kind != .other, input.kind != .unknown else {
      return TrashResult(
        sourcePath: input.path,
        destinationPath: nil,
        kind: input.kind,
        status: .rejected,
        skipReason: nil,
        warnings: [],
        error: TrashFailure(
          code: .unsupportedInputKind,
          explanation: "The Trash Input has an unsupported entry kind."
        )
      )
    }
    do {
      let receipt = try makeTrashClient().trashItem(atPath: input.path)
      return TrashResult(
        sourcePath: input.path,
        destinationPath: receipt.destinationPath,
        kind: input.kind,
        status: .moved,
        skipReason: nil,
        warnings: receipt.warnings,
        error: nil
      )
    } catch let error as TrashCapabilityError {
      return failedResult(input: input, code: error.code)
    } catch {
      return failedResult(input: input, code: .systemTrashFailed)
    }
  }

  private func failedResult(input: TrashInput, code: TrashErrorCode) -> TrashResult {
    let sourceUnchanged = sourceIsUnchanged(input)
    let status: TrashResultStatus = sourceUnchanged ? .notMoved : .stateUncertain
    let explanation = failureExplanation(code: code, sourceUnchanged: sourceUnchanged)
    return TrashResult(
      sourcePath: input.path,
      destinationPath: nil,
      kind: input.kind,
      status: status,
      skipReason: nil,
      warnings: [],
      error: TrashFailure(
        code: code,
        explanation: explanation
      )
    )
  }

  private func failureExplanation(code: TrashErrorCode, sourceUnchanged: Bool) -> String {
    let sourceState =
      sourceUnchanged
      ? "The source entry is unchanged."
      : "The source entry's final state is uncertain."
    switch code {
    case .finderAutomationConsentRequired:
      return
        "Finder Automation permission is required. Run rmp from an interactive desktop session "
        + "and allow the invoking terminal or rmp to control Finder. \(sourceState)"
    case .finderAutomationDenied:
      return
        "Finder Automation permission was denied. Enable the invoking terminal or rmp in System "
        + "Settings > Privacy & Security > Automation. \(sourceState)"
    case .finderAutomationTimedOut:
      return "Finder did not complete the Trash request before the timeout. \(sourceState)"
    case .finderUnavailable:
      return "Finder is unavailable for the Trash request. \(sourceState)"
    case .finalizerCleanupFailed:
      return
        "An internal symbolic-link finalizer could not be cleaned up. \(sourceState)"
    default:
      return "The system Trash operation failed; \(sourceState.lowercased())"
    }
  }

  private func sourceIsUnchanged(_ input: TrashInput) -> Bool {
    guard case let .entry(entry) = fileSystem.inspectEntry(at: input.path) else {
      return false
    }
    return entry.identity == input.plannedIdentity && entry.kind == input.kind
  }
}
struct TrashOperationApplication<FileSystem: TrashPlanningFileSystem> {
  private let fileSystem: FileSystem
  private let makeTrashClient: () -> any TrashClient
  private let makeConfirmationPrompt: (() -> any ConfirmationPrompt)?
  private let renderer: TrashResultRenderer

  init(
    fileSystem: FileSystem,
    makeTrashClient: @escaping () -> any TrashClient,
    makeConfirmationPrompt: (() -> any ConfirmationPrompt)? = nil
  ) {
    self.fileSystem = fileSystem
    self.makeTrashClient = makeTrashClient
    self.makeConfirmationPrompt = makeConfirmationPrompt
    renderer = TrashResultRenderer(currentDirectoryPath: fileSystem.currentDirectoryPath)
  }

  func run(request: TrashOperationRequest) -> CommandResult {
    do {
      let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(request: request)
      guard let input = plan.inputs.first else {
        return execute(plan)
      }
      if plan.confirmation == .each {
        return executeWithPerInputConfirmation(plan)
      }
      if !canProceedWithoutConfirmation(
        plan: plan,
        input: input,
        requestedInputCount: request.paths.count
      ) {
        return executeAfterBatchConfirmation(plan)
      }
      return execute(plan)
    } catch {
      if request.output == .json {
        return JSONTrashRenderer().render(
          error: error,
          request: request,
          currentDirectoryPath: fileSystem.currentDirectoryPath
        )
      }
      return PlanningErrorRenderer().render(error)
    }
  }

  private func canProceedWithoutConfirmation(
    plan: TrashPlan,
    input: TrashInput,
    requestedInputCount: Int
  ) -> Bool {
    switch plan.confirmation {
    case .never:
      true
    case .smart:
      requestedInputCount == 1 && input.kind != .directory
    case .once, .each:
      false
    case .conditionalOnce:
      requestedInputCount <= 3 && !plan.inputs.contains { $0.kind == .directory }
    }
  }

  private func execute(_ plan: TrashPlan) -> CommandResult {
    var results: [TrashResult] = []
    results.reserveCapacity(plan.entries.count)
    var shouldSkipRemainingInputs = false
    for entry in plan.entries {
      if shouldSkipRemainingInputs {
        results.append(skippedResult(for: entry, reason: .stoppedAfterFailure))
        continue
      }
      let result = result(for: entry)
      results.append(result)
      if plan.stopOnError && result.representsOperationFailure {
        shouldSkipRemainingInputs = true
      }
    }
    return renderer.render(results, output: plan.output)
  }

  private func result(for entry: TrashPlanEntry) -> TrashResult {
    switch entry {
    case let .input(input):
      return execute(input)
    case let .missing(path, ignored):
      if ignored {
        return skippedResult(for: entry, reason: .ignoredMissing)
      } else {
        let error = entry.planningError ?? .missingPath(path)
        return rejectedResult(
          path: path,
          code: error.code,
          explanation: error.explanation
        )
      }
    case let .inaccessible(path):
      let error = entry.planningError ?? .inaccessiblePath(path)
      return rejectedResult(
        path: path,
        code: error.code,
        explanation: error.explanation
      )
    }
  }

  private func rejectedResult(
    path: String,
    kind: TrashInputKind = .unknown,
    code: TrashErrorCode,
    explanation: String,
    failureExitSuppressed: Bool = false
  ) -> TrashResult {
    TrashResult(
      sourcePath: path,
      destinationPath: nil,
      kind: kind,
      status: .rejected,
      skipReason: nil,
      warnings: [],
      error: TrashFailure(code: code, explanation: explanation),
      failureExitSuppressed: failureExitSuppressed
    )
  }

  private func skippedResult(for entry: TrashPlanEntry, reason: TrashSkipReason) -> TrashResult {
    TrashResult(
      sourcePath: entry.path,
      destinationPath: nil,
      kind: entry.kind,
      status: .skipped,
      skipReason: reason,
      warnings: [],
      error: nil
    )
  }

  private func executeAfterBatchConfirmation(_ plan: TrashPlan) -> CommandResult {
    guard let prompt = interactivePrompt(for: plan) else {
      return renderer.render(
        resultsRejectingReadyInputs(
          in: plan,
          code: .confirmationRequired,
          explanation: "Confirmation is required before the Trash Input can be moved."
        ),
        output: plan.output
      )
    }
    switch decision(from: prompt.readResponse(prompt: batchPrompt(for: plan))) {
    case .approved:
      return execute(plan)
    case let .rejected(code, reason, _):
      return renderer.render(
        resultsRejectingReadyInputs(
          in: plan,
          code: code,
          explanation: "\(reason); no Trash Inputs were moved"
        ),
        output: plan.output
      )
    }
  }

  private func executeWithPerInputConfirmation(_ plan: TrashPlan) -> CommandResult {
    guard let prompt = interactivePrompt(for: plan) else {
      return renderer.render(
        resultsRejectingReadyInputs(
          in: plan,
          code: .confirmationRequired,
          explanation: "Confirmation is required before the Trash Input can be moved."
        ),
        output: plan.output
      )
    }
    var results: [TrashResult] = []
    results.reserveCapacity(plan.entries.count)
    var skipReason: TrashSkipReason?

    for entry in plan.entries {
      if let skipReason {
        results.append(skippedResult(for: entry, reason: skipReason))
        continue
      }
      let entryResult: TrashResult
      let confirmationWasInterrupted: Bool
      switch entry {
      case let .input(input):
        switch decision(from: prompt.readResponse(prompt: itemPrompt(for: input))) {
        case .approved:
          entryResult = execute(input)
          confirmationWasInterrupted = false
        case let .rejected(code, reason, stopsFurtherPrompts):
          entryResult = rejectedResult(
            path: input.path,
            kind: input.kind,
            code: code,
            explanation: "\(reason); the Trash Input was not moved",
            failureExitSuppressed: true
          )
          confirmationWasInterrupted = stopsFurtherPrompts
        }
      case .missing, .inaccessible:
        entryResult = result(for: entry)
        confirmationWasInterrupted = false
      }
      results.append(entryResult)
      if confirmationWasInterrupted {
        skipReason = .confirmationInterrupted
      } else if plan.stopOnError && entryResult.representsOperationFailure {
        skipReason = .stoppedAfterFailure
      }
    }
    return renderer.render(results, output: plan.output)
  }

  private func resultsRejectingReadyInputs(
    in plan: TrashPlan,
    code: TrashErrorCode,
    explanation: String
  ) -> [TrashResult] {
    plan.entries.map { entry in
      switch entry {
      case let .input(input):
        rejectedResult(
          path: input.path,
          kind: input.kind,
          code: code,
          explanation: explanation
        )
      case .missing, .inaccessible:
        result(for: entry)
      }
    }
  }

  private func execute(_ input: TrashInput) -> TrashResult {
    SingleTrashExecutor(
      fileSystem: fileSystem,
      makeTrashClient: makeTrashClient
    ).execute(input)
  }

  private func interactivePrompt(for plan: TrashPlan) -> (any ConfirmationPrompt)? {
    guard !plan.nonInteractive, let makeConfirmationPrompt else { return nil }
    let prompt = makeConfirmationPrompt()
    return prompt.isInputTTY ? prompt : nil
  }

  private func batchPrompt(for plan: TrashPlan) -> String {
    let directoryCount = plan.inputs.count { $0.kind == .directory }
    let itemNoun = plan.inputs.count == 1 ? "item" : "items"
    let directoryNoun = directoryCount == 1 ? "directory" : "directories"
    return
      "Move \(plan.inputs.count) \(itemNoun), including \(directoryCount) \(directoryNoun), "
      + "to Trash? [y/N] "
  }

  private func itemPrompt(for input: TrashInput) -> String {
    "Move [\(input.kind.rawValue)] \(DryRunRenderer().renderPath(input.path)) to Trash? [y/N] "
  }

  private func decision(from response: ConfirmationResponse) -> ConfirmationDecision {
    guard case let .answer(answer) = response else { return .interrupted }
    let words = answer.split(whereSeparator: { $0.isWhitespace })
    guard let word = words.first, words.count == 1 else {
      return words.isEmpty ? .declined : .invalid
    }
    switch word.lowercased() {
    case "y", "yes": return .approved
    case "n", "no": return .declined
    default: return .invalid
    }
  }

}
private enum ConfirmationDecision {
  case approved
  case rejected(
    code: TrashErrorCode,
    reason: String,
    stopsFurtherPrompts: Bool
  )

  static let declined = rejected(
    code: .confirmationDeclined,
    reason: "confirmation was declined",
    stopsFurtherPrompts: false
  )
  static let invalid = rejected(
    code: .confirmationInvalidResponse,
    reason: "confirmation response was invalid",
    stopsFurtherPrompts: false
  )
  static let interrupted = rejected(
    code: .confirmationInterrupted,
    reason: "confirmation input was interrupted",
    stopsFurtherPrompts: true
  )
}
