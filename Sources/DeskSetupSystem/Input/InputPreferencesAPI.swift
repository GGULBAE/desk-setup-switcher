import Foundation

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
}

public enum InputPreferencesAPIError: LocalizedError, Sendable {
  case synchronizationFailed

  public var errorDescription: String? {
    switch self {
    case .synchronizationFailed:
      "macOS did not synchronize the global input preference."
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
}
