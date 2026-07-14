import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// Value-free snapshot evidence passed across the system/presentation boundary.
public struct CaptureSnapshotEvidence: Hashable, Sendable {
  public var group: SettingGroup
  public var key: String
  public var state: SnapshotItemState

  public init(group: SettingGroup, key: String, state: SnapshotItemState) {
    self.group = group
    self.key = key
    self.state = state
  }
}

/// Deterministically classifies captured profile leaves without carrying any
/// SSID, address, device identifier, or other captured value into UI state.
public struct ProfileCaptureSummaryBuilder: Equatable, Sendable {
  public init() {}

  public func summary(
    settings: ProfileSettings,
    evidence: [CaptureSnapshotEvidence]
  ) -> ProfileCaptureSummary {
    var items: [CaptureSummaryItem] = []

    func applicable(_ included: Bool, _ group: SettingGroup, _ key: String) {
      guard included else { return }
      items.append(
        CaptureSummaryItem(group: group, key: key, disposition: .savedApplicable)
      )
    }

    for (index, display) in settings.display.value.displays.enumerated() {
      let prefix = "display.\(index)"
      applicable(
        settings.display.isIncluded && display.isPrimary.isIncluded,
        .display,
        "\(prefix).primary"
      )
      applicable(
        settings.display.isIncluded && display.origin.isIncluded,
        .display,
        "\(prefix).origin"
      )
      applicable(
        settings.display.isIncluded && display.mirroring.isIncluded,
        .display,
        "\(prefix).mirroring"
      )
      applicable(
        settings.display.isIncluded && display.mode.isIncluded,
        .display,
        "\(prefix).mode"
      )
      items.append(
        CaptureSummaryItem(
          group: .display,
          key: "\(prefix).rotation",
          disposition: .savedSnapshotOnly
        )
      )
      items.append(
        CaptureSummaryItem(
          group: .display,
          key: "\(prefix).active",
          disposition: .savedSnapshotOnly
        )
      )
    }

    let audio = settings.audio.value
    applicable(
      settings.audio.isIncluded && audio.defaultInputUID.isIncluded,
      .audio,
      "defaultInput"
    )
    applicable(
      settings.audio.isIncluded && audio.defaultOutputUID.isIncluded,
      .audio,
      "defaultOutput"
    )
    applicable(
      settings.audio.isIncluded && audio.systemOutputUID.isIncluded,
      .audio,
      "systemOutput"
    )
    applicable(settings.audio.isIncluded && audio.outputVolume.isIncluded, .audio, "outputVolume")
    applicable(settings.audio.isIncluded && audio.outputMuted.isIncluded, .audio, "outputMute")

    let network = settings.network.value
    applicable(settings.network.isIncluded && network.wifiPower.isIncluded, .network, "wifi.power")
    applicable(settings.network.isIncluded && network.wifiSSID.isIncluded, .network, "wifi.ssid")
    snapshotOnly(network.ipv4.value != nil, .network, "network.ipv4", items: &items)
    snapshotOnly(
      !network.dnsServers.value.isEmpty,
      .network,
      "network.dns",
      items: &items
    )
    snapshotOnly(
      network.webProxy.value != nil,
      .network,
      "network.webProxy",
      items: &items
    )
    snapshotOnly(
      network.secureWebProxy.value != nil,
      .network,
      "network.secureWebProxy",
      items: &items
    )

    let input = settings.input.value
    applicable(
      settings.input.isIncluded && input.pointerSpeed.isIncluded,
      .input,
      "com.apple.mouse.scaling"
    )
    applicable(
      settings.input.isIncluded && input.naturalScrolling.isIncluded,
      .input,
      "com.apple.swipescrolldirection"
    )
    applicable(
      settings.input.isIncluded && input.keyRepeatInterval.isIncluded,
      .input,
      "KeyRepeat"
    )
    applicable(
      settings.input.isIncluded && input.initialKeyRepeatDelay.isIncluded,
      .input,
      "InitialKeyRepeat"
    )
    applicable(
      settings.input.isIncluded && input.useStandardFunctionKeys.isIncluded,
      .input,
      "com.apple.keyboard.fnState"
    )

    var seenEvidence = Set<CaptureSnapshotEvidence>()
    for item in evidence where seenEvidence.insert(item).inserted {
      let disposition: CaptureItemDisposition?
      switch item.state {
      case .unreadable:
        disposition = .unreadable
      case .permissionRequired:
        disposition = .permissionRequired
      case .unsupported:
        disposition = .unsupported
      case .detected, .storable:
        disposition = nil
      }
      if let disposition {
        items.append(
          CaptureSummaryItem(
            group: item.group,
            key: sanitizedEvidenceKey(item),
            disposition: disposition
          )
        )
      }
    }

    return ProfileCaptureSummary(items: items)
  }

  private func sanitizedEvidenceKey(_ item: CaptureSnapshotEvidence) -> String {
    switch item.group {
    case .display:
      if item.key == "snapshot" || item.key.hasPrefix("capture.") {
        return item.key
      }
      return "display.settings"
    case .audio:
      return item.key.hasPrefix("device:") ? "audio.device" : item.key
    case .network:
      if item.key.hasPrefix("interface.") || item.key.hasPrefix("address.") {
        return "network.interface"
      }
      return item.key
    case .input:
      return item.key
    }
  }

  private func snapshotOnly(
    _ isPresent: Bool,
    _ group: SettingGroup,
    _ key: String,
    items: inout [CaptureSummaryItem]
  ) {
    guard isPresent else { return }
    items.append(
      CaptureSummaryItem(group: group, key: key, disposition: .savedSnapshotOnly)
    )
  }
}
