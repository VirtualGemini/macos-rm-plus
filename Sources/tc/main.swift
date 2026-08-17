// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import TrashCore
import TrashPlatform

let arguments = Array(CommandLine.arguments.dropFirst())
let result = CLIApplication(
  makeFileSystem: { FoundationTrashPlanningFileSystem() },
  makeTrashClient: { MacOSTrashClient() },
  effectiveUserID: { UInt32(geteuid()) },
  makeConfirmationPrompt: { StandardInputConfirmationPrompt() },
  currentDirectoryPath: { FileManager.default.currentDirectoryPath }
).run(arguments: arguments)
FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
FileHandle.standardError.write(Data(result.standardError.utf8))
exit(result.exitCode)
