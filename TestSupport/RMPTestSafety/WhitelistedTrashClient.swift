// SPDX-License-Identifier: Apache-2.0

import Darwin
import FileProvider
import Foundation

struct TrashVerificationEvidence: Equatable, Sendable {
  let returnedURL: URL
  let resourceIdentifier: Data?
}

struct AuthorizedTrashTarget: Sendable {
  let targetURL: URL
  fileprivate let runID: UUID
  fileprivate let plannedIdentity: FileIdentity
}

struct TrashVolumeInspection: Sendable {
  let isLocal: Bool
  let isMountPoint: Bool
  let isFileProviderRoot: Bool
}

struct TrashAuthorizationOperations: Sendable {
  let inspectVolume: @Sendable (URL) throws -> TrashVolumeInspection
  let deviceMatchesRun: @Sendable (_ entryDevice: UInt64, _ runDevice: UInt64) -> Bool
  let resourceIdentifier: @Sendable (URL) throws -> Data?

  static let system = TrashAuthorizationOperations(
    inspectVolume: { url in
      let values = try url.resourceValues(forKeys: [
        .volumeIsLocalKey,
        .volumeURLKey,
        .isUbiquitousItemKey,
      ])
      let standardizedURL = url.standardizedFileURL
      let volumeURL = values.volume?.standardizedFileURL
      let isFileProviderRoot: Bool
      if values.isUbiquitousItem == true {
        isFileProviderRoot = true
      } else {
        isFileProviderRoot = try isFileProviderItem(at: standardizedURL)
      }
      return TrashVolumeInspection(
        isLocal: values.volumeIsLocal == true,
        isMountPoint: volumeURL == standardizedURL,
        isFileProviderRoot: isFileProviderRoot
      )
    },
    deviceMatchesRun: { $0 == $1 },
    resourceIdentifier: archivedResourceIdentifier
  )
}

// The ticket and PRD define this safety-boundary name.
// swiftlint:disable:next inclusive_language
final class WhitelistedTrashClient {
  typealias SystemTrash = @Sendable (URL) throws -> URL

  private let context: TestSafetyContext
  private let authorization: TrashAuthorizationOperations
  private let systemTrash: SystemTrash

  init(context: TestSafetyContext) {
    self.context = context
    authorization = .system
    systemTrash = foundationSystemTrash
  }

  private init(
    testing context: TestSafetyContext,
    authorization: TrashAuthorizationOperations,
    systemTrash: @escaping SystemTrash
  ) {
    self.context = context
    self.authorization = authorization
    self.systemTrash = systemTrash
  }

  static func testing(
    context: TestSafetyContext,
    authorization: TrashAuthorizationOperations,
    systemTrash: @escaping SystemTrash
  ) -> WhitelistedTrashClient {
    WhitelistedTrashClient(
      testing: context,
      authorization: authorization,
      systemTrash: systemTrash
    )
  }

  func authorizeForPlanning(targetURL: URL) throws -> AuthorizedTrashTarget {
    try context.revalidate()
    let target = targetURL.standardizedFileURL
    return AuthorizedTrashTarget(
      targetURL: target,
      runID: context.runID,
      plannedIdentity: try authorize(target)
    )
  }

