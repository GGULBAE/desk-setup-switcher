import Foundation

public enum SettingGroup: String, Codable, CaseIterable, Hashable, Sendable {
  case display
  case audio
  case network
  case input
}

public struct SettingOption<Value>: Codable, Hashable, Sendable
where Value: Codable & Hashable & Sendable {
  public var isIncluded: Bool
  public var value: Value

  public init(isIncluded: Bool = true, value: Value) {
    self.isIncluded = isIncluded
    self.value = value
  }
}

public struct SettingGroupConfiguration<Value>: Codable, Hashable, Sendable
where Value: Codable & Hashable & Sendable {
  public var isIncluded: Bool
  public var value: Value

  public init(isIncluded: Bool = true, value: Value) {
    self.isIncluded = isIncluded
    self.value = value
  }
}

public struct DisplayIdentity: Codable, Hashable, Sendable {
  public var uuid: UUID?
  public var vendorID: UInt32?
  public var modelID: UInt32?
  public var serialNumber: UInt32?
  public var productName: String?
  public var isBuiltIn: Bool

  public init(
    uuid: UUID? = nil,
    vendorID: UInt32? = nil,
    modelID: UInt32? = nil,
    serialNumber: UInt32? = nil,
    productName: String? = nil,
    isBuiltIn: Bool = false
  ) {
    self.uuid = uuid
    self.vendorID = vendorID
    self.modelID = modelID
    self.serialNumber = serialNumber
    self.productName = productName
    self.isBuiltIn = isBuiltIn
  }
}

public struct DisplayPoint: Codable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

public struct DisplayMode: Codable, Hashable, Sendable {
  public var width: Int
  public var height: Int
  public var pixelWidth: Int
  public var pixelHeight: Int
  public var refreshRate: Double

  public init(
    width: Int,
    height: Int,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    refreshRate: Double
  ) {
    self.width = width
    self.height = height
    self.pixelWidth = pixelWidth ?? width
    self.pixelHeight = pixelHeight ?? height
    self.refreshRate = refreshRate
  }

  public var hasDistinctPixelDimensions: Bool {
    pixelWidth != width || pixelHeight != height
  }
}

/// Compares persisted display modes with modes reported by the current display session.
///
/// Core Graphics can report the same nominal refresh rate with small floating-point
/// differences (for example, 59.94 Hz and 60 Hz). Logical and pixel dimensions must
/// still match exactly.
public struct DisplayModeMatcher: Sendable {
  public static let refreshRateTolerance = 0.1

  public init() {}

  public func matches(_ lhs: DisplayMode, _ rhs: DisplayMode) -> Bool {
    lhs.width == rhs.width && lhs.height == rhs.height
      && lhs.pixelWidth == rhs.pixelWidth && lhs.pixelHeight == rhs.pixelHeight
      && abs(lhs.refreshRate - rhs.refreshRate) <= Self.refreshRateTolerance
  }

  /// Returns the session-reported mode that represents the desired persisted mode.
  public func match<S: Sequence>(
    _ desired: DisplayMode,
    among candidates: S
  ) -> DisplayMode? where S.Element == DisplayMode {
    candidates.first { matches($0, desired) }
  }

  /// Removes equivalent modes while preserving the first session-reported value and order.
  public func deduplicated<S: Sequence>(_ modes: S) -> [DisplayMode]
  where S.Element == DisplayMode {
    var unique: [DisplayMode] = []
    for mode in modes where match(mode, among: unique) == nil {
      unique.append(mode)
    }
    return unique
  }
}

public enum DisplayMirroring: Codable, Hashable, Sendable {
  case extended
  case mirrors(DisplayIdentity)
}

public struct DisplayTargetSettings: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var identity: DisplayIdentity
  public var isPrimary: SettingOption<Bool>
  public var origin: SettingOption<DisplayPoint>
  public var mirroring: SettingOption<DisplayMirroring>
  public var mode: SettingOption<DisplayMode>
  public var rotationDegrees: SettingOption<Int>
  public var isActive: SettingOption<Bool>

  public init(
    id: UUID = UUID(),
    identity: DisplayIdentity,
    isPrimary: SettingOption<Bool>,
    origin: SettingOption<DisplayPoint>,
    mirroring: SettingOption<DisplayMirroring>,
    mode: SettingOption<DisplayMode>,
    rotationDegrees: SettingOption<Int>,
    isActive: SettingOption<Bool>
  ) {
    self.id = id
    self.identity = identity
    self.isPrimary = isPrimary
    self.origin = origin
    self.mirroring = mirroring
    self.mode = mode
    self.rotationDegrees = rotationDegrees
    self.isActive = isActive
  }
}

