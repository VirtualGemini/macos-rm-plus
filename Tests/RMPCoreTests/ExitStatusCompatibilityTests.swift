// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Exit status compatibility uses macOS rm's success, failure, and usage values")
func exitStatusCompatibilityUsesMacOSValues() {
  let application = CLIApplication(makeFileSystem: { FakeTrashPlanningFileSystem(entries: [:]) })

  #expect(application.run(arguments: []).exitCode == 64)
  #expect(application.run(arguments: ["--unknown", "report.txt"]).exitCode == 64)
  #expect(application.run(arguments: ["-W", "report.txt"]).exitCode == 64)
  #expect(application.run(arguments: ["-f"]).exitCode == 0)
  #expect(application.run(arguments: ["--force"]).exitCode == 64)
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
