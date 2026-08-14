// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

#if !RMP_TESTING
  #error("rmp-test must only be built with RMP_TESTING enabled")
#endif

private let helpText = """
  Usage: rmp-test put-back-race --test-run-id <uuid>
         rmp-test duplicate-trash-name --test-run-id <uuid>
         rmp-test put-back-race-manual [OPTIONS] --test-run-id <uuid>
         rmp-test put-back-symlink-delay-manual [OPTIONS] --test-run-id <uuid>
         rmp-test put-back-symlink-finalizer-manual [OPTIONS] --test-run-id <uuid>
         rmp-test put-back-symlink-production-manual [OPTIONS] --test-run-id <uuid>
         rmp-test put-back-symlink-production-probe [OPTIONS] --test-run-id <uuid>
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
    --finalizer-fault <mode>
                          none | not-moved-before-error | moved-before-error

  put-back-symlink-production-probe options:
    --fixture <kind>      symbolic-link | broken-symbolic-link
    --finalizer-name <n>  hidden | visible, default hidden
    --preflight <mode>    enabled | disabled, default disabled

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
    if arguments.first == "duplicate-trash-name" {
      executeDuplicateTrashName(
        arguments: Array(arguments.dropFirst()),
        runtime: currentRuntime
      )
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
    if arguments.first == "put-back-symlink-production-probe" {
      executeProductionProbe(
        arguments: Array(arguments.dropFirst()),
        runtime: currentRuntime
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
    rejectUnsupportedFinalizerFault(
      restore: restore,
      fault: options.finalizerFault,
      cycles: cycles
    )

    let result = TestSafetyDriver.runWithInjectedRuntime(
      arguments: driverArguments,
      cleanupPolicy: .preserveRunDirectory
    ) {
      try currentRuntime()
    } operation: { context, paths in
      try runPutBackRaceOperation(
        context: context,
        paths: paths,
        options: options,
        restore: restore
      )
    }
    if let diagnostic = result.diagnostic {
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    }
    exit(result.exitCode)
  }

  private static func runPutBackRaceOperation(
    context: TestSafetyContext,
    paths: [String],
    options: RaceOptions,
    restore: PutBackRaceRestore
  ) throws -> Int32 {
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
    if options.cycles > 1 {
      guard restore.supportsCycles else {
        throw TestSafetyDiagnostic(
          code: .invalidCommandArguments,
          message: "--cycles is available only for a manual Put Back scenario."
        )
      }
      let reports = try runManualDifferential(
        context: context,
        cycles: options.cycles,
        kind: options.kind,
        restore: restore,
        settleSeconds: options.settleSeconds
      )
      writeDifferentialSummary(
        reports,
        cycles: options.cycles,
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
      settleSeconds: options.settleSeconds,
      finalizerFault: options.finalizerFault
    )
    writeSingleRunSummary(
      report,
      restore: restore,
      kind: options.kind,
      finalizerFault: options.finalizerFault,
      context: context
    )
    return 0
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

  private static func rejectUnsupportedFinalizerFault(
    restore: PutBackRaceRestore,
    fault: ProductionFinalizerFault,
    cycles: Int
  ) {
    guard fault != .none else { return }
    guard restore.usesProductionFinalizer else {
      let diagnostic = TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "--finalizer-fault is available only for the production Finalizer scenario."
      )
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
      exit(2)
    }
    guard cycles == 1 else {
      let diagnostic = TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "An injected Finalizer fault requires exactly one cycle."
      )
      FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
      exit(2)
    }
  }

  private static func parseRaceOptions(
    _ arguments: [String],
    defaultKind: PutBackRaceFixtureKind
  ) -> RaceOptions {
    do {
      let (finalizerFault, afterFault) = try extractProductionFinalizerFault(arguments)
      let (settleSeconds, afterSettle) = try extractSettleSeconds(afterFault)
      let (cycles, afterCycles) = try extractCycles(afterSettle)
      let (kind, driverArguments) = try extractFixtureKind(
        afterCycles,
        defaultKind: defaultKind
      )
      return RaceOptions(
        settleSeconds: settleSeconds,
        cycles: cycles,
        kind: kind,
        finalizerFault: finalizerFault,
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
    settleSeconds: TimeInterval,
    finalizerFault: ProductionFinalizerFault
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
        productionFinalizerFault: finalizerFault,
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

  private static func currentRuntime() throws -> TestSafetyRuntime {
    let effectiveUserID = geteuid()
    return TestSafetyRuntime(
      effectiveUserID: effectiveUserID,
      trustedUser: try TrustedUserAccount.current(effectiveUserID: effectiveUserID),
      executableName: try loadedExecutableName()
    )
  }
}

private func executeProductionProbe(
  arguments: [String],
  runtime: @escaping () throws -> TestSafetyRuntime
) -> Never {
  let options: ProductionProbeOptions
  do {
    options = try extractProductionProbeOptions(arguments)
  } catch let diagnostic as TestSafetyDiagnostic {
    FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    exit(2)
  } catch {
    let diagnostic = TestSafetyDiagnostic(
      code: .invalidCommandArguments,
      message: "put-back-symlink-production-probe arguments could not be parsed."
    )
    FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    exit(2)
  }
  let result = TestSafetyDriver.runWithInjectedRuntime(
    arguments: options.driverArguments,
    cleanupPolicy: .preserveRunDirectory,
    runtime: runtime
  ) { context, paths in
    guard paths.isEmpty else {
      throw TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "put-back-symlink-production-probe creates its own Test Fixture."
      )
    }
    try validateFixtureKind(
      options.kind,
      backend: .foundationSymlink,
      scenarioName: "put-back-symlink-production-probe"
    )
    let report = try PutBackRaceAcceptance.runProductionProbe(
      context: context,
      kind: options.kind,
      finalizerName: options.finalizerName,
      preflight: options.preflight
    )
    writeProductionProbeSummary(
      report,
      kind: options.kind,
      finalizerName: options.finalizerName,
      preflight: options.preflight,
      context: context
    )
    return 0
  }
  if let diagnostic = result.diagnostic {
    FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
  }
  exit(result.exitCode)
}

private func executeDuplicateTrashName(
  arguments: [String],
  runtime: @escaping () throws -> TestSafetyRuntime
) -> Never {
  let result = TestSafetyDriver.runWithInjectedRuntime(
    arguments: arguments,
    cleanupPolicy: .preserveRunDirectory,
    runtime: runtime
  ) { context, paths in
    guard paths.isEmpty else {
      throw TestSafetyDiagnostic(
        code: .invalidCommandArguments,
        message: "duplicate-trash-name creates its own Test Fixtures."
      )
    }
    let report = try PutBackRaceAcceptance.runDuplicateTrashName(context: context)
    writeDuplicateTrashNameSummary(report, context: context)
    return 0
  }
  if let diagnostic = result.diagnostic {
    FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
  }
  exit(result.exitCode)
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

RMPTestEntrypoint.execute(arguments: Array(CommandLine.arguments.dropFirst()))
