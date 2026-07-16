import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public enum NetworkAddressFamily: String, Codable, Hashable, Sendable {
  case ipv4
  case ipv6
}

public struct NetworkAddressSnapshot: Codable, Hashable, Sendable {
  public var address: String
  public var family: NetworkAddressFamily
  public var prefixLength: Int?
  public var subnetMask: String?

  public init(
    address: String,
    family: NetworkAddressFamily,
    prefixLength: Int? = nil,
    subnetMask: String? = nil
  ) {
    self.address = address
    self.family = family
    self.prefixLength = prefixLength
    self.subnetMask = subnetMask
  }
}

public enum NetworkInterfaceKind: String, Codable, Hashable, Sendable {
  case wifi
  case ethernet
  case loopback
  case bridge
  case vpn
  case other
}

public struct NetworkInterfaceSnapshot: Codable, Hashable, Sendable {
  public var bsdName: String
  public var kind: NetworkInterfaceKind
  public var isUp: Bool
  public var isRunning: Bool
  public var addresses: [NetworkAddressSnapshot]

  public init(
    bsdName: String,
    kind: NetworkInterfaceKind,
    isUp: Bool,
    isRunning: Bool,
    addresses: [NetworkAddressSnapshot] = []
  ) {
    self.bsdName = bsdName
    self.kind = kind
    self.isUp = isUp
    self.isRunning = isRunning
    self.addresses = addresses
  }

  public var linkActive: Bool {
    isUp && isRunning
  }
}

public enum WiFiSSIDAccess: String, Codable, Hashable, Sendable {
  case available
  case notAssociated
  case permissionRequired
  case permissionDenied
  case unavailable
}

public struct WiFiInterfaceSnapshot: Codable, Hashable, Sendable {
  public var bsdName: String
  public var powerOn: Bool
  public var ssid: String?
  public var ssidAccess: WiFiSSIDAccess

  public init(
    bsdName: String,
    powerOn: Bool,
    ssid: String?,
    ssidAccess: WiFiSSIDAccess
  ) {
    self.bsdName = bsdName
    self.powerOn = powerOn
    self.ssid = ssid
    self.ssidAccess = ssidAccess
  }
}

/// A read-only determination of whether macOS currently has the saved state
/// required to attempt a Wi-Fi association. It intentionally carries no SSID,
/// password, Keychain status, or underlying error.
public enum SavedWiFiAssociationPreflight: Equatable, Sendable {
  case available
  case unavailable(SavedWiFiAssociationUnavailableReason)
}

public enum SavedWiFiAssociationUnavailableReason: Equatable, Sendable {
  case invalidSSID
  case wifiInterfaceUnavailable
  case savedProfileUnavailable
  case savedCredentialUnavailable
  case preflightUnavailable
}

public struct NetworkServiceConfigurationSnapshot: Codable, Hashable, Sendable {
  public var serviceID: String
  public var serviceName: String?
  public var bsdName: String?
  public var interfaceType: String?
  public var kind: NetworkServiceKind?
  public var enabled: Bool
  public var ipv4: IPv4Configuration?
  /// Exact property-list representation used only for preflight rollback.
  public var ipv4ConfigurationData: Data?
  public var dnsServers: [String]
  public var webProxy: ProxyConfiguration?
  public var secureWebProxy: ProxyConfiguration?

  public init(
    serviceID: String,
    serviceName: String? = nil,
    bsdName: String? = nil,
    interfaceType: String? = nil,
    kind: NetworkServiceKind? = nil,
    enabled: Bool,
    ipv4: IPv4Configuration? = nil,
    ipv4ConfigurationData: Data? = nil,
    dnsServers: [String] = [],
    webProxy: ProxyConfiguration? = nil,
    secureWebProxy: ProxyConfiguration? = nil
  ) {
    self.serviceID = serviceID
    self.serviceName = serviceName
    self.bsdName = bsdName
    self.interfaceType = interfaceType
    self.kind = kind
    self.enabled = enabled
    self.ipv4 = ipv4
    self.ipv4ConfigurationData = ipv4ConfigurationData
    self.dnsServers = dnsServers
    self.webProxy = webProxy
    self.secureWebProxy = secureWebProxy
  }

  public var portableIdentity: NetworkServiceIdentity? {
    guard let kind,
      let serviceName = serviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !serviceName.isEmpty,
      let interfaceType = interfaceType?.trimmingCharacters(in: .whitespacesAndNewlines),
      !interfaceType.isEmpty
    else {
      return nil
    }
    return NetworkServiceIdentity(
      kind: kind,
      serviceName: serviceName,
      interfaceType: interfaceType
    )
  }
}

public struct NetworkSystemSnapshot: Codable, Hashable, Sendable {
  public var wifi: WiFiInterfaceSnapshot?
  public var interfaces: [NetworkInterfaceSnapshot]
  public var primaryInterfaceName: String?
  public var primaryServiceID: String?
  public var ipv4Gateway: String?
  public var ipv6Gateway: String?
  public var dnsServers: [String]
  public var services: [NetworkServiceConfigurationSnapshot]
  public var savedWiFiNetworkNames: [String]

  public init(
    wifi: WiFiInterfaceSnapshot? = nil,
    interfaces: [NetworkInterfaceSnapshot] = [],
    primaryInterfaceName: String? = nil,
    primaryServiceID: String? = nil,
    ipv4Gateway: String? = nil,
    ipv6Gateway: String? = nil,
    dnsServers: [String] = [],
    services: [NetworkServiceConfigurationSnapshot] = [],
    savedWiFiNetworkNames: [String] = []
  ) {
    self.wifi = wifi
    self.interfaces = interfaces
    self.primaryInterfaceName = primaryInterfaceName
    self.primaryServiceID = primaryServiceID
    self.ipv4Gateway = ipv4Gateway
    self.ipv6Gateway = ipv6Gateway
    self.dnsServers = dnsServers
    self.services = services
    self.savedWiFiNetworkNames = savedWiFiNetworkNames
  }

  public var primaryService: NetworkServiceConfigurationSnapshot? {
    if let primaryServiceID,
      let service = services.first(where: { $0.serviceID == primaryServiceID })
    {
      return service
    }
    if let primaryInterfaceName,
      let service = services.first(where: { $0.bsdName == primaryInterfaceName })
    {
      return service
    }
    return nil
  }
}

enum NetworkOperationPayload: Codable, Hashable, Sendable {
  case setWiFiPower(Bool)
  case associateSavedNetwork(ssid: String)
  case disassociateWiFi
  case setServiceIPv4(
    identity: NetworkServiceIdentity,
    configuration: IPv4Configuration
  )
  case restoreServiceIPv4(
    identity: NetworkServiceIdentity,
    configurationData: Data,
    expected: IPv4Configuration?
  )
}
