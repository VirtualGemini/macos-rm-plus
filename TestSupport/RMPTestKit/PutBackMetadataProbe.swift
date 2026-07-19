// SPDX-License-Identifier: Apache-2.0

#if RMP_PUT_BACK_METADATA_PROBE
  import Foundation

  private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }

  private func reflected(_ value: String?) -> String {
    value.map { String(reflecting: $0) } ?? "nil"
  }

  @main
  private enum PutBackMetadataProbe {
    static func main() {
      guard CommandLine.arguments.count == 2 else {
        writeStandardError("usage: put-back-metadata-probe <path-to-.DS_Store>\n")
        exit(2)
      }

      let path = CommandLine.arguments[1]
      let data: Data
      do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
      } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        print("NO_DSSTORE")
        return
      } catch {
        writeStandardError("could not read \(String(reflecting: path)): \(error)\n")
        exit(1)
      }

      let records = PutBackMetadataScanner.scan(data)
      guard !records.isEmpty else {
        print("NO_PTB_RECORDS size=\(data.count)")
        return
      }

      for record in records {
        print(
          "record file=\(reflected(record.fileName)) kind=\(record.kind.rawValue) "
            + "payload=\(String(reflecting: record.payload))"
        )
      }
    }
  }
#endif
