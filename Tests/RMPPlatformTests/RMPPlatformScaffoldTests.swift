// SPDX-License-Identifier: Apache-2.0

import RMPTestKit
import Testing

@testable import RMPPlatform

@Test("RMPPlatform and RMPTestKit targets are available")
func platformTargetsAreAvailable() {
  #expect(RMPPlatformModule.name == "RMPPlatform")
  #expect(RMPTestKitModule.name == "RMPTestKit")
}
