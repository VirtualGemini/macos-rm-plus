// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

let message = "rmp has not been implemented yet.\n"
FileHandle.standardError.write(Data(message.utf8))
exit(2)
