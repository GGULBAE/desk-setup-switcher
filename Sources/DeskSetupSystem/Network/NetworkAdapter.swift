import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public enum NetworkAdapterError: Error, Equatable, Sendable {
  case invalidPayload
}

public struct NetworkAdapter: SystemSettingsAdapter {
  public let group = SettingGroup.network

  private let systemAPI: any NetworkSystemAPI
  private let now: @Sendable () -> Date

  public init(
    systemAPI: any NetworkSystemAPI = LiveNetworkSystemAPI(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.systemAPI = systemAPI
    self.now = now
  }

  public func capability() async -> AdapterCapability {
    AdapterCapability(
      group: .network,
      state: .supported,
      reason: "Network snapshots, Wi-Fi power, and saved-network association use public macOS APIs."
    )
  }

  public func snapshot() async throws -> AdapterSnapshot {
    let system = try await systemAPI.readSnapshot()
    let primaryService = system.primaryService
    let dnsServers =
      primaryService?.dnsServers.isEmpty == false
      ? primaryService?.dnsServers ?? []
      : system.dnsServers
    let settings = NetworkProfileSettings(
      wifiPower: .init(
        isIncluded: system.wifi != nil,
        value: system.wifi?.powerOn
      ),
      wifiSSID: .init(
        isIncluded: system.wifi?.ssid != nil,
        value: system.wifi?.ssid
      ),
      ipv4: .init(
        isIncluded: false,
        value: primaryService?.ipv4
      ),
      dnsServers: .init(
        isIncluded: false,
        value: dnsServers
      ),
      webProxy: .init(
        isIncluded: false,
        value: primaryService?.webProxy
      ),
      secureWebProxy: .init(
        isIncluded: false,
        value: primaryService?.secureWebProxy
      )
    )

    return AdapterSnapshot(
      group: .network,
      capturedAt: now(),
      payload: .network(settings),
      items: snapshotItems(for: system)
    )
  }

  public func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue] {
    guard case .network(let settings) = desired,
      snapshot.group == .network,
      case .network = snapshot.payload
    else {
      return [
        ValidationIssue(
          group: .network,
          key: "network.payload",
          severity: .error,
          isFatal: true,
          message: "The network settings payload is invalid."
        )
      ]
    }

    var issues: [ValidationIssue] = []
    if settings.wifiPower.isIncluded, settings.wifiPower.value == nil {
      issues.append(
        ValidationIssue(
          group: .network,
          key: "wifi.power",
          severity: .error,
          isFatal: true,
          message: "The saved Wi-Fi power value is missing."
        )
      )
    }
    if settings.wifiSSID.isIncluded,
      let ssid = settings.wifiSSID.value,
      !isValidSSID(ssid)
    {
      issues.append(
        ValidationIssue(
          group: .network,
          key: "wifi.ssid",
          severity: .error,
          isFatal: true,
          message: "The saved Wi-Fi network name must contain 1 to 32 UTF-8 bytes."
        )
      )
    }
    return issues
  }

