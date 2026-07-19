// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum PutBackMetadataKind: String, Equatable, Sendable {
  case originalParent = "ptbL"
  case originalName = "ptbN"
}

public struct PutBackMetadataRecord: Equatable, Sendable {
  public let fileName: String?
  public let kind: PutBackMetadataKind
  public let payload: String

  public init(fileName: String?, kind: PutBackMetadataKind, payload: String) {
    self.fileName = fileName
    self.kind = kind
    self.payload = payload
  }
}

public enum PutBackMetadataScanner {
  public static func scan(_ data: Data) -> [PutBackMetadataRecord] {
    guard data.count >= 12 else { return [] }

    var records: [PutBackMetadataRecord] = []
    for offset in 0...(data.count - 12) {
      guard let kind = metadataKind(in: data, at: offset) else { continue }
      let dataTypeOffset = offset + 4
      let payloadOffset = dataTypeOffset + 4
      guard let dataType = ascii(in: data, range: dataTypeOffset..<(dataTypeOffset + 4)) else {
        continue
      }
      guard let payload = payload(in: data, dataType: dataType, at: payloadOffset) else {
        continue
      }
      records.append(
        PutBackMetadataRecord(
          fileName: fileName(in: data, before: offset),
          kind: kind,
          payload: payload
        )
      )
    }
    return records
  }

  private static func metadataKind(in data: Data, at offset: Int) -> PutBackMetadataKind? {
    guard let marker = ascii(in: data, range: offset..<(offset + 4)) else { return nil }
    return PutBackMetadataKind(rawValue: marker)
  }

  private static func fileName(in data: Data, before markerOffset: Int) -> String? {
    var result: String?
    let maximumLength = min(127, markerOffset / 2)
    guard maximumLength > 0 else { return nil }

    for length in 1...maximumLength {
      let nameOffset = markerOffset - length * 2
      let countOffset = nameOffset - 4
      guard countOffset >= 0,
        readUInt32(in: data, at: countOffset) == UInt32(length),
        let candidate = utf16BigEndian(
          in: data,
          range: nameOffset..<markerOffset
        ),
        candidate.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
      else {
        continue
      }
      result = candidate
    }
    return result
  }

  private static func payload(in data: Data, dataType: String, at offset: Int) -> String? {
    guard let count = readUInt32(in: data, at: offset) else {
      return "<\(dataType)>"
    }
    let payloadOffset = offset + 4
    switch dataType {
    case "ustr":
      let byteCount = Int(count) * 2
      guard byteCount <= data.count - payloadOffset else { return nil }
      return utf16BigEndian(in: data, range: payloadOffset..<(payloadOffset + byteCount))
    case "blob":
      let byteCount = min(Int(count), min(120, data.count - payloadOffset))
      guard byteCount >= 0 else { return nil }
      let hex = data[payloadOffset..<(payloadOffset + byteCount)]
        .map { String(format: "%02x", $0) }
        .joined()
      return "<blob \(count)> \(hex)"
    default:
      return "<\(dataType)>"
    }
  }

  private static func readUInt32(in data: Data, at offset: Int) -> UInt32? {
    guard offset >= 0, offset <= data.count - 4 else { return nil }
    return data[offset..<(offset + 4)].reduce(UInt32(0)) { value, byte in
      (value << 8) | UInt32(byte)
    }
  }

  private static func ascii(in data: Data, range: Range<Int>) -> String? {
    guard range.lowerBound >= 0, range.upperBound <= data.count else { return nil }
    return String(data: data[range], encoding: .ascii)
  }

  private static func utf16BigEndian(in data: Data, range: Range<Int>) -> String? {
    guard range.lowerBound >= 0, range.upperBound <= data.count else { return nil }
    return String(data: data[range], encoding: .utf16BigEndian)
  }
}
