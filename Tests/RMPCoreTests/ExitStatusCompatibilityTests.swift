// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Exit status compatibility uses macOS rm's success, failure, and usage values")
func exitStatusCompatibilityUsesMacOSValues() {
  let application = CLIApplication(makeFileSystem: { FakeTrashPlanningFileSystem(entries: [:]) })

  let cases: [(arguments: [String], exitCode: Int32)] = [
    ([], 64),
    (["--unknown", "report.txt"], 64),
    (["-W", "report.txt"], 64),
    (["-f"], 0),
    (["-if"], 0),
    (["-fi"], 64),
    (["-i", "-f"], 0),
    (["-f", "-i"], 64),
    (["-f", "--confirm=never"], 0),
    (["-f", "--confirm=each"], 0),
    (["-f", "--ignore-missing"], 0),
    (["-f", "--ignore-missing", "--confirm=each"], 64),
    (["-fI"], 0),
    (["-If"], 0),
    (["-f", "--force"], 64),
    (["--force", "-f"], 0),
    (["--force"], 64),
  ]

  for testCase in cases {
    #expect(application.run(arguments: testCase.arguments).exitCode == testCase.exitCode)
  }
}

@Test("Safety refusal uses the ordinary rm operational failure status")
func safetyRefusalUsesOperationalFailureStatus() {
  let rootIdentity = FileSystemIdentity(device: 1, inode: 1)
  let result = DryRunApplication(
    fileSystem: FakeTrashPlanningFileSystem(
      entries: ["/": .entry(.init(kind: .directory, identity: rootIdentity))]
    )
  ).run(request: TrashOperationRequest(paths: ["/"]))

  #expect(result.exitCode == 1)
}

@Test("JSON force-only empty invocation emits a complete empty document")
func jsonForceOnlyEmptyInvocationEmitsDocument() {
  let application = CLIApplication(makeFileSystem: { FakeTrashPlanningFileSystem(entries: [:]) })

  let result = application.run(arguments: ["-f", "--json"])

  #expect(
    result.standardOutput
      == "{\"dryRun\":false,\"failed\":0,\"items\":[],\"moved\":0,"
      + "\"operation\":\"trash\",\"schemaVersion\":1,\"skipped\":0,\"success\":true}\n"
  )
  #expect(result.standardError.isEmpty)
  #expect(result.exitCode == 0)
}

@Test("A moved Trash Warning does not change a successful exit status")
func movedTrashWarningKeepsSuccessStatus() {
  let probes = ApplicationProbes()
  probes.trashResult = .success(
    .init(
      destinationPath: "/Users/test/.Trash/shortcut",
      warnings: [.init(code: .symlinkPutBackNotGuaranteed)]
    )
  )
  let identity = FileSystemIdentity(device: 1, inode: 15)
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: ["shortcut": .entry(.init(kind: .symbolicLink, identity: identity))]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  #expect(application.run(arguments: ["shortcut"]).exitCode == 0)
}

@Test("Stop-on-error continues after moved Trash Warnings")
func stopOnErrorContinuesAfterMovedWarnings() {
  let probes = ApplicationProbes()
  probes.trashResult = .success(
    .init(
      destinationPath: "/Users/test/.Trash/item",
      warnings: [.init(code: .symlinkPutBackNotGuaranteed)]
    )
  )
  let entries: [String: FileSystemEntryInspection] = [
    "first": .entry(.init(kind: .symbolicLink, identity: .init(device: 1, inode: 15))),
    "second": .entry(.init(kind: .symbolicLink, identity: .init(device: 1, inode: 16))),
  ]
  let application = CLIApplication(
    makeFileSystem: { ApplicationFileSystem(entries: entries) },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  let result = application.run(
    arguments: ["--confirm=never", "--stop-on-error", "first", "second"]
  )

  #expect(probes.receivedTrashPaths == ["first", "second"])
  #expect(result.exitCode == 0)
}
