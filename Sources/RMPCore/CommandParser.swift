// SPDX-License-Identifier: Apache-2.0

enum ParsedCommand: Equatable, Sendable {
  case operation(OperationRequest)
  case help(HelpPage)
  case version
}

enum HelpPage: Equatable, Sendable {
  case primaryEnglish
  case compatibilityEnglish
  case primaryChinese
  case compatibilityChinese
}

enum CompatibilityWarning: Equatable, Sendable {
  case secureOverwriteIgnored
}

struct OperationRequest: Equatable, Sendable {
  let paths: [String]
  let confirmation: ConfirmationMode
  let ignoreMissing: Bool
  let output: OutputMode
  let dryRun: Bool
  let nonInteractive: Bool
  let stopOnError: Bool
  let strictOptions: Bool
  let warnings: [CompatibilityWarning]
}

enum CommandParsingError: Error, Equatable, Sendable {
  case noInputs
  case unknownOption(String)
  case invalidConfirmationMode(String)
  case conflictingOptions(String, String)
  case unsupportedCompatibilityOption(String)
  case strictCompatibilityOption(String)
  case conflictingInformationCommands
  case helpModifierRequiresHelp(String)
}

enum CommandParser {
  private struct State {
    var paths: [String] = []
    var confirmation = ConfirmationMode.smart
    var ignoreMissing = false
    var output = OutputMode.standard
    var dryRun = false
    var nonInteractive = false
    var stopOnError = false
    var strictOptions = false
    var optionsEnded = false
    var helpRequested = false
    var versionRequested = false
    var compatibilityHelp = false
    var chineseHelp = false
    var compatibilityOptions: [String] = []
    var warnings: [CompatibilityWarning] = []
    var sawJSON = false
    var sawQuiet = false
  }

  static func parse(arguments: [String]) throws(CommandParsingError) -> ParsedCommand {
    var state = State()

    for argument in arguments {
      try consume(argument, state: &state)
    }

    return try finalize(state)
  }

  private static func finalize(_ state: State) throws(CommandParsingError) -> ParsedCommand {
    if let command = try informationCommand(from: state) { return command }
    return try operationCommand(from: state)
  }

  private static func informationCommand(
    from state: State
  ) throws(CommandParsingError) -> ParsedCommand? {
    if state.helpRequested && state.versionRequested {
      throw .conflictingInformationCommands
    }
    if !state.helpRequested {
      if state.compatibilityHelp { throw .helpModifierRequiresHelp("-a") }
      if state.chineseHelp { throw .helpModifierRequiresHelp("-zh") }
    }
    if state.helpRequested {
      return .help(helpPage(compatibility: state.compatibilityHelp, chinese: state.chineseHelp))
    }
    if state.versionRequested { return .version }
    return nil
  }

  private static func operationCommand(
    from state: State
  ) throws(CommandParsingError) -> ParsedCommand {
    if state.sawJSON && state.sawQuiet {
      throw .conflictingOptions("--json", "--quiet")
    }
    if state.strictOptions, let option = state.compatibilityOptions.first {
      throw .strictCompatibilityOption(option)
    }
    guard !state.paths.isEmpty else { throw .noInputs }

    return .operation(
      OperationRequest(
        paths: state.paths,
        confirmation: state.confirmation,
        ignoreMissing: state.ignoreMissing,
        output: state.output,
        dryRun: state.dryRun,
        nonInteractive: state.nonInteractive,
        stopOnError: state.stopOnError,
        strictOptions: state.strictOptions,
        warnings: state.warnings
      ))
  }

  private static func helpPage(compatibility: Bool, chinese: Bool) -> HelpPage {
    if compatibility { return chinese ? .compatibilityChinese : .compatibilityEnglish }
    return chinese ? .primaryChinese : .primaryEnglish
  }

  private static func consume(
    _ argument: String, state: inout State
  ) throws(CommandParsingError) {
    if state.optionsEnded {
      state.paths.append(argument)
    } else if argument == "--" {
      state.optionsEnded = true
    } else if argument.hasPrefix("--") {
      try parseLongOption(argument, state: &state)
    } else if argument.hasPrefix("-") && argument != "-" {
      try parseShortOption(argument, state: &state)
    } else {
      state.paths.append(argument)
    }
  }

  private static func parseLongOption(
    _ option: String, state: inout State
  ) throws(CommandParsingError) {
    if option.hasPrefix("--confirm=") {
      let value = String(option.dropFirst("--confirm=".count))
      guard let mode = ConfirmationMode(rawValue: value) else {
        throw .invalidConfirmationMode(value)
      }
      state.confirmation = mode
      return
    }
    if applyLongPolicyOption(option, state: &state) { return }
    if applyLongOutputOption(option, state: &state) { return }
    if applyLongControlOption(option, state: &state) { return }
    throw .unknownOption(option)
  }

  private static func applyLongPolicyOption(_ option: String, state: inout State) -> Bool {
    switch option {
    case "--force": applyForce(to: &state); return true
    case "--interactive": applyInteractive(to: &state); return true
    case "--ignore-missing": state.ignoreMissing = true; return true
    case "--dry-run": state.dryRun = true; return true
    case "--non-interactive": state.nonInteractive = true; return true
    default: return false
    }
  }

  private static func applyLongOutputOption(_ option: String, state: inout State) -> Bool {
    switch option {
    case "--verbose":
      if !state.sawJSON { state.output = .verbose }
      return true
    case "--quiet":
      state.output = .quiet
      state.sawQuiet = true
      return true
    case "--json":
      state.output = .json
      state.sawJSON = true
      return true
    default: return false
    }
  }

  private static func applyLongControlOption(_ option: String, state: inout State) -> Bool {
    switch option {
    case "--stop-on-error": state.stopOnError = true; return true
    case "--strict-options": state.strictOptions = true; return true
    case "--help": state.helpRequested = true; return true
    case "--version": state.versionRequested = true; return true
    default: return false
    }
  }

  private static func parseShortOption(
    _ option: String, state: inout State
  ) throws(CommandParsingError) {
    if option == "-a" {
      state.compatibilityHelp = true
      return
    }
    if option == "-zh" {
      state.chineseHelp = true
      return
    }

    for character in option.dropFirst() {
      try parseShortCharacter(character, state: &state)
    }
  }

  private static func parseShortCharacter(
    _ character: Character, state: inout State
  ) throws(CommandParsingError) {
    switch character {
    case "f": applyForce(to: &state)
    case "i": applyInteractive(to: &state)
    case "I": state.confirmation = .conditionalOnce
    case "v":
      if !state.sawJSON { state.output = .verbose }
    default: try parseCompatibilityCharacter(character, state: &state)
    }
  }

  private static func parseCompatibilityCharacter(
    _ character: Character, state: inout State
  ) throws(CommandParsingError) {
    switch character {
    case "r", "R", "d", "x":
      state.compatibilityOptions.append("-\(character)")
    case "P":
      state.compatibilityOptions.append("-P")
      state.warnings.append(.secureOverwriteIgnored)
    case "W": throw .unsupportedCompatibilityOption("-W")
    default: throw .unknownOption("-\(character)")
    }
  }

  private static func applyForce(to state: inout State) {
    state.confirmation = .never
    state.ignoreMissing = true
  }

  private static func applyInteractive(to state: inout State) {
    state.confirmation = .each
    state.ignoreMissing = false
  }
}
