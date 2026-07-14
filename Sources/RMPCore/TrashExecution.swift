// SPDX-License-Identifier: Apache-2.0

public struct TrashMoveReceipt: Equatable, Sendable {
  public let destinationPath: String

  public init(destinationPath: String) {
    self.destinationPath = destinationPath
  }
}

public enum TrashErrorCode: String, Equatable, Sendable {
  case confirmationRequired = "confirmation_required"
  case inaccessibleInput = "inaccessible_input"
  case missingInput = "missing_input"
  case noInputs = "no_inputs"
  case protectedPath = "protected_path"
  case rootExecution = "root_execution"
  case safetyIdentityUnavailable = "safety_identity_unavailable"
  case systemTrashFailed = "trash_system_call_failed"
  case unsupportedInputKind = "unsupported_input_kind"
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

enum TrashResultStatus: String, Equatable, Sendable {
  case moved
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
        status: .notMoved,
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
    let status: TrashResultStatus = sourceIsUnchanged(input) ? .notMoved : .stateUncertain
    return TrashResult(
      sourcePath: input.path,
      destinationPath: nil,
      kind: input.kind,
      status: status,
      error: TrashFailure(
        code: code,
        explanation: failureExplanation(status: status)
      )
    )
  }

  private func sourceIsUnchanged(_ input: TrashInput) -> Bool {
    guard case let .entry(entry) = fileSystem.inspectEntry(at: input.path) else {
      return false
    }
    return entry.identity == input.plannedIdentity && entry.kind == input.kind
  }

  private func failureExplanation(status: TrashResultStatus) -> String {
    switch status {
    case .moved:
      "The Trash Input was moved to Trash."
    case .notMoved:
      "The system Trash operation failed; the source entry is unchanged."
    case .stateUncertain:
      "The system Trash operation failed; the source entry's final state is uncertain."
    }
  }
}

struct SingleTrashApplication<FileSystem: TrashPlanningFileSystem> {
  private let fileSystem: FileSystem
  private let makeTrashClient: () -> any TrashClient
  private let renderer = SingleTrashRenderer()

  init(
    fileSystem: FileSystem,
    makeTrashClient: @escaping () -> any TrashClient
  ) {
    self.fileSystem = fileSystem
    self.makeTrashClient = makeTrashClient
  }

  func run(request: TrashOperationRequest) -> CommandResult {
    do {
      let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(request: request)
      guard let input = plan.inputs.first else {
        return CommandResult(standardOutput: "", standardError: "", exitCode: 0)
      }
      guard canProceedWithoutConfirmation(plan: plan, input: input) else {
        let source = DryRunRenderer().renderPath(input.path)
        let message =
          "rmp: \(TrashErrorCode.confirmationRequired.rawValue) for \(source): "
          + "confirmation is required before this Trash Input can be moved\n"
        return CommandResult(
          standardOutput: "",
          standardError: message,
          exitCode: 1
        )
      }
      let result = SingleTrashExecutor(
        fileSystem: fileSystem,
        makeTrashClient: makeTrashClient
      ).execute(input)
      return renderer.render(result, output: plan.output)
    } catch {
      return PlanningErrorRenderer().render(error)
    }
  }

  private func canProceedWithoutConfirmation(plan: TrashPlan, input: TrashInput) -> Bool {
    switch plan.confirmation {
    case .never:
      true
    case .smart:
      input.kind != .directory
    case .once, .each, .conditionalOnce:
      false
    }
  }
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
    case .notMoved, .stateUncertain:
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
