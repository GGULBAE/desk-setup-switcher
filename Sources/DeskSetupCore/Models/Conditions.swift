import Foundation

public struct LocationRegion: Codable, Hashable, Sendable {
  public var latitude: Double
  public var longitude: Double
  public var radiusMeters: Double

  public init(latitude: Double, longitude: Double, radiusMeters: Double) {
    self.latitude = latitude
    self.longitude = longitude
    self.radiusMeters = radiusMeters
  }
}

public enum ProfileConditionKind: Codable, Hashable, Sendable {
  case displayConnected(DisplayIdentity)
  case audioInputConnected(uid: String)
  case audioOutputConnected(uid: String)
  case hardwareConnected(identifier: String)
  case wifiSSID(String)
  case ethernetConnected
  case ipAddressOrCIDR(String)
  case location(LocationRegion)
}

public struct ProfileCondition: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var kind: ProfileConditionKind
  public var isInverted: Bool

  public init(id: UUID = UUID(), kind: ProfileConditionKind, isInverted: Bool = false) {
    self.id = id
    self.kind = kind
    self.isInverted = isInverted
  }
}

public enum ConditionMatchMode: String, Codable, Hashable, Sendable {
  case all
  case any
}

public struct ProfileConditionSet: Codable, Hashable, Sendable {
  public var mode: ConditionMatchMode
  public var isInverted: Bool
  public var conditions: [ProfileCondition]

  public init(
    mode: ConditionMatchMode = .all,
    isInverted: Bool = false,
    conditions: [ProfileCondition] = []
  ) {
    self.mode = mode
    self.isInverted = isInverted
    self.conditions = conditions
  }
}

/// Identifies the independent system reader responsible for a family of
/// readiness facts. A failed reader marks its source unavailable so an empty
/// collection or `false` value cannot be mistaken for a successfully observed
/// absence.
public enum ConditionContextSource: String, CaseIterable, Codable, Hashable, Sendable {
  case displays
  case audio
  case network
  case hardware
  case location
}

public struct ConditionContext: Codable, Hashable, Sendable {
  public var displays: Set<DisplayIdentity>
  public var audioInputUIDs: Set<String>
  public var audioOutputUIDs: Set<String>
  public var hardwareIdentifiers: Set<String>
  public var wifiSSID: String?
  public var ethernetConnected: Bool
  public var ipAddresses: Set<String>
  public var location: LocationRegion?
  public var unavailableSources: Set<ConditionContextSource>

  public init(
    displays: Set<DisplayIdentity> = [],
    audioInputUIDs: Set<String> = [],
    audioOutputUIDs: Set<String> = [],
    hardwareIdentifiers: Set<String> = [],
    wifiSSID: String? = nil,
    ethernetConnected: Bool = false,
    ipAddresses: Set<String> = [],
    location: LocationRegion? = nil,
    unavailableSources: Set<ConditionContextSource> = []
  ) {
    self.displays = displays
    self.audioInputUIDs = audioInputUIDs
    self.audioOutputUIDs = audioOutputUIDs
    self.hardwareIdentifiers = hardwareIdentifiers
    self.wifiSSID = wifiSSID
    self.ethernetConnected = ethernetConnected
    self.ipAddresses = ipAddresses
    self.location = location
    self.unavailableSources = unavailableSources
  }

  private enum CodingKeys: String, CodingKey {
    case displays
    case audioInputUIDs
    case audioOutputUIDs
    case hardwareIdentifiers
    case wifiSSID
    case ethernetConnected
    case ipAddresses
    case location
    case unavailableSources
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    displays = try container.decode(Set<DisplayIdentity>.self, forKey: .displays)
    audioInputUIDs = try container.decode(Set<String>.self, forKey: .audioInputUIDs)
    audioOutputUIDs = try container.decode(Set<String>.self, forKey: .audioOutputUIDs)
    hardwareIdentifiers = try container.decode(Set<String>.self, forKey: .hardwareIdentifiers)
    wifiSSID = try container.decodeIfPresent(String.self, forKey: .wifiSSID)
    ethernetConnected = try container.decode(Bool.self, forKey: .ethernetConnected)
    ipAddresses = try container.decode(Set<String>.self, forKey: .ipAddresses)
    location = try container.decodeIfPresent(LocationRegion.self, forKey: .location)
    unavailableSources =
      try container.decodeIfPresent(Set<ConditionContextSource>.self, forKey: .unavailableSources)
      ?? []
  }
}

public struct ConditionItemResult: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var isMatched: Bool
  public var explanation: String

  public init(id: UUID, isMatched: Bool, explanation: String) {
    self.id = id
    self.isMatched = isMatched
    self.explanation = explanation
  }
}

public struct ConditionEvaluation: Codable, Hashable, Sendable {
  public var isMatched: Bool
  public var items: [ConditionItemResult]

  public init(isMatched: Bool, items: [ConditionItemResult]) {
    self.isMatched = isMatched
    self.items = items
  }
}
