import Foundation

/// Applies the current profile-setting policy without discarding saved values.
///
/// Registered supported values participate; retired setting kinds remain dormant
/// for round-trip compatibility and never request mutations. The transformation is
/// intentionally idempotent so it can be used at every persistence and planning
/// boundary.
public struct ProfileApplicabilityNormalizer: Sendable {
  public init() {}

  public func normalize(_ document: ProfileDocument) -> ProfileDocument {
    var normalized = document
    normalized.profiles = document.profiles.map(normalize)
    return normalized
  }

  public func normalize(_ profile: DeskProfile) -> DeskProfile {
    var normalized = profile
    // `isEnabled` remains in schema v1 for decode/round-trip compatibility,
    // but profile activation is no longer a product behavior.
    normalized.isEnabled = true
    normalized.settings = normalize(profile.settings)
    return normalized
  }

  public func normalize(_ settings: ProfileSettings) -> ProfileSettings {
    var normalized = settings

    normalizePrimaryDisplayApplicability(&normalized.display.value.displays)

    for index in normalized.display.value.displays.indices {
      // Registered resolutions always participate; schema-v1 exclusion flags are retired.
      normalized.display.value.displays[index].mode.isIncluded = true
      // Retired from profile capture/edit/apply. Keep legacy values dormant for JSON compatibility.
      normalized.display.value.displays[index].colorProfile.isIncluded = false
      normalized.display.value.displays[index].mirroring.isIncluded = false
      normalized.display.value.displays[index].origin.isIncluded = false
      normalized.display.value.displays[index].rotationDegrees.isIncluded = false
      normalized.display.value.displays[index].isActive.isIncluded = false
    }

    includeRegisteredValue(&normalized.audio.value.defaultInputUID)
    includeRegisteredValue(&normalized.audio.value.defaultOutputUID)
    includeRegisteredValue(&normalized.audio.value.inputVolume)
    includeRegisteredValue(&normalized.audio.value.outputVolume)
    includeRegisteredValue(&normalized.audio.value.outputMuted)
    normalized.audio.value.systemOutputUID.isIncluded = false

    for index in normalized.network.value.serviceIPv4.indices {
      normalized.network.value.serviceIPv4[index].configuration.isIncluded = false
    }
    normalized.network.value.wifiPower.isIncluded = false
    normalized.network.value.wifiSSID.isIncluded = false
    normalized.network.value.ipv4.isIncluded = false
    normalized.network.value.dnsServers.isIncluded = false
    normalized.network.value.webProxy.isIncluded = false
    normalized.network.value.secureWebProxy.isIncluded = false

    normalized.input.value.pointerSpeed.isIncluded = false
    normalized.input.value.naturalScrolling.isIncluded = false
    normalized.input.value.keyRepeatInterval.isIncluded = false
    normalized.input.value.initialKeyRepeatDelay.isIncluded = false
    normalized.input.value.useStandardFunctionKeys.isIncluded = false

    normalized.display.isIncluded = normalized.display.value.hasIncludedOption
    normalized.audio.isIncluded = normalized.audio.value.hasIncludedOption
    normalized.network.isIncluded = normalized.network.value.hasIncludedOption
    normalized.input.isIncluded = normalized.input.value.hasIncludedOption

    return normalized
  }

  /// Primary-display selection is one global setting represented on every display target.
  /// Legacy exclusion flags no longer hide a valid selection. Ambiguous selections
  /// still fail closed and retain their values for explicit repair in the picker.
  private func normalizePrimaryDisplayApplicability(
    _ displays: inout [DisplayTargetSettings]
  ) {
    guard !displays.isEmpty else { return }

    let primaryOptions = displays.map(\.isPrimary)
    let hasSingleSelection = primaryOptions.count(where: \.value) == 1

    for index in displays.indices {
      displays[index].isPrimary.isIncluded = hasSingleSelection
    }
  }

  /// Never invent missing values or suppress validation of an explicitly requested
  /// but missing value. Runtime availability remains an adapter/preflight concern.
  private func includeRegisteredValue<Value>(_ option: inout SettingOption<Value?>) {
    if option.value != nil {
      option.isIncluded = true
    }
  }
}
