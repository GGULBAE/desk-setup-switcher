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
  public var outputVolume: SettingOption<Double?>
  public var outputMuted: SettingOption<Bool?>

  public init(
    defaultInputUID: SettingOption<String?> = .init(isIncluded: false, value: nil),
    defaultOutputUID: SettingOption<String?> = .init(isIncluded: false, value: nil),
    systemOutputUID: SettingOption<String?> = .init(isIncluded: false, value: nil),
    outputVolume: SettingOption<Double?> = .init(isIncluded: false, value: nil),
    outputMuted: SettingOption<Bool?> = .init(isIncluded: false, value: nil)
  ) {
    self.defaultInputUID = defaultInputUID
    self.defaultOutputUID = defaultOutputUID
    self.systemOutputUID = systemOutputUID
    self.outputVolume = outputVolume
    self.outputMuted = outputMuted
  }
}

public enum IPv4Configuration: Codable, Hashable, Sendable {
  case dhcp
  case manual(address: String, subnetMask: String, router: String?)
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
  public var ipv4: SettingOption<IPv4Configuration?>
  public var dnsServers: SettingOption<[String]>
  public var webProxy: SettingOption<ProxyConfiguration?>
  public var secureWebProxy: SettingOption<ProxyConfiguration?>

  public init(
    wifiPower: SettingOption<Bool?> = .init(isIncluded: false, value: nil),
    wifiSSID: SettingOption<String?> = .init(isIncluded: false, value: nil),
    ipv4: SettingOption<IPv4Configuration?> = .init(isIncluded: false, value: nil),
    dnsServers: SettingOption<[String]> = .init(isIncluded: false, value: []),
    webProxy: SettingOption<ProxyConfiguration?> = .init(isIncluded: false, value: nil),
    secureWebProxy: SettingOption<ProxyConfiguration?> = .init(isIncluded: false, value: nil)
  ) {
    self.wifiPower = wifiPower
    self.wifiSSID = wifiSSID
    self.ipv4 = ipv4
    self.dnsServers = dnsServers
    self.webProxy = webProxy
    self.secureWebProxy = secureWebProxy
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
      || outputVolume.isIncluded
      || outputMuted.isIncluded
  }
}

extension NetworkProfileSettings {
  public var hasIncludedOption: Bool {
    wifiPower.isIncluded
      || wifiSSID.isIncluded
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
