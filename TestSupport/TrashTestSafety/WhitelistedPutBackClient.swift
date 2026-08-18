// SPDX-License-Identifier: Apache-2.0

import Carbon
import Darwin
import Foundation

struct FinderPutBackScriptInvocation: Equatable, Sendable {
  let handlerName: String
  let arguments: [String]
}

enum FinderPutBackScriptResult: Equatable, Sendable {
  case success(String)
  case failure(errorNumber: Int?)
}

// The ticket and PRD define this safety-boundary name.
// swiftlint:disable:next inclusive_language
final class WhitelistedPutBackClient {
  typealias ResourceIdentifier = (URL) throws -> Data?
  typealias ScriptMake = (String) -> NSAppleScript?
  typealias ScriptExecute = (FinderPutBackScriptInvocation) -> FinderPutBackScriptResult
  typealias SystemPutBack = (_ sourceURL: URL, _ destination: URL) throws -> URL

  private let context: TestSafetyContext
  private let resourceIdentifier: ResourceIdentifier
  private let systemPutBack: SystemPutBack

  convenience init(context: TestSafetyContext) {
    self.init(
      context: context,
      resourceIdentifier: testSafetyResourceIdentifier,
      scriptSource: Self.scriptSource
    )
  }

  init(
    context: TestSafetyContext,
    resourceIdentifier: @escaping ResourceIdentifier,
    systemPutBack: @escaping SystemPutBack
  ) {
    self.context = context
    self.resourceIdentifier = resourceIdentifier
    self.systemPutBack = systemPutBack
  }

  convenience init(
    context: TestSafetyContext,
    resourceIdentifier: @escaping ResourceIdentifier,
    scriptExecute: @escaping ScriptExecute
  ) {
    self.init(
      context: context,
      resourceIdentifier: resourceIdentifier,
      systemPutBack: Self.makeSystemPutBack(scriptExecute: scriptExecute)
    )
  }

  convenience init(
    context: TestSafetyContext,
    resourceIdentifier: @escaping ResourceIdentifier,
    scriptSource: String,
    makeScript: @escaping ScriptMake = { NSAppleScript(source: $0) }
  ) {
    self.init(
      context: context,
      resourceIdentifier: resourceIdentifier,
      scriptExecute: { invocation in
        Self.executeAppleScript(
          invocation,
          scriptSource: scriptSource,
          makeScript: makeScript
        )
      }
    )
  }

  func putBack(
    _ evidence: TrashVerificationEvidence,
    to expectedSourceURL: URL
  ) throws -> PutBackVerificationEvidence {
    try context.revalidate()
    let sourceURL = expectedSourceURL.standardizedFileURL
    let trashURL = evidence.returnedURL.standardizedFileURL
    try validate(sourceURL: sourceURL, trashURL: trashURL)
    try requireMissingSource(sourceURL)

    let currentTrashIdentifier: Data?
    do {
      currentTrashIdentifier = try resourceIdentifier(trashURL)
    } catch {
      throw evidenceMismatch("The exact Trash item could not be identified before Put Back.")
    }
    if let expectedIdentifier = evidence.resourceIdentifier {
      guard currentTrashIdentifier == expectedIdentifier else {
        throw evidenceMismatch("The exact Trash item identity changed before Put Back.")
      }
    }
    try context.revalidate()
    try requireMissingSource(sourceURL)

    let returnedURL: URL
    do {
      returnedURL = try systemPutBack(trashURL, context.runDirectoryURL).standardizedFileURL
    } catch let diagnostic as TestSafetyDiagnostic {
      throw diagnostic
    } catch {
      throw TestSafetyDiagnostic(
        code: .putBackSystemCallFailed,
        message: "Finder could not restore the exact Test Fixture from Trash."
      )
    }
    guard returnedURL == sourceURL else {
      throw evidenceMismatch("Finder restored the Test Fixture to an unexpected URL.")
    }

    let restoredIdentifier: Data?
    do {
      restoredIdentifier = try resourceIdentifier(returnedURL)
    } catch {
      throw evidenceMismatch("The restored Test Fixture could not be identified.")
    }
    if let expectedIdentifier = evidence.resourceIdentifier {
      guard restoredIdentifier == expectedIdentifier else {
        throw evidenceMismatch("The restored Test Fixture identity does not match the Trash item.")
      }
    }
    return PutBackVerificationEvidence(
      returnedURL: returnedURL,
      resourceIdentifier: restoredIdentifier
    )
  }

