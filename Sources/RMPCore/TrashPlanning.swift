// SPDX-License-Identifier: Apache-2.0

public struct FileSystemIdentity: Equatable, Hashable, Sendable {
  public let device: UInt64
  public let inode: UInt64

  public init(device: UInt64, inode: UInt64) {
    self.device = device
    self.inode = inode
  }
}

public enum TrashInputKind: String, Equatable, Sendable {
  case file
  case directory
  case symbolicLink = "symbolic-link"
  case brokenSymbolicLink = "broken-symbolic-link"
  case other
  case unknown
}

public struct FileSystemEntry: Equatable, Sendable {
  public let kind: TrashInputKind
  public let identity: FileSystemIdentity

  public init(kind: TrashInputKind, identity: FileSystemIdentity) {
    self.kind = kind
    self.identity = identity
  }
}

public enum FileSystemEntryInspection: Equatable, Sendable {
  case entry(FileSystemEntry)
  case missing
  case inaccessible
}

public protocol TrashPlanningFileSystem {
  var currentDirectoryPath: String { get }
  var homeDirectoryPath: String { get }

  func inspectEntry(at path: String) -> FileSystemEntryInspection
  func directoryIdentity(at path: String) -> FileSystemIdentity?
}

struct TrashInput: Equatable, Sendable {
  let path: String
  let kind: TrashInputKind
  let plannedIdentity: FileSystemIdentity?

  init(
    path: String,
    kind: TrashInputKind,
    plannedIdentity: FileSystemIdentity? = nil
  ) {
    self.path = path
    self.kind = kind
    self.plannedIdentity = plannedIdentity
  }
}

enum ConfirmationMode: String, Equatable, Sendable {
  case smart
  case never
  case once
  case each
  case conditionalOnce
}

enum OutputMode: Equatable, Sendable {
  case standard
  case verbose
  case quiet
  case json
}

struct TrashOperationRequest: Equatable, Sendable {
  let paths: [String]
  let confirmation: ConfirmationMode
  let ignoreMissing: Bool
  let output: OutputMode
  let dryRun: Bool
  let nonInteractive: Bool
  let stopOnError: Bool
  let strictOptions: Bool

  init(
    paths: [String],
    confirmation: ConfirmationMode = .smart,
    ignoreMissing: Bool = false,
    output: OutputMode = .standard,
    dryRun: Bool = true,
    nonInteractive: Bool = false,
    stopOnError: Bool = false,
    strictOptions: Bool = false
  ) {
    self.paths = paths
    self.confirmation = confirmation
    self.ignoreMissing = ignoreMissing
    self.output = output
    self.dryRun = dryRun
    self.nonInteractive = nonInteractive
    self.stopOnError = stopOnError
    self.strictOptions = strictOptions
  }
}

struct TrashPlan: Equatable, Sendable {
  let entries: [TrashPlanEntry]
  let confirmation: ConfirmationMode
  let ignoreMissing: Bool
  let output: OutputMode
  let dryRun: Bool
  let nonInteractive: Bool
  let stopOnError: Bool
  let strictOptions: Bool

  var inputs: [TrashInput] {
    entries.compactMap { entry in
      guard case let .input(input) = entry else { return nil }
      return input
    }
  }

  init(
    inputs: [TrashInput],
    confirmation: ConfirmationMode = .smart,
    ignoreMissing: Bool = false,
    output: OutputMode = .standard,
    dryRun: Bool = true,
    nonInteractive: Bool = false,
    stopOnError: Bool = false,
    strictOptions: Bool = false
  ) {
    self.init(
      entries: inputs.map(TrashPlanEntry.input),
      confirmation: confirmation,
      ignoreMissing: ignoreMissing,
      output: output,
      dryRun: dryRun,
      nonInteractive: nonInteractive,
      stopOnError: stopOnError,
      strictOptions: strictOptions
    )
  }

  init(
    entries: [TrashPlanEntry],
    confirmation: ConfirmationMode = .smart,
    ignoreMissing: Bool = false,
    output: OutputMode = .standard,
    dryRun: Bool = true,
    nonInteractive: Bool = false,
    stopOnError: Bool = false,
    strictOptions: Bool = false
  ) {
    self.entries = entries
    self.confirmation = confirmation
    self.ignoreMissing = ignoreMissing
    self.output = output
    self.dryRun = dryRun
    self.nonInteractive = nonInteractive
    self.stopOnError = stopOnError
    self.strictOptions = strictOptions
  }
}

enum TrashPlanEntry: Equatable, Sendable {
  case input(TrashInput)
  case missing(path: String, ignored: Bool)
  case inaccessible(path: String)

  var path: String {
    switch self {
    case let .input(input): input.path
    case let .missing(path, _), let .inaccessible(path): path
    }
  }

