// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

struct TestSafetyRuntime: Sendable {
  let effectiveUserID: uid_t
  let trustedUser: TrustedUserAccount
  let executableName: String

  static func testing(
    executableName: String,
    trustedUser: TrustedUserAccount
  ) -> TestSafetyRuntime {
    TestSafetyRuntime(
      effectiveUserID: trustedUser.userID,
      trustedUser: trustedUser,
      executableName: executableName
    )
  }
}

struct TestSafetyDriverResult: Sendable {
  let exitCode: Int32
  let diagnostic: TestSafetyDiagnostic?
}

enum TestSafetyDriver {
  static func runWithInjectedRuntime(
    arguments: [String],
    runtime: () throws -> TestSafetyRuntime,
    operation: (TestSafetyContext, [String]) throws -> Int32
  ) -> TestSafetyDriverResult {
    do {
      return run(arguments: arguments, runtime: try runtime(), operation: operation)
    } catch let diagnostic as TestSafetyDiagnostic {
      return TestSafetyDriverResult(exitCode: 2, diagnostic: diagnostic)
    } catch {
      return unexpectedFailure()
    }
  }

  static func run(
    arguments: [String],
    runtime: TestSafetyRuntime,
    establishContext: (
      _ runID: UUID,
      _ trustedUser: TrustedUserAccount,
      _ effectiveUserID: uid_t
    ) throws -> TestSafetyContext = { runID, trustedUser, effectiveUserID in
      try TestSafetyContext.establish(
        runID: runID,
        trustedUser: trustedUser,
        effectiveUserID: effectiveUserID
      )
    },
    operation: (TestSafetyContext, [String]) throws -> Int32
  ) -> TestSafetyDriverResult {
    do {
      try validateRuntime(runtime)
      let parsedArguments = try parseArguments(arguments)
      let context = try establishContext(
        parsedArguments.runID,
        runtime.trustedUser,
        runtime.effectiveUserID
      )
      let exitCode = try operation(context, parsedArguments.paths)
      try context.cleanupRunDirectory()
      return TestSafetyDriverResult(exitCode: exitCode, diagnostic: nil)
    } catch let diagnostic as TestSafetyDiagnostic {
      return TestSafetyDriverResult(exitCode: 2, diagnostic: diagnostic)
    } catch {
      return unexpectedFailure()
    }
  }

  private static func validateRuntime(_ runtime: TestSafetyRuntime) throws {
    guard runtime.executableName == "rmp-test" else {
      throw TestSafetyDiagnostic(
        code: .wrongExecutable,
        message: "The test safety driver must run from the rmp-test executable."
      )
    }
    try validateTestUserIdentity(runtime.trustedUser, effectiveUserID: runtime.effectiveUserID)
  }

  private static func parseArguments(_ arguments: [String]) throws -> ParsedTestArguments {
    var runIDText: String?
    var paths: [String] = []
    var index = arguments.startIndex
    var optionsEnded = false

    while index < arguments.endIndex {
      let argument = arguments[index]
      if !optionsEnded, argument == "--" {
        optionsEnded = true
        index = arguments.index(after: index)
      } else if !optionsEnded, argument == "--test-run-id" {
        guard runIDText == nil else {
          throw TestSafetyDiagnostic(
            code: .duplicateRunID,
            message: "--test-run-id may be supplied exactly once."
          )
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
          throw TestSafetyDiagnostic(
            code: .missingRunID,
            message: "--test-run-id requires a canonical UUID value."
          )
        }
        runIDText = arguments[valueIndex]
        index = arguments.index(after: valueIndex)
      } else {
        paths.append(argument)
        index = arguments.index(after: index)
      }
    }

    guard let runIDText else {
      throw TestSafetyDiagnostic(
        code: .missingRunID,
        message: "Every path-accepting rmp-test run requires --test-run-id."
      )
    }
    guard let runID = UUID(uuidString: runIDText), runIDText == runID.uuidString.lowercased() else {
      throw TestSafetyDiagnostic(
        code: .invalidRunID,
        message: "--test-run-id must be a canonical lowercase UUID."
      )
    }
    return ParsedTestArguments(runID: runID, paths: paths)
  }

  private static func unexpectedFailure() -> TestSafetyDriverResult {
    TestSafetyDriverResult(
      exitCode: 2,
      diagnostic: TestSafetyDiagnostic(
        code: .unexpectedError,
        message: "The test safety driver failed unexpectedly."
      )
    )
  }
}

private struct ParsedTestArguments {
  let runID: UUID
  let paths: [String]
}
