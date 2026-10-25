import CoreAudio
import Foundation

struct AudioDeviceManager: Sendable {
  private let systemObject = AudioObjectID(kAudioObjectSystemObject)

  func allDevices() -> [AudioDevice] {
    var address = propertyAddress(kAudioHardwarePropertyDevices)
    var dataSize: UInt32 = 0

    guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
      return []
    }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else { return [] }

    var ids = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
    guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &ids) == noErr else {
      return []
    }

    return ids.compactMap(device(withID:))
  }

  func device(withID id: AudioDeviceID) -> AudioDevice? {
    guard id != AudioDeviceID(kAudioObjectUnknown) else { return nil }

    let name = stringProperty(kAudioDevicePropertyDeviceNameCFString, of: id) ?? ""
    let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id) ?? ""

    return AudioDevice(
      id: id,
      uid: uid,
      name: name,
      isInput: hasStreams(id, scope: kAudioObjectPropertyScopeInput),
      isOutput: hasStreams(id, scope: kAudioObjectPropertyScopeOutput)
    )
  }

  func devices(of type: AudioDeviceType) -> [AudioDevice] {
    allDevices().filter { matches(type: type, device: $0) }
  }

  func currentDevice(of type: AudioDeviceType) -> AudioDevice? {
    let selector: AudioObjectPropertySelector
    switch type {
    case .input:
      selector = kAudioHardwarePropertyDefaultInputDevice
    case .output, .all:
      selector = kAudioHardwarePropertyDefaultOutputDevice
    case .system:
      selector = kAudioHardwarePropertyDefaultSystemOutputDevice
    }

    var address = propertyAddress(selector)
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

    let status = AudioObjectGetPropertyData(
      systemObject, &address, 0, nil, &dataSize, &deviceID)
    guard status == noErr else { return nil }

    return device(withID: deviceID)
  }

  func findDevice(name: String, type: AudioDeviceType?) -> AudioDevice? {
    let filterType = type == .all ? nil : type
    return allDevices().first { device in
      matches(type: filterType, device: device) && device.name == name
    }
  }

  func findDevice(uidSubstring: String, type: AudioDeviceType?) -> AudioDevice? {
    let filterType = type == .all ? nil : type
    return allDevices().first { device in
      matches(type: filterType, device: device) && device.uid.contains(uidSubstring)
    }
  }

  func device(offsetFrom currentDevice: AudioDevice, by offset: Int, type: AudioDeviceType) -> AudioDevice? {
    let eligible = devices(of: type)
    guard !eligible.isEmpty else { return nil }

    guard let index = eligible.firstIndex(where: { $0.id == currentDevice.id }) else {
      return offset >= 0 ? eligible.first : eligible.last
    }

    let count = eligible.count
    let newIndex = ((index + offset) % count + count) % count
    return eligible[newIndex]
  }

  func setDefaultDevice(_ device: AudioDevice, type: AudioDeviceType) throws {
    let selector: AudioObjectPropertySelector

    switch type {
    case .input:
      guard device.isInput else { throw AudioSourceError.notAnInputDevice(device) }
      selector = kAudioHardwarePropertyDefaultInputDevice
    case .output:
      guard device.isOutput else { throw AudioSourceError.notAnOutputDevice(device) }
      selector = kAudioHardwarePropertyDefaultOutputDevice
    case .system:
      guard device.isOutput else { throw AudioSourceError.notAnOutputDevice(device) }
      selector = kAudioHardwarePropertyDefaultSystemOutputDevice
    case .all:
      throw AudioSourceError.coreAudio("set device type \"all\"", OSStatus(kAudioHardwareBadObjectError))
    }

    var address = propertyAddress(selector)
    var deviceID = device.id
    let status = AudioObjectSetPropertyData(
      systemObject, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)

    guard status == noErr else {
      throw AudioSourceError.coreAudio("set \(type.displayName) audio device", status)
    }
  }

  func muteState(of device: AudioDevice, type: AudioDeviceType) throws -> Bool {
    var address = try muteAddress(for: type)
    guard AudioObjectHasProperty(device.id, &address) else {
      throw AudioSourceError.cannotBeMuted(device)
    }

    var muted: UInt32 = 0
    var dataSize = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(device.id, &address, 0, nil, &dataSize, &muted)
    guard status == noErr else {
      throw AudioSourceError.coreAudio("read mute state", status)
    }

    return muted != 0
  }

  @discardableResult
  func setMute(
    _ device: AudioDevice, type: AudioDeviceType, mode: MuteMode
  ) throws -> Bool {
    var address = try muteAddress(for: type)

    guard AudioObjectHasProperty(device.id, &address) else {
      throw AudioSourceError.cannotBeMuted(device)
    }

    var settable = DarwinBoolean(false)
    let settableStatus = AudioObjectIsPropertySettable(device.id, &address, &settable)
    guard settableStatus == noErr, settable.boolValue else {
      throw AudioSourceError.cannotBeMuted(device)
    }

    let muted: Bool
    switch mode {
    case .mute:
      muted = true
    case .unmute:
      muted = false
    case .toggle:
      muted = !(try muteState(of: device, type: type))
    }

    var value: UInt32 = muted ? 1 : 0
    let status = AudioObjectSetPropertyData(
      device.id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)

    guard status == noErr else {
      throw AudioSourceError.coreAudio("set mute state", status)
    }

    return muted
  }

  private func muteAddress(for type: AudioDeviceType) throws -> AudioObjectPropertyAddress {
    let scope: AudioObjectPropertyScope
    switch type {
    case .input:
      scope = kAudioObjectPropertyScopeInput
    case .output:
      scope = kAudioObjectPropertyScopeOutput
    case .system:
      throw AudioSourceError.systemCannotBeMuted
    case .all:
      throw AudioSourceError.coreAudio("set mute state for type \"all\"", OSStatus(kAudioHardwareBadObjectError))
    }

    return AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private func matches(type: AudioDeviceType?, device: AudioDevice) -> Bool {
    switch type {
    case .input:
      return device.isInput
    case .output, .system:
      return device.isOutput
    case .all, nil:
      return true
    }
  }

  private func hasStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
    return status == noErr && dataSize > 0
  }

  private func stringProperty(
    _ selector: AudioObjectPropertySelector, of deviceID: AudioDeviceID
  ) -> String? {
    var address = propertyAddress(selector)
    var value: CFString?
    var dataSize = UInt32(MemoryLayout<CFString?>.size)

    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
    }

    guard status == noErr, let value else { return nil }
    return value as String
  }

  private func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
  }
}