public struct DisplayProfileSettings: Codable, Hashable, Sendable {
  public var displays: [DisplayTargetSettings]

  public init(displays: [DisplayTargetSettings] = []) {
    self.displays = displays
  }
}

public struct AudioProfileSettings: Codable, Hashable, Sendable {
  public var defaultInputUID: SettingOption<String?>
  public var defaultOutputUID: SettingOption<String?>
  public var systemOutputUID: SettingOption<String?>
  public var inputVolume: SettingOption<Double?>
  public var outputVolume: SettingOption<Double?>
  public var outputMuted: SettingOption<Bool?>

  public init(
    defaultInputUID: SettingOption<String?> = .init(isIncluded: false, value: nil),
    defaultOutputUID: SettingOption<String?> = .init(isIncluded: false, value: nil),
    systemOutputUID: SettingOption<String?> = .init(isIncluded: false, value: nil),
    inputVolume: SettingOption<Double?> = .init(isIncluded: false, value: nil),
    outputVolume: SettingOption<Double?> = .init(isIncluded: false, value: nil),
    outputMuted: SettingOption<Bool?> = .init(isIncluded: false, value: nil)
  ) {
    self.defaultInputUID = defaultInputUID
    self.defaultOutputUID = defaultOutputUID
    self.systemOutputUID = systemOutputUID
    self.inputVolume = inputVolume
    self.outputVolume = outputVolume
    self.outputMuted = outputMuted
  }

  private enum CodingKeys: String, CodingKey {
    case defaultInputUID
    case defaultOutputUID
    case systemOutputUID
    case inputVolume
    case outputVolume
    case outputMuted
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    defaultInputUID =
      try container.decodeIfPresent(
        SettingOption<String?>.self,
        forKey: .defaultInputUID
      ) ?? .init(isIncluded: false, value: nil)
    defaultOutputUID =
      try container.decodeIfPresent(
        SettingOption<String?>.self,
        forKey: .defaultOutputUID
      ) ?? .init(isIncluded: false, value: nil)
    systemOutputUID =
      try container.decodeIfPresent(
        SettingOption<String?>.self,
        forKey: .systemOutputUID
      ) ?? .init(isIncluded: false, value: nil)
    inputVolume =
      try container.decodeIfPresent(
        SettingOption<Double?>.self,
        forKey: .inputVolume
      ) ?? .init(isIncluded: false, value: nil)
    outputVolume =
      try container.decodeIfPresent(
        SettingOption<Double?>.self,
        forKey: .outputVolume
      ) ?? .init(isIncluded: false, value: nil)
    outputMuted =
      try container.decodeIfPresent(
        SettingOption<Bool?>.self,
        forKey: .outputMuted
      ) ?? .init(isIncluded: false, value: nil)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(defaultInputUID, forKey: .defaultInputUID)
    try container.encode(defaultOutputUID, forKey: .defaultOutputUID)
    try container.encode(systemOutputUID, forKey: .systemOutputUID)
    try container.encode(inputVolume, forKey: .inputVolume)
    try container.encode(outputVolume, forKey: .outputVolume)
    try container.encode(outputMuted, forKey: .outputMuted)
  }
}

public enum IPv4Configuration: Codable, Hashable, Sendable {
  case dhcp
  case manual(address: String, subnetMask: String, router: String?)
}

public enum NetworkServiceKind: String, Codable, CaseIterable, Hashable, Sendable {
  case ethernet
  case wifi
}

/// A portable service identity assembled from public SystemConfiguration metadata.
/// Runtime service IDs and BSD names are deliberately not persisted as identity.
public struct NetworkServiceIdentity: Codable, Hashable, Sendable {
  public var kind: NetworkServiceKind
  public var serviceName: String
  public var interfaceType: String

  public init(
    kind: NetworkServiceKind,
    serviceName: String,
    interfaceType: String
  ) {
    self.kind = kind
    self.serviceName = serviceName
    self.interfaceType = interfaceType
  }
}

