import CoreAudio
import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// Official Core Audio property access only. Reading input-device metadata does not
/// start capture and therefore does not request microphone recording permission.
public struct CoreAudioSystemAPI: AudioSystemAPI {
  public init() {}

  public func devices() throws -> [AudioDeviceDescriptor] {
    try deviceIDs().map { deviceID in
      AudioDeviceDescriptor(
        uid: try stringProperty(
          objectID: deviceID,
          selector: kAudioDevicePropertyDeviceUID,
          propertyName: "device UID"
        ),
        name: try stringProperty(
          objectID: deviceID,
          selector: kAudioObjectPropertyName,
          propertyName: "device name"
        ),
        supportsInput: try hasStreams(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput),
        supportsOutput: try hasStreams(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput)
      )
    }.sorted { $0.uid < $1.uid }
  }

  public func defaultDeviceUID(for role: AudioDefaultDeviceRole) throws -> String? {
    var address = propertyAddress(selector: selector(for: role))
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )
    try requireNoError(status, operation: "read \(role.displayName) device")
    guard deviceID != kAudioObjectUnknown else { return nil }
    return try stringProperty(
      objectID: deviceID,
      selector: kAudioDevicePropertyDeviceUID,
      propertyName: "device UID"
    )
  }

  public func outputVolume(forDeviceUID uid: String) throws -> AudioControlState<Double> {
    let deviceID = try outputDeviceID(for: uid)
    var address = propertyAddress(
      selector: kAudioDevicePropertyVolumeScalar,
      scope: kAudioObjectPropertyScopeOutput
    )
    guard AudioObjectHasProperty(deviceID, &address) else { return .unsupported }

    let settable = try isSettable(objectID: deviceID, address: &address, key: "volume")
    var value = Float32.zero
    var size = UInt32(MemoryLayout<Float32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
    guard status == noErr else {
      return .unreadable(reason: "Core Audio could not read software volume (OSStatus \(status)).")
    }
    return .available(value: Double(value), isSettable: settable)
  }

  public func outputMute(forDeviceUID uid: String) throws -> AudioControlState<Bool> {
    let deviceID = try outputDeviceID(for: uid)
    var address = propertyAddress(
      selector: kAudioDevicePropertyMute,
      scope: kAudioObjectPropertyScopeOutput
    )
    guard AudioObjectHasProperty(deviceID, &address) else { return .unsupported }

    let settable = try isSettable(objectID: deviceID, address: &address, key: "mute")
    var value = UInt32.zero
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
    guard status == noErr else {
      return .unreadable(reason: "Core Audio could not read software mute (OSStatus \(status)).")
    }
    return .available(value: value != 0, isSettable: settable)
  }

  public func setDefaultDeviceUID(
    _ uid: String,
    for role: AudioDefaultDeviceRole
  ) throws {
    let descriptor = try descriptor(for: uid)
    switch role {
    case .input where !descriptor.supportsInput:
      throw AudioSystemError.deviceHasWrongScope(uid: uid, role: role)
    case .output where !descriptor.supportsOutput,
      .systemOutput where !descriptor.supportsOutput:
      throw AudioSystemError.deviceHasWrongScope(uid: uid, role: role)
    default:
      break
    }

    let deviceID = try deviceID(for: uid)
    var address = propertyAddress(selector: selector(for: role))
    guard
      try isSettable(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        address: &address,
        key: role.settingKey
      )
    else {
      throw AudioSystemError.controlNotSettable(uid: uid, key: role.settingKey)
    }

    var mutableDeviceID = deviceID
    let status = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      UInt32(MemoryLayout<AudioDeviceID>.size),
      &mutableDeviceID
    )
    try requireNoError(status, operation: "set \(role.displayName) device")
  }

  public func setOutputVolume(_ value: Double, forDeviceUID uid: String) throws {
    guard value.isFinite, (0.0...1.0).contains(value) else {
      throw AudioSystemError.invalidVolume(value)
    }
    let deviceID = try outputDeviceID(for: uid)
    var address = propertyAddress(
      selector: kAudioDevicePropertyVolumeScalar,
      scope: kAudioObjectPropertyScopeOutput
    )
    guard AudioObjectHasProperty(deviceID, &address) else {
      throw AudioSystemError.unsupportedControl(uid: uid, key: "volume")
    }
    guard try isSettable(objectID: deviceID, address: &address, key: "volume") else {
      throw AudioSystemError.controlNotSettable(uid: uid, key: "volume")
    }

    var scalar = Float32(value)
    let status = AudioObjectSetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<Float32>.size),
      &scalar
    )
    try requireNoError(status, operation: "set output volume")
  }

  public func setOutputMute(_ value: Bool, forDeviceUID uid: String) throws {
    let deviceID = try outputDeviceID(for: uid)
    var address = propertyAddress(
      selector: kAudioDevicePropertyMute,
      scope: kAudioObjectPropertyScopeOutput
    )
    guard AudioObjectHasProperty(deviceID, &address) else {
      throw AudioSystemError.unsupportedControl(uid: uid, key: "mute")
    }
    guard try isSettable(objectID: deviceID, address: &address, key: "mute") else {
      throw AudioSystemError.controlNotSettable(uid: uid, key: "mute")
    }

    var mute = UInt32(value ? 1 : 0)
    let status = AudioObjectSetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &mute
    )
    try requireNoError(status, operation: "set output mute")
  }

  private func deviceIDs() throws -> [AudioDeviceID] {
    var address = propertyAddress(selector: kAudioHardwarePropertyDevices)
    var size = UInt32.zero
    var status = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size
    )
    try requireNoError(status, operation: "enumerate device list size")
    guard size % UInt32(MemoryLayout<AudioDeviceID>.size) == 0 else {
      throw AudioSystemError.malformedProperty("device list")
    }
    guard size > 0 else { return [] }

    var result = [AudioDeviceID](
      repeating: kAudioObjectUnknown,
      count: Int(size) / MemoryLayout<AudioDeviceID>.size
    )
    status = result.withUnsafeMutableBytes { buffer in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        buffer.baseAddress!
      )
    }
    try requireNoError(status, operation: "enumerate devices")
    return result.filter { $0 != kAudioObjectUnknown }
  }

  private func descriptor(for uid: String) throws -> AudioDeviceDescriptor {
    guard let descriptor = try devices().first(where: { $0.uid == uid }) else {
      throw AudioSystemError.deviceNotFound(uid: uid)
    }
    return descriptor
  }

  private func deviceID(for uid: String) throws -> AudioDeviceID {
    for deviceID in try deviceIDs() {
      let candidate = try stringProperty(
        objectID: deviceID,
        selector: kAudioDevicePropertyDeviceUID,
        propertyName: "device UID"
      )
      if candidate == uid { return deviceID }
    }
    throw AudioSystemError.deviceNotFound(uid: uid)
  }

  private func outputDeviceID(for uid: String) throws -> AudioDeviceID {
    let descriptor = try descriptor(for: uid)
    guard descriptor.supportsOutput else {
      throw AudioSystemError.deviceHasWrongScope(uid: uid, role: .output)
    }
    return try deviceID(for: uid)
  }

  private func hasStreams(
    deviceID: AudioDeviceID,
    scope: AudioObjectPropertyScope
  ) throws -> Bool {
    var address = propertyAddress(
      selector: kAudioDevicePropertyStreams,
      scope: scope
    )
    guard AudioObjectHasProperty(deviceID, &address) else { return false }
    var size = UInt32.zero
    let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
    try requireNoError(status, operation: "read device stream scope")
    return size >= UInt32(MemoryLayout<AudioStreamID>.size)
  }

  private func stringProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    propertyName: String
  ) throws -> String {
    var address = propertyAddress(selector: selector)
    guard AudioObjectHasProperty(objectID, &address) else {
      throw AudioSystemError.malformedProperty(propertyName)
    }
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
    try requireNoError(status, operation: "read \(propertyName)")
    guard let value = value?.takeUnretainedValue() else {
      throw AudioSystemError.malformedProperty(propertyName)
    }
    return value as String
  }

  private func isSettable(
    objectID: AudioObjectID,
    address: inout AudioObjectPropertyAddress,
    key: String
  ) throws -> Bool {
    var settable = DarwinBoolean(false)
    let status = AudioObjectIsPropertySettable(objectID, &address, &settable)
    try requireNoError(status, operation: "check \(key) settable state")
    return settable.boolValue
  }

  private func selector(for role: AudioDefaultDeviceRole) -> AudioObjectPropertySelector {
    switch role {
    case .input: kAudioHardwarePropertyDefaultInputDevice
    case .output: kAudioHardwarePropertyDefaultOutputDevice
    case .systemOutput: kAudioHardwarePropertyDefaultSystemOutputDevice
    }
  }

  private func propertyAddress(
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private func requireNoError(_ status: OSStatus, operation: String) throws {
    guard status == noErr else {
      throw AudioSystemError.osStatus(operation: operation, status: status)
    }
  }
}
