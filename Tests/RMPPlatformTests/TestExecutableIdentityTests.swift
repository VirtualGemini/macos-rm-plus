// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@Suite("Test executable identity", .serialized)
struct TestExecutableIdentityTests {
  @Test("a copied executable cannot impersonate rmp-test through argv zero")
  func copiedExecutableCannotForgeIdentity() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let copiedExecutable = fixture.homeURL.appendingPathComponent("not-rmp-test")
    try FileManager.default.copyItem(at: try builtTestExecutable(), to: copiedExecutable)
    let process = Process()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [
      "-c",
      "ARGV0=rmp-test exec \"$1\" fixture",
      "identity-test",
      copiedExecutable.path,
    ]
    process.currentDirectoryURL = fixture.homeURL
    process.standardError = standardError
    var environment = ProcessInfo.processInfo.environment
    environment["LLVM_PROFILE_FILE"] = fixture.homeURL.appendingPathComponent("child.profraw").path
    process.environment = environment

    try process.run()
    process.waitUntilExit()
    let diagnostic = try #require(
      String(
        data: standardError.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      )
    )

    #expect(process.terminationStatus == 2)
    #expect(diagnostic.contains("test-safety.wrong-executable"))
  }
}

private func builtTestExecutable() throws -> URL {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let executable = repositoryRoot.appendingPathComponent(".build/debug/rmp-test")
  guard FileManager.default.isExecutableFile(atPath: executable.path) else {
    throw TestExecutableLookupError()
  }
  return executable
}

private struct TestExecutableLookupError: Error {}