public struct NetworkServiceIPv4Settings: Codable, Hashable, Sendable {
  public var identity: NetworkServiceIdentity
  public var configuration: SettingOption<IPv4Configuration?>

  public init(
    identity: NetworkServiceIdentity,
    configuration: SettingOption<IPv4Configuration?> = .init(
      isIncluded: false,
      value: nil
    )
  ) {
    self.identity = identity
    self.configuration = configuration
  }
}

public struct ProxyConfiguration: Codable, Hashable, Sendable {
  public var enabled: Bool
  public var host: String
  public var port: Int

  public init(enabled: Bool, host: String, port: Int) {
    self.enabled = enabled
    self.host = host
    self.port = port
  }
}

public struct NetworkProfileSettings: Codable, Hashable, Sendable {
  public var wifiPower: SettingOption<Bool?>
  public var wifiSSID: SettingOption<String?>
  public var serviceIPv4: [NetworkServiceIPv4Settings]
  public var ipv4: SettingOption<IPv4Configuration?>
  public var dnsServers: SettingOption<[String]>
  public var webProxy: SettingOption<ProxyConfiguration?>
  public var secureWebProxy: SettingOption<ProxyConfiguration?>

  public init(
    wifiPower: SettingOption<Bool?> = .init(isIncluded: false, value: nil),
    wifiSSID: SettingOption<String?> = .init(isIncluded: false, value: nil),
    serviceIPv4: [NetworkServiceIPv4Settings] = [],
    ipv4: SettingOption<IPv4Configuration?> = .init(isIncluded: false, value: nil),
    dnsServers: SettingOption<[String]> = .init(isIncluded: false, value: []),
    webProxy: SettingOption<ProxyConfiguration?> = .init(isIncluded: false, value: nil),
    secureWebProxy: SettingOption<ProxyConfiguration?> = .init(isIncluded: false, value: nil)
  ) {
    self.wifiPower = wifiPower
    self.wifiSSID = wifiSSID
    self.serviceIPv4 = serviceIPv4
    self.ipv4 = ipv4
    self.dnsServers = dnsServers
    self.webProxy = webProxy
    self.secureWebProxy = secureWebProxy
  }

  private enum CodingKeys: String, CodingKey {
    case wifiPower
    case wifiSSID
    case serviceIPv4
    case ipv4
    case dnsServers
    case webProxy
    case secureWebProxy
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    wifiPower =
      try container.decodeIfPresent(
        SettingOption<Bool?>.self,
        forKey: .wifiPower
      ) ?? .init(isIncluded: false, value: nil)
    wifiSSID =
      try container.decodeIfPresent(
        SettingOption<String?>.self,
        forKey: .wifiSSID
      ) ?? .init(isIncluded: false, value: nil)
    serviceIPv4 =
      try container.decodeIfPresent(
        [NetworkServiceIPv4Settings].self,
        forKey: .serviceIPv4
      ) ?? []
    ipv4 =
      try container.decodeIfPresent(
        SettingOption<IPv4Configuration?>.self,
        forKey: .ipv4
      ) ?? .init(isIncluded: false, value: nil)
    dnsServers =
      try container.decodeIfPresent(
        SettingOption<[String]>.self,
        forKey: .dnsServers
      ) ?? .init(isIncluded: false, value: [])
    webProxy =
      try container.decodeIfPresent(
        SettingOption<ProxyConfiguration?>.self,
        forKey: .webProxy
      ) ?? .init(isIncluded: false, value: nil)
    secureWebProxy =
      try container.decodeIfPresent(
        SettingOption<ProxyConfiguration?>.self,
        forKey: .secureWebProxy
      ) ?? .init(isIncluded: false, value: nil)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(wifiPower, forKey: .wifiPower)
    try container.encode(wifiSSID, forKey: .wifiSSID)
    try container.encode(serviceIPv4, forKey: .serviceIPv4)
    try container.encode(ipv4, forKey: .ipv4)
    try container.encode(dnsServers, forKey: .dnsServers)
    try container.encode(webProxy, forKey: .webProxy)
    try container.encode(secureWebProxy, forKey: .secureWebProxy)
  }
}

