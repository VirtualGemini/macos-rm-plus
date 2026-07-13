// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Native options populate independent Trash Operation policy fields")
func nativeOptionsPopulateIndependentPolicyFields() throws {
  let invocation = try CommandParser.parse(
    arguments: [
      "--confirm=once", "--ignore-missing", "--verbose", "--dry-run",
      "--non-interactive", "--stop-on-error", "--strict-options", "report.txt",
    ]
  )

  #expect(
    invocation
      == .init(
        command: .operation(
          .init(
            paths: ["report.txt"],
            confirmation: .once,
            ignoreMissing: true,
            output: .verbose,
            dryRun: true,
            nonInteractive: true,
            stopOnError: true,
            strictOptions: true
          )),
        warnings: []
      )
  )
}

@Test("Combined short options are processed once from left to right")
func combinedShortOptionsUseLeftToRightPrecedence() throws {
  let cases = [
    ShortOptionCase(["-rf", "build"], .never, true, .standard),
    ShortOptionCase(["-Rfv", "build"], .never, true, .verbose),
    ShortOptionCase(["-fi", "build"], .each, false, .standard),
    ShortOptionCase(["-if", "build"], .never, true, .standard),
  ]

  for testCase in cases {
    let request = try operationRequest(arguments: testCase.arguments)
    #expect(request.confirmation == testCase.confirmation)
    #expect(request.ignoreMissing == testCase.ignoreMissing)
    #expect(request.output == testCase.output)
  }
}

@Test("Repeated and explicit options override only their corresponding fields")
func repeatedAndExplicitOptionsOverrideCorrespondingFields() throws {
  let request = try operationRequest(
    arguments: [
      "-f", "--confirm=smart", "--ignore-missing", "-i", "--confirm=never", "report.txt",
    ])

  #expect(request.confirmation == .never)
  #expect(request.ignoreMissing)

  #expect(try operationRequest(arguments: ["--json", "-v", "report.txt"]).output == .json)
  #expect(try operationRequest(arguments: ["-v", "--json", "report.txt"]).output == .json)
}

@Test("Native option precedence follows a complete left-to-right behavior matrix")
func nativeOptionPrecedenceBehaviorMatrix() throws {
  let cases = [
    PolicyCase(["--force", "--interactive", "item"], .each, false, .standard),
    PolicyCase(["--interactive", "--force", "item"], .never, true, .standard),
    PolicyCase(["--ignore-missing", "-i", "item"], .each, true, .standard),
    PolicyCase(["-f", "--ignore-missing", "-i", "item"], .each, true, .standard),
    PolicyCase(["--ignore-missing", "-f", "-i", "item"], .each, false, .standard),
    PolicyCase(["-f", "-i", "item"], .each, false, .standard),
    PolicyCase(["-i", "--ignore-missing", "item"], .each, true, .standard),
    PolicyCase(["-I", "item"], .conditionalOnce, false, .standard),
    PolicyCase(["--quiet", "--verbose", "item"], .smart, false, .verbose),
    PolicyCase(["--verbose", "--quiet", "item"], .smart, false, .quiet),
    PolicyCase(["--json", "--verbose", "item"], .smart, false, .json),
    PolicyCase(["--verbose", "--json", "item"], .smart, false, .json),
  ]

  for testCase in cases {
    let request = try operationRequest(arguments: testCase.arguments)
    #expect(request.confirmation == testCase.confirmation)
    #expect(request.ignoreMissing == testCase.ignoreMissing)
    #expect(request.output == testCase.output)
  }
}

@Test("Double dash ends parsing and unknown options are usage errors")
func optionTerminatorAndUnknownOptionBehavior() throws {
  let request = try operationRequest(arguments: ["--dry-run", "--", "-filename"])
  #expect(request.paths == ["-filename"])

  let standardInputPath = try operationRequest(arguments: ["--dry-run", "-"])
  #expect(standardInputPath.paths == ["-"])

  #expect(throws: CommandParsingError.unknownOption("--unknown")) {
    try CommandParser.parse(arguments: ["--unknown", "report.txt"])
  }
}

