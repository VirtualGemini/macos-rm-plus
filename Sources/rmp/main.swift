// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import RMPCore
import RMPPlatform

let arguments = Array(CommandLine.arguments.dropFirst())
let result = CLIApplication(makeFileSystem: { FoundationTrashPlanningFileSystem() }).run(
  arguments: arguments
)
FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
FileHandle.standardError.write(Data(result.standardError.utf8))
exit(result.exitCode)