  public func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan {
    guard case .network(let desiredSettings) = desired,
      case .network(let currentSettings) = snapshot.payload,
      snapshot.group == .network
    else {
      throw NetworkAdapterError.invalidPayload
    }

    var operations: [PlannedOperation] = []
    var omissions: [PlanOmission] = []
    let targetSSID =
      desiredSettings.wifiSSID.isIncluded
      ? desiredSettings.wifiSSID.value
      : nil
    let currentSSID = currentSettings.wifiSSID.value
    var powerChange: (desired: Bool, current: Bool)?

    if desiredSettings.wifiPower.isIncluded {
      if let desiredPower = desiredSettings.wifiPower.value,
        let currentPower = currentSettings.wifiPower.value
      {
        if desiredPower != currentPower {
          powerChange = (desiredPower, currentPower)
        }
      } else {
        omissions.append(
          omission(
            key: "wifi.power",
            status: .skipped,
            reason:
              "Wi-Fi power cannot be changed because its current or desired state is unavailable."
          )
        )
      }
    }

    var associationOperation: PlannedOperation?
    if let targetSSID, targetSSID != currentSSID {
      let ssidItem = snapshot.items.first { $0.key == "wifi.ssid" }
      let hasExplicitRollbackState =
        (currentSSID != nil && ssidItem?.state == .storable)
        || (currentSSID == nil && ssidItem?.state == .detected)
      let effectivePower =
        desiredSettings.wifiPower.isIncluded
        ? desiredSettings.wifiPower.value
        : currentSettings.wifiPower.value

      if !isValidSSID(targetSSID) {
        omissions.append(
          omission(
            key: "wifi.ssid",
            status: .skipped,
            reason: "The saved Wi-Fi network name is invalid."
          )
        )
      } else if !hasExplicitRollbackState {
        omissions.append(
          omission(
            key: "wifi.ssid",
            status: .skipped,
            reason:
              "The current Wi-Fi association state is not explicit, so switching cannot be rolled back safely."
          )
        )
      } else if effectivePower != true {
        omissions.append(
          omission(
            key: "wifi.ssid",
            status: .skipped,
            reason: "Wi-Fi must be on before a saved network can be joined."
          )
        )
      } else {
        switch await systemAPI.preflightSavedWiFiAssociation(ssid: targetSSID) {
        case .available:
          var rollbackPayload: NetworkOperationPayload?
          if let currentSSID {
            switch await systemAPI.preflightSavedWiFiAssociation(ssid: currentSSID) {
            case .available:
              rollbackPayload = .associateSavedNetwork(ssid: currentSSID)
            case .unavailable(let reason):
              omissions.append(
                omission(
                  key: "wifi.ssid",
                  status: .skipped,
                  reason: rollbackPreflightOmissionReason(reason)
                )
              )
            }
          } else {
            rollbackPayload = .disassociateWiFi
          }

          if let rollbackPayload {
            associationOperation = try operation(
              key: "wifi.ssid",
              summary: "Join a saved Wi-Fi network using macOS-managed access.",
              risk: .moderate,
              isFatalOnFailure: true,
              payload: .associateSavedNetwork(ssid: targetSSID),
              rollback: rollbackPayload
            )
          }
        case .unavailable(let reason):
          omissions.append(
            omission(
              key: "wifi.ssid",
              status: .skipped,
              reason: targetPreflightOmissionReason(reason)
            )
          )
        }
      }
    }

    if let powerChange {
      operations.append(
        try operation(
          key: "wifi.power",
          summary: powerChange.desired ? "Turn Wi-Fi on." : "Turn Wi-Fi off.",
          risk: .low,
          isFatalOnFailure: associationOperation != nil,
          payload: .setWiFiPower(powerChange.desired),
          rollback: .setWiFiPower(powerChange.current)
        )
      )
    }
    if let associationOperation {
      operations.append(associationOperation)
    }

    appendUnsupportedChange(
      key: "network.ipv4",
      desired: desiredSettings.ipv4,
      current: currentSettings.ipv4,
      reason: "DHCP and static IPv4 changes require an authorized, rollback-safe implementation.",
      omissions: &omissions
    )
    appendUnsupportedChange(
      key: "network.dns",
      desired: desiredSettings.dnsServers,
      current: currentSettings.dnsServers,
      reason: "DNS changes require an authorized, rollback-safe implementation.",
      omissions: &omissions
    )
    appendUnsupportedChange(
      key: "network.webProxy",
      desired: desiredSettings.webProxy,
      current: currentSettings.webProxy,
      reason: "Proxy changes require an authorized, rollback-safe implementation.",
      omissions: &omissions
    )
    appendUnsupportedChange(
      key: "network.secureWebProxy",
      desired: desiredSettings.secureWebProxy,
      current: currentSettings.secureWebProxy,
      reason: "Proxy changes require an authorized, rollback-safe implementation.",
      omissions: &omissions
    )

    return AdapterPlan(
      group: .network,
      operations: operations,
      omissions: omissions
    )
  }

  public func apply(_ operation: PlannedOperation) async -> OperationResult {
    guard let payload = decode(operation.payload) else {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "The network operation payload is invalid."
      )
    }

