// SPDX-License-Identifier: Apache-2.0

struct TrashResultRenderer {
  private let pathRenderer = DryRunRenderer()
  private let currentDirectoryPath: String?
  private let unclassifiedFailure = TrashFailure(
    code: .systemTrashFailed,
    explanation: "The Trash operation failed without a classified error."
  )

  init(currentDirectoryPath: String? = nil) {
    self.currentDirectoryPath = currentDirectoryPath
  }

  func render(_ result: TrashResult, output: OutputMode) -> CommandResult {
    switch result.status {
    case .moved:
      let destination = result.destinationPath.map(pathRenderer.renderPath) ?? "<unknown>"
      let standardOutput =
        output == .quiet
        ? ""
        : "Moved \(pathRenderer.renderPath(result.sourcePath)) to Trash at \(destination).\n"
      let warningOutput = result.warnings.map { render($0, sourcePath: result.sourcePath) }.joined()
      return CommandResult(
        standardOutput: standardOutput,
        standardError: warningOutput,
        exitCode: result.requiresFailureExit
          ? ExitStatus.failure.rawValue
          : ExitStatus.success.rawValue
      )
    case .skipped:
      let explanation =
        switch result.skipReason {
        case .confirmationInterrupted:
          "after confirmation input was interrupted"
        case .ignoredMissing:
          "because the missing Trash Input was ignored"
        case .stoppedAfterFailure, nil:
          "after an earlier failure"
        }
      let standardOutput =
        output == .verbose
        ? "Skipped \(pathRenderer.renderPath(result.sourcePath)) \(explanation).\n"
        : ""
      return CommandResult(
        standardOutput: standardOutput,
        standardError: "",
        exitCode: ExitStatus.success.rawValue
      )
    case .rejected, .notMoved, .stateUncertain:
      let error = result.error ?? unclassifiedFailure
      let source = pathRenderer.renderPath(result.sourcePath)
      let message =
        "rmp: \(error.code.rawValue) (\(result.status.rawValue)) for \(source): "
        + "\(error.explanation)\n"
      return CommandResult(
        standardOutput: "",
        standardError: message,
        exitCode: ExitStatus.failure.rawValue
      )
    }
  }

  func render(_ results: [TrashResult], output: OutputMode) -> CommandResult {
    if output == .json, let currentDirectoryPath {
      return JSONTrashRenderer().render(
        results: results,
        dryRun: false,
        currentDirectoryPath: currentDirectoryPath
      )
    }
    let itemResults = results.map { render($0, output: output) }
    let standardError = itemResults.map(\.standardError).joined()
    let exitCode: Int32 =
      results.contains(where: \.requiresFailureExit)
      ? ExitStatus.failure.rawValue
      : ExitStatus.success.rawValue
    let standardOutput: String
    if output == .standard, results.count > 1 {
      standardOutput = renderSummary(results)
    } else {
      standardOutput = itemResults.map(\.standardOutput).joined()
    }
    return CommandResult(
      standardOutput: standardOutput,
      standardError: standardError,
      exitCode: exitCode
    )
  }

  private func renderSummary(_ results: [TrashResult]) -> String {
    let movedCount = results.count { $0.status == .moved }
    let failedCount = results.count {
      $0.status == .rejected || $0.status == .notMoved || $0.status == .stateUncertain
    }
    let warningCount = results.reduce(0) { $0 + $1.warnings.count }
    let skippedCount = results.count { $0.status == .skipped }
    let itemNoun = movedCount == 1 ? "item" : "items"
    let warningNoun = warningCount == 1 ? "warning" : "warnings"
    let warningSummary = warningCount == 0 ? "" : "; \(warningCount) \(warningNoun)"
    let skippedSummary = skippedCount == 0 ? "" : "; \(skippedCount) skipped"
    return
      "Moved \(movedCount) \(itemNoun) to Trash; \(failedCount) failed\(warningSummary)"
      + "\(skippedSummary).\n"
  }

  private func render(_ warning: TrashMoveWarning, sourcePath: String) -> String {
    let explanation: String
    switch warning.code {
    case .finalizerCleanupFailed:
      explanation =
        "Put Back was activated, but an internal symbolic-link finalizer could not be cleaned up."
    case .finalizerStateUncertain:
      explanation =
        "The finalizer call failed after its source state changed; "
        + "Put Back and cleanup could not be confirmed."
    case .symlinkPutBackNotGuaranteed:
      explanation =
        "The item was moved to Trash, but Finder Put Back could not be guaranteed."
    }
    return
      "rmp: \(warning.code.rawValue) (moved) for \(pathRenderer.renderPath(sourcePath)): "
      + "\(explanation)\n"
  }
}