  func trashItem(_ authorizedTarget: AuthorizedTrashTarget) throws -> TrashVerificationEvidence {
    try context.revalidate()
    guard authorizedTarget.runID == context.runID else {
      throw diagnostic(
        .trashPlanIdentityMismatch,
        "The authorized Trash target belongs to a different test run."
      )
    }
    let currentIdentity = try authorize(authorizedTarget.targetURL)
    guard currentIdentity == authorizedTarget.plannedIdentity else {
      throw diagnostic(
        .trashPlanIdentityMismatch,
        "The Trash target changed after planning."
      )
    }
    let sourceIdentifier: Data?
    do {
      sourceIdentifier = try authorization.resourceIdentifier(authorizedTarget.targetURL)
    } catch {
      throw diagnostic(
        .trashPathInspectionFailed,
        "The source Test Fixture resource identity could not be inspected."
      )
    }
    let returnedURL: URL
    do {
      returnedURL = try systemTrash(authorizedTarget.targetURL)
    } catch let diagnostic as TestSafetyDiagnostic {
      throw diagnostic
    } catch {
      throw diagnostic(
        .trashSystemCallFailed,
        "The macOS system Trash operation failed."
      )
    }
    let returnedIdentifier: Data?
    do {
      returnedIdentifier = try authorization.resourceIdentifier(returnedURL)
    } catch {
      throw evidenceMismatch("The returned Trash URL could not be identified.")
    }
    let expectedPrefix = fixturePrefix
    guard returnedURL.isFileURL, returnedURL.lastPathComponent.hasPrefix(expectedPrefix) else {
      throw evidenceMismatch("The returned Trash URL lost the Test Fixture run prefix.")
    }
    if let sourceIdentifier {
      guard returnedIdentifier == sourceIdentifier else {
        throw evidenceMismatch("The returned Trash item identity does not match the source.")
      }
    }
    return TrashVerificationEvidence(
      returnedURL: returnedURL,
      resourceIdentifier: returnedIdentifier
    )
  }

  private var fixturePrefix: String {
    "rmp-test-\(context.runID.uuidString.lowercased())-"
  }

  private func authorize(_ targetURL: URL) throws -> FileIdentity {
    let runURL = context.runDirectoryURL.standardizedFileURL
    let target = targetURL.standardizedFileURL
    let runComponents = runURL.pathComponents
    let targetComponents = target.pathComponents

    guard targetComponents.count > runComponents.count else {
      throw diagnostic(
        targetComponents == runComponents ? .trashSafetyDirectory : .trashOutsideRunDirectory,
        "A real Trash target must be below the authorized Run Directory."
      )
    }
    guard Array(targetComponents.prefix(runComponents.count)) == runComponents else {
      throw diagnostic(
        .trashOutsideRunDirectory,
        "A real Trash target must be a path-component descendant of the Run Directory."
      )
    }

    guard target.lastPathComponent.hasPrefix(fixturePrefix) else {
      throw diagnostic(
        .trashFixtureName,
        "A Test Fixture basename must carry the current run UUID prefix."
      )
    }

    return try validateComponents(Array(targetComponents.dropFirst(runComponents.count)))
  }

  private func validateComponents(_ components: [String]) throws -> FileIdentity {
    var parentDescriptor = try context.duplicateRunDirectoryDescriptor()
    defer { close(parentDescriptor) }

    var currentURL = context.runDirectoryURL.standardizedFileURL
    var finalIdentity: FileIdentity?
    for (index, component) in components.enumerated() {
      let isFinal = index == components.index(before: components.endIndex)
      currentURL.appendPathComponent(component, isDirectory: !isFinal)

      var status = stat()
      guard fstatat(parentDescriptor, component, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw diagnostic(.trashPathInspectionFailed, "The Trash target could not be inspected.")
      }
      guard
        authorization.deviceMatchesRun(
          UInt64(truncatingIfNeeded: status.st_dev),
          context.runDirectoryIdentity.device
        )
      else {
        throw diagnostic(.trashVolumeMismatch, "The Trash target crossed the authorized volume.")
      }
      if isFinal { finalIdentity = FileIdentity(status: status) }

      try validateVolume(at: currentURL, status: status, isFinal: isFinal)

      if !isFinal {
        let nextDescriptor = try openIntermediate(
          parentDescriptor: parentDescriptor,
          component: component,
          status: status
        )
        close(parentDescriptor)
        parentDescriptor = nextDescriptor
      }
    }
    guard let finalIdentity else {
      throw diagnostic(.trashPathInspectionFailed, "The Trash target identity is unavailable.")
    }
    return finalIdentity
  }

