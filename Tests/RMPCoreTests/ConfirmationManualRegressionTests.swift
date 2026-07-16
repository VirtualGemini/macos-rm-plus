// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Compatibility -r preserves smart directory confirmation")
func compatibilityRecursiveOptionPreservesSmartDirectoryConfirmation() {
  let probes = ApplicationProbes()
  let prompt = ManualRegressionConfirmationPrompt(responses: [.answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "build": .entry(.init(kind: .directory, identity: .init(device: 1, inode: 58)))
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(arguments: ["-r", "build"])

  #expect(result.exitCode == 0)
  #expect(prompt.receivedPrompts == ["Move 1 item, including 1 directory, to Trash? [y/N] "])
  #expect(probes.receivedTrashPaths == ["build"])
}

@Test("Compatibility -fI restores conditional confirmation without prompting for one file")
func forceThenConditionalConfirmationSkipsPromptForOneFile() {
  let probes = ApplicationProbes()
  let prompt = ManualRegressionConfirmationPrompt(responses: [])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 59)))
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

  let result = application.run(arguments: ["-fI", "report.txt"])

  #expect(result.exitCode == 0)
  #expect(probes.confirmationPromptFactoryCalls == 0)
  #expect(prompt.receivedPrompts.isEmpty)
  #expect(probes.receivedTrashPaths == ["report.txt"])
}

@Test("Compatibility -i restores per-input confirmation after explicit never")
func interactiveOptionOverridesExplicitNeverAtExecution() {
  let probes = ApplicationProbes()
  let prompt = ManualRegressionConfirmationPrompt(responses: [.answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 60)))
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(arguments: ["--confirm=never", "-i", "report.txt"])

  #expect(result.exitCode == 0)
  #expect(prompt.receivedPrompts == ["Move [file] \"report.txt\" to Trash? [y/N] "])
  #expect(probes.receivedTrashPaths == ["report.txt"])
}

@Test("Compatibility -iv keeps per-input confirmation and verbose success output")
func interactiveVerboseOptionConfirmsAndReportsMove() {
  let probes = ApplicationProbes()
  let prompt = ManualRegressionConfirmationPrompt(responses: [.answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 61)))
        ]
      )
    },
    makeTrashClient: { ApplicationTrashClient(probes: probes) },
    effectiveUserID: { 501 },
    makeConfirmationPrompt: { prompt }
  )

  let result = application.run(arguments: ["-iv", "report.txt"])

  #expect(result.exitCode == 0)
  #expect(prompt.receivedPrompts == ["Move [file] \"report.txt\" to Trash? [y/N] "])
  #expect(result.standardOutput.contains("Moved \"report.txt\" to Trash"))
  #expect(probes.receivedTrashPaths == ["report.txt"])
}

@Test("Non-interactive smart directory confirmation fails before prompting or Trash access")
func nonInteractiveSmartDirectoryFailsClosed() {
  let probes = ApplicationProbes()
  let prompt = ManualRegressionConfirmationPrompt(responses: [.answer("yes")])
  let application = CLIApplication(
    makeFileSystem: {
      ApplicationFileSystem(
        entries: [
          "build": .entry(.init(kind: .directory, identity: .init(device: 1, inode: 62)))
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

  let result = application.run(arguments: ["--non-interactive", "build"])

  #expect(result.exitCode == 1)
  #expect(result.standardError.contains("confirmation_required"))
  #expect(probes.confirmationPromptFactoryCalls == 0)
  #expect(prompt.receivedPrompts.isEmpty)
  #expect(probes.receivedTrashPaths.isEmpty)
}

private final class ManualRegressionConfirmationPrompt: ConfirmationPrompt, @unchecked Sendable {
  let isInputTTY = true
  private(set) var receivedPrompts: [String] = []
  private var responses: [ConfirmationResponse]

  init(responses: [ConfirmationResponse]) {
    self.responses = responses
  }

  func readResponse(prompt: String) -> ConfirmationResponse {
    receivedPrompts.append(prompt)
    guard !responses.isEmpty else { return .interrupted }
    return responses.removeFirst()
  }
}