    do {
      try await perform(payload)
      return OperationResult(
        operationID: operation.id,
        status: .succeeded,
        message: "The network operation completed."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "The network operation failed without exposing credentials."
      )
    }
  }

  public func rollback(_ operation: PlannedOperation) async -> OperationResult {
    guard let rollbackPayload = operation.rollbackPayload,
      let payload = decode(rollbackPayload)
    else {
      return OperationResult(
        operationID: operation.id,
        status: .rollbackFailed,
        message: "The network rollback payload is unavailable."
      )
    }

    do {
      try await perform(payload)
      return OperationResult(
        operationID: operation.id,
        status: .rolledBack,
        message: "The previous network state was restored."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .rollbackFailed,
        message: "The previous network state could not be restored."
      )
    }
  }

  public func diagnostics() async -> [DiagnosticEntry] {
    do {
      let snapshot = try await systemAPI.readSnapshot()
      return [
        DiagnosticEntry(
          severity: .info,
          component: "adapter.network",
          code: "network.snapshot.available",
          message:
            "Network snapshot available for \(snapshot.interfaces.count) interface(s); no addresses or SSIDs logged."
        )
      ]
    } catch {
      return [
        DiagnosticEntry(
          severity: .warning,
          component: "adapter.network",
          code: "network.snapshot.failed",
          message: "The network snapshot was unavailable; no sensitive values logged."
        )
      ]
    }
  }

  private func snapshotItems(for system: NetworkSystemSnapshot) -> [SnapshotItem] {
    var items: [SnapshotItem] = []
    if let wifi = system.wifi {
      items.append(
        SnapshotItem(
          key: "wifi.interface",
          label: "Wi-Fi interface \(wifi.bsdName)",
          state: .detected,
          detail: "Public CoreWLAN interface detected."
        )
      )
      items.append(
        SnapshotItem(
          key: "wifi.power",
          label: "Wi-Fi power",
          state: .storable,
          detail: wifi.powerOn ? "On" : "Off"
        )
      )
      items.append(ssidItem(for: wifi))
    } else {
      items.append(
        SnapshotItem(
          key: "wifi.interface",
          label: "Wi-Fi interface",
          state: .unsupported,
          detail: "No Wi-Fi interface was detected."
        )
      )
    }

    for interface in system.interfaces {
      items.append(
        SnapshotItem(
          key: "interface.\(interface.bsdName)",
          label: "Interface \(interface.bsdName)",
          state: .detected,
          detail: "\(interface.kind.rawValue); link \(interface.linkActive ? "active" : "inactive")"
        )
      )
      for (index, address) in interface.addresses.enumerated() {
        let suffix = address.prefixLength.map { "/\($0)" } ?? ""
        let subnet = address.subnetMask.map { "; subnet \($0)" } ?? ""
        items.append(
          SnapshotItem(
            key: "address.\(interface.bsdName).\(index)",
            label: "Local \(address.family.rawValue) address",
            state: .storable,
            detail: "\(address.address)\(suffix)\(subnet)"
          )
        )
      }
    }

    if let primaryInterfaceName = system.primaryInterfaceName {
      items.append(
        SnapshotItem(
          key: "network.primaryInterface",
          label: "Active interface",
          state: .storable,
          detail: primaryInterfaceName
        )
      )
    }
    appendOptionalItem(
      key: "network.ipv4Gateway",
      label: "IPv4 gateway",
      value: system.ipv4Gateway,
      items: &items
    )
    appendOptionalItem(
      key: "network.ipv6Gateway",
      label: "IPv6 gateway",
      value: system.ipv6Gateway,
      items: &items
    )
    if !system.dnsServers.isEmpty {
      items.append(
        SnapshotItem(
          key: "network.dns",
          label: "DNS servers",
          state: .storable,
          detail: system.dnsServers.joined(separator: ", ")
        )
      )
    }
    items.append(
      SnapshotItem(
        key: "network.serviceOrder",
        label: "Network service order",
        state: .unsupported,
        detail:
          "Readable service order detected; mutation is not supported without authorization and rollback."
      )
    )
    return items
  }

  private func ssidItem(for wifi: WiFiInterfaceSnapshot) -> SnapshotItem {
    switch wifi.ssidAccess {
    case .available:
      return SnapshotItem(
        key: "wifi.ssid",
        label: "Current Wi-Fi network",
        state: .storable,
        detail: "SSID is available."
      )
    case .notAssociated:
      return SnapshotItem(
        key: "wifi.ssid",
        label: "Current Wi-Fi network",
        state: .detected,
        detail: "Wi-Fi is not associated with a network."
      )
    case .permissionRequired, .permissionDenied:
      return SnapshotItem(
        key: "wifi.ssid",
        label: "Current Wi-Fi network",
        state: .permissionRequired,
        detail: "SSID access requires location authorization; other network facts remain available."
      )
    case .unavailable:
      return SnapshotItem(
        key: "wifi.ssid",
        label: "Current Wi-Fi network",
        state: .unreadable,
        detail: "The SSID could not be read."
      )
    }
  }

  private func appendOptionalItem(
    key: String,
    label: String,
    value: String?,
    items: inout [SnapshotItem]
  ) {
    guard let value else { return }
    items.append(
      SnapshotItem(
        key: key,
        label: label,
        state: .storable,
        detail: value
      )
    )
  }

  private func operation(
    key: String,
    summary: String,
    risk: OperationRisk,
    isFatalOnFailure: Bool,
    payload: NetworkOperationPayload,
    rollback: NetworkOperationPayload
  ) throws -> PlannedOperation {
    PlannedOperation(
      group: .network,
      key: key,
      summary: summary,
      risk: risk,
      isFatalOnFailure: isFatalOnFailure,
      preview: OperationPreview(
        previousValue: previewValue(rollback),
        desiredValue: previewValue(payload)
      ),
      payload: try encode(payload),
      rollbackPayload: try encode(rollback)
    )
  }

  private func previewValue(_ payload: NetworkOperationPayload) -> String {
    switch payload {
    case .setWiFiPower(let enabled):
      return enabled ? "On" : "Off"
    case .associateSavedNetwork(let ssid):
      return ssid
    case .disassociateWiFi:
      return "Not associated"
    }
  }

  private func omission(
    key: String,
    status: ApplicationItemStatus,
    reason: String
  ) -> PlanOmission {
    PlanOmission(group: .network, key: key, status: status, reason: reason)
  }

  private func targetPreflightOmissionReason(
    _ reason: SavedWiFiAssociationUnavailableReason
  ) -> String {
    switch reason {
    case .invalidSSID:
      "The target Wi-Fi network name is invalid."
    case .wifiInterfaceUnavailable:
      "The Wi-Fi interface is unavailable for saved-network preflight."
    case .savedProfileUnavailable:
      "macOS does not have a saved profile for the target Wi-Fi network."
    case .savedCredentialUnavailable:
      "macOS cannot confirm saved access for the target Wi-Fi network."
    case .preflightUnavailable:
      "Saved-network preflight is unavailable for the target Wi-Fi network."
    }
  }

  private func isValidSSID(_ ssid: String) -> Bool {
    guard let data = ssid.data(using: .utf8) else { return false }
    return (1...32).contains(data.count)
  }

  private func rollbackPreflightOmissionReason(
    _ reason: SavedWiFiAssociationUnavailableReason
  ) -> String {
    switch reason {
    case .invalidSSID:
      "The current Wi-Fi network name is invalid, so rollback is unavailable."
    case .wifiInterfaceUnavailable:
      "The Wi-Fi interface is unavailable, so rollback cannot be preflighted."
    case .savedProfileUnavailable:
      "macOS does not have a saved profile for the current Wi-Fi network, so rollback is unavailable."
    case .savedCredentialUnavailable:
      "macOS cannot confirm saved access for the current Wi-Fi network, so rollback is unavailable."
    case .preflightUnavailable:
      "Saved-network rollback preflight is unavailable for the current Wi-Fi network."
    }
  }

  private func appendUnsupportedChange<Value>(
    key: String,
    desired: SettingOption<Value>,
    current: SettingOption<Value>,
    reason: String,
    omissions: inout [PlanOmission]
  ) where Value: Codable & Hashable & Sendable {
    guard desired.isIncluded, desired.value != current.value else { return }
    omissions.append(
      omission(key: key, status: .unsupported, reason: reason)
    )
  }

  private func perform(_ payload: NetworkOperationPayload) async throws {
    switch payload {
    case .setWiFiPower(let enabled):
      try await systemAPI.setWiFiPower(enabled)
    case .associateSavedNetwork(let ssid):
      try await systemAPI.associateToSavedWiFi(ssid: ssid)
    case .disassociateWiFi:
      try await systemAPI.disassociateWiFi()
    }
  }

  private func encode(_ payload: NetworkOperationPayload) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(payload)
  }

  private func decode(_ data: Data) -> NetworkOperationPayload? {
    try? JSONDecoder().decode(NetworkOperationPayload.self, from: data)
  }
}
