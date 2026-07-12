import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// A technical value that can be shown behind an explicit disclosure without
/// making opaque device identifiers part of the default profile summary.
public struct FriendlyTechnicalDetail: Equatable, Sendable {
  public var label: String
  public var value: String

  public init(label: String, value: String) {
    self.label = label
    self.value = value
  }
}

/// User-facing text and optional troubleshooting details for one saved value.
public struct FriendlyDisplayValue: Equatable, Sendable {
  public var primaryText: String
  public var secondaryText: String?
  public var technicalDetails: [FriendlyTechnicalDetail]

  public init(
    primaryText: String,
    secondaryText: String? = nil,
    technicalDetails: [FriendlyTechnicalDetail] = []
  ) {
    self.primaryText = primaryText
    self.secondaryText = secondaryText
    self.technicalDetails = technicalDetails
  }

  /// Compact default text. Technical identifiers are intentionally excluded.
  public var compactText: String {
    guard let secondaryText, !secondaryText.isEmpty else { return primaryText }
    return "\(primaryText) — \(secondaryText)"
  }
}

/// A planned change with opaque identifiers separated from its default text.
public struct FriendlyOperationPreview: Equatable, Sendable {
  public var previousValue: FriendlyDisplayValue
  public var desiredValue: FriendlyDisplayValue

  public init(
    previousValue: FriendlyDisplayValue,
    desiredValue: FriendlyDisplayValue
  ) {
    self.previousValue = previousValue
    self.desiredValue = desiredValue
  }
}

public enum AudioDeviceRole: String, Equatable, Sendable {
  case defaultInput
  case defaultOutput
  case systemOutput

  public var fallbackName: String {
    switch self {
    case .defaultInput: "Selected input device"
    case .defaultOutput: "Selected output device"
    case .systemOutput: "Selected alert output device"
    }
  }
}

/// Deterministic formatting helpers shared by profile summaries and previews.
public enum FriendlyValueFormatter {
  public static func displayName(
    _ identity: DisplayIdentity,
    fallbackName: String? = nil
  ) -> FriendlyDisplayValue {
    let trimmedName = identity.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let primaryText: String
    if let trimmedName, !trimmedName.isEmpty {
      primaryText = trimmedName
    } else if let fallbackName, !fallbackName.isEmpty {
      primaryText = fallbackName
    } else if identity.isBuiltIn {
      primaryText = "Built-in display"
    } else {
      primaryText = "External display"
    }

    var details: [FriendlyTechnicalDetail] = []
    if let uuid = identity.uuid {
      details.append(.init(label: "Display UUID", value: uuid.uuidString))
    }
    if let vendorID = identity.vendorID {
      details.append(.init(label: "Vendor ID", value: String(vendorID)))
    }
    if let modelID = identity.modelID {
      details.append(.init(label: "Model ID", value: String(modelID)))
    }
    if let serialNumber = identity.serialNumber {
      details.append(.init(label: "Serial number", value: String(serialNumber)))
    }

    return FriendlyDisplayValue(primaryText: primaryText, technicalDetails: details)
  }

  public static func audioDevice(
    uid: String?,
    role: AudioDeviceRole,
    namesByUID: [String: String] = [:]
  ) -> FriendlyDisplayValue {
    guard let uid = normalized(uid) else {
      return FriendlyDisplayValue(primaryText: "No device saved")
    }

    let suppliedName = normalized(namesByUID[uid])
    return FriendlyDisplayValue(
      primaryText: suppliedName ?? role.fallbackName,
      secondaryText: suppliedName == nil ? "Device name unavailable" : nil,
      technicalDetails: [.init(label: "Audio device UID", value: uid)]
    )
  }

  public static func displayMode(_ mode: DisplayMode) -> String {
    "\(mode.width) × \(mode.height) at \(decimal(mode.refreshRate)) Hz"
  }

  public static func percentage(_ value: Double) -> String {
    guard value.isFinite else { return "Value unavailable" }
    return "\(decimal(value * 100, maximumFractionDigits: 1))%"
  }

