import CoreAudio
import Foundation

enum AudioDeviceType: String, CaseIterable, Sendable {
  case input
  case output
  case system
  case all

  var displayName: String { rawValue }
}

enum OutputFormat: String, Sendable {
  case human
  case cli
  case json
}

enum MuteMode: String, Sendable {
  case mute
  case unmute
  case toggle
}

enum Selection: Sendable {
  case id(AudioDeviceID)
  case uid(String)
  case name(String)
}

struct AudioDevice: Sendable, Equatable {
  let id: AudioDeviceID
  let uid: String
  let name: String
  let isInput: Bool
  let isOutput: Bool
}

struct DevicePayload: Encodable, Sendable {
  let name: String
  let type: String
  let id: String
  let uid: String
  let muted: Bool?
}

struct OperationReport: Encodable, Sendable {
  let status: String
  let action: String
  let devices: [DevicePayload]
  let error: String?
}

enum AudioSourceError: Error, CustomStringConvertible {
  case currentDeviceNotFound(AudioDeviceType)
  case nextDeviceNotFound(AudioDeviceType)
  case deviceNamedNotFound(String, AudioDeviceType?)
  case deviceUIDNotFound(String, AudioDeviceType?)
  case deviceIDNotFound(AudioDeviceID)
  case deviceHasNoStreams(AudioDevice)
  case deviceToMuteNotFound
  case notAnInputDevice(AudioDevice)
  case notAnOutputDevice(AudioDevice)
  case cannotBeMuted(AudioDevice)
  case systemCannotBeMuted
  case coreAudio(String, OSStatus)

  var description: String {
    switch self {
    case .currentDeviceNotFound(let type):
      return "Could not find the current audio device of type \(type.displayName).  Nothing was changed."
    case .nextDeviceNotFound(let type):
      return "Could not find the next audio device of type \(type.displayName).  Nothing was changed."
    case .deviceNamedNotFound(let name, let type):
      if let type {
        return
          "Could not find an audio device named \"\(name)\" of type \(type.displayName).  Nothing was changed."
      }
      return "Could not find an audio device named \"\(name)\".  Nothing was changed."
    case .deviceUIDNotFound(let uid, let type):
      if let type {
        return
          "Could not find an audio device with UID \"\(uid)\" of type \(type.displayName).  Nothing was changed."
      }
      return "Could not find an audio device with UID \"\(uid)\".  Nothing was changed."
    case .deviceIDNotFound(let id):
      return "Could not find an audio device with ID \(id).  Nothing was changed."
    case .deviceHasNoStreams(let device):
      return "Audio device \"\(device.name)\" has no input or output streams.  Nothing was changed."
    case .deviceToMuteNotFound:
      return "Could not find an audio device to mute.  Nothing was changed."
    case .notAnInputDevice(let device):
      return "Audio device \"\(device.name)\" is not an input device and may not be muted."
    case .notAnOutputDevice(let device):
      return "Audio device \"\(device.name)\" is not an output device and may not be muted."
    case .cannotBeMuted(let device):
      return "Audio device \"\(device.name)\" may not be muted."
    case .systemCannotBeMuted:
      return "audio device \"system\" may not be muted"
    case .coreAudio(let operation, let status):
      return "Failed to \(operation). Error: \(status) (0x\(String(status, radix: 16, uppercase: true)))"
    }
  }
}
