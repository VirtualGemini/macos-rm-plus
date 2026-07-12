// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("RMPCore target is available")
func coreTargetIsAvailable() {
  #expect(RMPCoreModule.name == "RMPCore")
}
