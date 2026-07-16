// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Information commands parse without Trash Inputs")
func informationCommandsParseWithoutInputs() throws {
  #expect(
    try CommandParser.parse(arguments: ["--help"])
      == .init(command: .help(.primaryEnglish), warnings: [])
  )
  #expect(
    try CommandParser.parse(arguments: ["--help", "-a"])
      == .init(command: .help(.compatibilityEnglish), warnings: [])
  )
  #expect(
    try CommandParser.parse(arguments: ["--help", "-zh"])
      == .init(command: .help(.primaryChinese), warnings: [])
  )
  #expect(
    try CommandParser.parse(arguments: ["--help", "-a", "-zh"])
      == .init(command: .help(.compatibilityChinese), warnings: [])
  )
  #expect(
    try CommandParser.parse(arguments: ["--version"])
      == .init(command: .version, warnings: [])
  )
}

@Test("Information commands retain compatibility warnings and strict validation")
func informationCommandsRetainCompatibilityDiagnostics() {
  let application = CLIApplication(makeFileSystem: { CountingTrashPlanningFileSystem() })

  let warning = application.run(arguments: ["--help", "-P"])
  #expect(warning.exitCode == 0)
  #expect(warning.standardError.contains("warning: -P does not securely overwrite"))

  let strict = application.run(arguments: ["--version", "--strict-options", "-r"])
  #expect(strict.exitCode == 2)
  #expect(strict.standardOutput.isEmpty)
  #expect(strict.standardError.contains("-r is not allowed with --strict-options"))

  let conflictingOutput = application.run(arguments: ["--help", "--json", "--quiet"])
  #expect(conflictingOutput.exitCode == 2)
  #expect(conflictingOutput.standardOutput.isEmpty)
  #expect(conflictingOutput.standardError.contains("conflicting options --json and --quiet"))
}

@Test("An empty invocation is reported as a usage error")
func emptyInvocationIsUsageError() {
  let result = CLIApplication(makeFileSystem: { CountingTrashPlanningFileSystem() }).run(
    arguments: [])

  #expect(result.exitCode == 2)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError == "rmp: at least one Trash Input is required\n")
}

@Test("Information commands do not inspect filesystem capabilities")
func informationCommandsBypassFilesystemCapabilities() {
  let fileSystem = CountingTrashPlanningFileSystem()
  let application = CLIApplication(makeFileSystem: { fileSystem })

  let help = application.run(arguments: ["--help"])
  let version = application.run(arguments: ["--version"])

  #expect(help.exitCode == 0)
  #expect(help.standardError.isEmpty)
  #expect(help.standardOutput.contains("rmp [OPTIONS] <PATH>..."))
  #expect(help.standardOutput.hasSuffix("\n"))
  #expect(version == .init(standardOutput: "rmp 0.1.0\n", standardError: "", exitCode: 0))
  #expect(fileSystem.inspectionCount == 0)
}

@Test("Information commands do not construct platform adapters")
func informationCommandsDoNotConstructPlatformAdapters() {
  let probe = AdapterFactoryProbe()
  let application = CLIApplication(
    makeFileSystem: {
      probe.fileSystemCreations += 1
      return CountingTrashPlanningFileSystem()
    },
    makeTrashClient: {
      probe.trashClientCreations += 1
      return InformationTrashClient()
    },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: {
      probe.confirmationPromptCreations += 1
      return InformationConfirmationPrompt()
    }
  )

  #expect(application.run(arguments: ["--help"]).exitCode == 0)
  #expect(application.run(arguments: ["--version"]).exitCode == 0)
  #expect(probe.fileSystemCreations == 0)
  #expect(probe.trashClientCreations == 0)
  #expect(probe.confirmationPromptCreations == 0)

  _ = application.run(arguments: ["--dry-run", "report.txt"])
  #expect(probe.fileSystemCreations == 1)
  #expect(probe.trashClientCreations == 0)
  #expect(probe.confirmationPromptCreations == 0)
}

@Test("Help surfaces distinguish native and Compatibility Options in English and Chinese")
func helpSurfacesExplainCompatibilityConsistently() {
  let application = CLIApplication(makeFileSystem: { CountingTrashPlanningFileSystem() })
  let primary = application.run(arguments: ["--help"]).standardOutput
  let compatibility = application.run(arguments: ["--help", "-a"]).standardOutput
  let primaryChinese = application.run(arguments: ["--help", "-zh"]).standardOutput
  let compatibilityChinese = application.run(arguments: ["--help", "-a", "-zh"]).standardOutput

  #expect(primary.contains("--confirm=<MODE>"))
  #expect(primary.contains("rmp --help -a"))
  #expect(!primary.contains("-P"))
  #expect(compatibility.contains("Accepted with no effect"))
  #expect(compatibility.contains("Accepted with a warning"))
  #expect(compatibility.contains("Unsupported"))
  #expect(compatibility.contains("-r, -R, -d, -x"))
  #expect(compatibility.contains("-P"))
  #expect(compatibility.contains("-W"))
  #expect(primaryChinese.contains("移入 macOS 系统废纸篓"))
  #expect(primaryChinese.contains("rmp --help -a -zh"))
  #expect(compatibilityChinese.contains("接受但无效果"))
  #expect(compatibilityChinese.contains("接受但会警告"))
  #expect(compatibilityChinese.contains("不支持"))
}

@Test("Primary help keeps exactly three examples in both languages")
func primaryHelpKeepsThreeExamples() {
  let application = CLIApplication(makeFileSystem: { CountingTrashPlanningFileSystem() })
  let primary = application.run(arguments: ["--help"]).standardOutput
  let primaryChinese = application.run(arguments: ["--help", "-zh"]).standardOutput

  #expect(primary.split(separator: "\n").count { $0.hasPrefix("  rmp ") } == 3)
  #expect(primaryChinese.split(separator: "\n").count { $0.hasPrefix("  rmp ") } == 3)
}

private final class CountingTrashPlanningFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/user"
  var inspectionCount = 0

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    inspectionCount += 1
    return .missing
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    inspectionCount += 1
    return nil
  }
}

private final class AdapterFactoryProbe {
  var fileSystemCreations = 0
  var trashClientCreations = 0
  var confirmationPromptCreations = 0
}

private struct InformationTrashClient: TrashClient {
  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    TrashMoveReceipt(destinationPath: path)
  }
}

private struct InformationConfirmationPrompt: ConfirmationPrompt {
  let isInputTTY = false

  func readResponse(prompt: String) -> ConfirmationResponse {
    .interrupted
  }
}
