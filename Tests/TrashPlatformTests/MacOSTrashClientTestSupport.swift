// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

final class FoundationTrashSimulator: @unchecked Sendable {
  let trashDirectoryURL: URL
  private(set) var recoverablePaths: Set<String> = []
  private(set) var receivedNames: [String] = []
  private var previousTrashURL: URL?

  init(trashDirectoryURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    receivedNames.append(sourceURL.lastPathComponent)
    let returnedURL = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
    if let previousTrashURL {
      recoverablePaths.insert(previousTrashURL.path)
    }
    previousTrashURL = returnedURL
    return returnedURL
  }
}

final class FinderMoveSimulator: @unchecked Sendable {
  private let trashDirectoryURL: URL
  private(set) var receivedPaths: [String] = []

  init(trashDirectoryURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    receivedPaths.append(sourceURL.path)
    let returnedURL = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
    return returnedURL
  }
}

final class PreflightFailureSimulator: @unchecked Sendable {
  private let trashDirectoryURL: URL

  init(trashDirectoryURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    if !sourceURL.lastPathComponent.hasPrefix(".tc-finalizer-") {
      let destination = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
      try FileManager.default.moveItem(at: sourceURL, to: destination)
    }
    throw InjectedTrashFailure()
  }
}

final class TargetTrashFailureSimulator: @unchecked Sendable {
  init(trashDirectoryURL _: URL) {}

  func trash(_: URL) throws -> URL {
    throw InjectedTrashFailure()
  }
}

final class ReplacedFinalizerFailureSimulator: @unchecked Sendable {
  private(set) var replacedFinalizerName: String?

  func trash(_ sourceURL: URL) throws -> URL {
    let parentURL = sourceURL.deletingLastPathComponent()
    let finalizerName = try FileManager.default.contentsOfDirectory(atPath: parentURL.path)
      .first { $0.hasPrefix(".tc-finalizer-") }
    guard let finalizerName else { throw InjectedTrashFailure() }
    let finalizerURL = parentURL.appendingPathComponent(finalizerName)
    try FileManager.default.removeItem(at: finalizerURL)
    try Data("replacement\n".utf8).write(to: finalizerURL)
    replacedFinalizerName = finalizerName
    throw InjectedTrashFailure()
  }
}

final class UnverifiedFinalizerSimulator: @unchecked Sendable {
  private(set) var replacementName: String?

  func replace(_ finalizerURL: URL) {
    do {
      try FileManager.default.removeItem(at: finalizerURL)
      try Data("unverified replacement\n".utf8).write(to: finalizerURL)
      replacementName = finalizerURL.lastPathComponent
    } catch {
      replacementName = nil
    }
  }
}

final class ActivationRetrySimulator: @unchecked Sendable {
  private let trashDirectoryURL: URL
  private(set) var recoverablePaths: Set<String> = []
  private var callCount = 0
  private var previousTrashURL: URL?

  init(trashDirectoryURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    callCount += 1
    if callCount == 2 {
      throw InjectedTrashFailure()
    }
    let returnedURL = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
    if let previousTrashURL {
      recoverablePaths.insert(previousTrashURL.path)
    }
    previousTrashURL = returnedURL
    return returnedURL
  }
}

final class MovedActivationFailureSimulator: @unchecked Sendable {
  private let trashDirectoryURL: URL
  private(set) var recoverablePaths: Set<String> = []
  private(set) var callCount = 0
  private var previousTrashURL: URL?

  init(trashDirectoryURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    callCount += 1
    let returnedURL = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
    if let previousTrashURL {
      recoverablePaths.insert(previousTrashURL.path)
    }
    previousTrashURL = returnedURL
    if callCount == 2 { throw InjectedTrashFailure() }
    return returnedURL
  }
}

final class ExhaustedActivationSimulator: @unchecked Sendable {
  private let trashDirectoryURL: URL
  private(set) var recoverablePaths: Set<String> = []
  private var callCount = 0
  private var previousTrashURL: URL?

  init(trashDirectoryURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    callCount += 1
    guard callCount < 2 else { throw InjectedTrashFailure() }
    let returnedURL = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
    if let previousTrashURL {
      recoverablePaths.insert(previousTrashURL.path)
    }
    previousTrashURL = returnedURL
    return returnedURL
  }
}

final class CleanupFailureSimulator: @unchecked Sendable {
  private let trashDirectoryURL: URL
  private(set) var recoverablePaths: Set<String> = []
  private var callCount = 0
  private var previousTrashURL: URL?

  init(trashDirectoryURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    callCount += 1
    let returnedURL = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: returnedURL)
    if let previousTrashURL {
      recoverablePaths.insert(previousTrashURL.path)
    }
    previousTrashURL = returnedURL
    if callCount >= 2 {
      try FileManager.default.createSymbolicLink(
        at: sourceURL,
        withDestinationURL: URL(fileURLWithPath: "occupied-finalizer-path")
      )
    }
    return returnedURL
  }
}

final class WrongReturnedIdentitySimulator: @unchecked Sendable {
  private let trashDirectoryURL: URL
  private let returnedURL: URL

  init(trashDirectoryURL: URL, returnedURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
    self.returnedURL = returnedURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    let actualURL = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: actualURL)
    return returnedURL
  }
}

final class WrongTargetReceiptSimulator: @unchecked Sendable {
  private let trashDirectoryURL: URL
  private let wrongReturnedURL: URL
  private(set) var recoverablePaths: Set<String> = []
  private var callCount = 0
  private var previousTrashURL: URL?

  init(trashDirectoryURL: URL, wrongReturnedURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
    self.wrongReturnedURL = wrongReturnedURL
  }

  func trash(_ sourceURL: URL) throws -> URL {
    callCount += 1
    let actualURL = trashDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
    try FileManager.default.moveItem(at: sourceURL, to: actualURL)
    if let previousTrashURL {
      recoverablePaths.insert(previousTrashURL.path)
    }
    previousTrashURL = actualURL
    return callCount == 1 ? wrongReturnedURL : actualURL
  }
}

struct RecoverableTrashFixture {
  let rootURL: URL
  let sourceDirectoryURL: URL
  let trashDirectoryURL: URL
  let targetURL: URL
  let linkURL: URL

  init(linkDestinationExists: Bool = true) throws {
    rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tc-production-finalizer-\(UUID().uuidString)",
      isDirectory: true
    )
    sourceDirectoryURL = rootURL.appendingPathComponent("source", isDirectory: true)
    trashDirectoryURL = rootURL.appendingPathComponent("Trash", isDirectory: true)
    targetURL = sourceDirectoryURL.appendingPathComponent("target.txt")
    linkURL = sourceDirectoryURL.appendingPathComponent("shortcut")
    try FileManager.default.createDirectory(
      at: sourceDirectoryURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: trashDirectoryURL,
      withIntermediateDirectories: false
    )
    if linkDestinationExists {
      try Data("target\n".utf8).write(to: targetURL)
    }
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
  }

  var trashedLinkURL: URL {
    trashDirectoryURL.appendingPathComponent(linkURL.lastPathComponent)
  }

  var trashedTargetURL: URL {
    trashDirectoryURL.appendingPathComponent(targetURL.lastPathComponent)
  }

  func sourceEntryNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: sourceDirectoryURL.path).sorted()
  }

  func trashEntryNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: trashDirectoryURL.path).sorted()
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

struct InjectedTrashFailure: Error {}

func macOSEntryExists(at url: URL) -> Bool {
  var status = stat()
  return lstat(url.path, &status) == 0
}
