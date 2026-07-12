// SPDX-License-Identifier: Apache-2.0

struct DryRunRenderer: Sendable {
  func render(_ plan: TrashPlan) -> String {
    let itemNoun = plan.inputs.count == 1 ? "item" : "items"
    var output = "Would move \(plan.inputs.count) \(itemNoun) to Trash:\n"
    for input in plan.inputs {
      output += "  [\(input.kind.rawValue)] \(renderPath(input.path))\n"
    }
    return output
  }

  func renderPath(_ path: String) -> String {
    var result = "\""
    for scalar in path.unicodeScalars {
      switch scalar.value {
      case 0x08:
        result += "\\b"
      case 0x09:
        result += "\\t"
      case 0x0A:
        result += "\\n"
      case 0x0C:
        result += "\\f"
      case 0x0D:
        result += "\\r"
      case 0x22:
        result += "\\\""
      case 0x5C:
        result += "\\\\"
      case 0x00...0x1F:
        result += "\\u00\(hexByte(UInt8(scalar.value)))"
      default:
        result.unicodeScalars.append(scalar)
      }
    }
    result += "\""
    return result
  }

  private func hexByte(_ byte: UInt8) -> String {
    let digits = Array("0123456789abcdef")
    return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
  }
}
