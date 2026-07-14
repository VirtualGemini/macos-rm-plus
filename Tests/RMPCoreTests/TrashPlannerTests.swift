// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import RMPCore

@Test("Trash Plan preserves top-level input order and entry kinds")
func trashPlanPreservesInputOrderAndKinds() throws {
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: [
      "report.txt": .entry(.init(kind: .file, identity: .init(device: 1, inode: 10))),
      "build": .entry(.init(kind: .directory, identity: .init(device: 1, inode: 11))),
      "shortcut": .entry(.init(kind: .symbolicLink, identity: .init(device: 1, inode: 12))),
      "broken": .entry(.init(kind: .brokenSymbolicLink, identity: .init(device: 1, inode: 13))),
      "pipe": .entry(.init(kind: .other, identity: .init(device: 1, inode: 14))),
    ]
  )

  let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(
    paths: ["report.txt", "build", "shortcut", "broken", "pipe"]
  )

  #expect(
    plan.inputs == [
      TrashInput(
        path: "report.txt", kind: .file,
        plannedIdentity: .init(device: 1, inode: 10)
      ),
      TrashInput(
        path: "build", kind: .directory,
        plannedIdentity: .init(device: 1, inode: 11)
      ),
      TrashInput(
        path: "shortcut", kind: .symbolicLink,
        plannedIdentity: .init(device: 1, inode: 12)
      ),
      TrashInput(
        path: "broken", kind: .brokenSymbolicLink,
        plannedIdentity: .init(device: 1, inode: 13)
      ),
      TrashInput(
        path: "pipe", kind: .other,
        plannedIdentity: .init(device: 1, inode: 14)
      ),
    ]
  )
  #expect(plan.confirmation == .smart)
  #expect(!plan.ignoreMissing)
  #expect(plan.output == .standard)
  #expect(plan.dryRun)
  #expect(!plan.nonInteractive)
  #expect(!plan.stopOnError)
  #expect(!plan.strictOptions)
}

@Test("Equivalent filesystem root, working directory, and home expressions are Protected Paths")
func equivalentProtectedPathExpressionsAreRejected() {
  let protectedExpressions = [
    ProtectedExpression(path: "/", identity: .init(device: 1, inode: 1), kind: .fileSystemRoot),
    ProtectedExpression(path: "//", identity: .init(device: 1, inode: 1), kind: .fileSystemRoot),
    ProtectedExpression(
      path: "/tmp/..", identity: .init(device: 1, inode: 1), kind: .fileSystemRoot),
    ProtectedExpression(path: ".", identity: .init(device: 1, inode: 2), kind: .currentDirectory),
    ProtectedExpression(
      path: "/work/.", identity: .init(device: 1, inode: 2), kind: .currentDirectory),
    ProtectedExpression(
      path: "/home/user", identity: .init(device: 1, inode: 3), kind: .homeDirectory),
    ProtectedExpression(
      path: "/home/user/../user",
      identity: .init(device: 1, inode: 3),
      kind: .homeDirectory
    ),
  ]

  for expression in protectedExpressions {
    let fileSystem = FakeTrashPlanningFileSystem(
      entries: [
        expression.path: .entry(.init(kind: .directory, identity: expression.identity))
      ]
    )

    do {
      _ = try TrashPlanner(fileSystem: fileSystem).makePlan(paths: [expression.path])
      Issue.record("Expected \(expression.path) to be rejected as a Protected Path")
    } catch {
      #expect(error == .protectedPath(path: expression.path, protectedPath: expression.kind))
    }
  }
}

@Test("Parent-directory expressions are always Protected Paths")
func parentDirectoryExpressionsAreRejected() {
  for path in ["..", "../", "./..", ".//../"] {
    let fileSystem = FakeTrashPlanningFileSystem(entries: [:])

    do {
      _ = try TrashPlanner(fileSystem: fileSystem).makePlan(paths: [path])
      Issue.record("Expected \(path) to be rejected as a Protected Path")
    } catch {
      #expect(error == .protectedPath(path: path, protectedPath: .parentDirectory))
    }
  }
}

@Test("A symlink entry may be planned even when its destination is protected")
func symlinkEntryToProtectedDestinationIsAllowed() throws {
  let fileSystem = FakeTrashPlanningFileSystem(
    entries: [
      "home-link": .entry(.init(kind: .symbolicLink, identity: .init(device: 1, inode: 20)))
    ]
  )

  let plan = try TrashPlanner(fileSystem: fileSystem).makePlan(paths: ["home-link"])
  let expected = TrashInput(
    path: "home-link", kind: .symbolicLink,
    plannedIdentity: .init(device: 1, inode: 20)
  )

  #expect(plan.inputs == [expected])
}

@Test("A missing Trash Input fails planning by default")
func missingTrashInputFailsPlanning() {
  let fileSystem = FakeTrashPlanningFileSystem(entries: [:])

  do {
    _ = try TrashPlanner(fileSystem: fileSystem).makePlan(paths: ["missing"])
    Issue.record("Expected a missing Trash Input to fail planning")
  } catch {
    #expect(error == .missingPath("missing"))
  }
}

struct FakeTrashPlanningFileSystem: TrashPlanningFileSystem {
  let currentDirectoryPath = "/work"
  let homeDirectoryPath = "/home/user"
  let entries: [String: FileSystemEntryInspection]

  init(entries: [String: FileSystemEntryInspection]) {
    var allEntries = entries
    allEntries["/"] = .entry(.init(kind: .directory, identity: .init(device: 1, inode: 1)))
    allEntries["/work"] = .entry(.init(kind: .directory, identity: .init(device: 1, inode: 2)))
    allEntries["/home/user"] = .entry(.init(kind: .directory, identity: .init(device: 1, inode: 3)))
    self.entries = allEntries
  }

  func inspectEntry(at path: String) -> FileSystemEntryInspection {
    entries[path] ?? .missing
  }

  func directoryIdentity(at path: String) -> FileSystemIdentity? {
    guard case let .entry(entry) = entries[path] else {
      return nil
    }
    return entry.identity
  }
}

private struct ProtectedExpression {
  let path: String
  let identity: FileSystemIdentity
  let kind: ProtectedPath
}
