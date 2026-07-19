// SPDX-License-Identifier: Apache-2.0

import Foundation
import RMPTestKit
import Testing

@Suite("Put Back metadata scanner")
struct PutBackMetadataScannerTests {
  @Test("extracts original parent and original name records")
  func extractsPutBackRecords() {
    let data =
      record(fileName: "rmp-test-item", kind: "ptbL", payload: "/Users/test/source")
      + record(fileName: "rmp-test-item", kind: "ptbN", payload: "rmp-test-item")

    let records = PutBackMetadataScanner.scan(data)

    #expect(
      records == [
        PutBackMetadataRecord(
          fileName: "rmp-test-item",
          kind: .originalParent,
          payload: "/Users/test/source"
        ),
        PutBackMetadataRecord(
          fileName: "rmp-test-item",
          kind: .originalName,
          payload: "rmp-test-item"
        ),
      ]
    )
  }

  @Test("ignores absent and truncated Put Back metadata")
  func ignoresAbsentAndTruncatedMetadata() {
    #expect(PutBackMetadataScanner.scan(Data()).isEmpty)
    #expect(PutBackMetadataScanner.scan(Data("prefix-ptbLustr".utf8)).isEmpty)
  }

  @Test("renders blob payload evidence without reading past available bytes")
  func rendersBlobPayload() {
    let data =
      bigEndianUInt32(4)
      + utf16BigEndian("item")
      + Data("ptbL".utf8)
      + Data("blob".utf8)
      + bigEndianUInt32(4)
      + Data([0xAB, 0xCD])

    let expected = PutBackMetadataRecord(
      fileName: "item",
      kind: .originalParent,
      payload: "<blob 4> abcd"
    )

    #expect(PutBackMetadataScanner.scan(data) == [expected])
  }
}

private func record(fileName: String, kind: String, payload: String) -> Data {
  bigEndianUInt32(UInt32(fileName.utf16.count))
    + utf16BigEndian(fileName)
    + Data(kind.utf8)
    + Data("ustr".utf8)
    + bigEndianUInt32(UInt32(payload.utf16.count))
    + utf16BigEndian(payload)
}

private func bigEndianUInt32(_ value: UInt32) -> Data {
  withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

private func utf16BigEndian(_ value: String) -> Data {
  value.utf16.reduce(into: Data()) { data, codeUnit in
    var bigEndian = codeUnit.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
  }
}
