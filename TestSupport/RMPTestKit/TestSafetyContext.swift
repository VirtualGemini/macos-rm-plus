// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

@_spi(RMPTestingEntrypoint)
public final class TestSafetyContext {
  @_spi(RMPTestingEntrypoint)
  public let runID: UUID
  let containerURL: URL
  let authorizedRootURL: URL
  let runDirectoryURL: URL
  let containerIdentity: FileIdentity
  let authorizedRootIdentity: FileIdentity
  let runDirectoryIdentity: FileIdentity

  var runMarkerURL: URL {
    runDirectoryURL.appendingPathComponent(Self.runMarkerName, isDirectory: false)
  }

  private static let containerName = "rmp-test"
  private static let authorizedRootName = "test"
  private static let containerMarkerName = ".rmp-test-container"
  private static let rootMarkerName = ".rmp-test-root"
  private static let runMarkerName = ".rmp-test-run"

  private let effectiveUserID: uid_t
  private let containerHandle: DirectoryHandle
  private let authorizedRootHandle: DirectoryHandle
  private let runDirectoryHandle: DirectoryHandle

  private init(
    runID: UUID,
    containerURL: URL,
    authorizedRootURL: URL,
    runDirectoryURL: URL,
    effectiveUserID: uid_t,
    handles: SafetyDirectoryHandles
  ) {
    self.runID = runID
    self.containerURL = containerURL
    self.authorizedRootURL = authorizedRootURL
    self.runDirectoryURL = runDirectoryURL
    self.effectiveUserID = effectiveUserID
    containerHandle = handles.container
    authorizedRootHandle = handles.authorizedRoot
    runDirectoryHandle = handles.runDirectory
    containerIdentity = handles.container.identity
    authorizedRootIdentity = handles.authorizedRoot.identity
    runDirectoryIdentity = handles.runDirectory.identity
  }

  static func establish(
    runID: UUID,
    trustedUser: TrustedUserAccount,
    effectiveUserID: uid_t = geteuid()
  ) throws -> TestSafetyContext {
    try validateTestUserIdentity(trustedUser, effectiveUserID: effectiveUserID)
    let urls = safetyURLs(homeDirectory: trustedUser.homeDirectory, runID: runID)
    let fixedHandles = try establishFixedDirectories(urls: urls, owner: effectiveUserID)
    let runHandle = try establishRunDirectory(
      runID: runID,
      runName: urls.runDirectory.lastPathComponent,
      fixedHandles: fixedHandles,
      owner: effectiveUserID
    )
    return TestSafetyContext(
      runID: runID,
      containerURL: urls.container,
      authorizedRootURL: urls.authorizedRoot,
      runDirectoryURL: urls.runDirectory,
      effectiveUserID: effectiveUserID,
      handles: SafetyDirectoryHandles(
        container: fixedHandles.container,
        authorizedRoot: fixedHandles.authorizedRoot,
        runDirectory: runHandle
      )
    )
  }

  func revalidate() throws {
    try validateDirectoryPath(
      containerURL.path,
      expectedIdentity: containerIdentity,
      owner: effectiveUserID,
      role: .container
    )
    try validateDirectoryEntry(
      parent: containerHandle,
      name: Self.authorizedRootName,
      expectedIdentity: authorizedRootIdentity,
      owner: effectiveUserID,
      role: .authorizedRoot
    )
    try validateDirectoryEntry(
      parent: authorizedRootHandle,
      name: runID.uuidString.lowercased(),
      expectedIdentity: runDirectoryIdentity,
      owner: effectiveUserID,
      role: .run
    )
    try validateLongLivedMarkers()
    try validateExistingMarker(
      parent: runDirectoryHandle,
      name: Self.runMarkerName,
      expected: runMarker,
      owner: effectiveUserID
    )
  }

