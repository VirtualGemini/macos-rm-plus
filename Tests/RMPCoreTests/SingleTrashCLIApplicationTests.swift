// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Root execution is rejected before planning or Trash capability construction")
func rootExecutionCannotBeForcedPastSafety() {
  let probes = ApplicationProbes()
  let application = CLIApplication(
    makeFileSystem: {
      probes.fileSystemFactoryCalls += 1
      return ApplicationFileSystem(entries: [:])
    },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 0 }
  )

  let argumentCases = [
    ["-f", "report.txt"],
    ["--confirm=never", "report.txt"],
    ["--non-interactive", "report.txt"],
  ]

  for arguments in argumentCases {
    let result = application.run(arguments: arguments)

    #expect(result.exitCode == 3)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("root_execution"))
    #expect(result.standardError.contains("report.txt"))
  }

  #expect(probes.fileSystemFactoryCalls == 0)
  #expect(probes.trashClientFactoryCalls == 0)
  #expect(probes.receivedTrashPaths.isEmpty)
}

@Test("Protected Path policy runs before Trash capability construction")
func protectedPathCannotBeForcedPastSafety() {
  let probes = ApplicationProbes()
  let homeIdentity = FileSystemIdentity(device: 1, inode: 3)
  let application = CLIApplication(
    makeFileSystem: {
      probes.fileSystemFactoryCalls += 1
      return ApplicationFileSystem(
        entries: [
          "home-alias": .entry(.init(kind: .directory, identity: homeIdentity))
        ]
      )
    },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 501 }
  )

  for arguments in [
    ["-f", "home-alias"],
    ["--confirm=never", "home-alias"],
    ["--non-interactive", "home-alias"],
  ] {
    let result = application.run(arguments: arguments)

    #expect(result.exitCode == 3)
    #expect(result.standardError.contains("protected_path"))
    #expect(result.standardError.contains("Protected Path rejected"))
    #expect(result.standardError.contains("home-alias"))
  }

  #expect(probes.fileSystemFactoryCalls == 3)
  #expect(probes.trashClientFactoryCalls == 0)
  #expect(probes.receivedTrashPaths.isEmpty)
}

@Test("Single-item CLI execution reports the exact system Trash destination")
func singleItemCLIExecutionReportsExactDestination() {
  let probes = ApplicationProbes()
  probes.trashResult = .success(
    .init(destinationPath: "/Users/test/.Trash/report 2.txt")
  )
  let identity = FileSystemIdentity(device: 1, inode: 10)
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: ["report.txt": .entry(.init(kind: .file, identity: identity))]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["report.txt"])

  #expect(result.exitCode == 0)
  #expect(result.standardError.isEmpty)
  #expect(result.standardOutput.contains("report.txt"))
  #expect(result.standardOutput.contains("/Users/test/.Trash/report 2.txt"))
  #expect(probes.receivedTrashPaths == ["report.txt"])
}

@Test("System Trash failure exposes a stable code, source path, and honest status")
func singleItemCLIExecutionReportsNotMovedFailure() {
  let probes = ApplicationProbes()
  probes.trashResult = .failure(.init(code: .systemTrashFailed))
  let identity = FileSystemIdentity(device: 1, inode: 11)
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: ["build": .entry(.init(kind: .directory, identity: identity))]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["--confirm=never", "build"])

  #expect(result.exitCode == 1)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError.contains("trash_system_call_failed"))
  #expect(result.standardError.contains("not_moved"))
  #expect(result.standardError.contains("build"))
  #expect(probes.receivedTrashPaths == ["build"])
}

@Test("CLI reports state_uncertain when a failed Trash call leaves no reliable source state")
func singleItemCLIExecutionReportsUncertainFailure() {
  let probes = ApplicationProbes()
  probes.trashResult = .failure(.init(code: .systemTrashFailed))
  let application = CLIApplication(
    makeFileSystem: { UncertainApplicationFileSystem(probes: probes) },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["shortcut"])

  #expect(result.exitCode == 1)
  #expect(result.standardError.contains("trash_system_call_failed"))
  #expect(result.standardError.contains("state_uncertain"))
  #expect(result.standardError.contains("shortcut"))
}

@Test("Failure diagnostics keep a control-character source path on one line")
func failureDiagnosticEscapesSourcePath() {
  let probes = ApplicationProbes()
  probes.trashResult = .failure(.init(code: .systemTrashFailed))
  let path = "line\nbreak"
  let identity = FileSystemIdentity(device: 1, inode: 12)
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [path: .entry(.init(kind: .file, identity: identity))]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: [path])

  #expect(result.exitCode == 1)
  #expect(result.standardError.contains("\"line\\nbreak\""))
  #expect(result.standardError.filter { $0 == "\n" }.count == 1)
}

