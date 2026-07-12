// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

#if !RMP_TESTING
  #error("rmp-test must only be built with RMP_TESTING enabled")
#endif

let message = "rmp-test safety driver has not been implemented yet.\n"
FileHandle.standardError.write(Data(message.utf8))
exit(2)
