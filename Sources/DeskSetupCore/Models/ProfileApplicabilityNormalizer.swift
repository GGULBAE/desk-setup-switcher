import Foundation

/// Applies the current adapter support policy without discarding snapshot data.
///
/// Unsupported values remain available for display and round-trip compatibility,
/// but they are never treated as requested mutations. The transformation is
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
    normalized.settings = normalize(profile.settings)
    return normalized
  }

  public func normalize(_ settings: ProfileSettings) -> ProfileSettings {
    var normalized = settings

    normalizePrimaryDisplayApplicability(&normalized.display.value.displays)

    for index in normalized.display.value.displays.indices {
      normalized.display.value.displays[index].origin.isIncluded = false
      normalized.display.value.displays[index].rotationDegrees.isIncluded = false
      normalized.display.value.displays[index].isActive.isIncluded = false
    }

    normalized.audio.value.systemOutputUID.isIncluded = false
    normalized.audio.value.outputMuted.isIncluded = false

    for index in normalized.network.value.serviceIPv4.indices {
      normalized.network.value.serviceIPv4[index].configuration.isIncluded = false
    }
    normalized.network.value.ipv4.isIncluded = false
    normalized.network.value.dnsServers.isIncluded = false
    normalized.network.value.webProxy.isIncluded = false
    normalized.network.value.secureWebProxy.isIncluded = false

    normalized.input.value.pointerSpeed.isIncluded = false
    normalized.input.value.naturalScrolling.isIncluded = false
    normalized.input.value.keyRepeatInterval.isIncluded = false
    normalized.input.value.initialKeyRepeatDelay.isIncluded = false
    normalized.input.value.useStandardFunctionKeys.isIncluded = false

    if !normalized.display.value.hasIncludedOption {
      normalized.display.isIncluded = false
    }
    if !normalized.audio.value.hasIncludedOption {
      normalized.audio.isIncluded = false
    }
    if !normalized.network.value.hasIncludedOption {
      normalized.network.isIncluded = false
    }
    if !normalized.input.value.hasIncludedOption {
      normalized.input.isIncluded = false
    }

    return normalized
  }

  /// Primary-display selection is one global setting represented on every display target.
  /// A mixed inclusion state can otherwise look disabled in the editor while an included
  /// target is still planned by an adapter. Invalid global states therefore fail closed:
  /// values are preserved for repair, but every primary leaf becomes dormant.
  private func normalizePrimaryDisplayApplicability(
    _ displays: inout [DisplayTargetSettings]
  ) {
    guard !displays.isEmpty else { return }

    let primaryOptions = displays.map(\.isPrimary)
    let allIncluded = primaryOptions.allSatisfy(\.isIncluded)
    let allExcluded = primaryOptions.allSatisfy { !$0.isIncluded }
    let hasSingleSelection = primaryOptions.count(where: \.value) == 1

    guard (allIncluded && hasSingleSelection) || allExcluded else {
      for index in displays.indices {
        displays[index].isPrimary.isIncluded = false
      }
      return
    }
  }
}
