import AppKit
import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

private var appRuntimeLocalizationBundle: Bundle {
  #if SWIFT_PACKAGE
    Bundle.module
  #else
    Bundle.main
  #endif
}

func appResolvedProfileSymbolName(_ symbolName: String) -> String {
  let candidate = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !candidate.isEmpty,
    NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil
  else {
    return "questionmark.square.dashed"
  }
  return candidate
}

/// Localizes messages produced by the framework targets at the UI boundary.
/// Device names, SSIDs, identifiers, and other user data intentionally fall
/// back verbatim when they are not localization keys.
func appLocalizedRuntime(_ value: String) -> String {
  let exact = appRuntimeLocalizationBundle.localizedString(
    forKey: value,
    value: value,
    table: "Localizable"
  )
  if exact != value {
    return exact
  }

  if value.hasPrefix("Inverted condition: ") {
    return appRuntimeLocalizedFormat(
      "Inverted condition: %@",
      appLocalizedRuntime(String(value.dropFirst("Inverted condition: ".count)))
    )
  }

  for group in SettingGroup.allCases {
    let raw = group.rawValue
    let title = appSettingGroupTitle(group)
    let templates: [(String, String)] = [
      (
        "No adapter is registered for the \(raw) settings group.",
        "No adapter is registered for the %@ settings group."
      ),
      ("No adapter is registered for \(raw).", "No adapter is registered for %@."),
      (
        "The \(raw) settings could not be read safely.", "The %@ settings could not be read safely."
      ),
      (
        "The \(raw) settings could not be planned safely.",
        "The %@ settings could not be planned safely."
      ),
      (
        "More than one adapter was registered for the \(raw) settings group.",
        "More than one adapter was registered for the %@ settings group."
      ),
      (
        "\(raw.capitalized) readiness facts are unavailable.", "%@ readiness facts are unavailable."
      ),
    ]
    if let template = templates.first(where: { $0.0 == value })?.1 {
      return appRuntimeLocalizedFormat(template, title)
    }
  }

  for source in ["display", "audio", "network", "hardware", "location"] {
    if value == "The required \(source) readiness facts are unavailable." {
      return appRuntimeLocalizedFormat(
        "The required %@ readiness facts are unavailable.",
        appLocalizedRuntime(source.capitalized)
      )
    }
  }

  if value.hasPrefix("Wi-Fi interface ") {
    return appRuntimeLocalizedFormat(
      "Wi-Fi interface %@",
      String(value.dropFirst("Wi-Fi interface ".count))
    )
  }
  if value.hasPrefix("Interface ") {
    return appRuntimeLocalizedFormat(
      "Interface %@",
      String(value.dropFirst("Interface ".count))
    )
  }
  for family in ["ipv4", "ipv6"] where value == "Local \(family) address" {
    return appRuntimeLocalizedFormat("Local %@ address", family.uppercased())
  }

  if let count = integer(in: value, prefix: "Core Audio reported ", suffix: " device(s).") {
    return appRuntimeLocalizedFormat("Core Audio reported %lld device(s).", count)
  }
  if let count = integer(
    in: value,
    prefix: "Core Audio reported ",
    suffix: " device(s); identifiers were omitted."
  ) {
    return appRuntimeLocalizedFormat(
      "Core Audio reported %lld device(s); identifiers were omitted.",
      count
    )
  }
  if let status = integer(
    in: value,
    prefix: "Core Audio could not read software volume (OSStatus ",
    suffix: ")."
  ) {
    return appRuntimeLocalizedFormat(
      "Core Audio could not read software volume (OSStatus %lld).",
      status
    )
  }
  if let status = integer(
    in: value,
    prefix: "Core Audio could not read software mute (OSStatus ",
    suffix: ")."
  ) {
    return appRuntimeLocalizedFormat(
      "Core Audio could not read software mute (OSStatus %lld).",
      status
    )
  }
  if let count = integer(
    in: value,
    prefix: "Network snapshot available for ",
    suffix: " interface(s); no addresses or SSIDs logged."
  ) {
    return appRuntimeLocalizedFormat(
      "Network snapshot available for %lld interface(s); no addresses or SSIDs logged.",
      count
    )
  }

  for role in ["default input", "default output", "system output"] {
    let localizedRole = appLocalizedRuntime(role.capitalized)
    let templates: [(String, String)] = [
      ("No \(role) device UID was saved.", "No %@ device UID was saved."),
      ("The saved \(role) device is absent.", "The saved %@ device is absent."),
      (
        "The saved device does not support the \(role) scope.",
        "The saved device does not support the %@ scope."
      ),
      (
        "The saved \(role) device is unavailable or has the wrong scope.",
        "The saved %@ device is unavailable or has the wrong scope."
      ),
      ("The current \(role) device could not be read.", "The current %@ device could not be read."),
      (
        "The current \(role) device could not be backed up.",
        "The current %@ device could not be backed up."
      ),
      ("Change the \(role) device", "Change the %@ device"),
    ]
    if let template = templates.first(where: { $0.0 == value })?.1 {
      return appRuntimeLocalizedFormat(template, localizedRole)
    }
  }

  let inputKeys: [(String, String)] = [
    ("com.apple.mouse.scaling", appLocalizedRuntime("Pointer speed")),
    ("com.apple.swipescrolldirection", appLocalizedRuntime("Natural scrolling")),
    ("KeyRepeat", appLocalizedRuntime("Key repeat")),
    ("InitialKeyRepeat", appLocalizedRuntime("Initial key repeat delay")),
    ("com.apple.keyboard.fnState", appLocalizedRuntime("Function-key behavior")),
  ]
  for (key, title) in inputKeys {
    if value == "Updated the experimental \(key) preference." {
      return appRuntimeLocalizedFormat("Updated the experimental %@ preference.", title)
    }
    if value == "The saved \(key) value is outside the safe range." {
      return appRuntimeLocalizedFormat("The saved %@ value is outside the safe range.", title)
    }
  }

  return value
}

