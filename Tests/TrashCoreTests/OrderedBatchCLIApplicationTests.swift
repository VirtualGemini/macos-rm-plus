// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import TrashCore

@Test("An operational failure does not stop later Trash Inputs by default")
func batchContinuesAfterOperationalFailure() {
  let probes = OrderedBatchProbes(
    trashResults: [
      "first": .success(.init(destinationPath: "/Trash/first")),
      "second": .failure(.init(code: .systemTrashFailed)),
      "third": .success(.init(destinationPath: "/Trash/third")),
    ]
  )
  let application = makeOrderedBatchApplication(
    paths: ["first", "second", "third"],
    probes: probes
  )

  let result = application.run(
    arguments: ["--confirm=never", "first", "second", "third"]
  )

  #expect(probes.receivedTrashPaths == ["first", "second", "third"])
  #expect(result.exitCode == 1)
  #expect(result.standardOutput == "Moved 2 items to Trash; 1 failed.\n")
  #expect(result.standardError.contains("trash_system_call_failed"))
  #expect(result.standardError.contains("\"second\""))
}

@Test("Stop-on-error skips every Trash Input after the first failure")
func batchStopsAfterFirstOperationalFailure() {
  let probes = OrderedBatchProbes(
    trashResults: [
      "first": .success(.init(destinationPath: "/Trash/first")),
      "second": .failure(.init(code: .systemTrashFailed)),
      "third": .success(.init(destinationPath: "/Trash/third")),
    ]
  )
  let application = makeOrderedBatchApplication(
    paths: ["first", "second", "third"],
    probes: probes
  )

  let result = application.run(
    arguments: ["--confirm=never", "--stop-on-error", "first", "second", "third"]
  )

  #expect(probes.receivedTrashPaths == ["first", "second"])
  #expect(result.exitCode == 1)
  #expect(result.standardOutput == "Moved 1 item to Trash; 1 failed; 1 skipped.\n")
  #expect(result.standardError.contains("trash_system_call_failed"))
  #expect(result.standardError.contains("\"second\""))
  #expect(!result.standardError.contains("\"third\""))
}

@Test("Batch summary keeps moved warnings distinct from failed inputs")
func batchSummaryCountsWarningsSeparately() {
  let probes = OrderedBatchProbes(
    trashResults: [
      "first": .success(
        .init(
          destinationPath: "/Trash/first",
          warnings: [.init(code: .symlinkPutBackNotGuaranteed)]
        )
      ),
      "second": .success(.init(destinationPath: "/Trash/second")),
    ]
  )
  let application = makeOrderedBatchApplication(paths: ["first", "second"], probes: probes)

  let result = application.run(arguments: ["--confirm=never", "first", "second"])

  #expect(result.exitCode == 0)
  #expect(result.standardOutput == "Moved 2 items to Trash; 0 failed; 1 warning.\n")
  #expect(result.standardError.contains("symlink_put_back_not_guaranteed"))
}

@Test("A missing Trash Input fails without preventing later inputs")
func batchContinuesAfterMissingInput() {
  let probes = OrderedBatchProbes(trashResults: [:])
  let application = makeOrderedBatchApplication(
    paths: ["first", "missing", "third"],
    missingPaths: ["missing"],
    probes: probes
  )

  let result = application.run(
    arguments: ["--confirm=never", "first", "missing", "third"]
  )

  #expect(probes.receivedTrashPaths == ["first", "third"])
  #expect(result.exitCode == 1)
  #expect(result.standardOutput == "Moved 2 items to Trash; 1 failed.\n")
  #expect(result.standardError.contains("missing_input"))
  #expect(result.standardError.contains("\"missing\""))
}

@Test("Ignore-missing skips the absent input without failing the batch")
func ignoredMissingInputDoesNotFailBatch() {
  let probes = OrderedBatchProbes(trashResults: [:])
  let application = makeOrderedBatchApplication(
    paths: ["first", "missing", "third"],
    missingPaths: ["missing"],
    probes: probes
  )

  let result = application.run(
    arguments: ["--confirm=never", "--ignore-missing", "first", "missing", "third"]
  )

  #expect(probes.receivedTrashPaths == ["first", "third"])
  #expect(result.exitCode == 0)
  #expect(result.standardOutput == "Moved 2 items to Trash; 0 failed; 1 skipped.\n")
  #expect(result.standardError.isEmpty)
}

