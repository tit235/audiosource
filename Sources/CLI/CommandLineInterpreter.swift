import Foundation

enum Command {
  case help
  case version
  case showAll
  case showCurrent
  case cycleNext
  case cyclePrevious
  case mute(MuteMode)
  case set(Selection)
  case none
}

private struct ParsedArguments {
  var format: OutputFormat = .human
  var type: AudioDeviceType?
  var muteMode: MuteMode?
  var selection: Selection?
  var basicCommand: BasicCommand?
  var showHelp = false
  var showVersion = false
}

private enum BasicCommand {
  case showAll
  case showCurrent
  case cycleNext
  case cyclePrevious
  case set
}

private struct UsageError: Error {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}

final class CommandLineInterpreter {
  func interpret(arguments: [String]) {
    do {
      let parsed = try parse(arguments)
      let commandCenter = CommandCenter()

      switch resolve(parsed) {
      case .help:
        printHelp()
      case .version:
        print("audiosource \(audioSourceVersion)")
      case .showAll:
        commandCenter.showAllDevices(type: parsed.type ?? .all, format: parsed.format)
      case .showCurrent:
        commandCenter.showCurrentDevice(type: parsed.type ?? .output, format: parsed.format)
      case .cycleNext:
        commandCenter.cycleNextDevice(type: parsed.type, format: parsed.format)
      case .cyclePrevious:
        commandCenter.cyclePreviousDevice(type: parsed.type, format: parsed.format)
      case .mute(let mode):
        commandCenter.muteDevice(
          mode: mode, selection: parsed.selection, type: parsed.type, format: parsed.format)
      case .set(let selection):
        commandCenter.setDevice(
          selection: selection, type: parsed.type ?? .output, format: parsed.format)
      case .none:
        throw UsageError("Please specify audio device.")
      }
    } catch let error as UsageError {
      printToStdErr(error.message)
      printHelp(toStandardError: true)
      exit(1)
    } catch {
      printToStdErr("Unexpected error: \(error)")
      exit(1)
    }
  }

  private func resolve(_ parsed: ParsedArguments) -> Command {
    if parsed.showHelp { return .help }
    if parsed.showVersion { return .version }

    switch parsed.basicCommand {
    case .showAll:
      return .showAll
    case .showCurrent:
      return .showCurrent
    case .set:
      if let mode = parsed.muteMode { return .mute(mode) }
      if let selection = parsed.selection { return .set(selection) }
      return .none
    case .cycleNext:
      if let mode = parsed.muteMode { return .mute(mode) }
      return .cycleNext
    case .cyclePrevious:
      if let mode = parsed.muteMode { return .mute(mode) }
      return .cyclePrevious
    case nil:
      if let mode = parsed.muteMode { return .mute(mode) }
      return .none
    }
  }

  private func parse(_ arguments: [String]) throws -> ParsedArguments {
    var parsed = ParsedArguments()
    var argumentIndex = 0

    while argumentIndex < arguments.count {
      let argument = arguments[argumentIndex]

      if argument == "--" {
        let remaining = arguments.dropFirst(argumentIndex + 1)
        if let extra = remaining.first {
          throw UsageError("Unexpected argument: \(extra)")
        }
        break
      }

      if argument.hasPrefix("--") {
        var name = String(argument.dropFirst(2))
        var inlineValue: String?

        if let equalsIndex = name.firstIndex(of: "=") {
          inlineValue = String(name[name.index(after: equalsIndex)...])
          name = String(name[..<equalsIndex])
        }

        switch name {
        case "all":
          try rejectValue(inlineValue, option: "--all")
          parsed.basicCommand = .showAll
        case "current":
          try rejectValue(inlineValue, option: "--current")
          parsed.basicCommand = .showCurrent
        case "next":
          try rejectValue(inlineValue, option: "--next")
          parsed.basicCommand = .cycleNext
        case "previous":
          try rejectValue(inlineValue, option: "--previous")
          parsed.basicCommand = .cyclePrevious
        case "help":
          try rejectValue(inlineValue, option: "--help")
          parsed.showHelp = true
        case "version":
          try rejectValue(inlineValue, option: "--version")
          parsed.showVersion = true
        case "format", "type", "mute", "id", "uid", "name":
          let value = try readValue(
            inlineValue, arguments: arguments, index: &argumentIndex, option: "--\(name)")
          try apply(option: name, value: value, to: &parsed)
        default:
          throw UsageError("Unknown option: \(argument)")
        }

        argumentIndex += 1
        continue
      }

      if argument.hasPrefix("-"), argument.count > 1 {
        let characters = Array(argument.dropFirst())
        var characterIndex = 0

        while characterIndex < characters.count {
          let option = characters[characterIndex]

          switch option {
          case "a":
            parsed.basicCommand = .showAll
          case "c":
            parsed.basicCommand = .showCurrent
          case "n":
            parsed.basicCommand = .cycleNext
          case "p":
            parsed.basicCommand = .cyclePrevious
          case "h":
            parsed.showHelp = true
          case "v":
            parsed.showVersion = true
          case "f", "t", "m", "i", "u", "s":
            let value: String
            if characterIndex + 1 < characters.count {
              value = String(characters[(characterIndex + 1)...])
              characterIndex = characters.count
            } else {
              value = try readValue(
                nil, arguments: arguments, index: &argumentIndex, option: "-\(option)")
            }
            try apply(shortOption: option, value: value, to: &parsed)
          default:
            throw UsageError("Unknown option: -\(option)")
          }

          characterIndex += 1
        }

        argumentIndex += 1
        continue
      }

      throw UsageError("Unexpected argument: \(argument)")
    }

    return parsed
  }

