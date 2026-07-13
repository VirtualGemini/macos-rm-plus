// SPDX-License-Identifier: Apache-2.0

public struct CLIApplication<FileSystem: TrashPlanningFileSystem> {
  private let dryRunApplication: DryRunApplication<FileSystem>
  private let renderer = DryRunRenderer()

  public init(fileSystem: FileSystem) {
    dryRunApplication = DryRunApplication(fileSystem: fileSystem)
  }

  public func run(arguments: [String]) -> CommandResult {
    let command: ParsedCommand
    do {
      command = try CommandParser.parse(arguments: arguments)
    } catch {
      return commandErrorResult(error)
    }

    switch command {
    case let .help(page):
      return .init(standardOutput: InformationRenderer.render(page), standardError: "", exitCode: 0)
    case .version:
      return .init(standardOutput: InformationRenderer.version, standardError: "", exitCode: 0)
    case let .operation(request):
      return runOperation(request)
    }
  }

  private func runOperation(_ request: OperationRequest) -> CommandResult {
    guard request.dryRun else {
      return .init(
        standardOutput: "",
        standardError: "rmp: only --dry-run execution is available in this build\n",
        exitCode: 2
      )
    }

    let result = dryRunApplication.run(request: request)
    guard result.exitCode == 0 else { return result }
    return .init(
      standardOutput: result.standardOutput,
      standardError: request.warnings.map(renderWarning).joined(),
      exitCode: result.exitCode
    )
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