public struct InputProfileSettings: Codable, Hashable, Sendable {
  public var pointerSpeed: SettingOption<Double?>
  public var naturalScrolling: SettingOption<Bool?>
  public var keyRepeatInterval: SettingOption<Double?>
  public var initialKeyRepeatDelay: SettingOption<Double?>
  public var useStandardFunctionKeys: SettingOption<Bool?>

  public init(
    pointerSpeed: SettingOption<Double?> = .init(isIncluded: false, value: nil),
    naturalScrolling: SettingOption<Bool?> = .init(isIncluded: false, value: nil),
    keyRepeatInterval: SettingOption<Double?> = .init(isIncluded: false, value: nil),
    initialKeyRepeatDelay: SettingOption<Double?> = .init(isIncluded: false, value: nil),
    useStandardFunctionKeys: SettingOption<Bool?> = .init(isIncluded: false, value: nil)
  ) {
    self.pointerSpeed = pointerSpeed
    self.naturalScrolling = naturalScrolling
    self.keyRepeatInterval = keyRepeatInterval
    self.initialKeyRepeatDelay = initialKeyRepeatDelay
    self.useStandardFunctionKeys = useStandardFunctionKeys
  }
}

public struct ProfileSettings: Codable, Hashable, Sendable {
  public var display: SettingGroupConfiguration<DisplayProfileSettings>
  public var audio: SettingGroupConfiguration<AudioProfileSettings>
  public var network: SettingGroupConfiguration<NetworkProfileSettings>
  public var input: SettingGroupConfiguration<InputProfileSettings>

  public init(
    display: SettingGroupConfiguration<DisplayProfileSettings> = .init(
      isIncluded: false,
      value: .init()
    ),
    audio: SettingGroupConfiguration<AudioProfileSettings> = .init(
      isIncluded: false,
      value: .init()
    ),
    network: SettingGroupConfiguration<NetworkProfileSettings> = .init(
      isIncluded: false,
      value: .init()
    ),
    input: SettingGroupConfiguration<InputProfileSettings> = .init(
      isIncluded: false,
      value: .init()
    )
  ) {
    self.display = display
    self.audio = audio
    self.network = network
    self.input = input
  }

  public func payload(for group: SettingGroup) -> SettingsPayload? {
    switch group {
    case .display where display.isIncluded && display.value.hasIncludedOption:
      return .display(display.value)
    case .audio where audio.isIncluded && audio.value.hasIncludedOption:
      return .audio(audio.value)
    case .network where network.isIncluded && network.value.hasIncludedOption:
      return .network(network.value)
    case .input where input.isIncluded && input.value.hasIncludedOption:
      return .input(input.value)
    default:
      return nil
    }
  }
}

extension DisplayProfileSettings {
  public var hasIncludedOption: Bool {
    displays.contains { display in
      display.isPrimary.isIncluded
        || display.origin.isIncluded
        || display.mirroring.isIncluded
        || display.mode.isIncluded
        || display.rotationDegrees.isIncluded
        || display.isActive.isIncluded
    }
  }
}

extension AudioProfileSettings {
  public var hasIncludedOption: Bool {
    defaultInputUID.isIncluded
      || defaultOutputUID.isIncluded
      || systemOutputUID.isIncluded
      || inputVolume.isIncluded
      || outputVolume.isIncluded
      || outputMuted.isIncluded
  }
}

extension NetworkProfileSettings {
  public var hasIncludedOption: Bool {
    wifiPower.isIncluded
      || wifiSSID.isIncluded
      || serviceIPv4.contains(where: { $0.configuration.isIncluded })
      || ipv4.isIncluded
      || dnsServers.isIncluded
      || webProxy.isIncluded
      || secureWebProxy.isIncluded
  }
}

extension InputProfileSettings {
  public var hasIncludedOption: Bool {
    pointerSpeed.isIncluded
      || naturalScrolling.isIncluded
      || keyRepeatInterval.isIncluded
      || initialKeyRepeatDelay.isIncluded
      || useStandardFunctionKeys.isIncluded
  }
}

public enum SettingsPayload: Codable, Hashable, Sendable {
  case display(DisplayProfileSettings)
  case audio(AudioProfileSettings)
  case network(NetworkProfileSettings)
  case input(InputProfileSettings)

  public var group: SettingGroup {
    switch self {
    case .display: .display
    case .audio: .audio
    case .network: .network
    case .input: .input
    }
  }
}
