// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

#if !RMP_TESTING
  #error("rmp-test must only be built with RMP_TESTING enabled")
#endif

RMPTestEntrypoint.execute(arguments: Array(CommandLine.arguments.dropFirst()))

private enum RMPTestEntrypoint {
  static func execute(arguments: [String]) -> Never {
    if arguments.first == "--help" {
      FileHandle.standardOutput.write(
        Data(
          """
          Usage: rmp-test put-back-race --test-run-id <uuid>
                 rmp-test [--test-run-id <uuid>] [--] <PATH>...

          """.utf8
        )
      )
      exit(0)
    }
    if arguments.first == "--version" {
      FileHandle.standardOutput.write(Data("rmp-test build=RMP_TESTING\n".utf8))
      exit(0)
    }
    if arguments.first == "put-back-race" {
      executePutBackRace(arguments: Array(arguments.dropFirst()))
    }

    let result = TestSafetyDriver.runWithInjectedRuntime(arguments: arguments) {
      try currentRuntime()
    } operation: { context, _ in
      let message =
        "rmp-test build=RMP_TESTING run=\(context.runID.uuidString.lowercased()) ready\n"
      FileHandle.standardOutput.write(Data(message.utf8))
      return 0
    }
    if let diagnostic = result.diagnostic {
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    }
    exit(result.exitCode)
  }

  private static func executePutBackRace(arguments: [String]) -> Never {
    let result = TestSafetyDriver.runWithInjectedRuntime(
      arguments: arguments,
      cleanupPolicy: .preserveRunDirectory
    ) {
      try currentRuntime()
    } operation: { context, paths in
      guard paths.isEmpty else {
        throw TestSafetyDiagnostic(
          code: .invalidCommandArguments,
          message: "put-back-race creates its own Test Fixture and accepts no paths."
        )
      }
      let report = try PutBackRaceAcceptance.run(context: context)
      let output = """
        rmp-test build=RMP_TESTING
        run=\(context.runID.uuidString.lowercased())
        scenario=put-back-race
        status=complete
        first-trash=\(report.firstTrashURL.path)
        restored=\(report.restoredURL.path)
        second-trash=\(report.secondTrashURL.path)
        run-directory=\(context.runDirectoryURL.path)
        manual-check=Open Finder Trash now and verify Put Back is available.
        manual-target=\(report.secondTrashURL.lastPathComponent)

        """
      FileHandle.standardOutput.write(Data(output.utf8))
      return 0
    }
    if let diagnostic = result.diagnostic {
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    }
    exit(result.exitCode)
  }

  private static func currentRuntime() throws -> TestSafetyRuntime {
    let effectiveUserID = geteuid()
    return TestSafetyRuntime(
      effectiveUserID: effectiveUserID,
      trustedUser: try TrustedUserAccount.current(effectiveUserID: effectiveUserID),
      executableName: try loadedExecutableName()
    )
  }
}

private func loadedExecutableName() throws -> String {
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

private func executableIdentityUnavailable() -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(
    code: .executableIdentityUnavailable,
    message: "The loaded executable identity could not be obtained from macOS."
  )
}
