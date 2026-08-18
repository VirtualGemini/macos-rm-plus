// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
  name: "macos-trash-cli",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "tc", targets: ["tc"]),
    .executable(name: "tc-test", targets: ["tc-test"]),
  ],
  dependencies: [
    .package(url: "https://github.com/realm/SwiftLint.git", exact: "0.65.0")
  ],
  targets: [
    .target(name: "TrashCore"),
    .target(name: "TrashPlatform", dependencies: ["TrashCore"]),
    .executableTarget(name: "tc", dependencies: ["TrashCore", "TrashPlatform"]),
    .target(
      name: "TrashTestKit",
      dependencies: ["TrashCore", "TrashPlatform"],
      path: "TestSupport/TrashTestKit"
    ),
    .executableTarget(
      name: "tc-test",
      dependencies: ["TrashCore", "TrashPlatform"],
      path: "TestSupport",
      exclude: ["TrashTestKit"],
      sources: ["TrashTestSafety", "tc-test"],
      swiftSettings: [.define("TC_TESTING")]
    ),
    .testTarget(name: "TrashCoreTests", dependencies: ["TrashCore"]),
    .testTarget(
      name: "TrashPlatformTests",
      dependencies: ["TrashPlatform", "TrashTestKit", "tc-test"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
