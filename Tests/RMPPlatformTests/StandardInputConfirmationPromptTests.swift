// SPDX-License-Identifier: Apache-2.0

import Darwin
import Testing

@testable import RMPCore
@testable import RMPPlatform

@Test("Standard-input confirmation exposes TTY state and maps terminal input")
func standardInputConfirmationMapsTerminalInput() {
  let probes = ConfirmationPromptProbes()
  probes.responses = ["yes", nil]
  let prompt = StandardInputConfirmationPrompt(
    isInputTTY: { true },
    writePrompt: { probes.writtenPrompts.append($0) },
    readLine: { probes.responses.removeFirst() }
  )

  #expect(prompt.isInputTTY)
  #expect(prompt.readResponse(prompt: "First? ") == .answer("yes"))
  #expect(prompt.readResponse(prompt: "Second? ") == .interrupted)
  #expect(probes.writtenPrompts == ["First? ", "Second? "])
}

@Test("Production confirmation prompt reports stdin TTY state without reading input")
func productionConfirmationPromptReportsTTYState() {
  let prompt = StandardInputConfirmationPrompt()

  #expect(prompt.isInputTTY == (isatty(STDIN_FILENO) == 1))
}

private final class ConfirmationPromptProbes: @unchecked Sendable {
  var writtenPrompts: [String] = []
  var responses: [String?] = []
}