  var kind: TrashInputKind {
    switch self {
    case let .input(input): input.kind
    case .missing, .inaccessible: .unknown
    }
  }

  var planningError: TrashPlanningError? {
    switch self {
    case .input, .missing(_, true): nil
    case let .missing(path, false): .missingPath(path)
    case let .inaccessible(path): .inaccessiblePath(path)
    }
  }
}

enum ProtectedPath: String, Equatable, Sendable {
  case fileSystemRoot = "filesystem-root"
  case currentDirectory = "current-directory"
  case homeDirectory = "home-directory"
  case parentDirectory = "parent-directory"
}

enum TrashPlanningError: Error, Equatable, Sendable {
  case noInputs
  case missingPath(String)
  case inaccessiblePath(String)
  case protectedPath(path: String, protectedPath: ProtectedPath)
  case unavailableProtectedPath(path: String, protectedPath: ProtectedPath)

  var code: TrashErrorCode {
    switch self {
    case .noInputs: .noInputs
    case .missingPath: .missingInput
    case .inaccessiblePath: .inaccessibleInput
    case .protectedPath: .protectedPath
    case .unavailableProtectedPath: .safetyIdentityUnavailable
    }
  }

  var explanation: String {
    switch self {
    case .noInputs: "At least one Trash Input is required."
    case .missingPath: "The Trash Input does not exist."
    case .inaccessiblePath: "The Trash Input cannot be inspected."
    case let .protectedPath(_, protectedPath):
      "Protected Path rejected: \(protectedPath.rawValue)."
    case let .unavailableProtectedPath(_, protectedPath):
      "Safety identity unavailable: \(protectedPath.rawValue)."
    }
  }

  var exitCode: Int32 {
    switch self {
    case .noInputs: 2
    case .missingPath, .inaccessiblePath: 1
    case .protectedPath, .unavailableProtectedPath: 3
    }
  }
}

struct TrashPlanner<FileSystem: TrashPlanningFileSystem> {
  private typealias ProtectedIdentities = [FileSystemIdentity: ProtectedPath]

  private let fileSystem: FileSystem

  init(fileSystem: FileSystem) {
    self.fileSystem = fileSystem
  }

  func makePlan(request: TrashOperationRequest) throws(TrashPlanningError) -> TrashPlan {
    guard !request.paths.isEmpty else {
      throw .noInputs
    }

    let protectedIdentities = try protectedIdentities(sourcePath: request.paths[0])
    var entries: [TrashPlanEntry] = []
    entries.reserveCapacity(request.paths.count)

    for path in request.paths {
      if isParentDirectoryExpression(path) {
        throw .protectedPath(path: path, protectedPath: .parentDirectory)
      }
      switch fileSystem.inspectEntry(at: path) {
      case let .entry(entry):
        if let protectedPath = protectedIdentities[entry.identity] {
          throw .protectedPath(path: path, protectedPath: protectedPath)
        }
        entries.append(
          .input(TrashInput(path: path, kind: entry.kind, plannedIdentity: entry.identity))
        )
      case .missing:
        if request.ignoreMissing {
          entries.append(.missing(path: path, ignored: true))
        } else {
          entries.append(.missing(path: path, ignored: false))
        }
      case .inaccessible:
        entries.append(.inaccessible(path: path))
      }
    }

    return TrashPlan(
      entries: entries,
      confirmation: request.confirmation,
      ignoreMissing: request.ignoreMissing,
      output: request.output,
      dryRun: request.dryRun,
      nonInteractive: request.nonInteractive,
      stopOnError: request.stopOnError,
      strictOptions: request.strictOptions
    )
  }

  func makePlan(paths: [String]) throws(TrashPlanningError) -> TrashPlan {
    try makePlan(request: TrashOperationRequest(paths: paths))
  }

  private func protectedIdentities(
    sourcePath: String
  ) throws(TrashPlanningError) -> ProtectedIdentities {
    let protectedDirectories: [(String, ProtectedPath)] = [
      (fileSystem.homeDirectoryPath, .homeDirectory),
      (fileSystem.currentDirectoryPath, .currentDirectory),
      ("/", .fileSystemRoot),
    ]
    var identities: [FileSystemIdentity: ProtectedPath] = [:]

    for (path, protectedPath) in protectedDirectories {
      guard let identity = fileSystem.directoryIdentity(at: path) else {
        throw .unavailableProtectedPath(path: sourcePath, protectedPath: protectedPath)
      }
      identities[identity] = protectedPath
    }

    return identities
  }

  private func isParentDirectoryExpression(_ path: String) -> Bool {
    guard !path.hasPrefix("/") else {
      return false
    }
    let meaningfulComponents = path.split(separator: "/").filter { $0 != "." }
    return meaningfulComponents == [".."]
  }
}
