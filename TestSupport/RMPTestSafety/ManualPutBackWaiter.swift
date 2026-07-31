// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

/// A registered watch over the Run Directory. `waitForChange` returns `true` when the kernel
/// reported a directory change and `false` when the slice expired without one.
struct DirectoryChangeWatch {
  let waitForChange: (TimeInterval) -> Bool
  let close: () -> Void
}

/// Restores the first Trash item by waiting for the maintainer's real Finder "Put Back" command
/// instead of scripting the move. This carries no Finder capability at all: it only observes the
/// authorized Run Directory and reports when the exact Test Fixture returns.
struct ManualPutBackWaiter {
  typealias Announce = (String) -> Void
  /// Reports whole seconds remaining in the wait window so a terminal can show a live countdown.
  typealias Heartbeat = (Int) -> Void
  typealias ResourceIdentifier = (URL) throws -> Data?
  typealias EntryProbe = (String) throws -> Bool
  typealias MakeDirectoryChangeWatch = () throws -> DirectoryChangeWatch
  typealias MonotonicClock = () -> TimeInterval

  static let defaultTimeout: TimeInterval = 180
  /// Upper bound on a single kernel wait. The restore is detected by the vnode event itself; this
  /// slice only bounds the pathological case of a change notification never arriving.
  static let waitSlice: TimeInterval = 0.25

  private let context: TestSafetyContext
  private let announce: Announce
  private let heartbeat: Heartbeat
  private let resourceIdentifier: ResourceIdentifier
  private let entryProbe: EntryProbe
  private let makeWatch: MakeDirectoryChangeWatch
  private let now: MonotonicClock
  private let timeout: TimeInterval

  init(
    context: TestSafetyContext,
    announce: @escaping Announce,
    heartbeat: @escaping Heartbeat = { _ in },
    timeout: TimeInterval = ManualPutBackWaiter.defaultTimeout,
    resourceIdentifier: @escaping ResourceIdentifier = testSafetyResourceIdentifier,
    entryProbe: EntryProbe? = nil,
    makeWatch: MakeDirectoryChangeWatch? = nil,
    now: @escaping MonotonicClock = { ProcessInfo.processInfo.systemUptime }
  ) {
    self.context = context
    self.announce = announce
    self.heartbeat = heartbeat
    self.timeout = timeout
    self.resourceIdentifier = resourceIdentifier
    self.entryProbe = entryProbe ?? { try Self.runDirectoryEntryExists(context: context, name: $0) }
    self.makeWatch = makeWatch ?? { try Self.watchRunDirectory(context: context) }
    self.now = now
  }

  func putBack(
    _ evidence: TrashVerificationEvidence,
    to expectedSourceURL: URL
  ) throws -> PutBackVerificationEvidence {
    try context.revalidate()
    let sourceURL = expectedSourceURL.standardizedFileURL
    let name = sourceURL.lastPathComponent
    guard
      sourceURL.deletingLastPathComponent() == context.runDirectoryURL.standardizedFileURL,
      name.hasPrefix("rmp-test-\(context.runID.uuidString.lowercased())-")
    else {
      throw evidenceMismatch("Manual Put Back evidence is outside the authorized Test Fixture.")
    }

    let watch = try makeWatch()
    defer { watch.close() }
    guard try !entryProbe(name) else {
      throw TestSafetyDiagnostic(
        code: .putBackSourceOccupied,
        message: "The original Test Fixture path is occupied; the first Trash did not complete."
      )
    }
    announce(
      Self.instruction(
        trashedName: evidence.returnedURL.lastPathComponent,
        timeout: timeout
      )
    )
    try waitForRestoredEntry(named: name, watch: watch)

    try context.revalidate()
    let restoredIdentifier: Data?
    do {
      restoredIdentifier = try resourceIdentifier(sourceURL)
    } catch {
      throw evidenceMismatch("The restored Test Fixture could not be identified.")
    }
    if let expectedIdentifier = evidence.resourceIdentifier {
      guard restoredIdentifier == expectedIdentifier else {
        throw evidenceMismatch("The restored Test Fixture identity does not match the Trash item.")
      }
    }
    return PutBackVerificationEvidence(
      returnedURL: sourceURL,
      resourceIdentifier: restoredIdentifier
    )
  }

  private func waitForRestoredEntry(named name: String, watch: DirectoryChangeWatch) throws {
    let deadline = now() + timeout
    var lastReported = -1
    while true {
      let remaining = deadline - now()
      guard remaining > 0 else {
        throw TestSafetyDiagnostic(
          code: .putBackManualTimeout,
          message: "Finder Put Back was not observed before the manual acceptance deadline."
        )
      }
      // Rounding up keeps the very first tick on the declared timeout: the clock has already
      // advanced a fraction by the time the window is measured, so rounding down would report
      // 179 for a 180 second window and skip every multiple-of-five tick until 175.
      let whole = Int(remaining.rounded(.up))
      if whole != lastReported, whole <= 5 || whole.isMultiple(of: 5) {
        heartbeat(whole)
        lastReported = whole
      }
      _ = watch.waitForChange(min(remaining, Self.waitSlice))
      if try entryProbe(name) { return }
    }
  }

  private static func instruction(trashedName: String, timeout: TimeInterval) -> String {
    """
    first-trash-complete
    trash-item=\(trashedName)
    Open Finder, select that item in Trash, and choose Put Back.
    rmp-test re-trashes it the moment it returns; waiting up to \(Int(timeout))s.
    """
  }

  private static func runDirectoryEntryExists(
    context: TestSafetyContext,
    name: String
  ) throws -> Bool {
    let descriptor = try context.duplicateRunDirectoryDescriptor()
    defer { close(descriptor) }
    var status = stat()
    if fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 { return true }
    guard errno == ENOENT else {
      throw posixDiagnostic(
        code: .putBackEvidenceMismatch,
        operation: "inspect the restored Test Fixture"
      )
    }
    return false
  }

  /// Watches the authorized Run Directory through a kqueue-backed dispatch source. The restore is
  /// observed as a vnode event rather than a timer, so the second Trash follows Put Back directly.
  private static func watchRunDirectory(context: TestSafetyContext) throws -> DirectoryChangeWatch {
    let directoryDescriptor = try context.duplicateRunDirectoryDescriptor()
    let signal = DispatchSemaphore(value: 0)
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: directoryDescriptor,
      eventMask: [.write, .extend, .link, .rename],
      queue: DispatchQueue(label: "rmp-test.put-back-race.run-directory")
    )
    source.setEventHandler { signal.signal() }
    source.setCancelHandler { close(directoryDescriptor) }
    source.resume()
    return DirectoryChangeWatch(
      waitForChange: { seconds in
        signal.wait(timeout: .now() + max(0, seconds)) == .success
      },
      close: { source.cancel() }
    )
  }
}

private func evidenceMismatch(_ message: String) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(code: .putBackEvidenceMismatch, message: message)
}
