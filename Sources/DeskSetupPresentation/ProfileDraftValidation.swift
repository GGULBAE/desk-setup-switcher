import Darwin
import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// Stable identifier used to connect a validation issue, its inline message,
/// accessibility invalid state, and keyboard focus target.
public struct DraftFieldIdentifier: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public static var profileName: Self {
    Self(rawValue: "profile.name")
  }

  public static var profileDescription: Self {
    Self(rawValue: "profile.description")
  }

  public static func group(_ group: SettingGroup) -> Self {
    Self(rawValue: "settings.\(group.rawValue)")
  }

  public static func display(_ id: UUID, _ field: DisplayDraftField) -> Self {
    Self(rawValue: "settings.display.\(id.uuidString.lowercased()).\(field.rawValue)")
  }

  public static var displayPrimary: Self {
    Self(rawValue: "settings.display.primary")
  }

  public static func audio(_ field: AudioDraftField) -> Self {
    Self(rawValue: "settings.audio.\(field.rawValue)")
  }

  public static func network(_ field: NetworkDraftField) -> Self {
    Self(rawValue: "settings.network.\(field.rawValue)")
  }

  public static func networkService(
    at index: Int,
    _ field: NetworkDraftField
  ) -> Self {
    Self(rawValue: "settings.network.serviceIPv4.\(max(0, index)).\(field.rawValue)")
  }

  public static func dnsServer(at index: Int) -> Self {
    Self(rawValue: "settings.network.dnsServers.\(max(0, index))")
  }

  public static func input(_ field: InputDraftField) -> Self {
    Self(rawValue: "settings.input.\(field.rawValue)")
  }
}

public enum DisplayDraftField: String, Equatable, Sendable {
  case originX
  case originY
  case modeWidth
  case modeHeight
  case modePixelWidth
  case modePixelHeight
  case modeRefreshRate
  case colorProfile
  case rotationDegrees
}

public enum AudioDraftField: String, Equatable, Sendable {
  case defaultInputDevice
  case defaultOutputDevice
  case systemOutputDevice
  case inputVolume
  case outputVolume
  case outputMute
}

public enum NetworkDraftField: String, Equatable, Sendable {
  case wifiPower
  case wifiSSID
  case ipv4
  case ipv4Address
  case ipv4SubnetMask
  case ipv4Router
  case dnsServers
  case webProxy
  case webProxyHost
  case webProxyPort
  case secureWebProxy
  case secureWebProxyHost
  case secureWebProxyPort
}

public enum InputDraftField: String, Equatable, Sendable {
  case pointerSpeed
  case naturalScrolling
  case keyRepeatInterval
  case initialKeyRepeatDelay
  case standardFunctionKeys
}

/// A localizable validation reason. Associated bounds are display metadata,
/// never user-entered raw values.
public enum DraftValidationMessage: Equatable, Sendable {
  case required
  case cannotBeBlank
  case enterProfileName
  case selectAtLeastOneSetting
  case outOfRange(minimum: Double, maximum: Double)
  case tooLong(maximum: Int)
  case invalidDisplayDimension
  case chooseOnePrimaryDisplay
  case repairPrimaryDisplayInclusion
  case invalidWiFiNetworkName
  case invalidIPv4Address
  case invalidSubnetMask
  case invalidIPAddress
  case invalidRotation

  public var localizationKey: String {
    switch self {
    case .required: "validation.required"
    case .cannotBeBlank: "validation.blank"
    case .enterProfileName: "validation.profile.name"
    case .selectAtLeastOneSetting: "validation.group.noLeaf"
    case .outOfRange: "validation.range"
    case .tooLong: "validation.length"
    case .invalidDisplayDimension: "validation.display.dimension"
    case .chooseOnePrimaryDisplay: "validation.display.primary"
    case .repairPrimaryDisplayInclusion: "validation.display.primaryInclusion"
    case .invalidWiFiNetworkName: "validation.wifi.name"
    case .invalidIPv4Address: "validation.ipv4.address"
    case .invalidSubnetMask: "validation.ipv4.subnetMask"
    case .invalidIPAddress: "validation.ipAddress"
    case .invalidRotation: "validation.display.rotation"
    }
  }

