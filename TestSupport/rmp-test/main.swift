// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

#if !RMP_TESTING
  #error("rmp-test must only be built with RMP_TESTING enabled")
#endif

private let helpText = """
  Usage: rmp-test put-back-race --test-run-id <uuid>
         rmp-test put-back-race-manual [OPTIONS] --test-run-id <uuid>
         rmp-test put-back-symlink-delay-manual [OPTIONS] --test-run-id <uuid>
         rmp-test put-back-symlink-finalizer-manual [OPTIONS] --test-run-id <uuid>
         rmp-test put-back-symlink-production-manual [OPTIONS] --test-run-id <uuid>
         rmp-test [--test-run-id <uuid>] [--] <PATH>...

  put-back-race-manual options:
    --settle-seconds <n>  re-trash delay bucket, 0-60, default 0
    --cycles <n>          differential cycles, 1-30, default 1
    --fixture <kind>      file | directory | symbolic-link |
                          broken-symbolic-link | quoted-name | newline-name

  put-back-symlink-delay-manual options:
    --settle-seconds <n>  pre-Trash delay after Put Back, 0-60, default 0
    --cycles <n>          differential cycles, 1-30, default 1
    --fixture <kind>      symbolic-link | broken-symbolic-link

  put-back-symlink-finalizer-manual options:
    --cycles <n>          finalizer validation cycles, 1-30, default 1
    --fixture <kind>      symbolic-link | broken-symbolic-link

  put-back-symlink-production-manual options:
    --cycles <n>          production finalizer validation cycles, 1-30, default 1
    --fixture <kind>      symbolic-link | broken-symbolic-link

  """

