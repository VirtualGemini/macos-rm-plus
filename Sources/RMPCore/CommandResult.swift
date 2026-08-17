// SPDX-License-Identifier: Apache-2.0

enum ExitStatus: Int32, Sendable {
  case success = 0
  case failure = 1
  case usage = 64
}

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