  public var defaultMessage: String {
    switch self {
    case .required: "Choose a value."
    case .cannotBeBlank: "Enter a value."
    case .enterProfileName: "Enter a profile name."
    case .selectAtLeastOneSetting: "Select at least one setting."
    case .outOfRange(let minimum, let maximum):
      "Enter a value from \(format(minimum)) through \(format(maximum))."
    case .tooLong(let maximum): "Enter \(maximum) characters or fewer."
    case .invalidDisplayDimension: "Choose a valid display mode."
    case .chooseOnePrimaryDisplay: "Choose one primary display."
    case .repairPrimaryDisplayInclusion:
      "Turn on Include for the primary display setting to repair this profile."
    case .invalidWiFiNetworkName: "Enter a Wi-Fi network name containing 1 to 32 UTF-8 bytes."
    case .invalidIPv4Address: "Enter a valid IPv4 address."
    case .invalidSubnetMask: "Enter a valid contiguous IPv4 subnet mask."
    case .invalidIPAddress: "Enter a valid IP address."
    case .invalidRotation: "Choose 0°, 90°, 180°, or 270°."
    }
  }

  private func format(_ value: Double) -> String {
    FriendlyValueFormatter.decimal(value)
  }
}

public struct DraftValidationIssue: Equatable, Sendable, Identifiable {
  public var fieldID: DraftFieldIdentifier
  public var group: SettingGroup?
  public var message: DraftValidationMessage

  public init(
    fieldID: DraftFieldIdentifier,
    group: SettingGroup?,
    message: DraftValidationMessage
  ) {
    self.fieldID = fieldID
    self.group = group
    self.message = message
  }

  public var id: DraftFieldIdentifier {
    fieldID
  }

  public var localizationKey: String {
    message.localizationKey
  }

  public var defaultMessage: String {
    message.defaultMessage
  }
}

public struct ProfileDraftValidation: Equatable, Sendable {
  public var issues: [DraftValidationIssue]

  public init(issues: [DraftValidationIssue]) {
    self.issues = issues
  }

  public var isValid: Bool {
    issues.isEmpty
  }

  public var firstInvalidField: DraftFieldIdentifier? {
    issues.first?.fieldID
  }

  public func issue(for fieldID: DraftFieldIdentifier) -> DraftValidationIssue? {
    issues.first { $0.fieldID == fieldID }
  }
}

/// Pure pre-save validation for user-editable profile fields.
public struct ProfileDraftValidator: Equatable, Sendable {
  public static let maximumStringScalars = 1_024

  public init() {}