  private func validateVolume(at url: URL, status: stat, isFinal: Bool) throws {
    let inspectionURL =
      isFinal && status.st_mode & S_IFMT == S_IFLNK
      ? url.deletingLastPathComponent() : url
    let volume: TrashVolumeInspection
    do {
      volume = try authorization.inspectVolume(inspectionURL)
    } catch {
      throw diagnostic(
        .trashPathInspectionFailed,
        "The Trash target volume could not be inspected."
      )
    }
    guard volume.isLocal else {
      throw diagnostic(.trashNetworkVolume, "Network volumes are not authorized for real tests.")
    }
    guard !volume.isMountPoint else {
      throw diagnostic(.trashMountPoint, "Mount points are not authorized for real tests.")
    }
    guard !volume.isFileProviderRoot else {
      throw diagnostic(
        .trashFileProviderRoot,
        "File Provider special roots are not authorized for real tests."
      )
    }
  }

  private func openIntermediate(
    parentDescriptor: Int32,
    component: String,
    status: stat
  ) throws -> Int32 {
    guard status.st_mode & S_IFMT == S_IFDIR else {
      let code: TestSafetyDiagnosticCode =
        status.st_mode & S_IFMT == S_IFLNK
        ? .trashIntermediateSymlink : .trashPathInspectionFailed
      throw diagnostic(code, "Every intermediate Trash path component must be a real directory.")
    }
    let descriptor = openat(
      parentDescriptor,
      component,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard descriptor >= 0 else {
      throw diagnostic(
        .trashIntermediateSymlink,
        "Intermediate symbolic links cannot be used by real tests."
      )
    }
    var openedStatus = stat()
    guard fstat(descriptor, &openedStatus) == 0,
      openedStatus.st_dev == status.st_dev,
      openedStatus.st_ino == status.st_ino
    else {
      close(descriptor)
      throw diagnostic(
        .trashPathInspectionFailed,
        "An intermediate Trash path component changed during authorization."
      )
    }
    return descriptor
  }
}

private func archivedResourceIdentifier(_ url: URL) throws -> Data? {
  guard
    let identifier = try url.resourceValues(forKeys: [.fileResourceIdentifierKey])
      .fileResourceIdentifier
  else {
    return nil
  }
  if let data = identifier as? Data { return data }
  return try NSKeyedArchiver.archivedData(
    withRootObject: identifier,
    requiringSecureCoding: true
  )
}

private func isFileProviderItem(at url: URL) throws -> Bool {
  let result = FileProviderProbeResult()
  // swift-format and SwiftLint disagree on this imported Objective-C callback layout.
  // swiftlint:disable closure_parameter_position
  NSFileProviderManager.getIdentifierForUserVisibleFile(at: url) {
    itemIdentifier, domainIdentifier, error in
    result.finish(
      isFileProviderItem: itemIdentifier != nil || domainIdentifier != nil,
      error: error
    )
  }
  // swiftlint:enable closure_parameter_position
  guard result.wait() else {
    throw FileProviderInspectionError.timedOut
  }
  if let error = result.error as? CocoaError, error.code == .fileNoSuchFile {
    return false
  }
  if let error = result.error { throw error }
  return result.isFileProviderItem
}

private final class FileProviderProbeResult: @unchecked Sendable {
  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)
  private(set) var isFileProviderItem = false
  private(set) var error: (any Error)?

  func finish(isFileProviderItem: Bool, error: (any Error)?) {
    lock.lock()
    self.isFileProviderItem = isFileProviderItem
    self.error = error
    lock.unlock()
    semaphore.signal()
  }

  func wait() -> Bool {
    semaphore.wait(timeout: .now() + 5) == .success
  }
}

private enum FileProviderInspectionError: Error {
  case timedOut
}

private func foundationSystemTrash(_ sourceURL: URL) throws -> URL {
  var resultingURL: NSURL?
  do {
    try FileManager.default.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
  } catch {
    throw diagnostic(
      .trashSystemCallFailed,
      "The macOS system Trash operation failed."
    )
  }
  guard let resultingURL else {
    throw diagnostic(
      .trashSystemCallFailed,
      "The system Trash API did not return verification evidence."
    )
  }
  return resultingURL as URL
}

private func diagnostic(
  _ code: TestSafetyDiagnosticCode,
  _ message: String
) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(code: code, message: message)
}

private func evidenceMismatch(_ message: String) -> TestSafetyDiagnostic {
  diagnostic(.trashEvidenceMismatch, message)
}
