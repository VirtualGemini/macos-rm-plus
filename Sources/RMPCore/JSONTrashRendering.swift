// SPDX-License-Identifier: Apache-2.0

import Foundation

enum JSONTrashOperationName: String, Encodable, Sendable {
  case trash
}

enum JSONTrashStatus: String, Encodable, Sendable {
  case planned
  case moved
  case failed
  case skipped
}

enum JSONTrashKind: String, Encodable, Sendable {
  case file
  case directory
  case symbolicLink = "symbolic-link"
  case brokenSymbolicLink = "broken-symbolic-link"
  case other
  case unknown

  init(_ kind: TrashInputKind) {
    switch kind {
    case .file: self = .file
    case .directory: self = .directory
    case .symbolicLink: self = .symbolicLink
    case .brokenSymbolicLink: self = .brokenSymbolicLink
    case .other: self = .other
    case .unknown: self = .unknown
    }
  }
}

struct JSONTrashOperation: Encodable, Sendable {
  let schemaVersion: Int
  let operation: JSONTrashOperationName
  let dryRun: Bool
  let success: Bool
  let moved: Int
  let failed: Int
  let skipped: Int
  let items: [JSONTrashItem]

  init(dryRun: Bool, items: [JSONTrashItem], success: Bool? = nil) {
    schemaVersion = 1
    operation = .trash
    self.dryRun = dryRun
    self.items = items
    moved = items.count { $0.status == .moved }
    failed = items.count { $0.status == .failed }
    skipped = items.count { $0.status == .skipped }
    self.success = success ?? (failed == 0)
  }
}

struct JSONTrashItem: Encodable, Sendable {
  let source: String
  let destination: String?
  let kind: JSONTrashKind
  let status: JSONTrashStatus
  let error: JSONTrashError?

  private enum CodingKeys: String, CodingKey {
    case source
    case destination
    case kind
    case status
    case error
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(source, forKey: .source)
    if let destination {
      try container.encode(destination, forKey: .destination)
    } else {
      try container.encodeNil(forKey: .destination)
    }
    try container.encode(kind, forKey: .kind)
    try container.encode(status, forKey: .status)
    if let error {
      try container.encode(error, forKey: .error)
    } else {
      try container.encodeNil(forKey: .error)
    }
  }
}

struct JSONTrashError: Encodable, Sendable {
  let code: TrashErrorCode
  let message: String

  private enum CodingKeys: String, CodingKey {
    case code
    case message
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(code.rawValue, forKey: .code)
    try container.encode(message, forKey: .message)
  }
}

protocol JSONTrashEncoding: Sendable {
  func encode(_ operation: JSONTrashOperation) throws -> Data
}

struct FoundationJSONTrashEncoder: JSONTrashEncoding {
  func encode(_ operation: JSONTrashOperation) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(operation)
  }
}

struct JSONTrashRenderer {
  private let encoder: any JSONTrashEncoding

  init(encoder: any JSONTrashEncoding = FoundationJSONTrashEncoder()) {
    self.encoder = encoder
  }

  func render(
    plan: TrashPlan,
    currentDirectoryPath: String
  ) -> CommandResult {
    let items = plan.entries.map { entry in
      item(for: entry, currentDirectoryPath: currentDirectoryPath)
    }
    let result = encode(
      JSONTrashOperation(dryRun: plan.dryRun, items: items)
    )
    let failures = plan.entries.compactMap(failureResult)
    let diagnostics = TrashResultRenderer().render(failures, output: .quiet)
    return CommandResult(
      standardOutput: result.standardOutput,
      standardError: result.standardError + diagnostics.standardError,
      exitCode: result.exitCode
    )
  }

  func render(
    results: [TrashResult],
    dryRun: Bool,
    currentDirectoryPath: String
  ) -> CommandResult {
    let items = results.map { result in
      item(for: result, currentDirectoryPath: currentDirectoryPath)
    }
    let success = !results.contains(where: \.representsOperationFailure)
    let encodedResult = encode(
      JSONTrashOperation(dryRun: dryRun, items: items, success: success)
    )
    let result =
      encodedResult.standardOutput.isEmpty
      ? encodedResult
      : encodedResult.withExitCode(
        results.contains(where: \.requiresFailureExit)
          ? ExitStatus.failure.rawValue
          : ExitStatus.success.rawValue
      )
    let diagnostics = TrashResultRenderer().render(results, output: .quiet)
    return CommandResult(
      standardOutput: result.standardOutput,
      standardError: result.standardError + diagnostics.standardError,
      exitCode: result.exitCode
    )
  }

