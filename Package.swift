// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
  name: "macos-rm-plus",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "rmp", targets: ["rmp"]),
    .executable(name: "rmp-test", targets: ["rmp-test"]),
  ],
  dependencies: [
    .package(url: "https://github.com/realm/SwiftLint.git", exact: "0.65.0")
  ],
  targets: [
    .target(name: "RMPCore"),
    .target(name: "RMPPlatform", dependencies: ["RMPCore"]),
    .executableTarget(name: "rmp", dependencies: ["RMPCore", "RMPPlatform"]),
    .target(
      name: "RMPTestKit",
      dependencies: ["RMPCore", "RMPPlatform"],
      path: "TestSupport/RMPTestKit"
    ),
    .executableTarget(
      name: "rmp-test",
      dependencies: ["RMPCore", "RMPPlatform", "RMPTestKit"],
      path: "TestSupport/rmp-test",
      swiftSettings: [.define("RMP_TESTING")]
    ),
    .testTarget(name: "RMPCoreTests", dependencies: ["RMPCore"]),
    .testTarget(
      name: "RMPPlatformTests",
      dependencies: ["RMPPlatform", "RMPTestKit"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