@Test("Per-input confirmation skips prompts for pre-capability failures and continues")
func perInputConfirmationContinuesAfterMissingInput() {
  let probes = OrderedBatchProbes(trashResults: [:])
  let prompt = OrderedBatchConfirmationPrompt(
    isInputTTY: true,
    responses: [.answer("yes")]
  )
  let application = makeOrderedBatchApplication(
    paths: ["missing", "ready"],
    missingPaths: ["missing"],
    probes: probes,
    prompt: prompt
  )

  let result = application.run(
    arguments: ["--confirm=each", "--verbose", "missing", "ready"]
  )

  #expect(prompt.receivedPrompts == ["Move [file] \"ready\" to Trash? [y/N] "])
  #expect(probes.receivedTrashPaths == ["ready"])
  #expect(result.exitCode == 1)
  #expect(result.standardOutput == "Moved \"ready\" to Trash at \"/Trash/ready\".\n")
  #expect(result.standardError.contains("missing_input"))
  #expect(result.standardError.contains("\"missing\""))
}

@Test("Single success uses one escaped item line in standard and verbose output")
func singleSuccessOutputModesUseOneEscapedLine() {
  let path = "source\n\"file\""
  let destination = "/Trash/destination\n\"file\""
  let probes = OrderedBatchProbes(
    trashResults: [path: .success(.init(destinationPath: destination))]
  )
  let application = makeOrderedBatchApplication(paths: [path], probes: probes)
  let expected =
    "Moved \"source\\n\\\"file\\\"\" to Trash at \"/Trash/destination\\n\\\"file\\\"\".\n"

  let standard = application.run(arguments: ["--confirm=never", path])
  let verbose = application.run(arguments: ["--confirm=never", "--verbose", path])
  let quiet = application.run(arguments: ["--confirm=never", "--quiet", path])

  #expect(standard.exitCode == 0)
  #expect(standard.standardOutput == expected)
  #expect(standard.standardOutput.filter { $0 == "\n" }.count == 1)
  #expect(verbose.standardOutput == expected)
  #expect(quiet.standardOutput.isEmpty)
  #expect(standard.standardError.isEmpty)
  #expect(verbose.standardError.isEmpty)
  #expect(quiet.standardError.isEmpty)
}

@Test("Per-input stop-on-error records every unprompted input as skipped")
func perInputConfirmationStopRecordsSkippedInputs() {
  let probes = OrderedBatchProbes(trashResults: [:])
  let prompt = OrderedBatchConfirmationPrompt(
    isInputTTY: true,
    responses: [.answer("no"), .answer("yes"), .answer("yes")]
  )
  let application = makeOrderedBatchApplication(
    paths: ["first", "second", "third"],
    probes: probes,
    prompt: prompt
  )

  let result = application.run(
    arguments: ["--confirm=each", "--stop-on-error", "--verbose", "first", "second", "third"]
  )

  #expect(probes.receivedTrashPaths.isEmpty)
  #expect(prompt.receivedPrompts == ["Move [file] \"first\" to Trash? [y/N] "])
  #expect(result.exitCode == 0)
  #expect(result.standardError.contains("confirmation_declined"))
  #expect(result.standardError.contains("\"first\""))
  #expect(
    result.standardOutput
      == """
      Skipped "second" after an earlier failure.
      Skipped "third" after an earlier failure.

      """
  )
}

@Test("Verbose reports every top-level result while quiet preserves only errors")
func batchVerboseAndQuietUseDocumentedChannels() {
  let verboseProbes = OrderedBatchProbes(
    trashResults: [
      "first": .success(.init(destinationPath: "/Trash/first receipt")),
      "third": .failure(.init(code: .systemTrashFailed)),
      "fourth": .success(.init(destinationPath: "/Trash/fourth receipt")),
    ]
  )
  let verboseApplication = makeOrderedBatchApplication(
    paths: ["first", "missing", "third", "fourth"],
    missingPaths: ["missing"],
    probes: verboseProbes
  )

  let verbose = verboseApplication.run(
    arguments: [
      "--confirm=never", "--ignore-missing", "--verbose", "first", "missing", "third",
      "fourth",
    ]
  )

  #expect(verboseProbes.receivedTrashPaths == ["first", "third", "fourth"])
  #expect(verbose.exitCode == 1)
  #expect(
    verbose.standardOutput
      == """
      Moved "first" to Trash at "/Trash/first receipt".
      Skipped "missing" because the missing Trash Input was ignored.
      Moved "fourth" to Trash at "/Trash/fourth receipt".

      """
  )
  #expect(verbose.standardError.contains("trash_system_call_failed"))
  #expect(verbose.standardError.contains("\"third\""))

  let quietProbes = OrderedBatchProbes(
    trashResults: ["third": .failure(.init(code: .systemTrashFailed))]
  )
  let quietApplication = makeOrderedBatchApplication(
    paths: ["first", "missing", "third", "fourth"],
    missingPaths: ["missing"],
    probes: quietProbes
  )
  let quiet = quietApplication.run(
    arguments: [
      "--confirm=never", "--ignore-missing", "--quiet", "first", "missing", "third", "fourth",
    ]
  )

  #expect(quiet.exitCode == 1)
  #expect(quiet.standardOutput.isEmpty)
  #expect(quiet.standardError.contains("trash_system_call_failed"))
  #expect(quiet.standardError.contains("\"third\""))
}

