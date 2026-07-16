// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Unsupported entry validation makes zero Trash capability calls")
func unsupportedEntryValidationDoesNotConstructTrashCapability() {
  let probes = ApplicationProbes()
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "pipe": .entry(.init(kind: .other, identity: .init(device: 1, inode: 40)))
        ]
      )
    },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["pipe"])

  #expect(result.exitCode == 1)
  #expect(result.standardError.contains("unsupported_input_kind"))
  #expect(result.standardError.contains("(rejected)"))
  #expect(result.standardError.contains("pipe"))
  #expect(probes.trashClientFactoryCalls == 0)
  #expect(probes.receivedTrashPaths.isEmpty)
}

@Test("An ignored missing single input succeeds without constructing a Trash capability")
func ignoredMissingInputDoesNotConstructTrashCapability() {
  let probes = ApplicationProbes()
  let application = CLIApplication(
    makeFileSystem: { ApplicationFileSystem(entries: [:]) },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["--ignore-missing", "missing"])

  #expect(result.exitCode == 0)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError.isEmpty)
  #expect(probes.trashClientFactoryCalls == 0)
}

@Test("CLI renders every global parsing diagnostic through the public command seam")
func cliRendersGlobalParsingDiagnostics() {
  let application = CLIApplication(
    makeFileSystem: { ApplicationFileSystem(entries: [:]) }
  )

  let invalidConfirmation = application.run(
    arguments: ["--confirm=sometimes", "report.txt"]
  )
  let conflictingInformation = application.run(arguments: ["--help", "--version"])
  let orphanedHelpModifier = application.run(arguments: ["-a"])

  #expect(invalidConfirmation.standardError.contains("invalid confirmation mode"))
  #expect(conflictingInformation.standardError.contains("cannot be used together"))
  #expect(orphanedHelpModifier.standardError.contains("only valid with --help"))
}

@Test("Unsupported JSON execution fails closed and quiet success stays silent")
func singleItemOutputModesDoNotMisrepresentResults() {
  let probes = ApplicationProbes()
  let identity = FileSystemIdentity(device: 1, inode: 60)
  let application = CLIApplication(
    makeFileSystem: {
      probes.fileSystemFactoryCalls += 1
      return ApplicationFileSystem(
        entries: ["report.txt": .entry(.init(kind: .file, identity: identity))]
      )
    },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 501 }
  )

  let json = application.run(arguments: ["--json", "report.txt"])

  #expect(json.exitCode == 2)
  #expect(json.standardOutput.isEmpty)
  #expect(json.standardError.contains("unsupported_output_mode"))
  #expect(json.standardError.contains("JSON Trash Operation results are not available"))
  #expect(json.standardError.contains("report.txt"))
  #expect(probes.fileSystemFactoryCalls == 0)
  #expect(probes.trashClientFactoryCalls == 0)

  let quiet = application.run(arguments: ["--quiet", "report.txt"])

  #expect(quiet.exitCode == 0)
  #expect(quiet.standardOutput.isEmpty)
  #expect(quiet.standardError.isEmpty)
  #expect(probes.receivedTrashPaths == ["report.txt"])
}

@Test("Unsupported JSON execution identifies every affected Trash Input")
func unsupportedJSONExecutionReportsEveryInput() {
  let application = CLIApplication(
    makeFileSystem: { ApplicationFileSystem(entries: [:]) },
    makeTrashClient: { ApplicationTrashClient(probes: ApplicationProbes()) },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["--json", "first", "second"])

  #expect(result.exitCode == 2)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError.contains("unsupported_output_mode"))
  #expect(result.standardError.contains("\"first\""))
  #expect(result.standardError.contains("\"second\""))
}

@Test("Planning failures expose stable codes and the affected source path")
func planningFailuresExposeStableCodes() {
  let homeIdentity = FileSystemIdentity(device: 1, inode: 3)
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "inaccessible": .inaccessible,
          "home-alias": .entry(.init(kind: .directory, identity: homeIdentity)),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: ApplicationProbes()) },
    effectiveUserID: { 501 }
  )

  let missing = application.run(arguments: ["missing"])
  let inaccessible = application.run(arguments: ["inaccessible"])
  let protected = application.run(arguments: ["home-alias"])

  #expect(missing.standardError.contains("missing_input"))
  #expect(missing.standardError.contains("missing"))
  #expect(inaccessible.standardError.contains("inaccessible_input"))
  #expect(inaccessible.standardError.contains("inaccessible"))
  #expect(protected.standardError.contains("protected_path"))
  #expect(protected.standardError.contains("home-alias"))
}

@Test("Unavailable safety identity reports the escaped source path without Trash access")
func unavailableSafetyIdentityReportsSourcePath() {
  let probes = ApplicationProbes()
  let path = "victim\n.txt"
  let application = CLIApplication(
    makeFileSystem: { SafetyIdentityUnavailableFileSystem() },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: [path])

  #expect(result.exitCode == 3)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError.contains("safety_identity_unavailable"))
  #expect(result.standardError.contains("\"victim\\n.txt\""))
  #expect(result.standardError.filter { $0 == "\n" }.count == 1)
  #expect(probes.trashClientFactoryCalls == 0)
  #expect(probes.receivedTrashPaths.isEmpty)
}

private struct SafetyIdentityUnavailableFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/test"

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    .entry(.init(kind: .file, identity: .init(device: 1, inode: 70)))
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    switch path {
    case "/": .init(device: 1, inode: 1)
    case currentDirectoryPath: .init(device: 1, inode: 2)
    case homeDirectoryPath: nil
    default: nil
    }
  }
}
