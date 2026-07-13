// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import rmp_test

enum ContextRevalidationCase: CaseIterable, CustomTestStringConvertible {
  case containerMarker
  case authorizedRootMarker
  case runMarker
  case containerIdentity
  case authorizedRootIdentity
  case runIdentity
  case containerPermissions
  case authorizedRootPermissions
  case runPermissions

  var testDescription: String {
    switch self {
    case .containerMarker: "container marker"
    case .authorizedRootMarker: "authorized-root marker"
    case .runMarker: "run marker"
    case .containerIdentity: "container identity"
    case .authorizedRootIdentity: "authorized-root identity"
    case .runIdentity: "run identity"
    case .containerPermissions: "container permissions"
    case .authorizedRootPermissions: "authorized-root permissions"
    case .runPermissions: "run permissions"
    }
  }

  var expectedCode: TestSafetyDiagnosticCode {
    switch self {
    case .containerMarker, .authorizedRootMarker, .runMarker: .markerMissing
    case .containerIdentity, .authorizedRootIdentity, .runIdentity: .directoryIdentityMismatch
    case .containerPermissions, .authorizedRootPermissions, .runPermissions:
      .directoryPermissions
    }
  }

  func invalidate(context: TestSafetyContext, fixture: SafetyHomeFixture) throws {
    switch self {
    case .containerMarker:
      try FileManager.default.removeItem(at: fixture.containerMarkerURL)
    case .authorizedRootMarker:
      try FileManager.default.removeItem(at: fixture.rootMarkerURL)
    case .runMarker:
      try FileManager.default.removeItem(at: context.runMarkerURL)
    case .containerIdentity:
      let displaced = fixture.homeURL.appendingPathComponent("displaced-container")
      try FileManager.default.moveItem(at: fixture.containerURL, to: displaced)
      try FileManager.default.createDirectory(
        at: fixture.containerURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    case .authorizedRootIdentity:
      let displaced = fixture.homeURL.appendingPathComponent("displaced-root")
      try FileManager.default.moveItem(at: fixture.authorizedRootURL, to: displaced)
      try FileManager.default.createDirectory(
        at: fixture.authorizedRootURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    case .runIdentity:
      let displaced = fixture.homeURL.appendingPathComponent("displaced-run")
      try FileManager.default.moveItem(at: context.runDirectoryURL, to: displaced)
      try FileManager.default.createDirectory(
        at: context.runDirectoryURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    case .containerPermissions:
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: fixture.containerURL.path
      )
    case .authorizedRootPermissions:
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: fixture.authorizedRootURL.path
      )
    case .runPermissions:
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: context.runDirectoryURL.path
      )
    }
  }
}
