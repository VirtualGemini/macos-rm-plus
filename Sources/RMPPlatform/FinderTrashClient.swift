// SPDX-License-Identifier: Apache-2.0

import Carbon
import Foundation
import RMPCore

enum FinderTrashClientFailure: Error {
  case automationConsentRequired
  case automationDenied
  case finderUnavailable
  case invalidResult
  case timedOut

  var code: TrashErrorCode {
    switch self {
    case .automationConsentRequired:
      .finderAutomationConsentRequired
    case .automationDenied:
      .finderAutomationDenied
    case .finderUnavailable:
      .finderUnavailable
    case .invalidResult:
      .systemTrashFailed
    case .timedOut:
      .finderAutomationTimedOut
    }
  }
}

struct FinderScriptInvocation: Equatable, Sendable {
  let handlerName: String
  let arguments: [String]
}

enum FinderScriptResult: Equatable, Sendable {
  case success(String)
  case failure(errorNumber: Int?)
}

public struct FinderTrashClient: TrashClient {
  typealias FinderDelete = @Sendable (URL) throws -> URL
  typealias ScriptMake = @Sendable (String) -> NSAppleScript?
  typealias ScriptExecute = @Sendable (FinderScriptInvocation) -> FinderScriptResult

  private var finderDelete: FinderDelete

  public init() {
    finderDelete = Self.makeFinderDelete(
      scriptSource: Self.scriptSource,
      makeScript: Self.liveScriptMake
    )
  }

  fileprivate init(finderDelete: @escaping FinderDelete) {
    self.init()
    self.finderDelete = finderDelete
  }

  fileprivate init(scriptExecute: @escaping ScriptExecute) {
    self.init()
    finderDelete = Self.makeFinderDelete(scriptExecute: scriptExecute)
  }

  fileprivate init(scriptSource: String, makeScript: @escaping ScriptMake) {
    self.init()
    finderDelete = Self.makeFinderDelete(scriptSource: scriptSource, makeScript: makeScript)
  }

  private static func makeFinderDelete(
    scriptExecute: @escaping ScriptExecute
  ) -> FinderDelete {
    { sourceURL in
      let invocation = FinderScriptInvocation(
        handlerName: "trashItem",
        arguments: [sourceURL.path]
      )
      switch scriptExecute(invocation) {
      case let .success(destinationText):
        guard let destinationURL = URL(string: destinationText), destinationURL.isFileURL else {
          throw FinderTrashClientFailure.invalidResult
        }
        return destinationURL
      case let .failure(errorNumber):
        throw Self.failure(for: errorNumber)
      }
    }
  }

  private static func makeFinderDelete(
    scriptSource: String,
    makeScript: @escaping ScriptMake
  ) -> FinderDelete {
    makeFinderDelete { invocation in
      Self.executeAppleScript(
        invocation,
        scriptSource: scriptSource,
        makeScript: makeScript
      )
    }
  }

  public func trashItem(atPath path: String) throws -> TrashMoveReceipt {
    do {
      let destinationURL = try finderDelete(URL(fileURLWithPath: path))
      return TrashMoveReceipt(destinationPath: destinationURL.path)
    } catch let failure as FinderTrashClientFailure {
      throw TrashCapabilityError(code: failure.code)
    } catch {
      throw TrashCapabilityError(code: .systemTrashFailed)
    }
  }

  private static let scriptSource = """
    on trashItem(sourcePath)
      set sourceItem to POSIX file sourcePath
      with timeout of 30 seconds
        tell application id "com.apple.finder"
          set deletedItem to delete sourceItem
          return URL of deletedItem
        end tell
      end timeout
    end trashItem
    """

  private static func executeAppleScript(
    _ invocation: FinderScriptInvocation,
    scriptSource: String,
    makeScript: ScriptMake
  ) -> FinderScriptResult {
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
    guard let destinationText = result.stringValue else {
      return .failure(errorNumber: nil)
    }
    return .success(destinationText)
  }

  private static func appleScriptErrorNumber(_ error: NSDictionary?) -> Int? {
    (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
  }

  fileprivate static let liveScriptMake: ScriptMake = { NSAppleScript(source: $0) }

  private static func failure(for errorNumber: Int?) -> FinderTrashClientFailure {
    switch errorNumber {
    case Int(errAEEventWouldRequireUserConsent):
      .automationConsentRequired
    case Int(errAEEventNotPermitted):
      .automationDenied
    case Int(errAETimeout):
      .timedOut
    case Int(procNotFound):
      .finderUnavailable
    default:
      .invalidResult
    }
  }
}

func makeInjectedFinderTrashClient(
  finderDelete: @escaping FinderTrashClient.FinderDelete
) -> any TrashClient {
  FinderTrashClient(finderDelete: finderDelete)
}

func makeInjectedFinderTrashClient(
  scriptExecute: @escaping FinderTrashClient.ScriptExecute
) -> any TrashClient {
  FinderTrashClient(scriptExecute: scriptExecute)
}

func makeInjectedFinderTrashClient(scriptSource: String) -> any TrashClient {
  FinderTrashClient(scriptSource: scriptSource, makeScript: FinderTrashClient.liveScriptMake)
}

func makeInjectedFinderTrashClient(
  scriptSource: String,
  makeScript: @escaping FinderTrashClient.ScriptMake
) -> any TrashClient {
  FinderTrashClient(scriptSource: scriptSource, makeScript: makeScript)
}
