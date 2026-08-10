// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import rmp_test

// The ticket and PRD define these safety-boundary names.
// swiftlint:disable inclusive_language
@Suite("Whitelisted production macOS Trash acceptance", .serialized)
struct WhitelistedMacOSTrashClientTests {
  @Test("runs the production finalizer lifecycle through a whitelist check on every Trash call")
  func runsProductionLifecycleThroughWhitelist() throws {
    let harness = try ProductionFinalizerHarness()
    defer { harness.remove() }
    let client = harness.makeClient()

    let evidence = try client.trashItem(harness.linkURL)

    #expect(
      evidence.returnedURL
        == harness.trashDirectoryURL.appendingPathComponent(harness.linkURL.lastPathComponent)
    )
    #expect(harness.simulator.recoverablePaths.contains(evidence.returnedURL.path))
    #expect(try harness.sourceEntryNames() == [harness.targetURL.lastPathComponent])
    #expect(try harness.trashEntryNames() == [harness.linkURL.lastPathComponent])
  }

  @Test("rejects a degraded production finalizer result after preserving the moved target")
  func rejectsDegradedProductionResult() throws {
    let harness = try ProductionFinalizerHarness(failActivationCalls: true)
    defer { harness.remove() }
    let client = harness.makeClient()

    let diagnostic = captureDiagnostic { _ = try client.trashItem(harness.linkURL) }

    #expect(diagnostic?.code == .trashSystemCallFailed)
    #expect(try harness.sourceEntryNames() == [harness.targetURL.lastPathComponent])
    #expect(try harness.trashEntryNames() == [harness.linkURL.lastPathComponent])
  }
}
// swiftlint:enable inclusive_language

private final class ProductionFinalizerHarness {
  let fixture: SafetyHomeFixture
  let context: TestSafetyContext
  let trashDirectoryURL: URL
  let targetURL: URL
  let linkURL: URL
  let simulator: FoundationTrashSimulator
  private let failActivationCalls: Bool

  init(failActivationCalls: Bool = false) throws {
    fixture = try SafetyHomeFixture()
    context = try fixture.establishContext()
    trashDirectoryURL = fixture.homeURL.appendingPathComponent("Trash", isDirectory: true)
    targetURL = try context.createFixtureFile(
      suffix: "production-finalizer-target",
      contents: Data("target\n".utf8)
    )
    linkURL = try context.createFixtureSymbolicLink(
      suffix: "production-finalizer-link",
      target: targetURL.lastPathComponent
    )
    try FileManager.default.createDirectory(
      at: trashDirectoryURL,
      withIntermediateDirectories: false
    )
    simulator = FoundationTrashSimulator(trashDirectoryURL: trashDirectoryURL)
    self.failActivationCalls = failActivationCalls
  }

  func makeClient() -> WhitelistedMacOSTrashClient {
    let calls = ActivationFailureSwitch(
      simulator: simulator,
      failActivationCalls: failActivationCalls
    )
    let trashClient = WhitelistedTrashClient.testingOnly(
      context: context,
      authorization: TrashAuthorizationOperations(
        inspectVolume: { _ in
          TrashVolumeInspection(isLocal: true, isMountPoint: false, isFileProviderRoot: false)
        },
        deviceMatchesRun: { $0 == $1 },
        resourceIdentifier: testSafetyResourceIdentifier
      ),
      systemTrash: calls.trash
    )
    return WhitelistedMacOSTrashClient(
      context: context,
      foundationTrashClient: trashClient,
      resourceIdentifier: testSafetyResourceIdentifier
    )
  }

  func sourceEntryNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: context.runDirectoryURL.path)
      .filter { !$0.hasPrefix(".rmp-test-") }
      .sorted()
  }

  func trashEntryNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: trashDirectoryURL.path).sorted()
  }

  func remove() {
    fixture.remove()
  }
}

private final class ActivationFailureSwitch: @unchecked Sendable {
  private let simulator: FoundationTrashSimulator
  private let failActivationCalls: Bool
  private var callCount = 0

  init(simulator: FoundationTrashSimulator, failActivationCalls: Bool) {
    self.simulator = simulator
    self.failActivationCalls = failActivationCalls
  }

  func trash(_ sourceURL: URL) throws -> URL {
    callCount += 1
    if failActivationCalls, callCount >= 3 {
      throw InjectedTrashFailure()
    }
    return try simulator.trash(sourceURL)
  }
}