  func render(
    paths: [String],
    dryRun: Bool,
    code: TrashErrorCode,
    message: String,
    currentDirectoryPath: String,
    exitCode: Int32 = ExitStatus.failure.rawValue
  ) -> CommandResult {
    let items = paths.map { path in
      JSONTrashItem(
        source: absolutePath(path, currentDirectoryPath: currentDirectoryPath),
        destination: nil,
        kind: JSONTrashKind(.unknown),
        status: .failed,
        error: JSONTrashError(code: code, message: message)
      )
    }
    return encode(
      JSONTrashOperation(dryRun: dryRun, items: items, success: false)
    ).withExitCode(exitCode)
  }

  func render(
    error: TrashPlanningError,
    request: TrashOperationRequest,
    currentDirectoryPath: String
  ) -> CommandResult {
    let result = render(
      paths: request.paths,
      dryRun: request.dryRun,
      code: error.code,
      message: error.explanation,
      currentDirectoryPath: currentDirectoryPath
    ).withExitCode(error.exitCode)
    let diagnostics = PlanningErrorRenderer().render(error)
    return CommandResult(
      standardOutput: result.standardOutput,
      standardError: result.standardError + diagnostics.standardError,
      exitCode: result.exitCode
    )
  }

  private func item(
    for entry: TrashPlanEntry,
    currentDirectoryPath: String
  ) -> JSONTrashItem {
    switch entry {
    case let .input(input):
      JSONTrashItem(
        source: absolutePath(input.path, currentDirectoryPath: currentDirectoryPath),
        destination: nil,
        kind: JSONTrashKind(input.kind),
        status: .planned,
        error: nil
      )
    case let .missing(path, ignored):
      JSONTrashItem(
        source: absolutePath(path, currentDirectoryPath: currentDirectoryPath),
        destination: nil,
        kind: JSONTrashKind(.unknown),
        status: ignored ? .skipped : .failed,
        error: entry.planningError.map {
          JSONTrashError(code: $0.code, message: $0.explanation)
        }
      )
    case let .inaccessible(path):
      JSONTrashItem(
        source: absolutePath(path, currentDirectoryPath: currentDirectoryPath),
        destination: nil,
        kind: JSONTrashKind(.unknown),
        status: .failed,
        error: entry.planningError.map {
          JSONTrashError(code: $0.code, message: $0.explanation)
        }
      )
    }
  }

  private func failureResult(for entry: TrashPlanEntry) -> TrashResult? {
    guard let error = entry.planningError else { return nil }
    return TrashResult(
      sourcePath: entry.path,
      destinationPath: nil,
      kind: entry.kind,
      status: .rejected,
      skipReason: nil,
      warnings: [],
      error: TrashFailure(code: error.code, explanation: error.explanation)
    )
  }

  private func item(
    for result: TrashResult,
    currentDirectoryPath: String
  ) -> JSONTrashItem {
    let status: JSONTrashStatus
    let error: JSONTrashError?
    switch result.status {
    case .moved:
      status = .moved
      error = nil
    case .skipped:
      status = .skipped
      error = nil
    case .rejected, .notMoved, .stateUncertain:
      status = .failed
      let failure =
        result.error
        ?? TrashFailure(
          code: .systemTrashFailed,
          explanation: "The Trash operation failed without a classified error."
        )
      error = JSONTrashError(code: failure.code, message: failure.explanation)
    }
    return JSONTrashItem(
      source: absolutePath(result.sourcePath, currentDirectoryPath: currentDirectoryPath),
      destination: result.destinationPath,
      kind: JSONTrashKind(result.kind),
      status: status,
      error: error
    )
  }

  private func encode(_ operation: JSONTrashOperation) -> CommandResult {
    do {
      let data = try encoder.encode(operation)
      guard let output = String(data: data, encoding: .utf8) else {
        return encodingFailure()
      }
      return CommandResult(
        standardOutput: output + "\n",
        standardError: "",
        exitCode: operation.success
          ? ExitStatus.success.rawValue
          : ExitStatus.failure.rawValue
      )
    } catch {
      return encodingFailure()
    }
  }

  private func encodingFailure() -> CommandResult {
    CommandResult(
      standardOutput: "",
      standardError:
        "rmp: \(TrashErrorCode.jsonEncodingFailed.rawValue): "
        + "could not encode the JSON Trash Operation result\n",
      exitCode: ExitStatus.failure.rawValue
    )
  }

  private func absolutePath(_ path: String, currentDirectoryPath: String) -> String {
    guard !path.hasPrefix("/") else { return path }
    let separator = currentDirectoryPath.hasSuffix("/") ? "" : "/"
    return currentDirectoryPath + separator + path
  }
}

private extension CommandResult {
  func withExitCode(_ exitCode: Int32) -> CommandResult {
    CommandResult(
      standardOutput: standardOutput,
      standardError: standardError,
      exitCode: exitCode
    )
  }
}
