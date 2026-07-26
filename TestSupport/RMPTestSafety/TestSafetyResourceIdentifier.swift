// SPDX-License-Identifier: Apache-2.0

import Foundation

func testSafetyResourceIdentifier(_ url: URL) throws -> Data? {
  guard
    let identifier = try url.resourceValues(forKeys: [.fileResourceIdentifierKey])
      .fileResourceIdentifier
  else {
    return nil
  }
  if let data = identifier as? Data { return data }
  return try NSKeyedArchiver.archivedData(
    withRootObject: identifier,
    requiringSecureCoding: true
  )
}
