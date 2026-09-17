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
/// value into UI state. Unavailable evidence is surfaced only for the three
/// visible Keyboard controls; snapshot-only and retired-field evidence remains
/// omitted because the user cannot act on it during capture.
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
    applicable(audio.outputMuted.isIncluded, .audio, "outputMute")

    let input = settings.input.value
    applicable(input.keyRepeatInterval.isIncluded, .input, "KeyRepeat")
    applicable(input.initialKeyRepeatDelay.isIncluded, .input, "InitialKeyRepeat")
    applicable(input.keyboardBrightness.isIncluded, .input, "KeyboardBrightness")

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
      let disposition = visibleKeyboardOmissionDisposition(item)
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

  private func visibleKeyboardOmissionDisposition(
    _ item: CaptureSnapshotEvidence
  ) -> CaptureItemDisposition? {
    guard item.group == .input,
      ["KeyRepeat", "InitialKeyRepeat", "KeyboardBrightness"].contains(item.key)
    else {
      // Permission-gated legacy Wi-Fi/Location values and retired settings are
      // not editor fields. Their denial must not degrade an unrelated capture.
      return nil
    }

    switch item.state {
    case .unreadable:
      return .unreadable
    case .permissionRequired:
      return .permissionRequired
    case .unsupported:
      return .unsupported
    case .detected, .storable:
      return nil
    }
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
