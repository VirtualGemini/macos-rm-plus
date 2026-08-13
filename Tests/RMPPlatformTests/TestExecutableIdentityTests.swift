// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@Suite("Test executable identity", .serialized)
struct TestExecutableIdentityTests {
  @Test(
    "pure information commands bypass the Test Safety Context",
    arguments: [
      InformationCommandCase(
        argument: "--help",
        standardOutput: """
          Usage: rmp-test put-back-race --test-run-id <uuid>
                 rmp-test duplicate-trash-name --test-run-id <uuid>
                 rmp-test put-back-race-manual [OPTIONS] --test-run-id <uuid>
                 rmp-test put-back-symlink-delay-manual [OPTIONS] --test-run-id <uuid>
                 rmp-test put-back-symlink-finalizer-manual [OPTIONS] --test-run-id <uuid>
                 rmp-test put-back-symlink-production-manual [OPTIONS] --test-run-id <uuid>
                 rmp-test put-back-symlink-production-probe [OPTIONS] --test-run-id <uuid>
                 rmp-test [--test-run-id <uuid>] [--] <PATH>...

          put-back-race-manual options:
            --settle-seconds <n>  re-trash delay bucket, 0-60, default 0
            --cycles <n>          differential cycles, 1-30, default 1
            --fixture <kind>      file | directory | symbolic-link |
                                  broken-symbolic-link | quoted-name | newline-name

          put-back-symlink-delay-manual options:
            --settle-seconds <n>  pre-Trash delay after Put Back, 0-60, default 0
            --cycles <n>          differential cycles, 1-30, default 1
            --fixture <kind>      symbolic-link | broken-symbolic-link

          put-back-symlink-finalizer-manual options:
            --cycles <n>          finalizer validation cycles, 1-30, default 1
            --fixture <kind>      symbolic-link | broken-symbolic-link

          put-back-symlink-production-manual options:
            --cycles <n>          production finalizer validation cycles, 1-30, default 1
            --fixture <kind>      symbolic-link | broken-symbolic-link
            --finalizer-fault <mode>
                                  none | not-moved-before-error | moved-before-error

          put-back-symlink-production-probe options:
            --fixture <kind>      symbolic-link | broken-symbolic-link
            --finalizer-name <n>  hidden | visible, default hidden
            --preflight <mode>    enabled | disabled, default disabled

          """
      ),
      InformationCommandCase(
        argument: "--version",
        standardOutput: "rmp-test build=RMP_TESTING\n"
      ),
      InformationCommandCase(
        argument: "--help -a",
        standardOutput: """
          Usage: rmp-test put-back-race --test-run-id <uuid>
                 rmp-test duplicate-trash-name --test-run-id <uuid>
                 rmp-test put-back-race-manual [OPTIONS] --test-run-id <uuid>
                 rmp-test put-back-symlink-delay-manual [OPTIONS] --test-run-id <uuid>
                 rmp-test put-back-symlink-finalizer-manual [OPTIONS] --test-run-id <uuid>
                 rmp-test put-back-symlink-production-manual [OPTIONS] --test-run-id <uuid>
                 rmp-test put-back-symlink-production-probe [OPTIONS] --test-run-id <uuid>
                 rmp-test [--test-run-id <uuid>] [--] <PATH>...

          put-back-race-manual options:
            --settle-seconds <n>  re-trash delay bucket, 0-60, default 0
            --cycles <n>          differential cycles, 1-30, default 1
            --fixture <kind>      file | directory | symbolic-link |
                                  broken-symbolic-link | quoted-name | newline-name

          put-back-symlink-delay-manual options:
            --settle-seconds <n>  pre-Trash delay after Put Back, 0-60, default 0
            --cycles <n>          differential cycles, 1-30, default 1
            --fixture <kind>      symbolic-link | broken-symbolic-link

          put-back-symlink-finalizer-manual options:
            --cycles <n>          finalizer validation cycles, 1-30, default 1
            --fixture <kind>      symbolic-link | broken-symbolic-link

          put-back-symlink-production-manual options:
            --cycles <n>          production finalizer validation cycles, 1-30, default 1
            --fixture <kind>      symbolic-link | broken-symbolic-link
            --finalizer-fault <mode>
                                  none | not-moved-before-error | moved-before-error

          put-back-symlink-production-probe options:
            --fixture <kind>      symbolic-link | broken-symbolic-link
            --finalizer-name <n>  hidden | visible, default hidden
            --preflight <mode>    enabled | disabled, default disabled

          """
      ),
    ]
  )
  func informationCommandsBypassSafetyContext(testCase: InformationCommandCase) throws {
    let result = try runBuiltTestExecutable(
      arguments: testCase.argument.split(separator: " ").map(String.init)
    )

    #expect(result.exitCode == 0)
    #expect(result.standardOutput == testCase.standardOutput)
    #expect(result.standardError.isEmpty)
  }

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

  @Test("an independently compiled executable cannot call the safety entry")
  func independentExecutableCannotCallSafetyEntry() throws {
    let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "rmp-test-entry-forgery-\(UUID().uuidString).swift"
    )
    defer { try? FileManager.default.removeItem(at: sourceURL) }
    try Data(
      """
      @testable import rmp_test
      _ = RMPTestEntrypoint.self
      """.utf8
    ).write(to: sourceURL)
    let process = Process()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
      "swiftc",
      "-typecheck",
      "-enable-testing",
      "-package-name",
      "macos_rm_plus",
      "-I",
      try builtTestExecutable().deletingLastPathComponent()
        .appendingPathComponent("Modules").path,
      sourceURL.path,
    ]
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()
    let diagnostic = try #require(
      String(
        data: standardError.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      )
    )

    #expect(process.terminationStatus != 0)
    #expect(!diagnostic.contains("no such module 'rmp_test'"))
    #expect(diagnostic.contains("cannot find 'RMPTestEntrypoint' in scope"))
  }

  @Test(
    "finalizer scenarios reject a nonzero settle delay before test setup",
    arguments: [
      "put-back-symlink-finalizer-manual",
      "put-back-symlink-production-manual",
    ]
  )
  func finalizerScenarioRejectsDelay(scenario: String) throws {
    let result = try runBuiltTestExecutable(
      arguments: [scenario, "--settle-seconds", "1"]
    )

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("test-safety.invalid-command-arguments"))
    #expect(result.standardError.contains("requires zero settle delay"))
  }
}

struct InformationCommandCase: CustomTestStringConvertible, Sendable {
  let argument: String
  let standardOutput: String

  var testDescription: String { argument }
}

private struct ProcessResult {
  let exitCode: Int32
  let standardOutput: String
  let standardError: String
}

private func runBuiltTestExecutable(arguments: [String]) throws -> ProcessResult {
  let process = Process()
  let standardOutput = Pipe()
  let standardError = Pipe()
  process.executableURL = try builtTestExecutable()
  process.arguments = arguments
  process.standardOutput = standardOutput
  process.standardError = standardError
  var environment = ProcessInfo.processInfo.environment
  environment["LLVM_PROFILE_FILE"] =
    FileManager.default.temporaryDirectory
    .appendingPathComponent("rmp-test-information-%p.profraw").path
  process.environment = environment

  try process.run()
  process.waitUntilExit()

  let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
  let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
  return ProcessResult(
    exitCode: process.terminationStatus,
    standardOutput: try #require(String(data: outputData, encoding: .utf8)),
    standardError: try #require(String(data: errorData, encoding: .utf8))
  )
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
