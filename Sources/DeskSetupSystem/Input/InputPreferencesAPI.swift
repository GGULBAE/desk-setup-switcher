import Foundation
import IOKit
import IOKit.hidsystem

public enum InputPreferenceKey: String, Codable, CaseIterable, Hashable, Sendable {
  case pointerSpeed = "com.apple.mouse.scaling"
  case naturalScrolling = "com.apple.swipescrolldirection"
  case keyRepeatInterval = "KeyRepeat"
  case initialKeyRepeatDelay = "InitialKeyRepeat"
  case standardFunctionKeys = "com.apple.keyboard.fnState"
}

public enum InputPreferenceValue: Codable, Hashable, Sendable {
  case boolean(Bool)
  case number(Double)

  var boolValue: Bool? {
    guard case .boolean(let value) = self else { return nil }
    return value
  }

  var numberValue: Double? {
    guard case .number(let value) = self else { return nil }
    return value
  }
}

public protocol InputPreferencesAPI: Sendable {
  func value(for key: InputPreferenceKey) -> InputPreferenceValue?
  func setValue(_ value: InputPreferenceValue?, for key: InputPreferenceKey) throws
  func runtimeNanoseconds(for key: InputPreferenceKey) -> Int64?
  func setRuntimeNanoseconds(_ value: Int64, for key: InputPreferenceKey) throws
}

public enum InputPreferencesAPIError: LocalizedError, Sendable {
  case synchronizationFailed
  case runtimeUnavailable

  public var errorDescription: String? {
    switch self {
    case .synchronizationFailed:
      "macOS did not synchronize the global input preference."
    case .runtimeUnavailable:
      "The active keyboard repeat setting could not be accessed."
    }
  }
}

/// Uses the public CFPreferences API with macOS global preference keys whose stability
/// is not documented by Apple. The adapter therefore reports these controls as experimental.
public struct CFPreferencesInputPreferencesAPI: InputPreferencesAPI {
  public init() {}

  public func value(for key: InputPreferenceKey) -> InputPreferenceValue? {
    guard
      let value = CFPreferencesCopyValue(
        key.rawValue as CFString,
        kCFPreferencesAnyApplication,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
      )
    else {
      return nil
    }

    let typeID = CFGetTypeID(value)
    if typeID == CFBooleanGetTypeID(), let boolean = value as? Bool {
      return .boolean(boolean)
    }
    if typeID == CFNumberGetTypeID(), let number = value as? NSNumber {
      return .number(number.doubleValue)
    }
    return nil
  }

  public func setValue(_ value: InputPreferenceValue?, for key: InputPreferenceKey) throws {
    let propertyValue: CFPropertyList?
    switch value {
    case .boolean(let boolean):
      propertyValue = boolean as CFBoolean
    case .number(let number):
      propertyValue = number as CFNumber
    case nil:
      propertyValue = nil
    }

    CFPreferencesSetValue(
      key.rawValue as CFString,
      propertyValue,
      kCFPreferencesAnyApplication,
      kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost
    )
    guard
      CFPreferencesSynchronize(
        kCFPreferencesAnyApplication,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
      )
    else {
      throw InputPreferencesAPIError.synchronizationFailed
    }
  }

  public func runtimeNanoseconds(for key: InputPreferenceKey) -> Int64? {
    try? withRuntimeConnection(for: key) { connection, runtimeKey in
      var value: Unmanaged<CFTypeRef>?
      guard IOHIDCopyCFTypeParameter(connection, runtimeKey, &value) == KERN_SUCCESS,
        let result = value?.takeRetainedValue(),
        CFGetTypeID(result) == CFNumberGetTypeID(),
        let number = result as? NSNumber,
        number.doubleValue.isFinite,
        number.doubleValue.rounded(.towardZero) == number.doubleValue,
        number.doubleValue > 0,
        number.doubleValue < Double(Int64.max)
      else { throw InputPreferencesAPIError.runtimeUnavailable }
      return number.int64Value
    }
  }

  public func setRuntimeNanoseconds(_ value: Int64, for key: InputPreferenceKey) throws {
    guard value > 0 else { throw InputPreferencesAPIError.runtimeUnavailable }
    try withRuntimeConnection(for: key) { connection, runtimeKey in
      guard IOHIDSetCFTypeParameter(connection, runtimeKey, NSNumber(value: value)) == KERN_SUCCESS
      else { throw InputPreferencesAPIError.runtimeUnavailable }
    }
  }

  private func withRuntimeConnection<T>(
    for key: InputPreferenceKey,
    _ body: (io_connect_t, CFString) throws -> T
  ) throws -> T {
    let runtimeKey: String
    switch key {
    case .keyRepeatInterval: runtimeKey = kIOHIDKeyRepeatKey
    case .initialKeyRepeatDelay: runtimeKey = kIOHIDInitialKeyRepeatKey
    case .pointerSpeed, .naturalScrolling, .standardFunctionKeys:
      throw InputPreferencesAPIError.runtimeUnavailable
    }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != 0 else { throw InputPreferencesAPIError.runtimeUnavailable }
    defer { IOObjectRelease(service) }
    var connection: io_connect_t = 0
    guard
      IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        == KERN_SUCCESS
    else { throw InputPreferencesAPIError.runtimeUnavailable }
    defer { IOServiceClose(connection) }
    return try body(connection, runtimeKey as CFString)
  }
}

/// Global repeat values use 60 Hz ticks; the public HID parameters use nanoseconds.
/// This mapping remains experimental together with the undocumented global keys.
enum KeyboardRepeatTiming {
  static func nanoseconds(for value: Double) -> Int64 {
    Int64((value * 1_000_000_000 / 60).rounded())
  }

  static func ticks(for nanoseconds: Int64) -> Double {
    let value = Double(nanoseconds) * 60 / 1_000_000_000
    // Preserve imported fractional values, but remove sub-nanosecond roundoff
    // for native integral steps so Capture does not dirty an unchanged profile.
    return abs(value - value.rounded()) < 0.000_001 ? value.rounded() : value
  }
}
