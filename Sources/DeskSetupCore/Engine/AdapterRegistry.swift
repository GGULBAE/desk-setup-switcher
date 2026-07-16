import Foundation

public enum AdapterRegistryError: Error, Hashable, Sendable {
  case duplicateAdapter(SettingGroup)
}

extension AdapterRegistryError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .duplicateAdapter(let group):
      "More than one adapter was registered for the \(group.rawValue) settings group."
    }
  }
}

/// An immutable registry keeps adapter lookup deterministic for the lifetime of an apply engine.
public struct AdapterRegistry: Sendable {
  private let adapters: [SettingGroup: any SystemSettingsAdapter]

  public init() {
    adapters = [:]
  }

  public init(_ adapters: [any SystemSettingsAdapter]) throws {
    var registered: [SettingGroup: any SystemSettingsAdapter] = [:]

    for adapter in adapters {
      guard registered[adapter.group] == nil else {
        throw AdapterRegistryError.duplicateAdapter(adapter.group)
      }
      registered[adapter.group] = adapter
    }

    self.adapters = registered
  }

  public func adapter(for group: SettingGroup) -> (any SystemSettingsAdapter)? {
    adapters[group]
  }

  public var registeredGroups: [SettingGroup] {
    SettingGroup.safeApplicationSequence.filter { adapters[$0] != nil }
  }
}

extension SettingGroup {
  /// Low-dependency groups are applied first. Network is last so rollback
  /// restores connectivity before reversing display and audio changes.
  public static var safeApplicationSequence: [SettingGroup] {
    [.input, .audio, .display, .network]
  }

  public var safeApplicationOrder: Int {
    switch self {
    case .input: 0
    case .audio: 1
    case .display: 2
    case .network: 3
    }
  }
}
