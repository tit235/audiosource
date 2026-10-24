import CoreAudio
import Foundation

final class CommandCenter {
  private let manager = AudioDeviceManager()

  private struct ReportedDevice {
    let name: String
    let type: AudioDeviceType
    let id: AudioDeviceID
    let uid: String
    let muted: Bool?

    var payload: DevicePayload {
      DevicePayload(
        name: name, type: type.displayName, id: String(id), uid: uid, muted: muted)
    }

    var cliLine: String {
      var fields = [name, type.displayName, String(id), uid]
      if let muted {
        fields.append(muted ? "true" : "false")
      }
      return fields.joined(separator: ",")
    }
  }

  func showAllDevices(type: AudioDeviceType, format: OutputFormat) {
    switch type {
    case .input:
      outputDevices(manager.devices(of: .input), type: .input, format: format)
    case .output, .system:
      outputDevices(manager.devices(of: .output), type: .output, format: format)
    case .all:
      outputDevices(manager.devices(of: .input), type: .input, format: format)
      outputDevices(manager.devices(of: .output), type: .output, format: format)
    }
  }

  func showCurrentDevice(type: AudioDeviceType, format: OutputFormat) {
    guard let device = manager.currentDevice(of: type) else {
      reportFailure(AudioSourceError.currentDeviceNotFound(type), action: "current", format: format)
    }

    let reported = ReportedDevice(
      name: device.name, type: type, id: device.id, uid: device.uid, muted: nil)

    switch format {
    case .human:
      print(device.name)
    case .cli:
      print(reported.cliLine)
    case .json:
      printJSON(reported.payload)
    }
  }

  func setDevice(selection: Selection, type: AudioDeviceType, format: OutputFormat) {
    do {
      let targets = try setTargets(for: selection, type: type)
      performSet(targets, format: format)
    } catch {
      reportFailure(error, action: "set", format: format)
    }
  }

  func cycleNextDevice(type requestedType: AudioDeviceType?, format: OutputFormat) {
    let type = requestedType ?? .output
    let types: [AudioDeviceType] = type == .all ? [.input, .output, .system] : [type]

    var targets: [(AudioDevice, AudioDeviceType)] = []
    var errors: [String] = []

    for scope in types {
      guard let current = manager.currentDevice(of: scope) else {
        errors.append(describe(AudioSourceError.currentDeviceNotFound(scope)))
        continue
      }

      guard let next = manager.nextDevice(after: current, type: scope) else {
        errors.append(describe(AudioSourceError.nextDeviceNotFound(scope)))
        continue
      }

      do {
        try manager.setDefaultDevice(next, type: scope)
        targets.append((next, scope))
      } catch {
        errors.append(describe(error))
      }
    }

    emit(action: "next", targets: targets, errors: errors, format: format)
  }

  func muteDevice(
    mode: MuteMode, selection: Selection?, type requestedType: AudioDeviceType?,
    format: OutputFormat
  ) {
    var type = requestedType
    var selectedDevice: AudioDevice?

    if let selection {
      do {
        selectedDevice = try resolveDevice(
          selection: selection, type: (type == nil || type == .all) ? nil : type)
      } catch {
        reportFailure(error, action: "mute", format: format)
      }
    }

    if type == nil {
      if let selectedDevice {
        if selectedDevice.isOutput {
          type = .output
        } else if selectedDevice.isInput {
          type = .input
        } else {
          reportFailure(AudioSourceError.deviceToMuteNotFound, action: "mute", format: format)
        }
      } else {
        type = .output
      }
    }

    guard let type else { return }

    if type == .system {
      reportFailure(AudioSourceError.systemCannotBeMuted, action: "mute", format: format)
    }

    var targets: [(AudioDevice, AudioDeviceType)] = []

    if type == .all {
      if let selectedDevice {
        if selectedDevice.isInput { targets.append((selectedDevice, .input)) }
        if selectedDevice.isOutput { targets.append((selectedDevice, .output)) }
      } else {
        if let input = manager.currentDevice(of: .input) { targets.append((input, .input)) }
        if let output = manager.currentDevice(of: .output) { targets.append((output, .output)) }
      }

      if targets.isEmpty {
        reportFailure(AudioSourceError.deviceToMuteNotFound, action: "mute", format: format)
      }
    } else {
      let device = selectedDevice ?? manager.currentDevice(of: type)

      guard let device else {
        reportFailure(
          AudioSourceError.currentDeviceNotFound(type), action: "mute", format: format)
      }

      if type == .input && !device.isInput {
        reportFailure(AudioSourceError.notAnInputDevice(device), action: "mute", format: format)
      }
      if type == .output && !device.isOutput {
        reportFailure(AudioSourceError.notAnOutputDevice(device), action: "mute", format: format)
      }

      targets = [(device, type)]
    }

    var reportedDevices: [ReportedDevice] = []
    var errors: [String] = []

    for (device, scope) in targets {
      do {
        let muted = try manager.setMute(device, type: scope, mode: mode)
        reportedDevices.append(
          ReportedDevice(
            name: device.name, type: scope, id: device.id, uid: device.uid, muted: muted))
      } catch {
        errors.append(describe(error))
      }
    }

    emit(action: "mute", reportedDevices: reportedDevices, errors: errors, format: format)
  }

