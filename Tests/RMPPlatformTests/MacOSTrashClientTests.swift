// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@testable import RMPCore
@testable import RMPPlatform

@Suite("macOS recoverable Trash client", .serialized)
struct MacOSTrashClientTests {
  @Test("a regular file remains Finder-backed")
  func regularFileUsesFinder() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let finder = FinderMoveSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: finder.trash,
      foundationTrash: { _ in
        Issue.record("Foundation must not receive a regular file")
        throw InjectedTrashFailure()
      }
    )

    let receipt = try client.trashItem(atPath: fixture.targetURL.path)

    #expect(receipt.destinationPath == fixture.trashedTargetURL.path)
    #expect(receipt.warnings.isEmpty)
    #expect(!macOSEntryExists(at: fixture.targetURL))
    #expect(macOSEntryExists(at: fixture.linkURL))
    #expect(finder.receivedPaths == [fixture.targetURL.path])
  }

  @Test("the production default trashes the symbolic link before its activation finalizer")
  func symbolicLinkRemainsRecoverable() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = FoundationTrashSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        Issue.record("Finder must not receive a symbolic link")
        throw InjectedTrashFailure()
      },
      foundationTrash: simulator.trash
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(simulator.receivedNames.count == 2)
    #expect(simulator.receivedNames[0] == fixture.linkURL.lastPathComponent)
    #expect(simulator.receivedNames[1].hasPrefix(".rmp-finalizer-"))
    #expect(simulator.recoverablePaths.contains(receipt.destinationPath))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(!macOSEntryExists(at: fixture.linkURL))
    #expect(try fixture.sourceEntryNames() == ["target.txt"])
    #expect(try fixture.trashEntryNames() == ["shortcut"])
  }

  @Test("visible finalizer names preserve the production ordering and cleanup lifecycle")
  func visibleFinalizerNamesPreserveProductionLifecycle() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = FoundationTrashSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        Issue.record("Finder must not receive a symbolic link")
        throw InjectedTrashFailure()
      },
      foundationTrash: simulator.trash,
      finalizerName: { "rmp-test-visible-finalizer-\(UUID().uuidString.lowercased())" }
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(simulator.receivedNames.count == 2)
    #expect(simulator.receivedNames[0] == fixture.linkURL.lastPathComponent)
    #expect(simulator.receivedNames[1].hasPrefix("rmp-test-visible-finalizer-"))
    #expect(simulator.receivedNames.allSatisfy { !$0.hasPrefix(".") })
    #expect(try fixture.sourceEntryNames() == ["target.txt"])
    #expect(try fixture.trashEntryNames() == ["shortcut"])
  }

  @Test("disabling preflight keeps target activation restore and cleanup unchanged")
  func disabledPreflightKeepsActivationLifecycle() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = FoundationTrashSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        Issue.record("Finder must not receive a symbolic link")
        throw InjectedTrashFailure()
      },
      foundationTrash: simulator.trash,
      performsFinalizerPreflight: false
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(simulator.receivedNames.count == 2)
    #expect(simulator.receivedNames[0] == fixture.linkURL.lastPathComponent)
    #expect(simulator.receivedNames[1].hasPrefix(".rmp-finalizer-"))
    #expect(simulator.recoverablePaths.contains(receipt.destinationPath))
    #expect(try fixture.sourceEntryNames() == ["target.txt"])
    #expect(try fixture.trashEntryNames() == ["shortcut"])
  }

  @Test("the diagnostic preflight completes before the target and activation lifecycle")
  func enabledPreflightCompletesBeforeTargetLifecycle() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = FoundationTrashSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        Issue.record("Finder must not receive a symbolic link")
        throw InjectedTrashFailure()
      },
      foundationTrash: simulator.trash,
      performsFinalizerPreflight: true
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(simulator.receivedNames.count == 3)
    #expect(simulator.receivedNames[0].hasPrefix(".rmp-finalizer-"))
    #expect(simulator.receivedNames[1] == fixture.linkURL.lastPathComponent)
    #expect(simulator.receivedNames[2].hasPrefix(".rmp-finalizer-"))
    #expect(try fixture.sourceEntryNames() == ["target.txt"])
    #expect(try fixture.trashEntryNames() == ["shortcut"])
  }

  @Test("a broken symbolic link uses the same recoverable finalizer protocol")
  func brokenSymbolicLinkRemainsRecoverable() throws {
    let fixture = try RecoverableTrashFixture(linkDestinationExists: false)
    defer { fixture.remove() }
    let simulator = FoundationTrashSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        Issue.record("Finder must not receive a broken symbolic link")
        throw InjectedTrashFailure()
      },
      foundationTrash: simulator.trash
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(simulator.recoverablePaths.contains(receipt.destinationPath))
    #expect(!macOSEntryExists(at: fixture.targetURL))
    #expect(!macOSEntryExists(at: fixture.linkURL))
    #expect(try fixture.sourceEntryNames().isEmpty)
    #expect(try fixture.trashEntryNames() == ["shortcut"])
  }

  @Test("a failed finalizer preflight leaves the target symbolic link untouched")
  func preflightFailureLeavesTargetUntouched() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = PreflightFailureSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash,
      performsFinalizerPreflight: true
    )

    do {
      _ = try client.trashItem(atPath: fixture.linkURL.path)
      Issue.record("Expected the finalizer preflight to fail")
    } catch let error as TrashCapabilityError {
      #expect(error.code == .systemTrashFailed)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }

    #expect(macOSEntryExists(at: fixture.linkURL))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(try fixture.sourceEntryNames() == ["shortcut", "target.txt"])
    #expect(try fixture.trashEntryNames().isEmpty)
  }

  @Test("a target Trash failure removes prepared finalizers and leaves the target untouched")
  func targetTrashFailureLeavesTargetUntouched() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = TargetTrashFailureSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash
    )

    do {
      _ = try client.trashItem(atPath: fixture.linkURL.path)
      Issue.record("Expected the target Trash call to fail")
    } catch let error as TrashCapabilityError {
      #expect(error.code == .systemTrashFailed)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }

    #expect(macOSEntryExists(at: fixture.linkURL))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(try fixture.sourceEntryNames() == ["shortcut", "target.txt"])
    #expect(try fixture.trashEntryNames().isEmpty)
  }

  @Test("a target failure reports a prepared Finalizer that could not be cleaned up")
  func targetFailureReportsFinalizerCleanupFailure() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = ReplacedFinalizerFailureSimulator()
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash
    )

    do {
      _ = try client.trashItem(atPath: fixture.linkURL.path)
      Issue.record("Expected the target Trash call to fail")
    } catch let error as TrashCapabilityError {
      #expect(error.code == .finalizerCleanupFailed)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }

    #expect(macOSEntryExists(at: fixture.linkURL))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(
      try fixture.sourceEntryNames()
        == [simulator.replacedFinalizerName, "shortcut", "target.txt"].compactMap { $0 }.sorted()
    )
    #expect(try fixture.trashEntryNames().isEmpty)
  }
}

