// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Smart confirmation prompts once for multiple top-level inputs")
func smartConfirmationPromptsOnceForMultipleInputs() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      probes.fileSystemFactoryCalls += 1
      return ApplicationFileSystem(
        entries: [
          "first": .entry(.init(kind: .file, identity: .init(device: 1, inode: 31))),
          "second": .entry(.init(kind: .file, identity: .init(device: 1, inode: 32))),
        ]
      )
    },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(arguments: ["first", "second"])

  #expect(result.exitCode == 0)
  #expect(prompt.receivedPrompts == ["Move 2 items, including 0 directories, to Trash? [y/N] "])
  #expect(probes.fileSystemFactoryCalls == 1)
  #expect(probes.receivedTrashPaths == ["first", "second"])
}

@Test("Smart confirmation prompts once for a directory and moves only after approval")
func smartConfirmationPromptsForDirectory() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "build": .entry(.init(kind: .directory, identity: .init(device: 1, inode: 30)))
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(arguments: ["build"])

  #expect(result.exitCode == 0)
  #expect(prompt.receivedPrompts == ["Move 1 item, including 1 directory, to Trash? [y/N] "])
  #expect(probes.receivedTrashPaths == ["build"])
}

@Test("Once confirmation accepts a case-insensitive affirmative response")
func onceConfirmationAcceptsAffirmativeResponse() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer(" Y ")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 33)))
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(arguments: ["--confirm=once", "report.txt"])

  #expect(result.exitCode == 0)
  #expect(prompt.receivedPrompts == ["Move 1 item, including 0 directories, to Trash? [y/N] "])
  #expect(probes.receivedTrashPaths == ["report.txt"])
}

@Test("Compatibility -I proceeds without a prompt for up to three ordinary files")
func conditionalOnceSkipsPromptForThreeFiles() {
  let probes = ApplicationProbes()
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "one": .entry(.init(kind: .file, identity: .init(device: 1, inode: 34))),
          "two": .entry(.init(kind: .file, identity: .init(device: 1, inode: 35))),
          "three": .entry(.init(kind: .file, identity: .init(device: 1, inode: 36))),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["-I", "one", "two", "three"])

  #expect(result.exitCode == 0)
  #expect(probes.receivedTrashPaths == ["one", "two", "three"])
}

@Test("Compatibility -I prompts for more than three inputs or any directory")
func conditionalOncePromptsAtDocumentedThresholds() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer("yes"), .answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "one": .entry(.init(kind: .file, identity: .init(device: 1, inode: 42))),
          "two": .entry(.init(kind: .file, identity: .init(device: 1, inode: 43))),
          "three": .entry(.init(kind: .file, identity: .init(device: 1, inode: 44))),
          "four": .entry(.init(kind: .file, identity: .init(device: 1, inode: 45))),
          "build": .entry(.init(kind: .directory, identity: .init(device: 1, inode: 46))),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let fourFiles = application.run(arguments: ["-I", "one", "two", "three", "four"])
  let directory = application.run(arguments: ["-I", "build"])

  #expect(fourFiles.exitCode == 0)
  #expect(directory.exitCode == 0)
  #expect(
    prompt.receivedPrompts
      == [
        "Move 4 items, including 0 directories, to Trash? [y/N] ",
        "Move 1 item, including 1 directory, to Trash? [y/N] ",
      ]
  )
  #expect(probes.receivedTrashPaths == ["one", "two", "three", "four", "build"])
}

@Test("Confirmation triggers count supplied inputs while summaries omit ignored missing paths")
func confirmationThresholdsCountSuppliedInputs() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer("yes"), .answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "one": .entry(.init(kind: .file, identity: .init(device: 1, inode: 51))),
          "two": .entry(.init(kind: .file, identity: .init(device: 1, inode: 52))),
          "three": .entry(.init(kind: .file, identity: .init(device: 1, inode: 53))),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let smart = application.run(arguments: ["--ignore-missing", "one", "missing"])
  let conditional = application.run(
    arguments: ["-I", "--ignore-missing", "one", "two", "three", "missing"]
  )

  #expect(smart.exitCode == 0)
  #expect(conditional.exitCode == 0)
  #expect(
    prompt.receivedPrompts
      == [
        "Move 1 item, including 0 directories, to Trash? [y/N] ",
        "Move 3 items, including 0 directories, to Trash? [y/N] ",
      ]
  )
  #expect(probes.receivedTrashPaths == ["one", "one", "two", "three"])
}

