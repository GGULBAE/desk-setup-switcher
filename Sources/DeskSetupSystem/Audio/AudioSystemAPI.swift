import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public enum AudioDefaultDeviceRole: String, Codable, CaseIterable, Hashable, Sendable {
  case input
  case output
  case systemOutput

  var settingKey: String {
    switch self {
    case .input: "defaultInput"
    case .output: "defaultOutput"
    case .systemOutput: "systemOutput"
    }
  }

  var displayName: String {
    switch self {
    case .input: "default input"
    case .output: "default output"
    case .systemOutput: "system output"
    }
  }
}

public struct AudioDeviceDescriptor: Hashable, Identifiable, Sendable {
  public var id: String { uid }

  public let uid: String
  public let name: String
  public let supportsInput: Bool
  public let supportsOutput: Bool

  public init(
    uid: String,
    name: String,
    supportsInput: Bool,
    supportsOutput: Bool
  ) {
    self.uid = uid
    self.name = name
    self.supportsInput = supportsInput
    self.supportsOutput = supportsOutput
  }
}

public enum AudioControlState<Value>: Hashable, Sendable
where Value: Hashable & Sendable {
  case available(value: Value, isSettable: Bool)
  case unsupported
  case unreadable(reason: String)

  public var value: Value? {
    guard case .available(let value, _) = self else { return nil }
    return value
  }

  public var isSettable: Bool {
    guard case .available(_, let isSettable) = self else { return false }
    return isSettable
  }
}

public enum AudioSystemError: Error, Equatable, Sendable {
  case osStatus(operation: String, status: Int32)
  case deviceNotFound(uid: String)
  case deviceHasWrongScope(uid: String, role: AudioDefaultDeviceRole)
  case unsupportedControl(uid: String, key: String)
  case controlNotSettable(uid: String, key: String)
  case invalidVolume(Double)
  case malformedProperty(String)
}

extension AudioSystemError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .osStatus(let operation, let status):
      "Core Audio \(operation) failed with OSStatus \(status)."
    case .deviceNotFound:
      "The saved audio device is not connected."
    case .deviceHasWrongScope(_, let role):
      "The saved audio device cannot be used as the \(role.displayName) device."
    case .unsupportedControl(_, let key):
      "The audio device does not expose a software \(key) control."
    case .controlNotSettable(_, let key):
      "The audio device's \(key) control is read-only."
    case .invalidVolume(let value):
      "The output volume \(value) is outside the supported scalar range."
    case .malformedProperty(let property):
      "Core Audio returned an invalid \(property) property."
    }
  }
}

/// A host-safe boundary around Core Audio. Tests inject a synthetic implementation;
/// the live implementation uses AudioObject property APIs and never opens an input stream.
public protocol AudioSystemAPI: Sendable {
  func devices() throws -> [AudioDeviceDescriptor]
  func defaultDeviceUID(for role: AudioDefaultDeviceRole) throws -> String?
  func outputVolume(forDeviceUID uid: String) throws -> AudioControlState<Double>
  func outputMute(forDeviceUID uid: String) throws -> AudioControlState<Bool>

  func setDefaultDeviceUID(_ uid: String, for role: AudioDefaultDeviceRole) throws
  func setOutputVolume(_ value: Double, forDeviceUID uid: String) throws
  func setOutputMute(_ value: Bool, forDeviceUID uid: String) throws
}

public enum AudioOperationCommand: Codable, Hashable, Sendable {
  case setDefaultDevice(role: AudioDefaultDeviceRole, uid: String)
  case setOutputVolume(deviceUID: String, value: Double)
  case setOutputMute(deviceUID: String, value: Bool)
}
