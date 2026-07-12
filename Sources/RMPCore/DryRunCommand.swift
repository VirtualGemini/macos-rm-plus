// SPDX-License-Identifier: Apache-2.0

struct DryRunRequest: Equatable, Sendable {
  let paths: [String]
}

enum DryRunCommandError: Error, Equatable, Sendable {
  case dryRunRequired
  case noInputs
  case unknownOption(String)
}

enum DryRunCommand {
  static func parse(arguments: [String]) throws(DryRunCommandError) -> DryRunRequest {
    var dryRun = false
    var optionsEnded = false
    var paths: [String] = []

    for argument in arguments {
      if optionsEnded {
        paths.append(argument)
      } else if argument == "--" {
        optionsEnded = true
      } else if argument == "--dry-run" {
        dryRun = true
      } else if argument.hasPrefix("-") {
        throw .unknownOption(argument)
      } else {
        paths.append(argument)
      }
    }

    guard dryRun else {
      throw .dryRunRequired
    }
    guard !paths.isEmpty else {
      throw .noInputs
    }

    return DryRunRequest(paths: paths)
  }
}
