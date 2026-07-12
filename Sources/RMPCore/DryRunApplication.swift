// SPDX-License-Identifier: Apache-2.0

public struct CommandResult: Equatable, Sendable {
  public let standardOutput: String
  public let standardError: String
  public let exitCode: Int32

  public init(standardOutput: String, standardError: String, exitCode: Int32) {
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.exitCode = exitCode
  }
}

public struct DryRunApplication<FileSystem: TrashPlanningFileSystem> {
  private let fileSystem: FileSystem
  private let renderer = DryRunRenderer()

  public init(fileSystem: FileSystem) {
    self.fileSystem = fileSystem
  }

  public func run(arguments: [String]) -> CommandResult {
    let request: DryRunRequest
    do {
      request = try DryRunCommand.parse(arguments: arguments)
    } catch {
      return commandErrorResult(error)
    }

    do {
      let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(paths: request.paths)
      return CommandResult(
        standardOutput: renderer.render(plan),
        standardError: "",
        exitCode: 0
      )
    } catch {
      return planningErrorResult(error)
    }
  }

  private func commandErrorResult(_ error: DryRunCommandError) -> CommandResult {
    let message: String
    switch error {
    case .dryRunRequired:
      message = "rmp: only --dry-run is available in this build\n"
    case .noInputs:
      message = "rmp: --dry-run requires at least one Trash Input\n"
    case let .unknownOption(option):
      message = "rmp: unknown option \(renderer.renderPath(option))\n"
    }
    return CommandResult(standardOutput: "", standardError: message, exitCode: 2)
  }

  private func planningErrorResult(_ error: TrashPlanningError) -> CommandResult {
    let message: String
    let exitCode: Int32
    switch error {
    case .noInputs:
      message = "rmp: --dry-run requires at least one Trash Input\n"
      exitCode = 2
    case let .missingPath(path):
      message = "rmp: Trash Input does not exist: \(renderer.renderPath(path))\n"
      exitCode = 1
    case let .inaccessiblePath(path):
      message = "rmp: Trash Input cannot be inspected: \(renderer.renderPath(path))\n"
      exitCode = 1
    case let .protectedPath(path, protectedPath):
      message =
        "rmp: Protected Path rejected (\(protectedPath.rawValue)): \(renderer.renderPath(path))\n"
      exitCode = 3
    case let .unavailableProtectedPath(protectedPath):
      message = "rmp: safety identity unavailable: \(protectedPath.rawValue)\n"
      exitCode = 3
    }
    return CommandResult(standardOutput: "", standardError: message, exitCode: exitCode)
  }
}
