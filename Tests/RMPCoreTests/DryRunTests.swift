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

@Test("Double dash permits a leading-hyphen Trash Input")
func doubleDashPermitsLeadingHyphenInput() throws {
  let request = try DryRunCommand.parse(arguments: ["--dry-run", "--", "-filename"])

  #expect(request.paths == ["-filename"])
}

@Test("Dry-run output uses the singular item label")
func dryRunOutputUsesSingularItemLabel() {
  let plan = TrashPlan(inputs: [.init(path: "report.txt", kind: .file)])

  #expect(
    DryRunRenderer().render(plan)
      == "Would move 1 item to Trash:\n  [file] \"report.txt\"\n"
  )
}

@Test("Dry-run parsing requires the mode and at least one Trash Input")
func dryRunParsingRejectsIncompleteCommands() {
  do {
    _ = try DryRunCommand.parse(arguments: ["report.txt"])
    Issue.record("Expected a command without --dry-run to fail")
  } catch {
    #expect(error == .dryRunRequired)
  }
  do {
    _ = try DryRunCommand.parse(arguments: ["--dry-run"])
    Issue.record("Expected a dry run without Trash Inputs to fail")
  } catch {
    #expect(error == .noInputs)
  }
}

@Test("Dry-run option parsing rejects unknown options before the option terminator")
func dryRunOptionParsingRejectsUnknownOptions() {
  let cases = [
    UnknownOptionCase(arguments: ["--dry-run", "-f", "report.txt"], option: "-f"),
    UnknownOptionCase(arguments: ["--dry-run", "--unknown", "report.txt"], option: "--unknown"),
  ]

  for testCase in cases {
    do {
      _ = try DryRunCommand.parse(arguments: testCase.arguments)
      Issue.record("Expected \(testCase.option) to be rejected")
    } catch {
      #expect(error == .unknownOption(testCase.option))
    }
  }
}

@Test("Dry-run application reports unknown options as usage errors")
func dryRunApplicationReportsUnknownOptions() {
  let result = DryRunApplication(fileSystem: FakeTrashPlanningFileSystem(entries: [:])).run(
    arguments: ["--dry-run", "--unknown", "report.txt"]
  )

  #expect(result.exitCode == 2)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError == "rmp: unknown option \"--unknown\"\n")
}

@Test("Dry-run rejects a Protected Path with exit code 3 before presenting a plan")
func dryRunRejectsProtectedPathWithSafetyExitCode() {
  let rootIdentity = FileSystemIdentity(device: 1, inode: 1)
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: ["/tmp/..": .entry(.init(kind: .directory, identity: rootIdentity))]
  )

  let result = DryRunApplication(fileSystem: fileSystem).run(
    arguments: ["--dry-run", "/tmp/.."]
  )

  #expect(result.exitCode == 3)
  #expect(result.standardOutput.isEmpty)
  #expect(
    result.standardError
      == "rmp: Protected Path rejected (filesystem-root): \"/tmp/..\"\n"
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
    arguments: ["--dry-run", "report.txt", "build"]
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

private struct UnknownOptionCase {
  let arguments: [String]
  let option: String
}
