// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import rmp_test

@Suite("Foundation symbolic-link Trash experiment", .serialized)
struct FoundationSymlinkTrashClientTests {
  @Test("passes a symbolic link itself to Foundation without resolving its target")
  func trashesSymbolicLinkWithoutFollowingTarget() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let target = try context.createFixtureFile(
      suffix: "symlink-target",
      contents: Data("target".utf8)
    )
    let link = try context.createFixtureSymbolicLink(
      suffix: "symlink",
      target: target.lastPathComponent
    )
    let returnedURL = URL(fileURLWithPath: "/Trash/\(link.lastPathComponent)")
    let spy = FoundationTrashSpy(returnedURL: returnedURL)
    let client = FoundationSymlinkTrashClient(systemTrash: spy.call)

    let actual = try client.trashItem(link)

    #expect(actual == returnedURL)
    #expect(spy.receivedURLs == [link])
    #expect(FileManager.default.fileExists(atPath: target.path))
  }

  @Test("rejects a regular file without invoking Foundation Trash")
  func rejectsRegularFile() throws {
    let fixture = try SafetyHomeFixture()
    defer { fixture.remove() }
    let context = try fixture.establishContext()
    let file = try context.createFixtureFile(
      suffix: "regular-file",
      contents: Data("file".utf8)
    )
    let spy = FoundationTrashSpy(returnedURL: URL(fileURLWithPath: "/Trash/unused"))
    let client = FoundationSymlinkTrashClient(systemTrash: spy.call)

    let diagnostic = captureDiagnostic { _ = try client.trashItem(file) }

    #expect(diagnostic?.code == .trashSymlinkRequired)
    #expect(spy.receivedURLs.isEmpty)
    #expect(FileManager.default.fileExists(atPath: file.path))
  }
}

private final class FoundationTrashSpy: @unchecked Sendable {
  private(set) var receivedURLs: [URL] = []
  private let returnedURL: URL

  init(returnedURL: URL) {
    self.returnedURL = returnedURL
  }

  func call(_ url: URL) throws -> URL {
    receivedURLs.append(url)
    return returnedURL
  }
}
