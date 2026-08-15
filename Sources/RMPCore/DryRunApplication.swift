// SPDX-License-Identifier: Apache-2.0

struct DryRunApplication<FileSystem: TrashPlanningFileSystem> {
  private let fileSystem: FileSystem
  private let renderer = DryRunRenderer()
  private let jsonRenderer = JSONTrashRenderer()

  init(fileSystem: FileSystem) {
    self.fileSystem = fileSystem
  }

  func run(request: TrashOperationRequest) -> CommandResult {
    do {
      let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(request: request)
      if request.output == .json {
        return jsonRenderer.render(
          plan: plan,
          currentDirectoryPath: fileSystem.currentDirectoryPath
        )
      }
      if let error = plan.entries.compactMap(\.planningError).first {
        return PlanningErrorRenderer().render(error)
      }
      return CommandResult(
        standardOutput: renderer.render(plan),
        standardError: "",
        exitCode: ExitStatus.success.rawValue
      )
    } catch {
      if request.output == .json {
        return jsonRenderer.render(
          error: error,
          request: request,
          currentDirectoryPath: fileSystem.currentDirectoryPath
        )
      }
      return PlanningErrorRenderer().render(error)
    }
  }
}

struct PlanningErrorRenderer {
  private let renderer = DryRunRenderer()

  func render(_ error: TrashPlanningError) -> CommandResult {
    let message: String
    switch error {
    case .noInputs:
      message =
        "rmp: \(error.code.rawValue): --dry-run requires at least one Trash Input\n"
    case let .missingPath(path):
      message =
        "rmp: \(error.code.rawValue): Trash Input does not exist: "
        + "\(renderer.renderPath(path))\n"
    case let .inaccessiblePath(path):
      message =
        "rmp: \(error.code.rawValue): Trash Input cannot be inspected: "
        + "\(renderer.renderPath(path))\n"
    case let .protectedPath(path, protectedPath):
      message =
        "rmp: \(error.code.rawValue) (\(protectedPath.rawValue)): "
        + "Protected Path rejected: \(renderer.renderPath(path))\n"
    case let .unavailableProtectedPath(path, protectedPath):
      message =
        "rmp: \(error.code.rawValue) for "
        + "\(renderer.renderPath(path)): "
        + "safety identity unavailable: \(protectedPath.rawValue)\n"
    }
    return CommandResult(standardOutput: "", standardError: message, exitCode: error.exitCode)
  }
}
