// SPDX-License-Identifier: Apache-2.0

import RMPTestKit
import Testing

@testable import RMPPlatform

@Suite("RMPPlatform scaffold", .serialized)
struct RMPPlatformScaffoldTests {
  @Test("RMPPlatform and RMPTestKit targets are available")
  func platformTargetsAreAvailable() {
    #expect(RMPPlatformModule.name == "RMPPlatform")
    #expect(RMPTestKitModule.name == "RMPTestKit")
  }
}
