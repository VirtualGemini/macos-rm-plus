// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import TrashCore

@Test("TrashCore target is available")
func coreTargetIsAvailable() {
  #expect(TrashCoreModule.name == "TrashCore")
}