@Test("Compatibility force and interactive options keep left-to-right execution behavior")
func compatibilityConfirmationPrecedenceReachesExecution() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 47)))
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let forceThenInteractive = application.run(arguments: ["-fi", "report.txt"])
  let interactiveThenForce = application.run(arguments: ["-if", "report.txt"])
  let missingAfterInteractive = application.run(arguments: ["-fi", "missing"])
  let ignoredMissingAfterForce = application.run(arguments: ["-if", "missing"])

  #expect(forceThenInteractive.exitCode == 0)
  #expect(interactiveThenForce.exitCode == 0)
  #expect(missingAfterInteractive.exitCode == 1)
  #expect(missingAfterInteractive.standardError.contains("missing_input"))
  #expect(ignoredMissingAfterForce.exitCode == 0)
  #expect(prompt.receivedPrompts == ["Move [file] \"report.txt\" to Trash? [y/N] "])
  #expect(probes.receivedTrashPaths == ["report.txt", "report.txt"])
}

@Test("Non-interactive and non-TTY confirmation never read or block")
func unavailableInteractiveInputFailsClosedWithoutReading() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(isInputTTY: false, responses: [])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 48)))
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: {
      probes.confirmationPromptFactoryCalls += 1
      return prompt
    }
  )

  let nonInteractive = application.run(
    arguments: ["--non-interactive", "--confirm=once", "report.txt"]
  )
  #expect(nonInteractive.exitCode == 1)
  #expect(nonInteractive.standardError.contains("confirmation_required"))
  #expect(probes.confirmationPromptFactoryCalls == 0)

  let nonTTY = application.run(arguments: ["--confirm=each", "report.txt"])
  #expect(nonTTY.exitCode == 1)
  #expect(nonTTY.standardError.contains("confirmation_required"))
  #expect(probes.confirmationPromptFactoryCalls == 1)
  #expect(prompt.receivedPrompts.isEmpty)
  #expect(probes.receivedTrashPaths.isEmpty)

  let never = application.run(
    arguments: ["--non-interactive", "--confirm=never", "report.txt"]
  )
  #expect(never.exitCode == 0)
  #expect(probes.confirmationPromptFactoryCalls == 1)
  #expect(probes.receivedTrashPaths == ["report.txt"])
}

@Test("An unavailable Confirmation Prompt fails closed without Trash access")
func unavailableConfirmationPromptFailsClosed() {
  let probes = ApplicationProbes()
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 57)))
        ]
      )
    },
    makeTrashClient: {
      probes.trashClientFactoryCalls += 1
      return ApplicationTrashClient(probes: probes)
    },
    effectiveUserID: { 501 }
  )

  let result = application.run(arguments: ["--confirm=once", "report.txt"])

  #expect(result.exitCode == 1)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError.contains("confirmation_required"))
  #expect(result.standardError.contains("report.txt"))
  #expect(probes.trashClientFactoryCalls == 0)
  #expect(probes.receivedTrashPaths.isEmpty)
}

@Test("Confirmation summaries inspect only top-level inputs")
func confirmationSummaryDoesNotTraverseDirectories() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ObservedApplicationFileSystem(
        entries: [
          "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 49))),
          "build": .entry(.init(kind: .directory, identity: .init(device: 1, inode: 50))),
        ],
        probes: probes
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(arguments: ["report.txt", "build"])

  #expect(result.exitCode == 0)
  #expect(prompt.receivedPrompts == ["Move 2 items, including 1 directory, to Trash? [y/N] "])
  #expect(probes.inspectedEntryPaths == ["report.txt", "build"])
  #expect(probes.receivedTrashPaths == ["report.txt", "build"])
}

