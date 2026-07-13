// SPDX-License-Identifier: Apache-2.0

enum ParsedCommand: Equatable, Sendable {
  case operation(TrashOperationRequest)
  case help(HelpPage)
  case version
}

struct ParsedInvocation: Equatable, Sendable {
  let command: ParsedCommand
  let warnings: [CompatibilityWarning]
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
  private enum MissingPathPolicy {
    case fail
    case ignoreFromForce
    case ignoreExplicitly

    var ignoresMissing: Bool {
      self != .fail
    }
  }

  private struct State {
    var paths: [String] = []
    var confirmation = ConfirmationMode.smart
    var missingPathPolicy = MissingPathPolicy.fail
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

  static func parse(arguments: [String]) throws(CommandParsingError) -> ParsedInvocation {
    var state = State()

    for argument in arguments {
      try consume(argument, state: &state)
    }

    return try finalize(state)
  }

  private static func finalize(_ state: State) throws(CommandParsingError) -> ParsedInvocation {
    if state.sawJSON && state.sawQuiet {
      throw .conflictingOptions("--json", "--quiet")
    }
    if state.strictOptions, let option = state.compatibilityOptions.first {
      throw .strictCompatibilityOption(option)
    }
    let command: ParsedCommand
    if let informationCommand = try informationCommand(from: state) {
      command = informationCommand
    } else {
      command = try operationCommand(from: state)
    }
    return ParsedInvocation(command: command, warnings: state.warnings)
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
    guard !state.paths.isEmpty else { throw .noInputs }

    return .operation(
      TrashOperationRequest(
        paths: state.paths,
        confirmation: state.confirmation,
        ignoreMissing: state.missingPathPolicy.ignoresMissing,
        output: state.output,
        dryRun: state.dryRun,
        nonInteractive: state.nonInteractive,
        stopOnError: state.stopOnError,
        strictOptions: state.strictOptions
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
      guard let mode = explicitConfirmationMode(value) else {
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
    case "--ignore-missing": state.missingPathPolicy = .ignoreExplicitly; return true
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
    state.missingPathPolicy = .ignoreFromForce
  }

  private static func applyInteractive(to state: inout State) {
    state.confirmation = .each
    if state.missingPathPolicy == .ignoreFromForce {
      state.missingPathPolicy = .fail
    }
  }

  private static func explicitConfirmationMode(_ value: String) -> ConfirmationMode? {
    switch value {
    case "smart": .smart
    case "never": .never
    case "once": .once
    case "each": .each
    default: nil
    }
  }
}
