import CoreLocation
import CoreWLAN
import Darwin
import Foundation
import Security
import SystemConfiguration

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public protocol NetworkSystemAPI: Sendable {
  func readSnapshot() async throws -> NetworkSystemSnapshot

  /// Checks only saved profile and Keychain state. Implementations must not
  /// scan, associate, mutate configuration, or return secret material.
  func preflightSavedWiFiAssociation(ssid: String) async -> SavedWiFiAssociationPreflight
  func setWiFiPower(_ enabled: Bool) async throws
  func associateToSavedWiFi(ssid: String) async throws
  func disassociateWiFi() async throws
}

extension NetworkSystemAPI {
  /// Conformers that do not implement the preflight remain conservatively
  /// unavailable, so a saved-network switch cannot be planned accidentally.
  public func preflightSavedWiFiAssociation(ssid: String) async -> SavedWiFiAssociationPreflight {
    .unavailable(.preflightUnavailable)
  }
}

public enum NetworkSystemAPIError: Error, Equatable, Sendable {
  case wifiInterfaceUnavailable
  case interfaceEnumerationFailed
  case invalidSSID
  case savedNetworkUnavailable
  case credentialUnavailable
  case operationFailed
}

/// Selects the first compatible network/profile pair after applying explicit,
/// deterministic ordering. Keeping this logic independent of CoreWLAN makes
/// the security-binding rule testable without scanning for or joining a live
/// Wi-Fi network.
func firstCompatibleSavedWiFiPair<Network, Profile, NetworkKey, ProfileKey>(
  networks: [Network],
  profiles: [Profile],
  networkSortKey: (Network) -> NetworkKey,
  profileSortKey: (Profile) -> ProfileKey,
  isCompatible: (Network, Profile) -> Bool
) -> (network: Network, profile: Profile)? where NetworkKey: Comparable, ProfileKey: Comparable {
  let orderedNetworks = networks.sorted {
    networkSortKey($0) < networkSortKey($1)
  }
  let orderedProfiles = profiles.sorted {
    profileSortKey($0) < profileSortKey($1)
  }

  for network in orderedNetworks {
    if let profile = orderedProfiles.first(where: { isCompatible(network, $0) }) {
      return (network, profile)
    }
  }
  return nil
}