  func cleanupRunDirectory() throws {
    try revalidate()
    guard try runDirectoryHandle.entryNames() == [Self.runMarkerName] else {
      throw TestSafetyDiagnostic(
        code: "test-safety.run-directory-not-empty",
        message: "The Run Directory contains Test Fixtures and was preserved for inspection."
      )
    }
    guard unlinkat(runDirectoryHandle.fileDescriptor, Self.runMarkerName, 0) == 0 else {
      throw posixDiagnostic(code: "test-safety.cleanup-failed", operation: "remove the run marker")
    }
    try validateDirectoryEntry(
      parent: authorizedRootHandle,
      name: runID.uuidString.lowercased(),
      expectedIdentity: runDirectoryIdentity,
      owner: effectiveUserID,
      role: .run
    )
    guard
      unlinkat(authorizedRootHandle.fileDescriptor, runID.uuidString.lowercased(), AT_REMOVEDIR)
        == 0
    else {
      throw posixDiagnostic(
        code: "test-safety.cleanup-failed",
        operation: "remove the Run Directory"
      )
    }
  }

  private var runMarker: TestSafetyMarker {
    TestSafetyMarker(
      role: .run,
      runID: runID,
      directoryIdentity: runDirectoryIdentity,
      containerIdentity: containerIdentity,
      authorizedRootIdentity: authorizedRootIdentity
    )
  }

  private func validateLongLivedMarkers() throws {
    try validateExistingMarker(
      parent: containerHandle,
      name: Self.containerMarkerName,
      expected: TestSafetyMarker(role: .container, directoryIdentity: containerIdentity),
      owner: effectiveUserID
    )
    try validateExistingMarker(
      parent: authorizedRootHandle,
      name: Self.rootMarkerName,
      expected: TestSafetyMarker(role: .authorizedRoot, directoryIdentity: authorizedRootIdentity),
      owner: effectiveUserID
    )
  }

  private static func safetyURLs(homeDirectory: String, runID: UUID) -> SafetyURLs {
    let home = URL(fileURLWithPath: homeDirectory, isDirectory: true)
    let container = home.appendingPathComponent(containerName, isDirectory: true)
    let authorizedRoot = container.appendingPathComponent(authorizedRootName, isDirectory: true)
    let runDirectory = authorizedRoot.appendingPathComponent(
      runID.uuidString.lowercased(),
      isDirectory: true
    )
    return SafetyURLs(
      container: container, authorizedRoot: authorizedRoot, runDirectory: runDirectory)
  }

  private static func establishFixedDirectories(
    urls: SafetyURLs,
    owner: uid_t
  ) throws -> FixedDirectoryHandles {
    let containerCreation = try DirectoryHandle.createOrValidate(
      path: urls.container.path,
      owner: owner,
      role: .container
    )
    try validateOrCreateMarker(
      parent: containerCreation.handle,
      name: containerMarkerName,
      expected: TestSafetyMarker(
        role: .container,
        directoryIdentity: containerCreation.handle.identity
      ),
      owner: owner,
      directoryWasCreated: containerCreation.created
    )
    let rootCreation = try DirectoryHandle.createOrValidate(
      parent: containerCreation.handle,
      name: authorizedRootName,
      owner: owner,
      role: .authorizedRoot
    )
    try validateOrCreateMarker(
      parent: rootCreation.handle,
      name: rootMarkerName,
      expected: TestSafetyMarker(
        role: .authorizedRoot,
        directoryIdentity: rootCreation.handle.identity
      ),
      owner: owner,
      directoryWasCreated: rootCreation.created
    )
    return FixedDirectoryHandles(
      container: containerCreation.handle,
      authorizedRoot: rootCreation.handle
    )
  }

  private static func establishRunDirectory(
    runID: UUID,
    runName: String,
    fixedHandles: FixedDirectoryHandles,
    owner: uid_t
  ) throws -> DirectoryHandle {
    let runDirectory = try DirectoryHandle.createExclusive(
      parent: fixedHandles.authorizedRoot,
      name: runName,
      owner: owner
    )
    try createMarkerExclusive(
      parent: runDirectory,
      name: runMarkerName,
      marker: TestSafetyMarker(
        role: .run,
        runID: runID,
        directoryIdentity: runDirectory.identity,
        containerIdentity: fixedHandles.container.identity,
        authorizedRootIdentity: fixedHandles.authorizedRoot.identity
      )
    )
    return runDirectory
  }
}

private struct SafetyURLs {
  let container: URL
  let authorizedRoot: URL
  let runDirectory: URL
}

private struct FixedDirectoryHandles {
  let container: DirectoryHandle
  let authorizedRoot: DirectoryHandle
}

private struct SafetyDirectoryHandles {
  let container: DirectoryHandle
  let authorizedRoot: DirectoryHandle
  let runDirectory: DirectoryHandle
}