@Test("Symbolic links and broken symbolic links are passed as their own top-level entries")
func symbolicLinkEntriesAreNotResolvedForExecution() {
  let probes = ApplicationProbes()
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "home-link": .entry(
            .init(kind: .symbolicLink, identity: .init(device: 1, inode: 20))
          ),
          "broken-link": .entry(
            .init(kind: .brokenSymbolicLink, identity: .init(device: 1, inode: 21))
          ),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  #expect(application.run(arguments: ["home-link"]).exitCode == 0)
  #expect(application.run(arguments: ["broken-link"]).exitCode == 0)
  #expect(probes.receivedTrashPaths == ["home-link", "broken-link"])
}

@Test("Non-dry-run execution rejects multiple inputs before filesystem or Trash access")
func multipleInputsRemainOutsideTheSingleItemExecutionScope() {
  let probes = ApplicationProbes()
  let application = CLIApplication(
    makeFileSystem: {
      probes.fileSystemFactoryCalls += 1
      return ApplicationFileSystem(entries: [:])
    },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["first", "second"])

  #expect(result.exitCode == 2)
  #expect(result.standardError.contains("unsupported_input_count"))
  #expect(result.standardError.contains("exactly one Trash Input"))
  #expect(result.standardError.contains("first"))
  #expect(result.standardError.contains("second"))
  #expect(probes.fileSystemFactoryCalls == 0)
  #expect(probes.trashClientFactoryCalls == 0)
  #expect(probes.receivedTrashPaths.isEmpty)
}

@Test("Execution fails closed when the parsed policy still requires confirmation")
func unimplementedConfirmationCannotSilentlyApproveTrash() {
  let probes = ApplicationProbes()
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "build": .entry(
            .init(kind: .directory, identity: .init(device: 1, inode: 30))
          ),
          "report.txt": .entry(
            .init(kind: .file, identity: .init(device: 1, inode: 31))
          ),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  let smartDirectory = application.run(arguments: ["build"])
  let interactiveFile = application.run(arguments: ["-i", "report.txt"])

  #expect(smartDirectory.exitCode == 1)
  #expect(smartDirectory.standardError.contains("confirmation_required"))
  #expect(interactiveFile.exitCode == 1)
  #expect(interactiveFile.standardError.contains("confirmation_required"))
  #expect(probes.receivedTrashPaths.isEmpty)

  let forcedDirectory = application.run(arguments: ["--confirm=never", "build"])
  #expect(forcedDirectory.exitCode == 0)
  #expect(probes.receivedTrashPaths == ["build"])
}

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
    makeFileSystem: { UnavailableSafetyIdentityFileSystem() },
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

private final class ApplicationProbes: @unchecked Sendable {
  var fileSystemFactoryCalls = 0
  var trashClientFactoryCalls = 0
  var receivedTrashPaths: [String] = []
  var trashResult: Result<TrashMoveReceipt, TrashCapabilityError> = .success(
    .init(destinationPath: "/Trash/item")
  )
}

private struct ApplicationFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/test"
  let entries: [String: FileSystemEntryInspection]

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    entries[path] ?? .missing
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    switch path {
    case "/": return .init(device: 1, inode: 1)
    case currentDirectoryPath: return .init(device: 1, inode: 2)
    case homeDirectoryPath: return .init(device: 1, inode: 3)
    default:
      guard case let .entry(entry) = entries[path] else { return nil }
      return entry.identity
    }
  }
}

private struct ApplicationTrashClient: TrashClient {
  let probes: ApplicationProbes

  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    probes.receivedTrashPaths.append(path)
    return try probes.trashResult.get()
  }
}

private struct UncertainApplicationFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/test"
  let probes: ApplicationProbes

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    guard path == "shortcut", probes.receivedTrashPaths.isEmpty else { return .missing }
    return .entry(
      .init(kind: .symbolicLink, identity: .init(device: 1, inode: 50))
    )
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    switch path {
    case "/": .init(device: 1, inode: 1)
    case currentDirectoryPath: .init(device: 1, inode: 2)
    case homeDirectoryPath: .init(device: 1, inode: 3)
    default: nil
    }
  }
}

private struct UnavailableSafetyIdentityFileSystem: TrashPlanningFileSystem {
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
