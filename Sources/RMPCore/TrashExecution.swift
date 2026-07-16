// SPDX-License-Identifier: Apache-2.0

public struct TrashMoveReceipt: Equatable, Sendable {
  public let destinationPath: String

  public init(destinationPath: String) {
    self.destinationPath = destinationPath
  }
}

public enum TrashErrorCode: String, Equatable, Sendable {
  case confirmationDeclined = "confirmation_declined"
  case confirmationInterrupted = "confirmation_interrupted"
  case confirmationInvalidResponse = "confirmation_invalid_response"
  case confirmationRequired = "confirmation_required"
  case inaccessibleInput = "inaccessible_input"
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

enum TrashResultStatus: String, Equatable, Sendable {
  case moved
  case rejected
  case notMoved = "not_moved"
  case stateUncertain = "state_uncertain"
}

struct TrashFailure: Equatable, Sendable {
  let code: TrashErrorCode
  let explanation: String
}

struct TrashResult: Equatable, Sendable {
  let sourcePath: String
  let destinationPath: String?
  let kind: TrashInputKind
  let status: TrashResultStatus
  let error: TrashFailure?
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
    guard input.kind != .other else {
      return TrashResult(
        sourcePath: input.path,
        destinationPath: nil,
        kind: input.kind,
        status: .rejected,
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
    let explanation =
      sourceUnchanged
      ? "The system Trash operation failed; the source entry is unchanged."
      : "The system Trash operation failed; the source entry's final state is uncertain."
    return TrashResult(
      sourcePath: input.path,
      destinationPath: nil,
      kind: input.kind,
      status: status,
      error: TrashFailure(
        code: code,
        explanation: explanation
      )
    )
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
  private let renderer = SingleTrashRenderer()

  init(
    fileSystem: FileSystem,
    makeTrashClient: @escaping () -> any TrashClient,
    makeConfirmationPrompt: (() -> any ConfirmationPrompt)? = nil
  ) {
    self.fileSystem = fileSystem
    self.makeTrashClient = makeTrashClient
    self.makeConfirmationPrompt = makeConfirmationPrompt
  }

  func run(request: TrashOperationRequest) -> CommandResult {
    do {
      let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(request: request)
      guard let input = plan.inputs.first else {
        return CommandResult(standardOutput: "", standardError: "", exitCode: 0)
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
    var operationResult = emptyResult
    for input in plan.inputs {
      operationResult = merge(operationResult, execute(input, output: plan.output))
    }
    return operationResult
  }

  private func executeAfterBatchConfirmation(_ plan: TrashPlan) -> CommandResult {
    guard let prompt = interactivePrompt(for: plan) else {
      return confirmationRequiredResult(inputs: plan.inputs)
    }
    switch decision(from: prompt.readResponse(prompt: batchPrompt(for: plan))) {
    case .approved:
      return execute(plan)
    case let .rejected(code, reason, _):
      return confirmationFailure(
        code: code,
        inputs: plan.inputs,
        explanation: "\(reason); no Trash Inputs were moved"
      )
    }
  }

  private func executeWithPerInputConfirmation(_ plan: TrashPlan) -> CommandResult {
    guard let prompt = interactivePrompt(for: plan) else {
      return confirmationRequiredResult(inputs: plan.inputs)
    }
    var operationResult = emptyResult
    for input in plan.inputs {
      let itemResult: CommandResult
      let inputWasInterrupted: Bool
      switch decision(from: prompt.readResponse(prompt: itemPrompt(for: input))) {
      case .approved:
        itemResult = execute(input, output: plan.output)
        inputWasInterrupted = false
      case let .rejected(code, reason, stopsFurtherPrompts):
        itemResult = confirmationFailure(
          code: code,
          inputs: [input],
          explanation: "\(reason); the Trash Input was not moved"
        )
        inputWasInterrupted = stopsFurtherPrompts
      }
      operationResult = merge(operationResult, itemResult)
      if inputWasInterrupted || (plan.stopOnError && itemResult.exitCode != 0) { break }
    }
    return operationResult
  }

  private func execute(_ input: TrashInput, output: OutputMode) -> CommandResult {
    let result = SingleTrashExecutor(
      fileSystem: fileSystem,
      makeTrashClient: makeTrashClient
    ).execute(input)
    return renderer.render(result, output: output)
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

  private func confirmationRequiredResult(inputs: [TrashInput]) -> CommandResult {
    confirmationFailure(
      code: .confirmationRequired,
      inputs: inputs,
      explanation: "confirmation is required before these Trash Inputs can be moved"
    )
  }

  private func confirmationFailure(
    code: TrashErrorCode,
    inputs: [TrashInput],
    explanation: String
  ) -> CommandResult {
    let sources = inputs.map { DryRunRenderer().renderPath($0.path) }.joined(separator: ", ")
    let message =
      "rmp: \(code.rawValue) for \(sources): \(explanation)\n"
    return CommandResult(
      standardOutput: "",
      standardError: message,
      exitCode: 1
    )
  }

  private func merge(_ first: CommandResult, _ second: CommandResult) -> CommandResult {
    CommandResult(
      standardOutput: first.standardOutput + second.standardOutput,
      standardError: first.standardError + second.standardError,
      exitCode: max(first.exitCode, second.exitCode)
    )
  }

  private var emptyResult: CommandResult {
    CommandResult(standardOutput: "", standardError: "", exitCode: 0)
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

private struct SingleTrashRenderer {
  private let pathRenderer = DryRunRenderer()

  func render(_ result: TrashResult, output: OutputMode) -> CommandResult {
    switch result.status {
    case .moved:
      if output == .quiet {
        return CommandResult(standardOutput: "", standardError: "", exitCode: 0)
      }
      let destination = result.destinationPath.map(pathRenderer.renderPath) ?? "<unknown>"
      return CommandResult(
        standardOutput:
          "Moved \(pathRenderer.renderPath(result.sourcePath)) to Trash at \(destination).\n",
        standardError: "",
        exitCode: 0
      )
    case .rejected, .notMoved, .stateUncertain:
      let error =
        result.error
        ?? TrashFailure(
          code: .systemTrashFailed,
          explanation: "The Trash operation failed without a classified error."
        )
      let source = pathRenderer.renderPath(result.sourcePath)
      let message =
        "rmp: \(error.code.rawValue) (\(result.status.rawValue)) for \(source): "
        + "\(error.explanation)\n"
      return CommandResult(
        standardOutput: "",
        standardError: message,
        exitCode: 1
      )
    }
  }
}
