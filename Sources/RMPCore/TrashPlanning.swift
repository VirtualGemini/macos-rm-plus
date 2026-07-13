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
  let inputs: [TrashInput]
  let confirmation: ConfirmationMode
  let ignoreMissing: Bool
  let output: OutputMode
  let dryRun: Bool
  let nonInteractive: Bool
  let stopOnError: Bool
  let strictOptions: Bool

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
    self.inputs = inputs
    self.confirmation = confirmation
    self.ignoreMissing = ignoreMissing
    self.output = output
    self.dryRun = dryRun
    self.nonInteractive = nonInteractive
    self.stopOnError = stopOnError
    self.strictOptions = strictOptions
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
  case unavailableProtectedPath(ProtectedPath)
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

    let protectedIdentities = try protectedIdentities()
    var inputs: [TrashInput] = []
    inputs.reserveCapacity(request.paths.count)

    for path in request.paths {
      if isParentDirectoryExpression(path) {
        throw .protectedPath(path: path, protectedPath: .parentDirectory)
      }
      switch fileSystem.inspectEntry(at: path) {
      case let .entry(entry):
        if let protectedPath = protectedIdentities[entry.identity] {
          throw .protectedPath(path: path, protectedPath: protectedPath)
        }
        inputs.append(TrashInput(path: path, kind: entry.kind))
      case .missing:
        if !request.ignoreMissing { throw .missingPath(path) }
      case .inaccessible:
        throw .inaccessiblePath(path)
      }
    }

    return TrashPlan(
      inputs: inputs,
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

  private func protectedIdentities() throws(TrashPlanningError) -> ProtectedIdentities {
    let protectedDirectories: [(String, ProtectedPath)] = [
      (fileSystem.homeDirectoryPath, .homeDirectory),
      (fileSystem.currentDirectoryPath, .currentDirectory),
      ("/", .fileSystemRoot),
    ]
    var identities: [FileSystemIdentity: ProtectedPath] = [:]

    for (path, protectedPath) in protectedDirectories {
      guard let identity = fileSystem.directoryIdentity(at: path) else {
        throw .unavailableProtectedPath(protectedPath)
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
