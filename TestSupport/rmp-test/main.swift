// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
@_spi(RMPTestingEntrypoint) import RMPTestKit

#if !RMP_TESTING
  #error("rmp-test must only be built with RMP_TESTING enabled")
#endif

let result = TestSafetyDriver.run(
  arguments: Array(CommandLine.arguments.dropFirst())
) { context, _ in
  let message = "rmp-test build=RMP_TESTING run=\(context.runID.uuidString.lowercased()) ready\n"
  FileHandle.standardOutput.write(Data(message.utf8))
  return 0
}
if let diagnostic = result.diagnostic {
  FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
}
exit(result.exitCode)
