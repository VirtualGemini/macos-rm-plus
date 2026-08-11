// SPDX-License-Identifier: Apache-2.0

import Foundation

func writeSingleRunSummary(
  _ report: PutBackRaceReport,
  restore: PutBackRaceRestore,
  kind: PutBackRaceFixtureKind,
  finalizerFault: ProductionFinalizerFault,
  context: TestSafetyContext
) {
  let faultSummary = productionFaultSummary(restore: restore, fault: finalizerFault)
  let output = """
    rmp-test build=RMP_TESTING
    run=\(context.runID.uuidString.lowercased())
    scenario=\(restore.scenarioName)
    fixture=\(kind.rawValue)
    trash-backend=\(restore.trashBackend.rawValue)
    status=complete
    first-trash=\(report.firstTrashURL.path)
    foundation-control-finalizer=\(controlFinalizerDescription(restore: restore))
    restored=\(report.restoredURL.path)
    settle-seconds=\(report.settleSeconds)
    second-trash=\(report.secondTrashURL.path)
    foundation-finalizer=\(restore.finalizerDescription(fault: finalizerFault))
    \(faultSummary)
    run-directory=\(context.runDirectoryURL.path)
    \(manualCheckText(backend: restore.trashBackend, plural: false))
    manual-target=\(report.secondTrashURL.lastPathComponent)
    restore-method=\(restore.restoreDescription)

    """
  FileHandle.standardOutput.write(Data(output.utf8))
}

func writeDifferentialSummary(
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
    "foundation-control-finalizer=\(controlFinalizerDescription(restore: restore))",
    "foundation-finalizer=\(restore.finalizerDescription())",
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

func validateFixtureKind(
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

func extractSettleSeconds(
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

func extractCycles(_ arguments: [String]) throws -> (Int, [String]) {
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

func extractFixtureKind(
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

private func manualCheckText(backend: TestSystemTrashBackend, plural: Bool) -> String {
  _ = backend
  let target = plural ? "every target below" : "manual-target below"
  return
    "manual-check=Open Trash now and verify Put Back is offered for \(target); no wait is needed."
}

private func productionFaultSummary(
  restore: PutBackRaceRestore,
  fault: ProductionFinalizerFault
) -> String {
  guard restore.usesProductionFinalizer else { return "" }
  let warning = fault.expectedWarning?.rawValue ?? "none"
  return "injected-finalizer-fault=\(fault.rawValue)\ntrash-warning=\(warning)"
}

private func controlFinalizerDescription(restore: PutBackRaceRestore) -> String {
  restore.trashBackend == .foundationSymlink ? "cleaned" : "not-required"
}
