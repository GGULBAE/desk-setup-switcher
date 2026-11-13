import Foundation

/// Applies the current profile-setting policy without discarding saved values.
///
/// Explicit inclusion flags select supported values; retired setting kinds remain dormant
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

    for index in normalized.display.value.displays.indices {
      // Display values remain schema-compatible data, but the current product does not
      // capture, edit, or apply them.
      normalized.display.value.displays[index].isPrimary.isIncluded = false
      normalized.display.value.displays[index].mode.isIncluded = false
      normalized.display.value.displays[index].colorProfile.isIncluded = false
      normalized.display.value.displays[index].mirroring.isIncluded = false
      normalized.display.value.displays[index].origin.isIncluded = false
      normalized.display.value.displays[index].rotationDegrees.isIncluded = false
      normalized.display.value.displays[index].isActive.isIncluded = false
    }

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
    normalized.input.value.keyboardBrightness.isIncluded = false
    normalized.input.value.useStandardFunctionKeys.isIncluded = false

    normalized.display.isIncluded = false
    normalized.audio.isIncluded = normalized.audio.value.hasIncludedOption
    normalized.network.isIncluded = normalized.network.value.hasIncludedOption
    normalized.input.isIncluded = normalized.input.value.hasIncludedOption

    return normalized
  }

}
