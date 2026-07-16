// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import RMPCore

public struct StandardInputConfirmationPrompt: ConfirmationPrompt {
  private let inputIsTTY: @Sendable () -> Bool
  private let promptWriter: @Sendable (String) -> Void
  private let lineReader: @Sendable () -> String?

  public init() {
    self.init(
      isInputTTY: { isatty(STDIN_FILENO) == 1 },
      writePrompt: { prompt in
        FileHandle.standardError.write(Data(prompt.utf8))
      },
      readLine: { readLine(strippingNewline: true) }
    )
  }

  init(
    isInputTTY: @escaping @Sendable () -> Bool,
    writePrompt: @escaping @Sendable (String) -> Void,
    readLine: @escaping @Sendable () -> String?
  ) {
    inputIsTTY = isInputTTY
    promptWriter = writePrompt
    lineReader = readLine
  }

  public var isInputTTY: Bool {
    inputIsTTY()
  }

  public func readResponse(prompt: String) -> ConfirmationResponse {
    promptWriter(prompt)
    guard let response = lineReader() else { return .interrupted }
    return .answer(response)
  }
}