/// Official-API implementation. It does not probe any host or create any
/// outbound connection; association is performed only when the user applies a
/// profile and only with a credential already held by macOS.
public actor LiveNetworkSystemAPI: NetworkSystemAPI {
  public init() {}

  public func readSnapshot() async throws -> NetworkSystemSnapshot {
    let wifi = readWiFiSnapshot()
    let configuration = readSystemConfiguration()
    let interfaces = try readInterfaces(wifiBSDName: wifi?.bsdName)

    return NetworkSystemSnapshot(
      wifi: wifi,
      interfaces: interfaces,
      primaryInterfaceName: configuration.primaryInterfaceName,
      primaryServiceID: configuration.primaryServiceID,
      ipv4Gateway: configuration.ipv4Gateway,
      ipv6Gateway: configuration.ipv6Gateway,
      dnsServers: configuration.dnsServers,
      serviceOrder: configuration.serviceOrder,
      services: configuration.services
    )
  }

  public func setWiFiPower(_ enabled: Bool) async throws {
    guard let interface = CWWiFiClient.shared().interface() else {
      throw NetworkSystemAPIError.wifiInterfaceUnavailable
    }
    do {
      try interface.setPower(enabled)
    } catch {
      throw NetworkSystemAPIError.operationFailed
    }
  }

  public func preflightSavedWiFiAssociation(
    ssid: String
  ) async -> SavedWiFiAssociationPreflight {
    guard let ssidData = ssid.data(using: .utf8), (1...32).contains(ssidData.count) else {
      return .unavailable(.invalidSSID)
    }
    guard let interface = CWWiFiClient.shared().interface() else {
      return .unavailable(.wifiInterfaceUnavailable)
    }

    let savedProfiles =
      interface.configuration()?.networkProfiles.array
      as? [CWNetworkProfile] ?? []
    let matchingProfiles = savedProfiles.filter { $0.ssidData == ssidData }
    guard !matchingProfiles.isEmpty else {
      return .unavailable(.savedProfileUnavailable)
    }
    if matchingProfiles.contains(where: { $0.security == .none }) {
      return .available
    }

    return savedWiFiCredentialIsAvailable(ssidData: ssidData)
      ? .available
      : .unavailable(.savedCredentialUnavailable)
  }

  public func associateToSavedWiFi(ssid: String) async throws {
    guard let ssidData = ssid.data(using: .utf8), (1...32).contains(ssidData.count) else {
      throw NetworkSystemAPIError.invalidSSID
    }
    guard let interface = CWWiFiClient.shared().interface() else {
      throw NetworkSystemAPIError.wifiInterfaceUnavailable
    }
    let savedProfiles =
      interface.configuration()?.networkProfiles.array
      as? [CWNetworkProfile] ?? []
    let matchingProfiles = savedProfiles.filter { $0.ssidData == ssidData }
    guard !matchingProfiles.isEmpty else {
      throw NetworkSystemAPIError.savedNetworkUnavailable
    }

    let networks: Set<CWNetwork>
    do {
      networks = try interface.scanForNetworks(withSSID: ssidData)
    } catch {
      throw NetworkSystemAPIError.savedNetworkUnavailable
    }
    guard
      let selection = firstCompatibleSavedWiFiPair(
        networks: networks.filter { $0.ssid == ssid },
        profiles: matchingProfiles,
        networkSortKey: { $0.bssid ?? "" },
        profileSortKey: { $0.security.rawValue },
        isCompatible: { network, profile in
          network.supportsSecurity(profile.security)
        }
      )
    else {
      throw NetworkSystemAPIError.savedNetworkUnavailable
    }
    let network = selection.network
    let savedProfile = selection.profile

    if savedProfile.security == .none {
      do {
        try interface.associate(to: network, password: nil)
        return
      } catch {
        throw NetworkSystemAPIError.operationFailed
      }
    }

    var password: NSString?
    defer { password = nil }
    var status = CWKeychainFindWiFiPassword(.user, ssidData, &password)
    if status != errSecSuccess || password == nil {
      password = nil
      status = CWKeychainFindWiFiPassword(.system, ssidData, &password)
    }
    guard status == errSecSuccess, password != nil else {
      throw NetworkSystemAPIError.credentialUnavailable
    }

    do {
      try interface.associate(to: network, password: password as String?)
    } catch {
      throw NetworkSystemAPIError.operationFailed
    }
  }

  public func disassociateWiFi() async throws {
    guard let interface = CWWiFiClient.shared().interface() else {
      throw NetworkSystemAPIError.wifiInterfaceUnavailable
    }
    interface.disassociate()
  }

  private func savedWiFiCredentialIsAvailable(ssidData: Data) -> Bool {
    var password: NSString?
    let userStatus = CWKeychainFindWiFiPassword(.user, ssidData, &password)
    let userCredentialIsAvailable = userStatus == errSecSuccess && password != nil
    password = nil
    if userCredentialIsAvailable {
      return true
    }

    let systemStatus = CWKeychainFindWiFiPassword(.system, ssidData, &password)
    let systemCredentialIsAvailable = systemStatus == errSecSuccess && password != nil
    password = nil
    return systemCredentialIsAvailable
  }

  private func readWiFiSnapshot() -> WiFiInterfaceSnapshot? {
    guard let interface = CWWiFiClient.shared().interface(),
      let bsdName = interface.interfaceName
    else {
      return nil
    }

    let powerOn = interface.powerOn()
    let ssid = powerOn ? interface.ssid() : nil
    let access = Self.classifySSIDAccess(
      powerOn: powerOn,
      ssid: ssid,
      authorizationStatus: CLLocationManager().authorizationStatus
    )

    return WiFiInterfaceSnapshot(
      bsdName: bsdName,
      powerOn: powerOn,
      ssid: ssid,
      ssidAccess: access
    )
  }

  /// CoreWLAN documents a nil SSID as ambiguous: it can mean that the
  /// interface is not participating in a network, but it can also mean a read
  /// error or an SSID that cannot be represented as a string. Therefore only
  /// a powered-off interface is positive evidence of no association. A
  /// powered-on nil result must never be used as a rollback target, even when
  /// Location Services is authorized.
  static func classifySSIDAccess(
    powerOn: Bool,
    ssid: String?,
    authorizationStatus: CLAuthorizationStatus
  ) -> WiFiSSIDAccess {
    if ssid != nil {
      return .available
    }
    if !powerOn {
      return .notAssociated
    }

    switch authorizationStatus {
    case .notDetermined:
      return .permissionRequired
    case .denied, .restricted:
      return .permissionDenied
    case .authorizedAlways, .authorized:
      return .unavailable
    @unknown default:
      return .unavailable
    }
  }

  private struct SystemConfigurationSnapshot {
    var primaryInterfaceName: String?
    var primaryServiceID: String?
    var ipv4Gateway: String?
    var ipv6Gateway: String?
    var dnsServers: [String]
    var serviceOrder: [String]
    var services: [NetworkServiceConfigurationSnapshot]
  }

  private func readSystemConfiguration() -> SystemConfigurationSnapshot {
    let dynamicStore = SCDynamicStoreCreate(
      nil,
      "DeskSetupSwitcher.NetworkSnapshot" as CFString,
      nil,
      nil
    )
    let ipv4 = dynamicDictionary("State:/Network/Global/IPv4", store: dynamicStore)
    let ipv6 = dynamicDictionary("State:/Network/Global/IPv6", store: dynamicStore)
    let dns = dynamicDictionary("State:/Network/Global/DNS", store: dynamicStore)

    // Read the non-Sendable SystemConfiguration dictionaries into Sendable
    // values before using nil coalescing. This avoids older Swift 6
    // compilers treating `??`'s autoclosure as a cross-actor send.
    let ipv4PrimaryInterface = ipv4["PrimaryInterface"] as? String
    let ipv6PrimaryInterface = ipv6["PrimaryInterface"] as? String
    let ipv4PrimaryService = ipv4["PrimaryService"] as? String
    let ipv6PrimaryService = ipv6["PrimaryService"] as? String
    let ipv4Gateway = ipv4["Router"] as? String
    let ipv6Gateway = ipv6["Router"] as? String
    let dnsServers = dns[kSCPropNetDNSServerAddresses as String] as? [String] ?? []
    let primaryInterface = ipv4PrimaryInterface ?? ipv6PrimaryInterface
    let primaryService = ipv4PrimaryService ?? ipv6PrimaryService

    var serviceOrder: [String] = []
    var services: [NetworkServiceConfigurationSnapshot] = []
    if let preferences = SCPreferencesCreate(
      nil,
      "DeskSetupSwitcher.NetworkSnapshot" as CFString,
      nil
    ), let set = SCNetworkSetCopyCurrent(preferences) {
      serviceOrder = SCNetworkSetGetServiceOrder(set) as? [String] ?? []
      let configuredServices = SCNetworkSetCopyServices(set) as? [SCNetworkService] ?? []
      services = configuredServices.compactMap(readService).sorted {
        $0.serviceID < $1.serviceID
      }
    }

    return SystemConfigurationSnapshot(
      primaryInterfaceName: primaryInterface,
      primaryServiceID: primaryService,
      ipv4Gateway: ipv4Gateway,
      ipv6Gateway: ipv6Gateway,
      dnsServers: dnsServers,
      serviceOrder: serviceOrder,
      services: services
    )
  }

  private func dynamicDictionary(
    _ key: String,
    store: SCDynamicStore?
  ) -> [String: Any] {
    guard let store,
      let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    else {
      return [:]
    }
    return value
  }

  private func readService(
    _ service: SCNetworkService
  ) -> NetworkServiceConfigurationSnapshot? {
    guard let serviceID = SCNetworkServiceGetServiceID(service) as String? else {
      return nil
    }
    let interface = SCNetworkServiceGetInterface(service)
    let bsdName = interface.flatMap { SCNetworkInterfaceGetBSDName($0) as String? }

    let ipv4 = protocolConfiguration(service, type: kSCNetworkProtocolTypeIPv4)
    let dns = protocolConfiguration(service, type: kSCNetworkProtocolTypeDNS)
    let proxies = protocolConfiguration(service, type: kSCNetworkProtocolTypeProxies)

    return NetworkServiceConfigurationSnapshot(
      serviceID: serviceID,
      bsdName: bsdName,
      enabled: SCNetworkServiceGetEnabled(service),
      ipv4: parseIPv4(ipv4),
      dnsServers: stringArray(dns, key: kSCPropNetDNSServerAddresses as String),
      webProxy: parseProxy(
        proxies,
        enableKey: kSCPropNetProxiesHTTPEnable as String,
        hostKey: kSCPropNetProxiesHTTPProxy as String,
        portKey: kSCPropNetProxiesHTTPPort as String
      ),
      secureWebProxy: parseProxy(
        proxies,
        enableKey: kSCPropNetProxiesHTTPSEnable as String,
        hostKey: kSCPropNetProxiesHTTPSProxy as String,
        portKey: kSCPropNetProxiesHTTPSPort as String
      )
    )
  }

  private func protocolConfiguration(
    _ service: SCNetworkService,
    type: CFString
  ) -> [String: Any] {
    guard let networkProtocol = SCNetworkServiceCopyProtocol(service, type),
      let configuration = SCNetworkProtocolGetConfiguration(networkProtocol)
        as? [String: Any]
    else {
      return [:]
    }
    return configuration
  }

  private func parseIPv4(_ configuration: [String: Any]) -> IPv4Configuration? {
    let method = stringValue(
      configuration,
      key: kSCPropNetIPv4ConfigMethod as String
    )
    if method == kSCValNetIPv4ConfigMethodDHCP as String {
      return .dhcp
    }
    guard method == kSCValNetIPv4ConfigMethodManual as String,
      let address = stringArray(
        configuration,
        key: kSCPropNetIPv4Addresses as String
      ).first,
      let subnetMask = stringArray(
        configuration,
        key: kSCPropNetIPv4SubnetMasks as String
      ).first
    else {
      return nil
    }
    return .manual(
      address: address,
      subnetMask: subnetMask,
      router: stringValue(configuration, key: kSCPropNetIPv4Router as String)
    )
  }

  private func parseProxy(
    _ configuration: [String: Any],
    enableKey: String,
    hostKey: String,
    portKey: String
  ) -> ProxyConfiguration? {
    guard
      configuration[enableKey] != nil
        || configuration[hostKey] != nil
        || configuration[portKey] != nil
    else {
      return nil
    }
    let enabled = (configuration[enableKey] as? NSNumber)?.boolValue ?? false
    let host = configuration[hostKey] as? String ?? ""
    let port = (configuration[portKey] as? NSNumber)?.intValue ?? 0
    return ProxyConfiguration(enabled: enabled, host: host, port: port)
  }

  private func stringValue(_ dictionary: [String: Any], key: String) -> String? {
    dictionary[key] as? String
  }

  private func stringArray(_ dictionary: [String: Any], key: String) -> [String] {
    dictionary[key] as? [String] ?? []
  }

  private struct MutableInterface {
    var flags: UInt32
    var addresses: [NetworkAddressSnapshot]
  }

  private func readInterfaces(wifiBSDName: String?) throws -> [NetworkInterfaceSnapshot] {
    let configuredKinds = configuredInterfaceKinds()
    var interfaces: [String: MutableInterface] = [:]
    var pointer: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&pointer) == 0, let first = pointer else {
      throw NetworkSystemAPIError.interfaceEnumerationFailed
    }
    defer { freeifaddrs(pointer) }

    var current: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = current {
      defer { current = entry.pointee.ifa_next }
      let name = String(cString: entry.pointee.ifa_name)
      let flags = entry.pointee.ifa_flags
      var mutable = interfaces[name] ?? MutableInterface(flags: flags, addresses: [])
      mutable.flags = flags

      if let address = entry.pointee.ifa_addr {
        let family = Int32(address.pointee.sa_family)
        if family == AF_INET || family == AF_INET6,
          let addressText = numericAddress(address)
        {
          let familyValue: NetworkAddressFamily = family == AF_INET ? .ipv4 : .ipv6
          let maskPointer = entry.pointee.ifa_netmask
          let mask = maskPointer.flatMap { numericAddress(UnsafePointer($0)) }
          let prefix = maskPointer.flatMap { prefixLength(UnsafePointer($0)) }
          mutable.addresses.append(
            NetworkAddressSnapshot(
              address: addressText,
              family: familyValue,
              prefixLength: prefix,
              subnetMask: mask
            )
          )
        }
      }
      interfaces[name] = mutable
    }

    return interfaces.map { name, value in
      let kind: NetworkInterfaceKind
      if value.flags & UInt32(IFF_LOOPBACK) != 0 {
        kind = .loopback
      } else if name == wifiBSDName {
        kind = .wifi
      } else {
        kind = configuredKinds[name] ?? inferredKind(for: name)
      }
      return NetworkInterfaceSnapshot(
        bsdName: name,
        kind: kind,
        isUp: value.flags & UInt32(IFF_UP) != 0,
        isRunning: value.flags & UInt32(IFF_RUNNING) != 0,
        addresses: value.addresses.sorted {
          if $0.family != $1.family {
            return $0.family.rawValue < $1.family.rawValue
          }
          return $0.address < $1.address
        }
      )
    }.sorted { $0.bsdName < $1.bsdName }
  }

  private func configuredInterfaceKinds() -> [String: NetworkInterfaceKind] {
    let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
    var result: [String: NetworkInterfaceKind] = [:]
    for interface in interfaces {
      guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
        let type = SCNetworkInterfaceGetInterfaceType(interface)
      else {
        continue
      }
      if CFEqual(type, kSCNetworkInterfaceTypeIEEE80211) {
        result[bsdName] = .wifi
      } else if CFEqual(type, kSCNetworkInterfaceTypeEthernet) {
        result[bsdName] = .ethernet
      } else if CFEqual(type, kSCNetworkInterfaceTypeIPSec)
        || CFEqual(type, kSCNetworkInterfaceTypePPP)
        || CFEqual(type, kSCNetworkInterfaceTypeL2TP)
      {
        result[bsdName] = .vpn
      } else if bsdName.hasPrefix("bridge") {
        result[bsdName] = .bridge
      } else {
        result[bsdName] = .other
      }
    }
    return result
  }

  private func inferredKind(for bsdName: String) -> NetworkInterfaceKind {
    if bsdName.hasPrefix("bridge") {
      return .bridge
    }
    if bsdName.hasPrefix("utun") || bsdName.hasPrefix("ppp")
      || bsdName.hasPrefix("ipsec")
    {
      return .vpn
    }
    return .other
  }

  private func numericAddress(_ address: UnsafePointer<sockaddr>) -> String? {
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let result = getnameinfo(
      address,
      socklen_t(address.pointee.sa_len),
      &host,
      socklen_t(host.count),
      nil,
      0,
      NI_NUMERICHOST
    )
    guard result == 0 else { return nil }
    let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }

  private func prefixLength(_ mask: UnsafePointer<sockaddr>) -> Int? {
    let family = Int32(mask.pointee.sa_family)
    let bytes: [UInt8]
    if family == AF_INET {
      let value = UnsafeRawPointer(mask).assumingMemoryBound(to: sockaddr_in.self)
        .pointee.sin_addr
      bytes = withUnsafeBytes(of: value) { Array($0) }
    } else if family == AF_INET6 {
      let value = UnsafeRawPointer(mask).assumingMemoryBound(to: sockaddr_in6.self)
        .pointee.sin6_addr
      bytes = withUnsafeBytes(of: value) { Array($0) }
    } else {
      return nil
    }

    var prefix = 0
    var encounteredZero = false
    for byte in bytes {
      for shift in stride(from: 7, through: 0, by: -1) {
        let isSet = byte & UInt8(1 << shift) != 0
        if isSet {
          guard !encounteredZero else { return nil }
          prefix += 1
        } else {
          encounteredZero = true
        }
      }
    }
    return prefix
  }
}