  private var fixturePrefix: String {
    "tc-test-\(context.runID.uuidString.lowercased())-"
  }

  private static let scriptSource = """
    on putBackItem(trashedPath, destinationPath)
      set trashedItem to POSIX file trashedPath
      set destinationFolder to POSIX file destinationPath as alias
      with timeout of 30 seconds
        tell application id "com.apple.finder"
          set restoredItem to move trashedItem to destinationFolder
          return URL of restoredItem
        end tell
      end timeout
    end putBackItem
    """

  private static func makeSystemPutBack(
    scriptExecute: @escaping ScriptExecute
  ) -> SystemPutBack {
    { sourceURL, destination in
      let invocation = FinderPutBackScriptInvocation(
        handlerName: "putBackItem",
        arguments: [sourceURL.path, destination.path]
      )
      switch scriptExecute(invocation) {
      case let .success(returnedURLText):
        guard let returnedURL = URL(string: returnedURLText), returnedURL.isFileURL else {
          throw TestSafetyDiagnostic(
            code: .putBackSystemCallFailed,
            message: "Finder returned an invalid Put Back URL."
          )
        }
        return returnedURL
      case let .failure(errorNumber):
        let suffix = errorNumber.map { " (Apple Event error \($0))." } ?? "."
        throw TestSafetyDiagnostic(
          code: .putBackSystemCallFailed,
          message: "Finder could not restore the exact Test Fixture\(suffix)"
        )
      }
    }
  }

  private static func executeAppleScript(
    _ invocation: FinderPutBackScriptInvocation,
    scriptSource: String,
    makeScript: ScriptMake
  ) -> FinderPutBackScriptResult {
    guard let script = makeScript(scriptSource) else {
      return .failure(errorNumber: nil)
    }
    var compilationError: NSDictionary?
    guard script.compileAndReturnError(&compilationError) else {
      return .failure(errorNumber: appleScriptErrorNumber(compilationError))
    }

    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kASAppleScriptSuite),
      eventID: AEEventID(kASSubroutineEvent),
      targetDescriptor: nil,
      returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(
      NSAppleEventDescriptor(string: invocation.handlerName),
      forKeyword: AEKeyword(keyASSubroutineName)
    )
    let arguments = NSAppleEventDescriptor.list()
    for (index, argument) in invocation.arguments.enumerated() {
      arguments.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
    }
    event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))

    var executionError: NSDictionary?
    let result = script.executeAppleEvent(event, error: &executionError)
    if let executionError, executionError.keyEnumerator().nextObject() != nil {
      return .failure(errorNumber: appleScriptErrorNumber(executionError))
    }
    guard let returnedURLText = result.stringValue else {
      return .failure(errorNumber: nil)
    }
    return .success(returnedURLText)
  }

  private static func appleScriptErrorNumber(_ error: NSDictionary?) -> Int? {
    (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
  }

  private func validate(sourceURL: URL, trashURL: URL) throws {
    guard
      sourceURL.deletingLastPathComponent() == context.runDirectoryURL.standardizedFileURL,
      sourceURL.lastPathComponent.hasPrefix(fixturePrefix),
      trashURL.isFileURL,
      trashURL.lastPathComponent.hasPrefix(fixturePrefix)
    else {
      throw evidenceMismatch("Put Back evidence is outside the authorized Test Fixture identity.")
    }
  }

  private func requireMissingSource(_ sourceURL: URL) throws {
    let descriptor = try context.duplicateRunDirectoryDescriptor()
    defer { close(descriptor) }
    var status = stat()
    if fstatat(
      descriptor,
      sourceURL.lastPathComponent,
      &status,
      AT_SYMLINK_NOFOLLOW
    ) == 0 {
      throw TestSafetyDiagnostic(
        code: .putBackSourceOccupied,
        message: "The original Test Fixture path is occupied; Put Back was not attempted."
      )
    }
    guard errno == ENOENT else {
      throw evidenceMismatch("The original Test Fixture path could not be inspected.")
    }
  }
}

private func evidenceMismatch(_ message: String) -> TestSafetyDiagnostic {
  TestSafetyDiagnostic(code: .putBackEvidenceMismatch, message: message)
}
