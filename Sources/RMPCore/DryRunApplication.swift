// SPDX-License-Identifier: Apache-2.0

struct DryRunApplication<FileSystem: TrashPlanningFileSystem> {
  private let fileSystem: FileSystem
  private let renderer = DryRunRenderer()

  init(fileSystem: FileSystem) {
    self.fileSystem = fileSystem
  }

  func run(request: TrashOperationRequest) -> CommandResult {
    do {
      let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(request: request)
      return CommandResult(
        standardOutput: renderer.render(plan),
        standardError: "",
        exitCode: 0
      )
    } catch {
      return PlanningErrorRenderer().render(error)
    }
  }
}

struct PlanningErrorRenderer {
  private let renderer = DryRunRenderer()

  func render(_ error: TrashPlanningError) -> CommandResult {
    let message: String
    let exitCode: Int32
    switch error {
    case .noInputs:
      message =
        "rmp: \(TrashErrorCode.noInputs.rawValue): --dry-run requires at least one Trash Input\n"
      exitCode = 2
    case let .missingPath(path):
      message =
        "rmp: \(TrashErrorCode.missingInput.rawValue): Trash Input does not exist: "
        + "\(renderer.renderPath(path))\n"
      exitCode = 1
    case let .inaccessiblePath(path):
      message =
        "rmp: \(TrashErrorCode.inaccessibleInput.rawValue): Trash Input cannot be inspected: "
        + "\(renderer.renderPath(path))\n"
      exitCode = 1
    case let .protectedPath(path, protectedPath):
      message =
        "rmp: \(TrashErrorCode.protectedPath.rawValue) (\(protectedPath.rawValue)): "
        + "Protected Path rejected: \(renderer.renderPath(path))\n"
      exitCode = 3
    case let .unavailableProtectedPath(path, protectedPath):
      message =
        "rmp: \(TrashErrorCode.safetyIdentityUnavailable.rawValue) for "
        + "\(renderer.renderPath(path)): "
        + "safety identity unavailable: \(protectedPath.rawValue)\n"
      exitCode = 3
    }
    return CommandResult(standardOutput: "", standardError: message, exitCode: exitCode)
  }
}
