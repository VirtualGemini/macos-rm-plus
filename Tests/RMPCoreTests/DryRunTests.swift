// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Dry-run output reports kinds and preserves unusual path text")
func dryRunOutputReportsKindsAndPreservesPaths() {
  let longComponent = String(repeating: "a", count: 255)
  let plan = TrashPlan(
    inputs: [
      .init(path: "space name", kind: .file),
      .init(path: "雪", kind: .directory),
      .init(path: "line\nbreak", kind: .symbolicLink),
      .init(path: longComponent, kind: .brokenSymbolicLink),
      .init(path: "-leading-hyphen", kind: .other),
    ]
  )

  let output = DryRunRenderer().render(plan)

  #expect(output.hasPrefix("Would move 5 items to Trash:\n"))
  #expect(output.contains("  [file] \"space name\"\n"))
  #expect(output.contains("  [directory] \"雪\"\n"))
  #expect(output.contains("  [symbolic-link] \"line\\nbreak\"\n"))
  #expect(output.contains("  [broken-symbolic-link] \"\(longComponent)\"\n"))
  #expect(output.hasSuffix("  [other] \"-leading-hyphen\"\n"))
}

@Test("Dry-run output uses the singular item label")
func dryRunOutputUsesSingularItemLabel() {
  let plan = TrashPlan(inputs: [.init(path: "report.txt", kind: .file)])

  #expect(
    DryRunRenderer().render(plan)
      == "Would move 1 item to Trash:\n  [file] \"report.txt\"\n"
  )
}

@Test("Dry-run application reports unknown options as usage errors")
func dryRunApplicationReportsUnknownOptions() {
  let result = CLIApplication(makeFileSystem: { FakeTrashPlanningFileSystem(entries: [:]) }).run(
    arguments: ["--dry-run", "--unknown", "report.txt"]
  )

  #expect(result.exitCode == 2)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError == "rmp: unknown option \"--unknown\"\n")
}

@Test("CLI compatibility warnings use stderr and usage failures return exit code 2")
func cliCompatibilityDiagnosticsUseStableChannelsAndExitCodes() {
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: [
      "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 10)))
    ])
  let application = CLIApplication(makeFileSystem: { fileSystem })

  let warning = application.run(arguments: ["--dry-run", "-P", "report.txt"])
  #expect(warning.exitCode == 0)
  #expect(warning.standardOutput.contains("Would move 1 item to Trash"))
  #expect(warning.standardError.contains("warning: -P does not securely overwrite"))

  let unsupported = application.run(arguments: ["--dry-run", "-W", "report.txt"])
  #expect(unsupported.exitCode == 2)
  #expect(unsupported.standardOutput.isEmpty)
  #expect(unsupported.standardError.contains("unsupported Compatibility Option -W"))

  let failedWithWarning = application.run(arguments: ["--dry-run", "-P", "missing"])
  #expect(failedWithWarning.exitCode == 1)
  #expect(failedWithWarning.standardError.contains("warning: -P does not securely overwrite"))
  #expect(failedWithWarning.standardError.contains("Trash Input does not exist"))

  let unavailableExecution = application.run(arguments: ["-P", "report.txt"])
  #expect(unavailableExecution.exitCode == 2)
  #expect(unavailableExecution.standardError.contains("warning: -P does not securely overwrite"))
  #expect(unavailableExecution.standardError.contains("only --dry-run execution is available"))
}

@Test("Parsed native policy is preserved in the execution-facing Trash Plan")
func parsedPolicyIsPreservedInTrashPlan() throws {
  let request = TrashOperationRequest(
    paths: ["missing", "report.txt"],
    confirmation: .each,
    ignoreMissing: true,
    output: .verbose,
    dryRun: true,
    nonInteractive: true,
    stopOnError: true,
    strictOptions: true
  )
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: [
      "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 10)))
    ])

  let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(request: request)
  let expected = TrashInput(
    path: "report.txt", kind: .file,
    plannedIdentity: .init(device: 1, inode: 10)
  )

  #expect(plan.inputs == [expected])
  #expect(plan.confirmation == .each)
  #expect(plan.ignoreMissing)
  #expect(plan.output == .verbose)
  #expect(plan.dryRun)
  #expect(plan.nonInteractive)
  #expect(plan.stopOnError)
  #expect(plan.strictOptions)
}

@Test("Dry-run rejects a Protected Path with exit code 3 before presenting a plan")
func dryRunRejectsProtectedPathWithSafetyExitCode() {
  let rootIdentity = FileSystemIdentity(device: 1, inode: 1)
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: ["/tmp/..": .entry(.init(kind: .directory, identity: rootIdentity))]
  )

  let result = DryRunApplication(fileSystem: fileSystem).run(
    request: TrashOperationRequest(paths: ["/tmp/.."])
  )

  #expect(result.exitCode == 3)
  #expect(result.standardOutput.isEmpty)
  #expect(
    result.standardError
      == "rmp: protected_path (filesystem-root): Protected Path rejected: \"/tmp/..\"\n"
  )
}

@Test("Dry-run presents the complete top-level Trash Plan without an execution capability")
func dryRunPresentsCompletePlanWithoutExecutionCapability() {
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: [
      "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 10))),
      "build": .entry(.init(kind: .directory, identity: .init(device: 1, inode: 11))),
    ]
  )

  let result = DryRunApplication(fileSystem: fileSystem).run(
    request: TrashOperationRequest(paths: ["report.txt", "build"])
  )

  #expect(result.exitCode == 0)
  #expect(result.standardError.isEmpty)
  #expect(
    result.standardOutput
      == """
      Would move 2 items to Trash:
        [file] "report.txt"
        [directory] "build"

      """
  )
}
