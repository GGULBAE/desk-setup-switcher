import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public struct LiveConditionDisplayReader: ConditionDisplayReading {
  private let systemAPI: any DisplaySystemAPI

  public init(systemAPI: any DisplaySystemAPI = CoreGraphicsDisplaySystemAPI()) {
    self.systemAPI = systemAPI
  }

  public func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity> {
    Set(
      try await systemAPI.activeDisplays()
        .filter(\.isActive)
        .map(\.identity)
    )
  }
}

public struct LiveConditionAudioReader: ConditionAudioReading {
  private let systemAPI: any AudioSystemAPI

  public init(systemAPI: any AudioSystemAPI = CoreAudioSystemAPI()) {
    self.systemAPI = systemAPI
  }

  public func readAudioFacts() async throws -> ConditionAudioFacts {
    let devices = try systemAPI.devices()
    return ConditionAudioFacts(
      inputUIDs: Set(devices.lazy.filter(\.supportsInput).map(\.uid)),
      outputUIDs: Set(devices.lazy.filter(\.supportsOutput).map(\.uid))
    )
  }
}

public struct LiveConditionNetworkReader: ConditionNetworkReading {
  private let systemAPI: any NetworkSystemAPI

  public init(systemAPI: any NetworkSystemAPI = LiveNetworkSystemAPI()) {
    self.systemAPI = systemAPI
  }

  public func readNetworkFacts() async throws -> ConditionNetworkFacts {
    let snapshot = try await systemAPI.readSnapshot()
    let readableSSID = snapshot.wifi.flatMap { wifi -> String? in
      guard wifi.ssidAccess == .available,
        let ssid = wifi.ssid?.trimmingCharacters(in: .whitespacesAndNewlines),
        !ssid.isEmpty
      else {
        return nil
      }
      return ssid
    }
    let localAddresses = snapshot.interfaces
      .filter { $0.isUp && $0.kind != .loopback }
      .flatMap(\.addresses)
      .map(\.address)
      .filter { !$0.isEmpty && $0 != "0.0.0.0" && $0 != "::" }

    return ConditionNetworkFacts(
      wifiSSID: readableSSID,
      ethernetConnected: snapshot.interfaces.contains {
        $0.kind == .ethernet && $0.linkActive
      },
      ipAddresses: Set(localAddresses)
    )
  }
}