/// Formats typed draft-validation messages without attempting to use a
/// user-specific, already-interpolated value as a localization key.
func appLocalizedDraftValidationMessage(_ message: DraftValidationMessage) -> String {
  switch message {
  case .outOfRange(let minimum, let maximum):
    return appRuntimeLocalizedFormat(
      "Enter a value from %@ through %@.",
      FriendlyValueFormatter.decimal(minimum),
      FriendlyValueFormatter.decimal(maximum)
    )
  case .tooLong(let maximum):
    return appRuntimeLocalizedFormat(
      "Enter %lld characters or fewer.",
      maximum
    )
  case .required,
    .cannotBeBlank,
    .enterProfileName,
    .selectAtLeastOneSetting,
    .invalidDisplayDimension,
    .chooseOnePrimaryDisplay,
    .repairPrimaryDisplayInclusion,
    .invalidWiFiNetworkName,
    .invalidIPv4Address,
    .invalidSubnetMask,
    .invalidIPAddress,
    .invalidRotation:
    return appLocalizedRuntime(message.defaultMessage)
  }
}

func appProfileDraftValidationError(_ profile: DeskProfile) -> String? {
  guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return appLocalized("Enter a profile name.")
  }
  return ProfileDraftValidator().validate(profile).issues.first.map {
    appLocalizedDraftValidationMessage($0.message)
  }
}

func appOperationPreviewValue(
  _ value: String,
  operation: PlannedOperation,
  isPreviousValue: Bool
) -> String {
  switch operation.key {
  case "wifi.ssid":
    return isPreviousValue && value == "Not associated"
      ? appLocalizedRuntime(value) : value
  case "display.atomic-configuration":
    return appLocalizedDisplayOperationValue(value)
  case "defaultInput", "defaultOutput", "systemOutput":
    return appLocalizedFriendlyAudioValue(value)
  default:
    return appLocalizedRuntime(value)
  }
}