extension MacOSTrashClientTests {
  @Test("a prepared backup finalizer recovers from the first activation failure")
  func backupFinalizerRecoversActivationFailure() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = ActivationRetrySimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(simulator.recoverablePaths.contains(receipt.destinationPath))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(!macOSEntryExists(at: fixture.linkURL))
    #expect(try fixture.sourceEntryNames() == ["target.txt"])
    #expect(try fixture.trashEntryNames() == ["shortcut"])
  }

  @Test("an activation error after the finalizer moved stops before the backup shifts metadata")
  func movedActivationFailureStopsBeforeBackup() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = MovedActivationFailureSimulator(
      trashDirectoryURL: fixture.trashDirectoryURL
    )
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(receipt.warnings.map(\.code) == [.finalizerStateUncertain])
    #expect(simulator.recoverablePaths.contains(receipt.destinationPath))
    #expect(simulator.callCount == 2)
    #expect(try fixture.sourceEntryNames() == ["target.txt"])
    #expect(try fixture.trashEntryNames().contains("shortcut"))
    #expect(
      try fixture.trashEntryNames().count { $0.hasPrefix(".rmp-finalizer-") } == 1
    )
  }

  @Test("exhausted activation attempts preserve the target receipt with a stable warning")
  func exhaustedActivationAttemptsPreserveReceipt() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = ExhaustedActivationSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(receipt.warnings.map(\.code) == [.symlinkPutBackNotGuaranteed])
    #expect(!simulator.recoverablePaths.contains(receipt.destinationPath))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(!macOSEntryExists(at: fixture.linkURL))
    #expect(try fixture.sourceEntryNames() == ["target.txt"])
    #expect(try fixture.trashEntryNames() == ["shortcut"])
  }

  @Test("post-activation cleanup failure does not misreport Put Back as unavailable")
  func cleanupFailurePreservesRecoverableReceipt() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = CleanupFailureSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash
    )

    let receipt = try client.trashItem(atPath: fixture.linkURL.path)

    #expect(receipt.destinationPath == fixture.trashedLinkURL.path)
    #expect(receipt.warnings.map(\.code) == [.finalizerCleanupFailed])
    #expect(simulator.recoverablePaths.contains(receipt.destinationPath))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(!macOSEntryExists(at: fixture.linkURL))
  }

  @Test("a failed preflight restore stops before the target is moved")
  func preflightRestoreFailureLeavesTargetUntouched() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let simulator = FoundationTrashSimulator(trashDirectoryURL: fixture.trashDirectoryURL)
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash,
      restoreItem: { _, _ in throw InjectedTrashFailure() },
      performsFinalizerPreflight: true
    )

    do {
      _ = try client.trashItem(atPath: fixture.linkURL.path)
      Issue.record("Expected the preflight restore to fail")
    } catch let error as TrashCapabilityError {
      #expect(error.code == .finalizerCleanupFailed)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }

    #expect(macOSEntryExists(at: fixture.linkURL))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(try fixture.sourceEntryNames() == ["shortcut", "target.txt"])
    #expect(try fixture.trashEntryNames().count == 1)
    #expect(try fixture.trashEntryNames()[0].hasPrefix(".rmp-finalizer-"))
  }

  @Test("preflight refuses a returned Trash URL with the wrong identity")
  func preflightRejectsWrongReturnedIdentity() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let unrelatedURL = fixture.trashDirectoryURL.appendingPathComponent("unrelated.txt")
    try Data("unrelated\n".utf8).write(to: unrelatedURL)
    let simulator = WrongReturnedIdentitySimulator(
      trashDirectoryURL: fixture.trashDirectoryURL,
      returnedURL: unrelatedURL
    )
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash,
      performsFinalizerPreflight: true
    )

    do {
      _ = try client.trashItem(atPath: fixture.linkURL.path)
      Issue.record("Expected the preflight Trash identity check to fail")
    } catch let error as TrashCapabilityError {
      #expect(error.code == .finalizerCleanupFailed)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }

    #expect(macOSEntryExists(at: fixture.linkURL))
    #expect(macOSEntryExists(at: fixture.targetURL))
    #expect(macOSEntryExists(at: unrelatedURL))
    #expect(try Data(contentsOf: unrelatedURL) == Data("unrelated\n".utf8))
    #expect(try fixture.sourceEntryNames() == ["shortcut", "target.txt"])
  }

  @Test("a wrong target receipt is rejected after activating the actual moved link")
  func targetRejectsWrongReturnedIdentityAfterActivation() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let unrelatedURL = fixture.trashDirectoryURL.appendingPathComponent("unrelated.txt")
    try Data("unrelated\n".utf8).write(to: unrelatedURL)
    let simulator = WrongTargetReceiptSimulator(
      trashDirectoryURL: fixture.trashDirectoryURL,
      wrongReturnedURL: unrelatedURL
    )
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in throw InjectedTrashFailure() },
      foundationTrash: simulator.trash
    )

    do {
      _ = try client.trashItem(atPath: fixture.linkURL.path)
      Issue.record("Expected the target Trash identity check to fail")
    } catch let error as TrashCapabilityError {
      #expect(error.code == .systemTrashFailed)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }

    #expect(!macOSEntryExists(at: fixture.linkURL))
    #expect(macOSEntryExists(at: fixture.trashedLinkURL))
    #expect(simulator.recoverablePaths.contains(fixture.trashedLinkURL.path))
    #expect(macOSEntryExists(at: unrelatedURL))
    #expect(try Data(contentsOf: unrelatedURL) == Data("unrelated\n".utf8))
    #expect(try fixture.sourceEntryNames() == ["target.txt"])
    #expect(try fixture.trashEntryNames() == ["shortcut", "unrelated.txt"])
  }

  @Test("a missing source reports the stable system failure without calling either backend")
  func missingSourceDoesNotCallTrashBackends() {
    let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "rmp-missing-\(UUID().uuidString)"
    )
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        Issue.record("Finder must not receive a missing source")
        throw InjectedTrashFailure()
      },
      foundationTrash: { _ in
        Issue.record("Foundation must not receive a missing source")
        throw InjectedTrashFailure()
      }
    )

    do {
      _ = try client.trashItem(atPath: missingURL.path)
      Issue.record("Expected the missing source to fail")
    } catch let error as TrashCapabilityError {
      #expect(error.code == .systemTrashFailed)
    } catch {
      Issue.record("Expected a stable TrashCapabilityError")
    }
  }

  @Test("an ordinary-entry Finder capability error is preserved")
  func finderCapabilityErrorIsPreserved() throws {
    let fixture = try RecoverableTrashFixture()
    defer { fixture.remove() }
    let client = makeInjectedMacOSTrashClient(
      finderTrash: { _ in
        throw TrashCapabilityError(code: .finderAutomationDenied)
      },
      foundationTrash: { _ in
        Issue.record("Foundation must not receive a regular file")
        throw InjectedTrashFailure()
      }
    )

    do {
      _ = try client.trashItem(atPath: fixture.targetURL.path)
      Issue.record("Expected Finder Automation denial")
    } catch let error as TrashCapabilityError {
      #expect(error.code == .finderAutomationDenied)
    } catch {
      Issue.record("Expected the Finder capability error to be preserved")
    }
  }
}
