// SPDX-License-Identifier: Apache-2.0

public struct CLIApplication<FileSystem: TrashPlanningFileSystem> {
  private let makeFileSystem: () -> FileSystem
  private let makeTrashClient: (() -> any TrashClient)?
  private let makeConfirmationPrompt: (() -> any ConfirmationPrompt)?
  private let effectiveUserID: () -> UInt32
  private let renderer = DryRunRenderer()

  public init(makeFileSystem: @escaping () -> FileSystem) {
    self.makeFileSystem = makeFileSystem
    makeTrashClient = nil
    makeConfirmationPrompt = nil
    effectiveUserID = { 1 }
  }

  public init(
    makeFileSystem: @escaping () -> FileSystem,
    makeTrashClient: @escaping () -> any TrashClient,
    effectiveUserID: @escaping () -> UInt32
  ) {
    self.makeFileSystem = makeFileSystem
    self.makeTrashClient = makeTrashClient
    makeConfirmationPrompt = nil
    self.effectiveUserID = effectiveUserID
  }

  public init(
    makeFileSystem: @escaping () -> FileSystem,
    makeTrashClient: @escaping () -> any TrashClient,
    effectiveUserID: @escaping () -> UInt32,
    makeConfirmationPrompt: @escaping () -> any ConfirmationPrompt
  ) {
    self.makeFileSystem = makeFileSystem
    self.makeTrashClient = makeTrashClient
    self.makeConfirmationPrompt = makeConfirmationPrompt
    self.effectiveUserID = effectiveUserID
  }

  public func run(arguments: [String]) -> CommandResult {
    let invocation: ParsedInvocation
    do {
      invocation = try CommandParser.parse(arguments: arguments)
    } catch {
      return commandErrorResult(error)
    }

    switch invocation.command {
    case let .help(page):
      return .init(
        standardOutput: InformationRenderer.render(page),
        standardError: renderWarnings(invocation.warnings),
        exitCode: 0
      )
    case .version:
      return .init(
        standardOutput: InformationRenderer.version,
        standardError: renderWarnings(invocation.warnings),
        exitCode: 0
      )
    case let .operation(request):
      return runOperation(request, warnings: invocation.warnings)
    }
  }

  private func runOperation(
    _ request: TrashOperationRequest, warnings: [CompatibilityWarning]
  ) -> CommandResult {
    if !request.dryRun, effectiveUserID() == 0 {
      let sources = request.paths.map(renderer.renderPath).joined(separator: ", ")
      let inputNoun = request.paths.count == 1 ? "Trash Input" : "Trash Inputs"
      let message =
        "rmp: \(TrashErrorCode.rootExecution.rawValue): refusing to move \(inputNoun) \(sources) "
        + "while running as root because Trash ownership and recovery would be unsafe\n"
      return .init(
        standardOutput: "",
        standardError: renderWarnings(warnings) + message,
        exitCode: 3
      )
    }
    if request.dryRun {
      let result = DryRunApplication(fileSystem: makeFileSystem()).run(request: request)
      return .init(
        standardOutput: result.standardOutput,
        standardError: renderWarnings(warnings) + result.standardError,
        exitCode: result.exitCode
      )
    }
    guard request.output != .json else {
      let source = renderer.renderPath(request.paths[0])
      return .init(
        standardOutput: "",
        standardError:
          renderWarnings(warnings)
          + "rmp: \(TrashErrorCode.unsupportedOutputMode.rawValue) for \(source): "
          + "JSON Trash Operation results are not available in this build\n",
        exitCode: 2
      )
    }
    guard let makeTrashClient else {
      return .init(
        standardOutput: "",
        standardError:
          renderWarnings(warnings) + "rmp: only --dry-run execution is available in this build\n",
        exitCode: 2
      )
    }
    let result = SingleTrashApplication(
      fileSystem: makeFileSystem(),
      makeTrashClient: makeTrashClient,
      makeConfirmationPrompt: makeConfirmationPrompt
    ).run(request: request)
    return .init(
      standardOutput: result.standardOutput,
      standardError: renderWarnings(warnings) + result.standardError,
      exitCode: result.exitCode
    )
  }

  private func renderWarnings(_ warnings: [CompatibilityWarning]) -> String {
    warnings.map(renderWarning).joined()
  }

  private func renderWarning(_ warning: CompatibilityWarning) -> String {
    switch warning {
    case .secureOverwriteIgnored:
      "rmp: warning: -P does not securely overwrite; the item will only be moved to Trash\n"
    }
  }

  private func commandErrorResult(_ error: CommandParsingError) -> CommandResult {
    let message: String
    switch error {
    case .noInputs:
      message = "rmp: at least one Trash Input is required\n"
    case let .unknownOption(option):
      message = "rmp: unknown option \(renderer.renderPath(option))\n"
    case let .invalidConfirmationMode(mode):
      message = "rmp: invalid confirmation mode \(renderer.renderPath(mode))\n"
    case let .conflictingOptions(first, second):
      message = "rmp: conflicting options \(first) and \(second)\n"
    case let .unsupportedCompatibilityOption(option):
      message = "rmp: unsupported Compatibility Option \(option)\n"
    case let .strictCompatibilityOption(option):
      message = "rmp: Compatibility Option \(option) is not allowed with --strict-options\n"
    case .conflictingInformationCommands:
      message = "rmp: --help and --version cannot be used together\n"
    case let .helpModifierRequiresHelp(option):
      message = "rmp: \(option) is only valid with --help\n"
    }
    return CommandResult(standardOutput: "", standardError: message, exitCode: 2)
  }
}
