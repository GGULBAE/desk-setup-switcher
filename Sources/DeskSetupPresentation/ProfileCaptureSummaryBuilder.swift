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

/// Deterministically reports saved, applicable leaves and actionable permission
/// gaps without carrying any SSID, address, device identifier, or other captured
/// value into UI state. Snapshot-only, unreadable, and unsupported evidence is
/// intentionally omitted from user-facing capture results because the user
/// cannot act on it during capture.
public struct ProfileCaptureSummaryBuilder: Equatable, Sendable {
  public init() {}

  public func summary(
    settings: ProfileSettings,
    evidence: [CaptureSnapshotEvidence]
  ) -> ProfileCaptureSummary {
    let settings = ProfileApplicabilityNormalizer().normalize(settings)
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
        display.isPrimary.isIncluded,
        .display,
        "\(prefix).primary"
      )
      applicable(
        display.mirroring.isIncluded,
        .display,
        "\(prefix).mirroring"
      )
      applicable(
        display.mode.isIncluded,
        .display,
        "\(prefix).mode"
      )
      applicable(
        display.colorProfile.isIncluded,
        .display,
        "\(prefix).colorProfile"
      )
    }

    let audio = settings.audio.value
    applicable(
      audio.defaultInputUID.isIncluded,
      .audio,
      "defaultInput"
    )
    applicable(
      audio.defaultOutputUID.isIncluded,
      .audio,
      "defaultOutput"
    )
    applicable(audio.inputVolume.isIncluded, .audio, "inputVolume")
    applicable(audio.outputVolume.isIncluded, .audio, "outputVolume")

    let network = settings.network.value
    for (index, service) in network.serviceIPv4.enumerated() {
      applicable(
        service.configuration.isIncluded,
        .network,
        "network.serviceIPv4.\(service.identity.kind.rawValue).\(index)"
      )
    }

    var seenEvidence = Set<CaptureSnapshotEvidence>()
    for item in evidence where seenEvidence.insert(item).inserted {
      let disposition: CaptureItemDisposition?
      switch item.state {
      case .permissionRequired:
        // Permission-gated legacy Wi-Fi/Location values are not editor fields.
        // Their denial must not make an otherwise unrelated capture incomplete.
        disposition = nil
      case .detected, .storable, .unreadable, .unsupported:
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

}