  public static func decimal(
    _ value: Double,
    maximumFractionDigits: Int = 2
  ) -> String {
    guard value.isFinite else { return "Value unavailable" }
    let digits = min(max(0, maximumFractionDigits), 6)
    let scale = pow(10, Double(digits))
    let roundedValue = (value * scale).rounded() / scale
    let rendered = String(
      format: "%.*f",
      locale: Locale(identifier: "en_US_POSIX"),
      digits,
      roundedValue
    )
    guard rendered.contains(".") else { return rendered }
    return
      rendered
      .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

public enum ProfileSummaryItemKind: String, Equatable, Sendable {
  case display
  case displayMode
  case displayRole
  case displayMirroring
  case displayActivity
  case displayRotation
  case displayPosition
  case defaultOutput
  case outputVolume
  case outputMute
  case systemOutput
  case defaultInput
  case wifiPower
  case wifiNetwork
  case ipv4
  case dnsServers
  case webProxy
  case secureWebProxy
  case pointerSpeed
  case naturalScrolling
  case keyRepeatInterval
  case initialKeyRepeatDelay
  case standardFunctionKeys
}

public struct ProfileSummaryItem: Equatable, Sendable {
  public var kind: ProfileSummaryItemKind
  public var label: String
  public var value: FriendlyDisplayValue

  public init(
    kind: ProfileSummaryItemKind,
    label: String,
    value: FriendlyDisplayValue
  ) {
    self.kind = kind
    self.label = label
    self.value = value
  }
}

public struct ProfileGroupSummary: Equatable, Sendable {
  public var group: SettingGroup
  public var items: [ProfileSummaryItem]

  public init(group: SettingGroup, items: [ProfileSummaryItem]) {
    self.group = group
    self.items = items
  }

  /// Compact, identifier-free text suitable for the collapsed group row.
  public var summaryText: String {
    items.map(\.value.compactText).joined(separator: " · ")
  }

  /// Details intended for a separate, collapsed technical-information section.
  public var technicalDetails: [FriendlyTechnicalDetail] {
    items.flatMap(\.value.technicalDetails)
  }
}

/// Turns persisted profile settings into stable, human-readable summaries.
/// The optional name map is transient presentation metadata and never changes
/// the persisted profile schema.
public struct ProfilePresentationBuilder: Equatable, Sendable {
  public static let groupOrder: [SettingGroup] = [.display, .audio, .network, .input]

  public var audioDeviceNamesByUID: [String: String]

  public init(audioDeviceNamesByUID: [String: String] = [:]) {
    self.audioDeviceNamesByUID = audioDeviceNamesByUID
  }

  public func summaries(for profile: DeskProfile) -> [ProfileGroupSummary] {
    Self.groupOrder.compactMap {
      summary(for: $0, in: profile.settings)
    }
  }

  public func summary(
    for group: SettingGroup,
    in settings: ProfileSettings
  ) -> ProfileGroupSummary? {
    guard settings.payload(for: group) != nil else { return nil }

    switch group {
    case .display:
      return displaySummary(settings.display.value)
    case .audio:
      return audioSummary(settings.audio.value)
    case .network:
      return networkSummary(settings.network.value)
    case .input:
      return inputSummary(settings.input.value)
    }
  }

  /// Sanitizes the local-only preview for display. Known Core Audio UIDs and
  /// unnamed-display identifiers are moved behind technical disclosure while
  /// display names, SSIDs, proxy hosts, and other user-provided text remain
  /// verbatim.
  public func operationPreview(
    for operation: PlannedOperation
  ) -> FriendlyOperationPreview? {
    guard let preview = operation.preview else { return nil }
    return FriendlyOperationPreview(
      previousValue: operationPreviewValue(preview.previousValue, operation: operation),
      desiredValue: operationPreviewValue(preview.desiredValue, operation: operation)
    )
  }

  private func displaySummary(_ settings: DisplayProfileSettings) -> ProfileGroupSummary {
    let includedDisplays = settings.displays.filter(hasIncludedDisplayValue)
    let usesOrdinals = includedDisplays.count > 1
    var items: [ProfileSummaryItem] = []

    for (index, display) in includedDisplays.enumerated() {
      let suffix = usesOrdinals ? " \(index + 1)" : ""
      let fallbackName =
        display.identity.isBuiltIn
        ? "Built-in display" : "External display\(suffix)"
      items.append(
        .init(
          kind: .display,
          label: "Display\(suffix)",
          value: FriendlyValueFormatter.displayName(
            display.identity,
            fallbackName: fallbackName
          )
        ))

      if display.mode.isIncluded {
        items.append(
          .init(
            kind: .displayMode,
            label: "Display\(suffix) mode",
            value: .init(
              primaryText: FriendlyValueFormatter.displayMode(display.mode.value)
            )
          ))
      }
      if display.isPrimary.isIncluded {
        items.append(
          .init(
            kind: .displayRole,
            label: "Display\(suffix) role",
            value: .init(
              primaryText: display.isPrimary.value ? "Primary display" : "Secondary display"
            )
          ))
      }
      if display.mirroring.isIncluded {
        items.append(
          .init(
            kind: .displayMirroring,
            label: "Display\(suffix) arrangement",
            value: mirroringValue(display.mirroring.value)
          ))
      }
      if display.isActive.isIncluded {
        items.append(
          .init(
            kind: .displayActivity,
            label: "Display\(suffix) state",
            value: .init(primaryText: display.isActive.value ? "Active" : "Inactive")
          ))
      }
      if display.rotationDegrees.isIncluded {
        items.append(
          .init(
            kind: .displayRotation,
            label: "Display\(suffix) rotation",
            value: .init(primaryText: "\(display.rotationDegrees.value)°")
          ))
      }
      if display.origin.isIncluded {
        items.append(
          .init(
            kind: .displayPosition,
            label: "Display\(suffix) position",
            value: .init(
              primaryText: "\(display.origin.value.x), \(display.origin.value.y)"
            )
          ))
      }
    }

    return ProfileGroupSummary(group: .display, items: items)
  }

  private func audioSummary(_ settings: AudioProfileSettings) -> ProfileGroupSummary {
    var items: [ProfileSummaryItem] = []

    if settings.defaultOutputUID.isIncluded {
      items.append(
        audioItem(
          kind: .defaultOutput,
          label: "Default output",
          uid: settings.defaultOutputUID.value,
          role: .defaultOutput
        ))
    }
    if settings.outputVolume.isIncluded {
      items.append(
        .init(
          kind: .outputVolume,
          label: "Output volume",
          value: optionalValue(settings.outputVolume.value) {
            .init(primaryText: FriendlyValueFormatter.percentage($0))
          }
        ))
    }
    if settings.outputMuted.isIncluded {
      items.append(
        .init(
          kind: .outputMute,
          label: "Output mute",
          value: optionalValue(settings.outputMuted.value) {
            .init(primaryText: $0 ? "Muted" : "Not muted")
          }
        ))
    }
    if settings.systemOutputUID.isIncluded {
      items.append(
        audioItem(
          kind: .systemOutput,
          label: "Alert output",
          uid: settings.systemOutputUID.value,
          role: .systemOutput
        ))
    }
    if settings.defaultInputUID.isIncluded {
      items.append(
        audioItem(
          kind: .defaultInput,
          label: "Default input",
          uid: settings.defaultInputUID.value,
          role: .defaultInput
        ))
    }

    return ProfileGroupSummary(group: .audio, items: items)
  }

  private func networkSummary(_ settings: NetworkProfileSettings) -> ProfileGroupSummary {
    var items: [ProfileSummaryItem] = []

    if settings.wifiPower.isIncluded {
      items.append(
        .init(
          kind: .wifiPower,
          label: "Wi-Fi",
          value: optionalValue(settings.wifiPower.value) {
            .init(primaryText: $0 ? "On" : "Off")
          }
        ))
    }
    if settings.wifiSSID.isIncluded {
      items.append(
        .init(
          kind: .wifiNetwork,
          label: "Wi-Fi network",
          value: optionalStringValue(settings.wifiSSID.value)
        ))
    }
    if settings.ipv4.isIncluded {
      items.append(
        .init(
          kind: .ipv4,
          label: "IPv4",
          value: ipv4Value(settings.ipv4.value)
        ))
    }
    if settings.dnsServers.isIncluded {
      let servers = settings.dnsServers.value.filter { !$0.isEmpty }
      items.append(
        .init(
          kind: .dnsServers,
          label: "DNS servers",
          value: .init(
            primaryText: servers.isEmpty ? "No custom DNS servers" : servers.joined(separator: ", ")
          )
        ))
    }
    if settings.webProxy.isIncluded {
      items.append(
        .init(
          kind: .webProxy,
          label: "Web proxy",
          value: proxyValue(settings.webProxy.value)
        ))
    }
    if settings.secureWebProxy.isIncluded {
      items.append(
        .init(
          kind: .secureWebProxy,
          label: "Secure web proxy",
          value: proxyValue(settings.secureWebProxy.value)
        ))
    }

    return ProfileGroupSummary(group: .network, items: items)
  }

  private func inputSummary(_ settings: InputProfileSettings) -> ProfileGroupSummary {
    var items: [ProfileSummaryItem] = []

    if settings.pointerSpeed.isIncluded {
      items.append(
        .init(
          kind: .pointerSpeed,
          label: "Pointer speed",
          value: optionalValue(settings.pointerSpeed.value) {
            .init(primaryText: FriendlyValueFormatter.decimal($0))
          }
        ))
    }
    if settings.naturalScrolling.isIncluded {
      items.append(
        .init(
          kind: .naturalScrolling,
          label: "Natural scrolling",
          value: optionalValue(settings.naturalScrolling.value) {
            .init(primaryText: $0 ? "On" : "Off")
          }
        ))
    }
    if settings.keyRepeatInterval.isIncluded {
      items.append(
        .init(
          kind: .keyRepeatInterval,
          label: "Key repeat interval",
          value: optionalValue(settings.keyRepeatInterval.value) {
            .init(primaryText: "\(FriendlyValueFormatter.decimal($0)) seconds")
          }
        ))
    }
    if settings.initialKeyRepeatDelay.isIncluded {
      items.append(
        .init(
          kind: .initialKeyRepeatDelay,
          label: "Initial key repeat delay",
          value: optionalValue(settings.initialKeyRepeatDelay.value) {
            .init(primaryText: "\(FriendlyValueFormatter.decimal($0)) seconds")
          }
        ))
    }
    if settings.useStandardFunctionKeys.isIncluded {
      items.append(
        .init(
          kind: .standardFunctionKeys,
          label: "Function keys",
          value: optionalValue(settings.useStandardFunctionKeys.value) {
            .init(primaryText: $0 ? "Standard function keys" : "Media controls")
          }
        ))
    }

    return ProfileGroupSummary(group: .input, items: items)
  }

  private func audioItem(
    kind: ProfileSummaryItemKind,
    label: String,
    uid: String?,
    role: AudioDeviceRole
  ) -> ProfileSummaryItem {
    .init(
      kind: kind,
      label: label,
      value: FriendlyValueFormatter.audioDevice(
        uid: uid,
        role: role,
        namesByUID: audioDeviceNamesByUID
      )
    )
  }

  private func operationPreviewValue(
    _ rawValue: String,
    operation: PlannedOperation
  ) -> FriendlyDisplayValue {
    if operation.group == .display,
      operation.key == "display.atomic-configuration"
    {
      return displayOperationPreviewValue(rawValue)
    }

    guard operation.group == .audio,
      let role = audioRole(forOperationKey: operation.key)
    else {
      return .init(primaryText: rawValue)
    }

    if let splitValue = splitAudioPreviewValue(rawValue) {
      return .init(
        primaryText: splitValue.name,
        technicalDetails: [.init(label: "Audio device UID", value: splitValue.uid)]
      )
    }

    return FriendlyValueFormatter.audioDevice(
      uid: rawValue,
      role: role,
      namesByUID: audioDeviceNamesByUID
    )
  }

  private func displayOperationPreviewValue(_ rawValue: String) -> FriendlyDisplayValue {
    let lines = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
    let usesOrdinals = lines.count > 1
    var technicalDetails: [FriendlyTechnicalDetail] = []

    let friendlyLines = lines.enumerated().map { index, rawLine in
      var line = String(rawLine)
      let displayNumber = index + 1
      let displayFallback = usesOrdinals ? "External display \(displayNumber)" : "External display"

      if let separator = line.range(of: " • ") {
        let identity = String(line[..<separator.lowerBound])
        let sanitized = sanitizedDisplayIdentity(identity, fallbackName: displayFallback)
        line.replaceSubrange(line.startIndex..<separator.lowerBound, with: sanitized.text)
        if let identifier = sanitized.identifier {
          technicalDetails.append(
            .init(label: "Display \(displayNumber) identifier", value: identifier)
          )
        }
      }

      if let mirrorSeparator = line.range(of: " → ", options: .backwards) {
        let identityStart = mirrorSeparator.upperBound
        let identity = String(line[identityStart...])
        let sanitized = sanitizedDisplayIdentity(identity, fallbackName: "Another display")
        line.replaceSubrange(identityStart..<line.endIndex, with: sanitized.text)
        if let identifier = sanitized.identifier {
          technicalDetails.append(
            .init(label: "Display \(displayNumber) mirror identifier", value: identifier)
          )
        }
      }

      return line
    }

    return .init(
      primaryText: friendlyLines.joined(separator: "\n"),
      technicalDetails: technicalDetails
    )
  }

  private func sanitizedDisplayIdentity(
    _ rawValue: String,
    fallbackName: String
  ) -> (text: String, identifier: String?) {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.hasPrefix("🖥") else {
      return (value, nil)
    }

    let identifier = value.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
    return (fallbackName, identifier.isEmpty ? nil : identifier)
  }

  private func audioRole(forOperationKey key: String) -> AudioDeviceRole? {
    switch key {
    case "defaultInput": .defaultInput
    case "defaultOutput": .defaultOutput
    case "systemOutput": .systemOutput
    default: nil
    }
  }

  private func splitAudioPreviewValue(_ value: String) -> (name: String, uid: String)? {
    guard value.last == "]",
      let separator = value.range(of: " [", options: .backwards)
    else {
      return nil
    }

    let name = value[..<separator.lowerBound]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let uidEnd = value.index(before: value.endIndex)
    let uid = value[separator.upperBound..<uidEnd]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !uid.isEmpty else { return nil }
    return (name, uid)
  }

  private func hasIncludedDisplayValue(_ display: DisplayTargetSettings) -> Bool {
    display.isPrimary.isIncluded
      || display.origin.isIncluded
      || display.mirroring.isIncluded
      || display.mode.isIncluded
      || display.rotationDegrees.isIncluded
      || display.isActive.isIncluded
  }

  private func mirroringValue(_ mirroring: DisplayMirroring) -> FriendlyDisplayValue {
    switch mirroring {
    case .extended:
      return .init(primaryText: "Extended desktop")
    case .mirrors(let identity):
      let target = FriendlyValueFormatter.displayName(identity, fallbackName: "Another display")
      return .init(
        primaryText: "Mirrors \(target.primaryText)",
        technicalDetails: target.technicalDetails
      )
    }
  }

  private func ipv4Value(_ configuration: IPv4Configuration?) -> FriendlyDisplayValue {
    guard let configuration else {
      return .init(primaryText: "Value unavailable")
    }
    switch configuration {
    case .dhcp:
      return .init(primaryText: "Automatic (DHCP)")
    case .manual(let address, let subnetMask, let router):
      let secondaryParts = ["Subnet \(subnetMask)", router.map { "Router \($0)" }]
        .compactMap { $0 }
      return .init(
        primaryText: "Manual — \(address)",
        secondaryText: secondaryParts.joined(separator: " · ")
      )
    }
  }

  private func proxyValue(_ proxy: ProxyConfiguration?) -> FriendlyDisplayValue {
    guard let proxy else { return .init(primaryText: "Value unavailable") }
    guard proxy.enabled else { return .init(primaryText: "Off") }
    return .init(primaryText: "\(proxy.host):\(proxy.port)")
  }

  private func optionalStringValue(_ value: String?) -> FriendlyDisplayValue {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else {
      return .init(primaryText: "Value unavailable")
    }
    return .init(primaryText: value)
  }

  private func optionalValue<Value>(
    _ value: Value?,
    transform: (Value) -> FriendlyDisplayValue
  ) -> FriendlyDisplayValue {
    guard let value else { return .init(primaryText: "Value unavailable") }
    return transform(value)
  }
}

public enum MenuActionDisabledReason: String, CaseIterable, Equatable, Sendable {
  case profileDisabled
  case readinessRefreshing
  case applying
  case transactionInProgress
  case pendingDisplayConfirmation
  case noIncludedSettings
  case conditionsUnsatisfied
  case noChanges
  case unavailableSettings
  case noAvailableOperations
  case forceApplyNotNeeded
  case temporarilyUnavailable

  public var defaultMessage: String {
    switch self {
    case .profileDisabled: "Enable this profile to apply it."
    case .readinessRefreshing: "Checking whether this profile can be applied…"
    case .applying: "This profile is being applied."
    case .transactionInProgress: "Another profile action is still in progress."
    case .pendingDisplayConfirmation:
      "Confirm or revert the previous display change first."
    case .noIncludedSettings: "Include at least one setting before applying this profile."
    case .conditionsUnsatisfied: "The profile conditions are not satisfied."
    case .noChanges: "The Mac already matches this profile."
    case .unavailableSettings: "One or more included settings are unavailable."
    case .noAvailableOperations: "No available setting can be applied."
    case .forceApplyNotNeeded: "Available-items apply is only needed for a partial profile."
    case .temporarilyUnavailable: "This action is temporarily unavailable."
    }
  }

  public var symbolName: String {
    switch self {
    case .profileDisabled: "pause.circle"
    case .readinessRefreshing: "arrow.clockwise"
    case .applying, .transactionInProgress: "hourglass"
    case .pendingDisplayConfirmation: "display.trianglebadge.exclamationmark"
    case .noIncludedSettings: "square.dashed"
    case .conditionsUnsatisfied: "checklist.unchecked"
    case .noChanges: "checkmark.circle"
    case .unavailableSettings, .noAvailableOperations: "exclamationmark.circle"
    case .forceApplyNotNeeded: "info.circle"
    case .temporarilyUnavailable: "clock"
    }
  }
}

public struct MenuActionAvailability: Equatable, Sendable {
  public var isEnabled: Bool
  public var disabledReason: MenuActionDisabledReason?

  public init(
    isEnabled: Bool,
    disabledReason: MenuActionDisabledReason? = nil
  ) {
    self.isEnabled = isEnabled
    self.disabledReason = isEnabled ? nil : (disabledReason ?? .temporarilyUnavailable)
  }
}

/// Presentation state for one profile's primary and secondary menu actions.
/// Inputs are cached, read-only readiness facts; constructing this state performs
/// no snapshot, planning, or system mutation.
public struct MenuProfileActionState: Equatable, Sendable {
  public var review: MenuActionAvailability
  public var apply: MenuActionAvailability
  public var forceApply: MenuActionAvailability

  public init(
    profile: DeskProfile,
    readiness: ProfileReadiness,
    normalApplyAvailable: Bool,
    forceApplyAvailable: Bool,
    isRefreshing: Bool = false,
    isTransactionLocked: Bool = false,
    rejectionReasons: [ApplyRejectionReason] = [],
    forceRejectionReasons: [ApplyRejectionReason]? = nil
  ) {
    let normalRejectionReasons = Set(rejectionReasons)
    let forceRejectionReasons = Set(forceRejectionReasons ?? rejectionReasons)
    let sharedBlocker = Self.sharedBlocker(
      readiness: readiness,
      isRefreshing: isRefreshing,
      isTransactionLocked: isTransactionLocked
    )

    review = sharedBlocker.map(Self.disabled) ?? .init(isEnabled: true)

    if let sharedBlocker {
      apply = Self.disabled(sharedBlocker)
      forceApply = Self.disabled(sharedBlocker)
      return
    }

    guard profile.isEnabled else {
      apply = Self.disabled(.profileDisabled)
      forceApply = Self.disabled(.profileDisabled)
      return
    }

    let hasIncludedSettings = SettingGroup.safeApplicationSequence.contains {
      profile.settings.payload(for: $0) != nil
    }
    guard hasIncludedSettings else {
      apply = Self.disabled(.noIncludedSettings)
      forceApply = Self.disabled(.noIncludedSettings)
      return
    }

    if normalApplyAvailable {
      apply = .init(isEnabled: true)
    } else {
      apply = Self.disabled(
        Self.applyDisabledReason(
          readiness: readiness,
          rejectionReasons: normalRejectionReasons
        ))
    }

    if forceApplyAvailable {
      forceApply = .init(isEnabled: true)
    } else {
      forceApply = Self.disabled(
        Self.forceApplyDisabledReason(
          readiness: readiness,
          rejectionReasons: forceRejectionReasons
        ))
    }
  }

  private static func sharedBlocker(
    readiness: ProfileReadiness,
    isRefreshing: Bool,
    isTransactionLocked: Bool
  ) -> MenuActionDisabledReason? {
    if readiness == .applying { return .applying }
    if isTransactionLocked { return .transactionInProgress }
    if isRefreshing { return .readinessRefreshing }
    return nil
  }

  private static func applyDisabledReason(
    readiness: ProfileReadiness,
    rejectionReasons: Set<ApplyRejectionReason>
  ) -> MenuActionDisabledReason {
    if let explicitReason = mappedRejectionReason(rejectionReasons) {
      return explicitReason
    }
    switch readiness {
    case .ready, .applied:
      return .noChanges
    case .partial:
      return .unavailableSettings
    case .unavailable:
      return .noAvailableOperations
    case .failed:
      return .temporarilyUnavailable
    case .applying:
      return .applying
    }
  }

  private static func forceApplyDisabledReason(
    readiness: ProfileReadiness,
    rejectionReasons: Set<ApplyRejectionReason>
  ) -> MenuActionDisabledReason {
    if let explicitReason = mappedRejectionReason(rejectionReasons) {
      return explicitReason
    }
    switch readiness {
    case .ready, .applied:
      return .forceApplyNotNeeded
    case .partial, .unavailable:
      return .noAvailableOperations
    case .failed:
      return .temporarilyUnavailable
    case .applying:
      return .applying
    }
  }

  private static func mappedRejectionReason(
    _ rejectionReasons: Set<ApplyRejectionReason>
  ) -> MenuActionDisabledReason? {
    let ordered: [(ApplyRejectionReason, MenuActionDisabledReason)] = [
      (.profileDisabled, .profileDisabled),
      (.transactionInProgress, .transactionInProgress),
      (.safetyConfirmationCapacityReached, .pendingDisplayConfirmation),
      (.noIncludedSettings, .noIncludedSettings),
      (.conditionsUnsatisfied, .conditionsUnsatisfied),
      (.noOperations, .noChanges),
      (.fatalValidationIssues, .unavailableSettings),
      (.unavailableItems, .unavailableSettings),
    ]
    return ordered.first { rejectionReasons.contains($0.0) }?.1
  }

  private static func disabled(
    _ reason: MenuActionDisabledReason
  ) -> MenuActionAvailability {
    .init(isEnabled: false, disabledReason: reason)
  }
}