@Test("Secure-overwrite compatibility warning is unconditional and does not fail success")
func secureOverwriteWarningIgnoresTerminalAndQuietState() {
  let warning =
    "tc: warning: -P does not securely overwrite; the item will only be moved to Trash\n"
  let ttyProbes = OrderedBatchProbes(trashResults: [:])
  let ttyPrompt = OrderedBatchConfirmationPrompt(isInputTTY: true, responses: [.answer("yes")])
  let ttyApplication = makeOrderedBatchApplication(
    paths: ["report"],
    probes: ttyProbes,
    prompt: ttyPrompt
  )

  let ttyResult = ttyApplication.run(
    arguments: ["-P", "--quiet", "--confirm=once", "report"]
  )

  #expect(ttyProbes.receivedTrashPaths == ["report"])
  #expect(ttyProbes.confirmationPromptFactoryCalls == 1)
  #expect(ttyPrompt.receivedPrompts.count == 1)
  #expect(ttyResult.exitCode == 0)
  #expect(ttyResult.standardOutput.isEmpty)
  #expect(ttyResult.standardError == warning)

  let nonTTYProbes = OrderedBatchProbes(trashResults: [:])
  let nonTTYPrompt = OrderedBatchConfirmationPrompt(isInputTTY: false, responses: [.answer("yes")])
  let nonTTYApplication = makeOrderedBatchApplication(
    paths: ["report"],
    probes: nonTTYProbes,
    prompt: nonTTYPrompt
  )

  let nonTTYResult = nonTTYApplication.run(
    arguments: ["-P", "--quiet", "--confirm=once", "report"]
  )

  #expect(nonTTYProbes.receivedTrashPaths.isEmpty)
  #expect(nonTTYProbes.confirmationPromptFactoryCalls == 1)
  #expect(nonTTYPrompt.receivedPrompts.isEmpty)
  #expect(nonTTYResult.exitCode == 1)
  #expect(nonTTYResult.standardOutput.isEmpty)
  #expect(nonTTYResult.standardError.hasPrefix(warning))
  #expect(nonTTYResult.standardError.contains("confirmation_required"))

  let nonInteractiveProbes = OrderedBatchProbes(trashResults: [:])
  let nonInteractivePrompt = OrderedBatchConfirmationPrompt(isInputTTY: true, responses: [])
  let nonInteractiveApplication = makeOrderedBatchApplication(
    paths: ["report"],
    probes: nonInteractiveProbes,
    prompt: nonInteractivePrompt
  )
  let nonInteractiveResult = nonInteractiveApplication.run(
    arguments: ["-P", "--quiet", "--non-interactive", "--confirm=never", "report"]
  )

  #expect(nonInteractiveProbes.receivedTrashPaths == ["report"])
  #expect(nonInteractiveProbes.confirmationPromptFactoryCalls == 0)
  #expect(nonInteractiveResult.exitCode == 0)
  #expect(nonInteractiveResult.standardOutput.isEmpty)
  #expect(nonInteractiveResult.standardError == warning)
}

@Test("Strict options reject -P in either order before every capability boundary")
func strictSecureOverwriteRejectionShortCircuitsCapabilities() {
  let argumentCases = [
    ["--strict-options", "-P", "report"],
    ["-P", "--strict-options", "report"],
  ]

  for arguments in argumentCases {
    let probes = OrderedBatchProbes(trashResults: [:])
    let prompt = OrderedBatchConfirmationPrompt(isInputTTY: true, responses: [.answer("yes")])
    let application = makeOrderedBatchApplication(
      paths: ["report"],
      probes: probes,
      prompt: prompt
    )

    let result = application.run(arguments: arguments)

    #expect(result.exitCode == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(
      result.standardError
        == "tc: Compatibility Option -P is not allowed with --strict-options\n"
    )
    #expect(!result.standardError.contains("warning:"))
    #expect(probes.fileSystemFactoryCalls == 0)
    #expect(probes.inspectedEntryPaths.isEmpty)
    #expect(probes.trashClientFactoryCalls == 0)
    #expect(probes.confirmationPromptFactoryCalls == 0)
    #expect(probes.receivedTrashPaths.isEmpty)
    #expect(prompt.receivedPrompts.isEmpty)
  }
}