  public func validate(_ profile: DeskProfile) -> ProfileDraftValidation {
    var issues: [DraftValidationIssue] = []
    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      append(.enterProfileName, field: .profileName, group: nil, to: &issues)
    }
    validateStringLength(profile.name, field: .profileName, group: nil, issues: &issues)
    validateStringLength(
      profile.profileDescription,
      field: .profileDescription,
      group: nil,
      issues: &issues
    )
    validateSettings(profile.settings, issues: &issues)
    return ProfileDraftValidation(issues: issues)
  }

  public func validate(_ settings: ProfileSettings) -> ProfileDraftValidation {
    var issues: [DraftValidationIssue] = []
    validateSettings(settings, issues: &issues)
    return ProfileDraftValidation(issues: issues)
  }

  private func validateSettings(
    _ settings: ProfileSettings,
    issues: inout [DraftValidationIssue]
  ) {
    validateDisplay(settings.display, issues: &issues)
    validateAudio(settings.audio, issues: &issues)
    validateNetwork(settings.network, issues: &issues)
  }

  private func validateDisplay(
    _ group: SettingGroupConfiguration<DisplayProfileSettings>,
    issues: inout [DraftValidationIssue]
  ) {
    guard
      group.value.displays.contains(where: {
        $0.isPrimary.isIncluded || $0.mirroring.isIncluded || $0.mode.isIncluded
          || $0.colorProfile.isIncluded
      })
    else { return }

    let primaryOptions = group.value.displays.map(\.isPrimary)
    let includesPrimaryDisplay = primaryOptions.contains(where: \.isIncluded)
    if includesPrimaryDisplay, !primaryOptions.allSatisfy(\.isIncluded) {
      append(
        .repairPrimaryDisplayInclusion,
        field: .displayPrimary,
        group: .display,
        to: &issues
      )
    } else if includesPrimaryDisplay,
      primaryOptions.count(where: { $0.value }) != 1
    {
      append(
        .chooseOnePrimaryDisplay,
        field: .displayPrimary,
        group: .display,
        to: &issues
      )
    }

    for display in group.value.displays {
      if display.origin.isIncluded {
        validateInteger(
          display.origin.value.x,
          range: Int(Int32.min)...Int(Int32.max),
          field: .display(display.id, .originX),
          group: .display,
          issues: &issues
        )
        validateInteger(
          display.origin.value.y,
          range: Int(Int32.min)...Int(Int32.max),
          field: .display(display.id, .originY),
          group: .display,
          issues: &issues
        )
      }

      if display.mode.isIncluded {
        let mode = display.mode.value
        validateDisplayDimension(
          mode.width,
          field: .display(display.id, .modeWidth),
          issues: &issues
        )
        validateDisplayDimension(
          mode.height,
          field: .display(display.id, .modeHeight),
          issues: &issues
        )
        validateDisplayDimension(
          mode.pixelWidth,
          field: .display(display.id, .modePixelWidth),
          issues: &issues
        )
        validateDisplayDimension(
          mode.pixelHeight,
          field: .display(display.id, .modePixelHeight),
          issues: &issues
        )
        validateNumber(
          mode.refreshRate,
          range: 0...1_000,
          field: .display(display.id, .modeRefreshRate),
          group: .display,
          issues: &issues
        )
      }

      if display.colorProfile.isIncluded {
        guard let target = display.colorProfile.value else {
          append(
            .required,
            field: .display(display.id, .colorProfile),
            group: .display,
            to: &issues
          )
          continue
        }
        if isBlank(target.registeredProfileID) || isBlank(target.fileSHA256) {
          append(
            .cannotBeBlank,
            field: .display(display.id, .colorProfile),
            group: .display,
            to: &issues
          )
        }
        validateStringLength(
          target.registeredProfileID,
          field: .display(display.id, .colorProfile),
          group: .display,
          issues: &issues
        )
        validateStringLength(
          target.fileSHA256,
          field: .display(display.id, .colorProfile),
          group: .display,
          issues: &issues
        )
      }

    }
  }

  private func validateAudio(
    _ group: SettingGroupConfiguration<AudioProfileSettings>,
    issues: inout [DraftValidationIssue]
  ) {
    guard
      group.value.defaultInputUID.isIncluded
        || group.value.defaultOutputUID.isIncluded
        || group.value.inputVolume.isIncluded
        || group.value.outputVolume.isIncluded
    else { return }

    validateIncludedString(
      group.value.defaultInputUID,
      field: .audio(.defaultInputDevice),
      group: .audio,
      issues: &issues
    )
    validateIncludedString(
      group.value.defaultOutputUID,
      field: .audio(.defaultOutputDevice),
      group: .audio,
      issues: &issues
    )
    validateIncludedNumber(
      group.value.inputVolume,
      range: 0...1,
      field: .audio(.inputVolume),
      group: .audio,
      issues: &issues
    )
    validateIncludedNumber(
      group.value.outputVolume,
      range: 0...1,
      field: .audio(.outputVolume),
      group: .audio,
      issues: &issues
    )
  }

  private func validateNetwork(
    _ group: SettingGroupConfiguration<NetworkProfileSettings>,
    issues: inout [DraftValidationIssue]
  ) {
    guard group.value.serviceIPv4.contains(where: { $0.configuration.isIncluded })
    else { return }

    for (index, service) in group.value.serviceIPv4.enumerated()
    where service.configuration.isIncluded {
      guard let configuration = service.configuration.value else {
        append(
          .required,
          field: .networkService(at: index, .ipv4),
          group: .network,
          to: &issues
        )
        continue
      }
      if case .manual(let address, let subnetMask, let router) = configuration {
        if !isIPv4Address(address) {
          append(
            .invalidIPv4Address,
            field: .networkService(at: index, .ipv4Address),
            group: .network,
            to: &issues
          )
        }
        if !isContiguousIPv4Mask(subnetMask) {
          append(
            .invalidSubnetMask,
            field: .networkService(at: index, .ipv4SubnetMask),
            group: .network,
            to: &issues
          )
        }
        if let router, !isIPv4Address(router) {
          append(
            .invalidIPv4Address,
            field: .networkService(at: index, .ipv4Router),
            group: .network,
            to: &issues
          )
        }
      }
    }

  }

  private func validateIncludedString(
    _ option: SettingOption<String?>,
    field: DraftFieldIdentifier,
    group: SettingGroup,
    issues: inout [DraftValidationIssue]
  ) {
    guard option.isIncluded else { return }
    guard let value = option.value else {
      append(.required, field: field, group: group, to: &issues)
      return
    }
    if isBlank(value) {
      append(.cannotBeBlank, field: field, group: group, to: &issues)
    }
    validateStringLength(value, field: field, group: group, issues: &issues)
  }

  private func validateIncludedNumber(
    _ option: SettingOption<Double?>,
    range: ClosedRange<Double>,
    field: DraftFieldIdentifier,
    group: SettingGroup,
    issues: inout [DraftValidationIssue]
  ) {
    guard option.isIncluded else { return }
    guard let value = option.value else {
      append(.required, field: field, group: group, to: &issues)
      return
    }
    validateNumber(
      value,
      range: range,
      field: field,
      group: group,
      issues: &issues
    )
  }

  private func validateNumber(
    _ value: Double,
    range: ClosedRange<Double>,
    field: DraftFieldIdentifier,
    group: SettingGroup,
    issues: inout [DraftValidationIssue]
  ) {
    if !value.isFinite || !range.contains(value) {
      append(
        .outOfRange(minimum: range.lowerBound, maximum: range.upperBound),
        field: field,
        group: group,
        to: &issues
      )
    }
  }

  private func validateInteger(
    _ value: Int,
    range: ClosedRange<Int>,
    field: DraftFieldIdentifier,
    group: SettingGroup,
    issues: inout [DraftValidationIssue]
  ) {
    if !range.contains(value) {
      append(
        .outOfRange(
          minimum: Double(range.lowerBound),
          maximum: Double(range.upperBound)
        ),
        field: field,
        group: group,
        to: &issues
      )
    }
  }

  private func validateDisplayDimension(
    _ value: Int,
    field: DraftFieldIdentifier,
    issues: inout [DraftValidationIssue]
  ) {
    if !(1...100_000).contains(value) {
      append(
        .invalidDisplayDimension,
        field: field,
        group: .display,
        to: &issues
      )
    }
  }

  private func append(
    _ message: DraftValidationMessage,
    field: DraftFieldIdentifier,
    group: SettingGroup?,
    to issues: inout [DraftValidationIssue]
  ) {
    issues.append(
      DraftValidationIssue(fieldID: field, group: group, message: message)
    )
  }

  @discardableResult
  private func validateStringLength(
    _ value: String?,
    field: DraftFieldIdentifier,
    group: SettingGroup?,
    issues: inout [DraftValidationIssue]
  ) -> Bool {
    guard let value,
      value.unicodeScalars.count > Self.maximumStringScalars
    else { return false }
    append(
      .tooLong(maximum: Self.maximumStringScalars),
      field: field,
      group: group,
      to: &issues
    )
    return true
  }

  private func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func isIPv4Address(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.utf8.contains(0) else { return false }
    var address = in_addr()
    return trimmed.withCString { inet_pton(AF_INET, $0, &address) == 1 }
  }

  private func isContiguousIPv4Mask(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.utf8.contains(0) else { return false }
    var address = in_addr()
    guard trimmed.withCString({ inet_pton(AF_INET, $0, &address) == 1 }) else {
      return false
    }

    let bytes = withUnsafeBytes(of: &address) { Array($0) }
    var sawZero = false
    for byte in bytes {
      for shift in stride(from: 7, through: 0, by: -1) {
        let isOne = byte & (UInt8(1) << shift) != 0
        if sawZero, isOne { return false }
        if !isOne { sawZero = true }
      }
    }
    return true
  }
}
