// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Information commands parse without Trash Inputs")
func informationCommandsParseWithoutInputs() throws {
  #expect(try CommandParser.parse(arguments: ["--help"]) == .help(.primaryEnglish))
  #expect(try CommandParser.parse(arguments: ["--help", "-a"]) == .help(.compatibilityEnglish))
  #expect(try CommandParser.parse(arguments: ["--help", "-zh"]) == .help(.primaryChinese))
  #expect(
    try CommandParser.parse(arguments: ["--help", "-a", "-zh"])
      == .help(.compatibilityChinese)
  )
  #expect(try CommandParser.parse(arguments: ["--version"]) == .version)
}

@Test("Information commands do not inspect filesystem capabilities")
func informationCommandsBypassFilesystemCapabilities() {
  let fileSystem = CountingTrashPlanningFileSystem()
  let application = CLIApplication(fileSystem: fileSystem)

  let help = application.run(arguments: ["--help"])
  let version = application.run(arguments: ["--version"])

  #expect(help.exitCode == 0)
  #expect(help.standardError.isEmpty)
  #expect(help.standardOutput.contains("rmp [OPTIONS] <PATH>..."))
  #expect(version == .init(standardOutput: "rmp 0.1.0\n", standardError: "", exitCode: 0))
  #expect(fileSystem.inspectionCount == 0)
}

@Test("Help surfaces distinguish native and Compatibility Options in English and Chinese")
func helpSurfacesExplainCompatibilityConsistently() {
  let application = CLIApplication(fileSystem: CountingTrashPlanningFileSystem())
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