  private func setTargets(
    for selection: Selection, type: AudioDeviceType
  ) throws -> [(AudioDevice, AudioDeviceType)] {
    if type != .all {
      let device = try resolveDevice(selection: selection, type: type)
      return [(device, type)]
    }

    switch selection {
    case .id(let id):
      guard let device = manager.device(withID: id) else {
        throw AudioSourceError.deviceIDNotFound(id)
      }

      var targets: [(AudioDevice, AudioDeviceType)] = []
      if device.isInput { targets.append((device, .input)) }
      if device.isOutput {
        targets.append((device, .output))
        targets.append((device, .system))
      }

      guard !targets.isEmpty else {
        throw AudioSourceError.deviceHasNoStreams(device)
      }
      return targets

    case .name(let name):
      return try allTypeTargets { scope in
        manager.findDevice(name: name, type: scope)
      } notFound: {
        AudioSourceError.deviceNamedNotFound(name, .all)
      }

    case .uid(let uid):
      return try allTypeTargets { scope in
        manager.findDevice(uidSubstring: uid, type: scope)
      } notFound: {
        AudioSourceError.deviceUIDNotFound(uid, .all)
      }
    }
  }

  private func allTypeTargets(
    lookup: (AudioDeviceType) -> AudioDevice?,
    notFound: () -> AudioSourceError
  ) throws -> [(AudioDevice, AudioDeviceType)] {
    var targets: [(AudioDevice, AudioDeviceType)] = []

    for scope in [AudioDeviceType.input, .output, .system] {
      if let device = lookup(scope) {
        targets.append((device, scope))
      }
    }

    guard !targets.isEmpty else {
      throw notFound()
    }

    return targets
  }

  private func resolveDevice(selection: Selection, type: AudioDeviceType?) throws -> AudioDevice {
    switch selection {
    case .id(let id):
      guard let device = manager.device(withID: id) else {
        throw AudioSourceError.deviceIDNotFound(id)
      }
      return device
    case .name(let name):
      guard let device = manager.findDevice(name: name, type: type) else {
        throw AudioSourceError.deviceNamedNotFound(name, type)
      }
      return device
    case .uid(let uid):
      guard let device = manager.findDevice(uidSubstring: uid, type: type) else {
        throw AudioSourceError.deviceUIDNotFound(uid, type)
      }
      return device
    }
  }

  private func performSet(
    _ targets: [(AudioDevice, AudioDeviceType)], format: OutputFormat
  ) {
    var reportedDevices: [ReportedDevice] = []
    var errors: [String] = []

    for (device, scope) in targets {
      do {
        try manager.setDefaultDevice(device, type: scope)
        reportedDevices.append(
          ReportedDevice(
            name: device.name, type: scope, id: device.id, uid: device.uid, muted: nil))
      } catch {
        errors.append(describe(error))
      }
    }

    emit(action: "set", reportedDevices: reportedDevices, errors: errors, format: format)
  }

  private func emit(
    action: String, targets: [(AudioDevice, AudioDeviceType)], errors: [String],
    format: OutputFormat
  ) {
    let reportedDevices = targets.map { device, scope in
      ReportedDevice(
        name: device.name, type: scope, id: device.id, uid: device.uid, muted: nil)
    }
    emit(action: action, reportedDevices: reportedDevices, errors: errors, format: format)
  }

  private func emit(
    action: String, reportedDevices: [ReportedDevice], errors: [String], format: OutputFormat
  ) {
    let status = errors.isEmpty ? "success" : "error"

    switch format {
    case .human:
      for device in reportedDevices {
        print(humanMessage(action: action, device: device))
      }
      for message in errors {
        printToStdErr(message)
      }
    case .cli:
      for device in reportedDevices {
        print(device.cliLine)
      }
      for message in errors {
        printToStdErr(message)
      }
    case .json:
      printJSON(
        OperationReport(
          status: status,
          action: action,
          devices: reportedDevices.map(\.payload),
          error: errors.isEmpty ? nil : errors.joined(separator: "\n")
        ))
    }

    if !errors.isEmpty {
      exit(1)
    }
  }

  private func humanMessage(action: String, device: ReportedDevice) -> String {
    switch action {
    case "mute":
      let state = device.muted == true ? "muted" : "unmuted"
      return "Setting device \(device.name) to \(state)"
    default:
      return "\(device.type.displayName) audio device set to \"\(device.name)\""
    }
  }

  private func outputDevices(
    _ devices: [AudioDevice], type: AudioDeviceType, format: OutputFormat
  ) {
    for device in devices {
      let reported = ReportedDevice(
        name: device.name, type: type, id: device.id, uid: device.uid, muted: nil)

      switch format {
      case .human:
        print(device.name)
      case .cli:
        print(reported.cliLine)
      case .json:
        printJSON(reported.payload)
      }
    }
  }

  private func reportFailure(_ error: Error, action: String, format: OutputFormat) -> Never {
    emit(action: action, reportedDevices: [], errors: [describe(error)], format: format)
    exit(1)
  }

  private func describe(_ error: Error) -> String {
    if let error = error as? AudioSourceError {
      return error.description
    }
    return error.localizedDescription
  }

  private func printJSON<T: Encodable>(_ value: T) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]

      guard
        let jsonString = try String(
          data: encoder.encode(value),
          encoding: .utf8
        )
      else {
        printToStdErr("Error converting JSON data to string")
        exit(1)
      }

      print(jsonString)
    } catch {
      printToStdErr("Error encoding JSON: \(error)")
      exit(1)
    }
  }
}
