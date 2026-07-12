// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

struct TestSafetyRuntime: Sendable {
  let effectiveUserID: uid_t
  let trustedUser: TrustedUserAccount
  let executableName: String
  let testingBuildEnabled: Bool

  static func testing(
    executableName: String,
    trustedUser: TrustedUserAccount
  ) -> TestSafetyRuntime {
    TestSafetyRuntime(
      effectiveUserID: trustedUser.userID,
      trustedUser: trustedUser,
      executableName: executableName,
      testingBuildEnabled: true
    )
  }
}

@_spi(RMPTestingEntrypoint)
public struct TestSafetyDriverResult: Sendable {
  public let exitCode: Int32
  public let diagnostic: TestSafetyDiagnostic?
}

@_spi(RMPTestingEntrypoint)
public enum TestSafetyDriver {
  @_spi(RMPTestingEntrypoint)
  public static func run(
    arguments: [String],
    operation: (TestSafetyContext, [String]) throws -> Int32
  ) -> TestSafetyDriverResult {
    do {
      let effectiveUserID = geteuid()
      let runtime = TestSafetyRuntime(
        effectiveUserID: effectiveUserID,
        trustedUser: try TrustedUserAccount.current(effectiveUserID: effectiveUserID),
        executableName: try LoadedExecutableIdentity.currentName(),
        testingBuildEnabled: TestingBuildIdentity.isEnabled
      )
      return run(arguments: arguments, runtime: runtime, operation: operation)
    } catch let diagnostic as TestSafetyDiagnostic {
      return TestSafetyDriverResult(exitCode: 2, diagnostic: diagnostic)
    } catch {
      return unexpectedFailure()
    }
  }

  static func run(
    arguments: [String],
    runtime: TestSafetyRuntime,
    operation: (TestSafetyContext, [String]) throws -> Int32
  ) -> TestSafetyDriverResult {
    do {
      try validateRuntime(runtime)
      let runID = try parseRunID(arguments)
      let context = try TestSafetyContext.establish(
        runID: runID,
        trustedUser: runtime.trustedUser,
        effectiveUserID: runtime.effectiveUserID
      )
      let exitCode = try operation(context, pathArguments(from: arguments))
      try context.cleanupRunDirectory()
      return TestSafetyDriverResult(exitCode: exitCode, diagnostic: nil)
    } catch let diagnostic as TestSafetyDiagnostic {
      return TestSafetyDriverResult(exitCode: 2, diagnostic: diagnostic)
    } catch {
      return unexpectedFailure()
    }
  }

  private static func validateRuntime(_ runtime: TestSafetyRuntime) throws {
    guard runtime.testingBuildEnabled else {
      throw TestSafetyDiagnostic(
        code: .testingBuildRequired,
        message: "The rmp-test driver requires the compile-time RMP_TESTING build flag."
      )
    }
    guard runtime.executableName == "rmp-test" else {
      throw TestSafetyDiagnostic(
        code: .wrongExecutable,
        message: "The test safety driver must run from the rmp-test executable."
      )
    }
    try validateTestUserIdentity(runtime.trustedUser, effectiveUserID: runtime.effectiveUserID)
  }

  private static func parseRunID(_ arguments: [String]) throws -> UUID {
    var runIDText: String?
    var index = arguments.startIndex

    while index < arguments.endIndex {
      let argument = arguments[index]
      if argument == "--test-run-id" {
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
    return runID
  }

  private static func pathArguments(from arguments: [String]) -> [String] {
    var paths: [String] = []
    var index = arguments.startIndex
    while index < arguments.endIndex {
      if arguments[index] == "--test-run-id" {
        index = arguments.index(index, offsetBy: 2)
      } else {
        paths.append(arguments[index])
        index = arguments.index(after: index)
      }
    }
    return paths
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

private enum TestingBuildIdentity {
  static var isEnabled: Bool {
    guard let processHandle = dlopen(nil, RTLD_LAZY) else { return false }
    defer { dlclose(processHandle) }
    return dlsym(processHandle, "rmp_testing_build_identity") != nil
  }
}

private enum LoadedExecutableIdentity {
  static func currentName() throws -> String {
    var requiredSize: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &requiredSize)
    guard requiredSize > 0 else { throw executableIdentityUnavailable() }
    var buffer = [CChar](repeating: 0, count: Int(requiredSize))
    guard _NSGetExecutablePath(&buffer, &requiredSize) == 0 else {
      throw executableIdentityUnavailable()
    }
    let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    guard let path = String(bytes: pathBytes, encoding: .utf8), !path.isEmpty else {
      throw executableIdentityUnavailable()
    }
    return URL(fileURLWithPath: path).lastPathComponent
  }

  private static func executableIdentityUnavailable() -> TestSafetyDiagnostic {
    TestSafetyDiagnostic(
      code: .executableIdentityUnavailable,
      message: "The loaded executable identity could not be obtained from macOS."
    )
  }
}