/// Localizes typed presentation phrases without ever looking up a user/device
/// value as a localization key. In particular, names such as "Home" or
/// "Office" remain verbatim even though those words are app localization keys.
func appProfileSummaryValue(_ item: ProfileSummaryItem) -> String {
  let primary: String
  let secondary: String?

  switch item.kind {
  case .display:
    primary = appLocalizedKnownDisplayName(item.value.primaryText)
    secondary = item.value.secondaryText
  case .displayMirroring:
    primary = appLocalizedMirroringValue(item.value.primaryText)
    secondary = item.value.secondaryText
  case .defaultInput, .defaultOutput, .systemOutput:
    primary = appLocalizedFriendlyAudioPrimary(item.value.primaryText)
    secondary = item.value.secondaryText.map(appLocalizedFriendlyAudioSecondary)
  case .wifiNetwork:
    primary = appLocalizedOnlyKnownValue(item.value.primaryText, keys: ["Value unavailable"])
    secondary = item.value.secondaryText
  case .ipv4:
    primary = appLocalizedIPv4Primary(item.value.primaryText)
    secondary = item.value.secondaryText.map(appLocalizedIPv4Secondary)
  case .dnsServers:
    primary = appLocalizedOnlyKnownValue(
      item.value.primaryText,
      keys: ["No custom DNS servers", "Value unavailable"]
    )
    secondary = item.value.secondaryText
  case .webProxy, .secureWebProxy:
    primary = appLocalizedOnlyKnownValue(
      item.value.primaryText,
      keys: ["Off", "Value unavailable"]
    )
    secondary = item.value.secondaryText
  case .displayMode, .displayRole, .displayActivity, .displayRotation,
    .displayPosition, .outputVolume, .outputMute, .wifiPower,
    .pointerSpeed, .naturalScrolling, .keyRepeatInterval, .initialKeyRepeatDelay,
    .standardFunctionKeys:
    primary = appLocalizedPresentationText(item.value.primaryText)
    secondary = item.value.secondaryText.map(appLocalizedPresentationText)
  }

  guard let secondary, !secondary.isEmpty else { return primary }
  return "\(primary) — \(secondary)"
}

private func appLocalizedOnlyKnownValue(_ value: String, keys: Set<String>) -> String {
  keys.contains(value) ? appLocalizedRuntime(value) : value
}

private func appLocalizedKnownDisplayName(_ value: String) -> String {
  if value == "Built-in display" || value == "External display" || value == "Another display" {
    return appLocalizedRuntime(value)
  }

  let words = value.split(separator: " ")
  if words.count == 3,
    words[0] == "External",
    words[1] == "display",
    let number = Int64(words[2])
  {
    return appRuntimeLocalizedFormat(
      "%@ %lld",
      appLocalizedRuntime("External display"),
      number
    )
  }
  return value
}

private func appLocalizedMirroringValue(_ value: String) -> String {
  if value == "Extended desktop" {
    return appLocalizedRuntime(value)
  }
  guard value.hasPrefix("Mirrors ") else { return value }
  let target = String(value.dropFirst("Mirrors ".count))
  return appRuntimeLocalizedFormat("Mirrors %@", appLocalizedKnownDisplayName(target))
}

private func appLocalizedFriendlyAudioValue(_ value: String) -> String {
  let parts = value.components(separatedBy: " — ")
  guard parts.count == 2 else {
    return appLocalizedFriendlyAudioPrimary(value)
  }
  return
    "\(appLocalizedFriendlyAudioPrimary(parts[0])) — \(appLocalizedFriendlyAudioSecondary(parts[1]))"
}

private func appLocalizedFriendlyAudioPrimary(_ value: String) -> String {
  appLocalizedOnlyKnownValue(
    value,
    keys: [
      "No device saved",
      "Selected input device",
      "Selected output device",
      "Selected alert output device",
    ]
  )
}

private func appLocalizedFriendlyAudioSecondary(_ value: String) -> String {
  appLocalizedOnlyKnownValue(value, keys: ["Device name unavailable"])
}

private func appLocalizedIPv4Primary(_ value: String) -> String {
  if value == "Automatic (DHCP)" || value == "Value unavailable" {
    return appLocalizedRuntime(value)
  }
  guard value.hasPrefix("Manual — ") else { return value }
  let address = String(value.dropFirst("Manual — ".count))
  return "\(appLocalizedRuntime("Manual")) — \(address)"
}

private func appLocalizedIPv4Secondary(_ value: String) -> String {
  value.components(separatedBy: " · ").map { component in
    if component.hasPrefix("Subnet ") {
      return appRuntimeLocalizedFormat(
        "Subnet %@",
        String(component.dropFirst("Subnet ".count))
      )
    }
    if component.hasPrefix("Router ") {
      return appRuntimeLocalizedFormat(
        "Router %@",
        String(component.dropFirst("Router ".count))
      )
    }
    return component
  }.joined(separator: " · ")
}