@Test("Invalid confirmation and conflicting output choices are usage errors")
func invalidAndConflictingOptionsAreRejected() {
  #expect(throws: CommandParsingError.noInputs) {
    try CommandParser.parse(arguments: [])
  }
  #expect(throws: CommandParsingError.invalidConfirmationMode("sometimes")) {
    try CommandParser.parse(arguments: ["--confirm=sometimes", "report.txt"])
  }
  #expect(throws: CommandParsingError.invalidConfirmationMode("conditionalOnce")) {
    try CommandParser.parse(arguments: ["--confirm=conditionalOnce", "report.txt"])
  }
  #expect(throws: CommandParsingError.conflictingOptions("--json", "--quiet")) {
    try CommandParser.parse(arguments: ["--json", "--quiet", "report.txt"])
  }
  #expect(throws: CommandParsingError.conflictingInformationCommands) {
    try CommandParser.parse(arguments: ["--help", "--version"])
  }
  #expect(throws: CommandParsingError.unknownOption("-z")) {
    try CommandParser.parse(arguments: ["-fz", "report.txt"])
  }
  #expect(throws: CommandParsingError.helpModifierRequiresHelp("-a")) {
    try CommandParser.parse(arguments: ["-a"])
  }
  #expect(throws: CommandParsingError.helpModifierRequiresHelp("-zh")) {
    try CommandParser.parse(arguments: ["-zh"])
  }
}

@Test("Compatibility options follow the accepted warned unsupported matrix")
func compatibilityOptionsFollowMatrix() throws {
  let accepted = try parsedOperation(arguments: ["-rdx", "report.txt"])
  #expect(accepted.warnings.isEmpty)

  let warned = try parsedOperation(arguments: ["-P", "report.txt"])
  #expect(warned.warnings == [.secureOverwriteIgnored])

  let repeatedWarning = try parsedOperation(arguments: ["-PP", "report.txt"])
  #expect(repeatedWarning.warnings == [.secureOverwriteIgnored, .secureOverwriteIgnored])

  #expect(throws: CommandParsingError.unsupportedCompatibilityOption("-W")) {
    try CommandParser.parse(arguments: ["-W", "report.txt"])
  }
}

@Test("Strict mode rejects every no-effect Compatibility Option regardless of order")
func strictModeRejectsNoEffectCompatibilityOptions() {
  for option in ["-r", "-R", "-d", "-x", "-P"] {
    #expect(throws: CommandParsingError.strictCompatibilityOption(option)) {
      try CommandParser.parse(arguments: [option, "--strict-options", "report.txt"])
    }
    #expect(throws: CommandParsingError.strictCompatibilityOption(option)) {
      try CommandParser.parse(arguments: ["--strict-options", option, "report.txt"])
    }
  }
}

private func operationRequest(arguments: [String]) throws -> TrashOperationRequest {
  try parsedOperation(arguments: arguments).request
}

private func parsedOperation(
  arguments: [String]
) throws -> (request: TrashOperationRequest, warnings: [CompatibilityWarning]) {
  let invocation = try CommandParser.parse(arguments: arguments)
  guard case let .operation(request) = invocation.command else {
    Issue.record("Expected a Trash Operation command")
    throw UnexpectedInformationCommand()
  }
  return (request, invocation.warnings)
}

private struct UnexpectedInformationCommand: Error {}

private struct ShortOptionCase {
  let arguments: [String]
  let confirmation: ConfirmationMode
  let ignoreMissing: Bool
  let output: OutputMode

  init(
    _ arguments: [String], _ confirmation: ConfirmationMode, _ ignoreMissing: Bool,
    _ output: OutputMode
  ) {
    self.arguments = arguments
    self.confirmation = confirmation
    self.ignoreMissing = ignoreMissing
    self.output = output
  }
}

private struct PolicyCase {
  let arguments: [String]
  let confirmation: ConfirmationMode
  let ignoreMissing: Bool
  let output: OutputMode

  init(
    _ arguments: [String], _ confirmation: ConfirmationMode, _ ignoreMissing: Bool,
    _ output: OutputMode
  ) {
    self.arguments = arguments
    self.confirmation = confirmation
    self.ignoreMissing = ignoreMissing
    self.output = output
  }
}
