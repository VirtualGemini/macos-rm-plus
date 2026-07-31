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
                 rmp-test put-back-race-manual [--settle-seconds <n>] --test-run-id <uuid>
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
      executePutBackRace(arguments: Array(arguments.dropFirst()), restore: .finderScript)
    }
    if arguments.first == "put-back-race-manual" {
      executePutBackRace(arguments: Array(arguments.dropFirst()), restore: .manualFinderMenu)
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

  private enum PutBackRaceRestore {
    case finderScript
    case manualFinderMenu

    var scenarioName: String {
      switch self {
      case .finderScript: "put-back-race"
      case .manualFinderMenu: "put-back-race-manual"
      }
    }

    var restoreDescription: String {
      switch self {
      case .finderScript: "finder-apple-event-move"
      case .manualFinderMenu: "maintainer-finder-put-back-command"
      }
    }
  }

  private static func executePutBackRace(
    arguments: [String],
    restore: PutBackRaceRestore
  ) -> Never {
    let settleSeconds: TimeInterval
    let driverArguments: [String]
    do {
      (settleSeconds, driverArguments) = try extractSettleSeconds(arguments)
    } catch let diagnostic as TestSafetyDiagnostic {
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
      exit(2)
    } catch {
      exit(2)
    }

    let result = TestSafetyDriver.runWithInjectedRuntime(
      arguments: driverArguments,
      cleanupPolicy: .preserveRunDirectory
    ) {
      try currentRuntime()
    } operation: { context, paths in
      guard paths.isEmpty else {
        throw TestSafetyDiagnostic(
          code: .invalidCommandArguments,
          message: "\(restore.scenarioName) creates its own Test Fixture and accepts no paths."
        )
      }
      let report = try runScenario(restore, context: context, settleSeconds: settleSeconds)
      let output = """
        rmp-test build=RMP_TESTING
        run=\(context.runID.uuidString.lowercased())
        scenario=\(restore.scenarioName)
        status=complete
        first-trash=\(report.firstTrashURL.path)
        restored=\(report.restoredURL.path)
        settle-seconds=\(report.settleSeconds)
        second-trash=\(report.secondTrashURL.path)
        run-directory=\(context.runDirectoryURL.path)
        manual-check=Wait at least 5 seconds for Finder's deferred write-back, then open Trash and \
        verify Put Back is offered for manual-target below.
        manual-target=\(report.secondTrashURL.lastPathComponent)
        restore-method=\(restore.restoreDescription)

        """
      FileHandle.standardOutput.write(Data(output.utf8))
      return 0
    }
    if let diagnostic = result.diagnostic {
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    }
    exit(result.exitCode)
  }

  /// Strips `--settle-seconds <n>` before the Test Safety Context driver sees the arguments; the
  /// driver treats every unrecognized token as a path.
  private static func extractSettleSeconds(
    _ arguments: [String]
  ) throws -> (TimeInterval, [String]) {
    var settleSeconds: TimeInterval = 0
    var remaining: [String] = []
    var index = arguments.startIndex
    while index < arguments.endIndex {
      guard arguments[index] == "--settle-seconds" else {
        remaining.append(arguments[index])
        index = arguments.index(after: index)
        continue
      }
      let valueIndex = arguments.index(after: index)
      guard valueIndex < arguments.endIndex,
        let parsed = TimeInterval(arguments[valueIndex]),
        parsed >= 0, parsed <= 60
      else {
        throw TestSafetyDiagnostic(
          code: .invalidCommandArguments,
          message: "--settle-seconds requires a value between 0 and 60."
        )
      }
      settleSeconds = parsed
      index = arguments.index(after: valueIndex)
    }
    return (settleSeconds, remaining)
  }

  private static func runScenario(
    _ restore: PutBackRaceRestore,
    context: TestSafetyContext,
    settleSeconds: TimeInterval
  ) throws -> PutBackRaceReport {
    switch restore {
    case .finderScript:
      return try PutBackRaceAcceptance.run(context: context)
    case .manualFinderMenu:
      return try PutBackRaceAcceptance.runManual(
        context: context,
        settleSeconds: settleSeconds,
        announce: { message in
          FileHandle.standardOutput.write(Data("\(message)\n".utf8))
        },
        heartbeat: { remaining in
          FileHandle.standardOutput.write(Data("waiting-for-put-back=\(remaining)s\n".utf8))
        }
      )
    }
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