private func appLocalizedDisplayOperationValue(_ value: String) -> String {
  value.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine in
    var line = String(rawLine)
    if let separator = line.range(of: " • ") {
      let identity = String(line[..<separator.lowerBound])
      let localizedIdentity = appLocalizedKnownDisplayName(identity)
      line.replaceSubrange(line.startIndex..<separator.lowerBound, with: localizedIdentity)
    }
    if let mirrorSeparator = line.range(of: " → ", options: .backwards) {
      let targetStart = mirrorSeparator.upperBound
      let target = String(line[targetStart...])
      let localizedTarget = appLocalizedKnownDisplayName(target)
      line.replaceSubrange(targetStart..<line.endIndex, with: localizedTarget)
    }
    return line
  }.joined(separator: "\n")
}

/// Localizes the small, deterministic presentation phrases emitted by
/// `DeskSetupPresentation` while leaving device names and user data untouched.
func appLocalizedPresentationText(_ value: String) -> String {
  let exact = appLocalizedRuntime(value)
  if exact != value {
    return exact
  }

  for separator in [" — ", " · "] where value.contains(separator) {
    return value.components(separatedBy: separator)
      .map(appLocalizedPresentationText)
      .joined(separator: separator)
  }

  if value.hasPrefix("Mirrors ") {
    return appRuntimeLocalizedFormat(
      "Mirrors %@",
      appLocalizedPresentationText(String(value.dropFirst("Mirrors ".count)))
    )
  }
  if value.hasPrefix("Subnet ") {
    return appRuntimeLocalizedFormat(
      "Subnet %@",
      String(value.dropFirst("Subnet ".count))
    )
  }
  if value.hasPrefix("Router ") {
    return appRuntimeLocalizedFormat(
      "Router %@",
      String(value.dropFirst("Router ".count))
    )
  }

  if value.hasPrefix("Display ") || value.hasPrefix("External display ") {
    let words = value.split(separator: " ")
    if let numberIndex = words.firstIndex(where: { Int($0) != nil }),
      let number = Int64(words[numberIndex])
    {
      let prefix = words[..<numberIndex].joined(separator: " ")
      let suffix = words.dropFirst(numberIndex + 1).joined(separator: " ")
      let numbered = appRuntimeLocalizedFormat("%@ %lld", appLocalizedRuntime(prefix), number)
      return suffix.isEmpty
        ? numbered
        : appRuntimeLocalizedFormat("%@ %@", numbered, appLocalizedRuntime(suffix))
    }
  }

  if let range = value.range(of: " at "), value.hasSuffix(" Hz") {
    let dimensions = String(value[..<range.lowerBound])
    let rateStart = range.upperBound
    let rateEnd = value.index(value.endIndex, offsetBy: -" Hz".count)
    let rate = String(value[rateStart..<rateEnd])
    return appRuntimeLocalizedFormat("%@ at %@ Hz", dimensions, rate)
  }

  if value.hasSuffix(" seconds") {
    let duration = String(value.dropLast(" seconds".count))
    return appRuntimeLocalizedFormat("%@ seconds", duration)
  }

  return value
}

func appSnapshotItemLabel(_ item: SnapshotItem) -> String {
  if item.key.hasPrefix("device:") {
    return item.label
  }
  if item.key.hasPrefix("display."), item.key != "display.active" {
    switch item.label {
    case "Built-in Display", "External Display":
      return appLocalizedRuntime(item.label)
    default:
      // A display product name is user/device-provided and stays verbatim.
      return item.label
    }
  }
  return appLocalizedRuntime(item.label)
}

private func appRuntimeLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
  let format = appRuntimeLocalizationBundle.localizedString(
    forKey: key,
    value: key,
    table: "Localizable"
  )
  return String(format: format, locale: Locale.current, arguments: arguments)
}

private func integer(in value: String, prefix: String, suffix: String) -> Int64? {
  guard value.hasPrefix(prefix), value.hasSuffix(suffix) else { return nil }
  let start = value.index(value.startIndex, offsetBy: prefix.count)
  let end = value.index(value.endIndex, offsetBy: -suffix.count)
  return Int64(value[start..<end])
}
