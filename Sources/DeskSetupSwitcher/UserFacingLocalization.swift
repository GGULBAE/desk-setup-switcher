import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

private var appRuntimeLocalizationBundle: Bundle {
  #if SWIFT_PACKAGE
    Bundle.module
  #else
    Bundle.main
  #endif
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

func appOperationPreviewValue(
  _ value: String,
  operation: PlannedOperation,
  isPreviousValue: Bool
) -> String {
  switch operation.key {
  case "wifi.ssid":
    return isPreviousValue && value == "Not associated"
      ? appLocalizedRuntime(value) : value
  case "display.atomic-configuration", "defaultInput", "defaultOutput",
    "systemOutput":
    // These values contain user/device-provided names or identifiers and must
    // remain verbatim, even if they happen to equal a localization key.
    return value
  default:
    return appLocalizedRuntime(value)
  }
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