@Test("Large batches inspect and process only their top-level inputs")
func largeBatchCostsScaleWithTopLevelInputCount() {
  let paths = (0..<1_000).map { "input-\($0)" }
  let probes = OrderedBatchProbes(trashResults: [:])
  let application = makeOrderedBatchApplication(paths: paths, probes: probes)

  let result = application.run(
    arguments: ["--confirm=never", "--quiet"] + paths
  )

  #expect(result.exitCode == 0)
  #expect(result.standardOutput.isEmpty)
  #expect(result.standardError.isEmpty)
  #expect(probes.fileSystemFactoryCalls == 1)
  #expect(probes.inspectedEntryPaths == paths)
  #expect(probes.trashClientFactoryCalls == paths.count)
  #expect(probes.receivedTrashPaths == paths)
}

private final class OrderedBatchProbes: @unchecked Sendable {
  private let trashResults: [String: Result<TrashMoveReceipt, TrashCapabilityError>]
  private(set) var fileSystemFactoryCalls = 0
  private(set) var inspectedEntryPaths: [String] = []
  private(set) var trashClientFactoryCalls = 0
  private(set) var confirmationPromptFactoryCalls = 0
  private(set) var receivedTrashPaths: [String] = []

  init(trashResults: [String: Result<TrashMoveReceipt, TrashCapabilityError>]) {
    self.trashResults = trashResults
  }

  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    receivedTrashPaths.append(path)
    return try trashResults[path, default: .success(.init(destinationPath: "/Trash/\(path)"))]
      .get()
  }

  func recordFileSystemFactoryCall() {
    fileSystemFactoryCalls += 1
  }

  func recordInspection(at path: String) {
    inspectedEntryPaths.append(path)
  }

  func recordTrashClientFactoryCall() {
    trashClientFactoryCalls += 1
  }

  func recordConfirmationPromptFactoryCall() {
    confirmationPromptFactoryCalls += 1
  }
}

private struct OrderedBatchFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/test"
  let entries: [String: FileSystemEntryInspection]
  let probes: OrderedBatchProbes

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    probes.recordInspection(at: path)
    return entries[path] ?? .missing
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    switch path {
    case "/": return .init(device: 1, inode: 1)
    case currentDirectoryPath: return .init(device: 1, inode: 2)
    case homeDirectoryPath: return .init(device: 1, inode: 3)
    default:
      guard case let .entry(entry) = entries[path] else { return nil }
      return entry.identity
    }
  }
}

private struct OrderedBatchTrashClient: TrashClient {
  let probes: OrderedBatchProbes

  func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    try probes.trashItem(atPath: path)
  }
}

private final class OrderedBatchConfirmationPrompt: ConfirmationPrompt, @unchecked Sendable {
  let isInputTTY: Bool
  private var responses: [ConfirmationResponse]
  private(set) var receivedPrompts: [String] = []

  init(isInputTTY: Bool, responses: [ConfirmationResponse]) {
    self.isInputTTY = isInputTTY
    self.responses = responses
  }

  func readResponse(prompt: String) -> ConfirmationResponse {
    receivedPrompts.append(prompt)
    guard !responses.isEmpty else { return .interrupted }
    return responses.removeFirst()
  }
}

private func makeOrderedBatchApplication(
  paths: [String],
  missingPaths: Set<String> = [],
  probes: OrderedBatchProbes,
  prompt: OrderedBatchConfirmationPrompt? = nil
) -> CLIApplication<OrderedBatchFileSystem> {
  let entryPairs: [(String, FileSystemEntryInspection)] = paths.enumerated().compactMap { element in
    let (offset, path) = element
    guard !missingPaths.contains(path) else { return nil }
    return (
      path,
      FileSystemEntryInspection.entry(
        .init(kind: .file, identity: .init(device: 1, inode: UInt64(offset + 10)))
      )
    )
  }
  let entries = Dictionary(uniqueKeysWithValues: entryPairs)
  let makeFileSystem = {
    probes.recordFileSystemFactoryCall()
    return OrderedBatchFileSystem(entries: entries, probes: probes)
  }
  let makeTrashClient = {
    probes.recordTrashClientFactoryCall()
    return OrderedBatchTrashClient(probes: probes)
  }
  if let prompt {
    return CLIApplication(
      makeFileSystem: makeFileSystem,
      makeTrashClient: makeTrashClient,
      effectiveUserID: { 501 },
      makeConfirmationPrompt: {
        probes.recordConfirmationPromptFactoryCall()
        return prompt
      }
    )
  }
  return CLIApplication(
    makeFileSystem: makeFileSystem,
    makeTrashClient: makeTrashClient,
    effectiveUserID: { 501 }
  )
}