private enum RMPTestEntrypoint {
  static func execute(arguments: [String]) -> Never {
    if arguments.first == "--help" {
      FileHandle.standardOutput.write(Data(helpText.utf8))
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
    if arguments.first == "put-back-symlink-delay-manual" {
      executePutBackRace(
        arguments: Array(arguments.dropFirst()),
        restore: .manualFoundationSymlinkDelay
      )
    }
    if arguments.first == "put-back-symlink-finalizer-manual" {
      executePutBackRace(
        arguments: Array(arguments.dropFirst()),
        restore: .manualFoundationSymlinkFinalizer
      )
    }
    if arguments.first == "put-back-symlink-production-manual" {
      executePutBackRace(
        arguments: Array(arguments.dropFirst()),
        restore: .manualProductionSymlinkFinalizer
      )
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

  private static func executePutBackRace(
    arguments: [String],
    restore: PutBackRaceRestore
  ) -> Never {
    let options = parseRaceOptions(arguments, defaultKind: restore.defaultFixtureKind)
    let settleSeconds = options.settleSeconds
    let cycles = options.cycles
    let driverArguments = options.driverArguments
    rejectNonzeroFinalizerDelay(restore: restore, settleSeconds: settleSeconds)

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
      try validateFixtureKind(
        options.kind,
        backend: restore.trashBackend,
        scenarioName: restore.scenarioName
      )
      if cycles > 1 {
        guard restore.supportsCycles else {
          throw TestSafetyDiagnostic(
            code: .invalidCommandArguments,
            message: "--cycles is available only for a manual Put Back scenario."
          )
        }
        let reports = try runManualDifferential(
          context: context,
          cycles: cycles,
          kind: options.kind,
          restore: restore,
          settleSeconds: settleSeconds
        )
        writeDifferentialSummary(
          reports,
          cycles: cycles,
          kind: options.kind,
          restore: restore,
          context: context
        )
        return 0
      }
      let report = try runScenario(
        restore,
        context: context,
        kind: options.kind,
        settleSeconds: settleSeconds
      )
      writeSingleRunSummary(report, restore: restore, kind: options.kind, context: context)
      return 0
    }
    if let diagnostic = result.diagnostic {
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    }
    exit(result.exitCode)
  }

  private static func rejectNonzeroFinalizerDelay(
    restore: PutBackRaceRestore,
    settleSeconds: TimeInterval
  ) {
    guard restore.requiresZeroSettle, settleSeconds != 0 else { return }
    let diagnostic = TestSafetyDiagnostic(
      code: .invalidCommandArguments,
      message: "\(restore.scenarioName) requires zero settle delay."
    )
    FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    exit(2)
  }

  private static func parseRaceOptions(
    _ arguments: [String],
    defaultKind: PutBackRaceFixtureKind
  ) -> RaceOptions {
    do {
      let (settleSeconds, afterSettle) = try extractSettleSeconds(arguments)
      let (cycles, afterCycles) = try extractCycles(afterSettle)
      let (kind, driverArguments) = try extractFixtureKind(
        afterCycles,
        defaultKind: defaultKind
      )
      return RaceOptions(
        settleSeconds: settleSeconds,
        cycles: cycles,
        kind: kind,
        driverArguments: driverArguments
      )
    } catch let diagnostic as TestSafetyDiagnostic {
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
      exit(2)
    } catch {
      exit(2)
    }
  }

  private static func runScenario(
    _ restore: PutBackRaceRestore,
    context: TestSafetyContext,
    kind: PutBackRaceFixtureKind,
    settleSeconds: TimeInterval
  ) throws -> PutBackRaceReport {
    switch restore {
    case .finderScript:
      return try PutBackRaceAcceptance.run(context: context)
    case .manualFinderMenu, .manualFoundationSymlinkDelay,
      .manualFoundationSymlinkFinalizer, .manualProductionSymlinkFinalizer:
      return try PutBackRaceAcceptance.runManual(
        context: context,
        suffix: kind.suffix(cycle: "put-back-race"),
        kind: kind,
        trashBackend: restore.trashBackend,
        settleSeconds: settleSeconds,
        finalizeWithFoundation: restore.usesFoundationFinalizer,
        retrashWithProductionFinalizer: restore.usesProductionFinalizer,
        announce: { message in
          FileHandle.standardOutput.write(Data("\(message)\n".utf8))
        },
        heartbeat: { remaining in
          FileHandle.standardOutput.write(Data("waiting-for-put-back=\(remaining)s\n".utf8))
        }
      )
    }
  }

  private static func runManualDifferential(
    context: TestSafetyContext,
    cycles: Int,
    kind: PutBackRaceFixtureKind,
    restore: PutBackRaceRestore,
    settleSeconds: TimeInterval
  ) throws -> [PutBackRaceReport] {
    do {
      return try PutBackRaceAcceptance.runManualCycles(
        context: context,
        cycles: cycles,
        kind: kind,
        trashBackend: restore.trashBackend,
        settleSeconds: settleSeconds,
        finalizeWithFoundation: restore.usesFoundationFinalizer,
        retrashWithProductionFinalizer: restore.usesProductionFinalizer,
        announce: { cycle, message in
          FileHandle.standardOutput.write(Data("cycle=\(cycle)/\(cycles)\n\(message)\n".utf8))
        },
        heartbeat: { remaining in
          FileHandle.standardOutput.write(Data("waiting-for-put-back=\(remaining)s\n".utf8))
        }
      )
    } catch let failure as PutBackRaceCycleFailure {
      writeDifferentialSummary(
        failure.completedReports,
        cycles: cycles,
        kind: kind,
        restore: restore,
        context: context
      )
      FileHandle.standardError.write(
        Data("differential stopped in cycle \(failure.cycle)\n".utf8)
      )
      throw failure.underlying
    }
  }

  private static func writeSingleRunSummary(
    _ report: PutBackRaceReport,
    restore: PutBackRaceRestore,
    kind: PutBackRaceFixtureKind,
    context: TestSafetyContext
  ) {
    let output = """
      rmp-test build=RMP_TESTING
      run=\(context.runID.uuidString.lowercased())
      scenario=\(restore.scenarioName)
      fixture=\(kind.rawValue)
      trash-backend=\(restore.trashBackend.rawValue)
      status=complete
      first-trash=\(report.firstTrashURL.path)
      restored=\(report.restoredURL.path)
      settle-seconds=\(report.settleSeconds)
      second-trash=\(report.secondTrashURL.path)
      foundation-finalizer=\(restore.finalizerDescription)
      run-directory=\(context.runDirectoryURL.path)
      \(manualCheckText(backend: restore.trashBackend, plural: false))
      manual-target=\(report.secondTrashURL.lastPathComponent)
      restore-method=\(restore.restoreDescription)

      """
    FileHandle.standardOutput.write(Data(output.utf8))
  }

  private static func writeDifferentialSummary(
    _ reports: [PutBackRaceReport],
    cycles: Int,
    kind: PutBackRaceFixtureKind,
    restore: PutBackRaceRestore,
    context: TestSafetyContext
  ) {
    var lines = [
      "rmp-test build=RMP_TESTING",
      "run=\(context.runID.uuidString.lowercased())",
      "scenario=\(restore.scenarioName)-differential",
      "fixture=\(kind.rawValue)",
      "trash-backend=\(restore.trashBackend.rawValue)",
      "completed-cycles=\(reports.count)/\(cycles)",
      "foundation-finalizer=\(restore.finalizerDescription)",
      "run-directory=\(context.runDirectoryURL.path)",
      manualCheckText(backend: restore.trashBackend, plural: true),
    ]
    for (index, report) in reports.enumerated() {
      lines.append(
        "target-\(String(format: "%02d", index + 1)) settle=\(report.settleSeconds) "
          + report.secondTrashURL.lastPathComponent
      )
    }
    FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n\n").utf8))
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

private func validateFixtureKind(
  _ kind: PutBackRaceFixtureKind,
  backend: TestSystemTrashBackend,
  scenarioName: String
) throws {
  guard backend == .foundationSymlink else { return }
  guard kind == .symbolicLink || kind == .brokenSymbolicLink else {
    throw TestSafetyDiagnostic(
      code: .invalidCommandArguments,
      message: "\(scenarioName) accepts only symbolic-link fixtures."
    )
  }
}

private func manualCheckText(backend: TestSystemTrashBackend, plural: Bool) -> String {
  _ = backend
  let target = plural ? "every target below" : "manual-target below"
  return
    "manual-check=Open Trash now and verify Put Back is offered for \(target); no wait is needed."
}

/// Strips `--settle-seconds <n>` before the Test Safety Context driver sees the arguments; the
/// driver treats every unrecognized token as a path.
private func extractSettleSeconds(
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

/// Strips `--cycles <n>` for the same reason as `--settle-seconds`.
private func extractCycles(_ arguments: [String]) throws -> (Int, [String]) {
  var cycles = 1
  var remaining: [String] = []
  var index = arguments.startIndex
  while index < arguments.endIndex {
    guard arguments[index] == "--cycles" else {
      remaining.append(arguments[index])
      index = arguments.index(after: index)
      continue
    }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex,
      let parsed = Int(arguments[valueIndex]),
      parsed >= 1, parsed <= 30
    else {
      throw TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "--cycles requires a value between 1 and 30."
      )
    }
    cycles = parsed
    index = arguments.index(after: valueIndex)
  }
  return (cycles, remaining)
}

/// Strips `--fixture <kind>` for the same reason as the other race options.
private func extractFixtureKind(
  _ arguments: [String],
  defaultKind: PutBackRaceFixtureKind = .file
) throws -> (PutBackRaceFixtureKind, [String]) {
  var kind = defaultKind
  var remaining: [String] = []
  var index = arguments.startIndex
  while index < arguments.endIndex {
    guard arguments[index] == "--fixture" else {
      remaining.append(arguments[index])
      index = arguments.index(after: index)
      continue
    }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex,
      let parsed = PutBackRaceFixtureKind(rawValue: arguments[valueIndex])
    else {
      let known = PutBackRaceFixtureKind.allCases.map(\.rawValue).joined(separator: ", ")
      throw TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "--fixture requires one of: \(known)."
      )
    }
    kind = parsed
    index = arguments.index(after: valueIndex)
  }
  return (kind, remaining)
}

RMPTestEntrypoint.execute(arguments: Array(CommandLine.arguments.dropFirst()))