  private func readValue(
    _ inlineValue: String?, arguments: [String], index: inout Int, option: String
  ) throws -> String {
    if let inlineValue { return inlineValue }

    index += 1
    guard index < arguments.count else {
      throw UsageError("Missing value for option \(option).")
    }

    return arguments[index]
  }

  private func rejectValue(_ value: String?, option: String) throws {
    if value != nil {
      throw UsageError("Option \(option) does not take a value.")
    }
  }

  private func apply(shortOption: Character, value: String, to parsed: inout ParsedArguments) throws {
    let longOption: String
    switch shortOption {
    case "f": longOption = "format"
    case "t": longOption = "type"
    case "m": longOption = "mute"
    case "i": longOption = "id"
    case "u": longOption = "uid"
    case "s": longOption = "name"
    default: return
    }

    try apply(option: longOption, value: value, to: &parsed)
  }

  private func apply(option: String, value: String, to parsed: inout ParsedArguments) throws {
    switch option {
    case "format":
      guard let format = OutputFormat(rawValue: value) else {
        throw UsageError("Unknown format \"\(value)\".")
      }
      parsed.format = format
    case "type":
      guard let type = AudioDeviceType(rawValue: value) else {
        throw UsageError("Invalid device type \"\(value)\" specified.")
      }
      parsed.type = type
    case "mute":
      guard let mode = MuteMode(rawValue: value) else {
        throw UsageError("Invalid mute operation type \"\(value)\" specified.")
      }
      parsed.muteMode = mode
    case "id":
      guard let id = UInt32(value) else {
        throw UsageError("Invalid device id \"\(value)\" specified.")
      }
      parsed.selection = .id(id)
      parsed.basicCommand = .set
    case "uid":
      parsed.selection = .uid(value)
      parsed.basicCommand = .set
    case "name":
      parsed.selection = .name(value)
      parsed.basicCommand = .set
    default:
      break
    }
  }

  private func printHelp(toStandardError: Bool = false) {
    let help = """
      Usage: audiosource [options]

      Options:
        -a, --all              Show all audio devices
        -c, --current          Show the current audio device
        -f, --format <format>  Output format: human, cli, json (default: human)
        -t, --type <type>      Device type: input, output, system, all (default: output)
        -m, --mute <mode>      Set mute state: mute, unmute, toggle
        -n, --next             Cycle to the next audio device
        -p, --previous         Cycle to the previous audio device
        -i, --id <id>          Set the audio device by numeric ID
        -u, --uid <uid>        Set the audio device by UID or UID substring
        -s, --name <name>      Set the audio device by name
        -h, --help             Show this help
        -v, --version          Show the version

      Formats:
        human  Human-readable output.
        cli    Comma-separated device fields: name,type,id,uid
               Muting appends a fifth field: muted (true/false).
        json   JSON objects. Listing emits one object per line; current, set,
               next, previous, and mute emit a single operation result.

      Examples:
        audiosource -a
        audiosource -c -f json
        audiosource -s "MacBook Pro Speakers"
        audiosource -m toggle -t input
        audiosource -m mute -s "MacBook Pro Speakers" -f json
      """

    if toStandardError {
      printToStdErr(help)
    } else {
      print(help)
    }
  }
}