@Test("Each confirmation rejection continues to the next top-level input")
func eachConfirmationRejectionContinues() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer("n"), .answer("y")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "first": .entry(.init(kind: .file, identity: .init(device: 1, inode: 37))),
          "second": .entry(.init(kind: .file, identity: .init(device: 1, inode: 38))),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(arguments: ["--confirm=each", "first", "second"])

  #expect(result.exitCode == 1)
  #expect(result.standardError.contains("confirmation_declined"))
  #expect(result.standardError.contains("first"))
  #expect(
    prompt.receivedPrompts
      == [
        "Move [file] \"first\" to Trash? [y/N] ",
        "Move [file] \"second\" to Trash? [y/N] ",
      ]
  )
  #expect(probes.receivedTrashPaths == ["second"])
}

@Test("Stop-on-error stops per-input confirmation after a rejection")
func eachConfirmationRejectionStopsWhenRequested() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(responses: [.answer("n"), .answer("y")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "first": .entry(.init(kind: .file, identity: .init(device: 1, inode: 39))),
          "second": .entry(.init(kind: .file, identity: .init(device: 1, inode: 40))),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(
    arguments: ["--confirm=each", "--stop-on-error", "first", "second"]
  )

  #expect(result.exitCode == 1)
  #expect(prompt.receivedPrompts == ["Move [file] \"first\" to Trash? [y/N] "])
  #expect(probes.receivedTrashPaths.isEmpty)
}

@Test("Negative, invalid, and interrupted confirmations never authorize Trash")
func unapprovedConfirmationResponsesNeverTrash() {
  let cases: [(ConfirmationResponse, String)] = [
    (.answer(""), "confirmation_declined"),
    (.answer("no"), "confirmation_declined"),
    (.answer("maybe"), "confirmation_invalid_response"),
    (.interrupted, "confirmation_interrupted"),
  ]

  for (response, expectedCode) in cases {
    let probes = ApplicationProbes()
    let prompt = ApplicationConfirmationPrompt(responses: [response])
    let application = CLIApplication(
      makeFileSystem: {
        ApplicationFileSystem(
          entries: [
            "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 41)))
          ]
        )
      },
      makeTrashClient: { ApplicationTrashClient(probes: probes) },
      effectiveUserID: { 501 },
      makeConfirmationPrompt: { prompt }
    )

    let result = application.run(arguments: ["--confirm=once", "report.txt"])

    #expect(result.exitCode == 1)
    #expect(result.standardError.contains(expectedCode))
    #expect(result.standardError.contains("report.txt"))
    #expect(probes.receivedTrashPaths.isEmpty)
  }
}

@Test("Invalid per-input confirmation continues while interrupted input stops")
func interruptedPerInputConfirmationStops() {
  let probes = ApplicationProbes()
  let prompt = ApplicationConfirmationPrompt(
    responses: [.answer("maybe"), .interrupted, .answer("yes")]
  )
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "invalid": .entry(.init(kind: .file, identity: .init(device: 1, inode: 54))),
          "interrupted": .entry(.init(kind: .file, identity: .init(device: 1, inode: 55))),
          "approved": .entry(.init(kind: .file, identity: .init(device: 1, inode: 56))),
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(
    arguments: ["--confirm=each", "invalid", "interrupted", "approved"]
  )

  #expect(result.exitCode == 1)
  #expect(result.standardError.contains("confirmation_invalid_response"))
  #expect(result.standardError.contains("confirmation_interrupted"))
  #expect(prompt.receivedPrompts.count == 2)
  #expect(probes.receivedTrashPaths.isEmpty)
}

private struct ObservedApplicationFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/test"
  let entries: [String: FileSystemEntryInspection]
  let probes: ApplicationProbes

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    probes.inspectedEntryPaths.append(path)
    return entries[path] ?? .missing
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

private final class ApplicationConfirmationPrompt: ConfirmationPrompt, @unchecked Sendable {
  let isInputTTY: Bool
  private(set) var receivedPrompts: [String] = []
  private var responses: [ConfirmationResponse]

  init(isInputTTY: Bool = true, responses: [ConfirmationResponse]) {
    self.isInputTTY = isInputTTY
    self.responses = responses
  }

  func readResponse(prompt: String) -> ConfirmationResponse {
    receivedPrompts.append(prompt)
    guard !responses.isEmpty else { return .interrupted }
    return responses.removeFirst()
  }
}
