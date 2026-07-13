// SPDX-License-Identifier: Apache-2.0

public struct CLIApplication<FileSystem: TrashPlanningFileSystem> {
  private let makeFileSystem: () -> FileSystem
  private let renderer = DryRunRenderer()

  public init(makeFileSystem: @escaping () -> FileSystem) {
    self.makeFileSystem = makeFileSystem
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
    guard request.dryRun else {
      return .init(
        standardOutput: "",
        standardError:
          renderWarnings(warnings) + "rmp: only --dry-run execution is available in this build\n",
        exitCode: 2
      )
    }

    let result = DryRunApplication(fileSystem: makeFileSystem()).run(request: request)
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
