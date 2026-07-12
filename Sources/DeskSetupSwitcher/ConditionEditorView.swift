import CoreLocation
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

private enum NewConditionInput: Identifiable {
  case ipAddressOrCIDR(currentAddresses: [String])
  case location

  var id: String {
    switch self {
    case .ipAddressOrCIDR: "ipAddressOrCIDR"
    case .location: "location"
    }
  }
}

struct ConditionEditorView: View {
  @EnvironmentObject private var locationPermission: LocationPermissionController
  @Binding var conditionSet: ProfileConditionSet
  let availableDisplays: [DisplayIdentity]
  let availableAudioInputUIDs: [String]
  let availableAudioOutputUIDs: [String]
  let availableHardwareIdentifiers: [String]
  let currentWiFiSSID: String?
  let currentIPAddresses: [String]
  let currentLocation: LocationRegion?
  @State private var showLocationExplanation = false
  @State private var showLocationEditorAfterExplanation = false
  @State private var newConditionInput: NewConditionInput?

  init(
    conditionSet: Binding<ProfileConditionSet>,
    availableDisplays: [DisplayIdentity],
    availableAudioInputUIDs: [String] = [],
    availableAudioOutputUIDs: [String] = [],
    availableHardwareIdentifiers: [String] = [],
    currentWiFiSSID: String? = nil,
    currentIPAddresses: [String] = [],
    currentLocation: LocationRegion? = nil
  ) {
    _conditionSet = conditionSet
    self.availableDisplays = availableDisplays
    self.availableAudioInputUIDs = availableAudioInputUIDs
    self.availableAudioOutputUIDs = availableAudioOutputUIDs
    self.availableHardwareIdentifiers = availableHardwareIdentifiers
    self.currentWiFiSSID = currentWiFiSSID
    self.currentIPAddresses = currentIPAddresses
    self.currentLocation = currentLocation
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Picker("Match", selection: $conditionSet.mode) {
          Text("All conditions").tag(ConditionMatchMode.all)
          Text("Any condition").tag(ConditionMatchMode.any)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Condition match mode")

        Toggle("Reverse overall result", isOn: $conditionSet.isInverted)
          .toggleStyle(.checkbox)
          .help(
            "After evaluating the conditions, treat ready as not ready and not ready as ready."
          )
      }

      ForEach($conditionSet.conditions) { $condition in
        ConditionRow(
          condition: $condition,
          availableDisplays: availableDisplays,
          availableAudioInputUIDs: detectedAudioInputUIDs,
          availableAudioOutputUIDs: detectedAudioOutputUIDs,
          availableHardwareIdentifiers: detectedHardwareIdentifiers,
          currentWiFiSSID: nonBlankCurrentWiFiSSID
        ) {
          conditionSet.conditions.removeAll { $0.id == condition.id }
        }
      }

      Menu {
        Button("Display connected") {
          guard let display = detectedDisplayChoices.first?.identity else { return }
          conditionSet.conditions.append(
            ProfileCondition(
              kind: .displayConnected(display)
            )
          )
        }
        .disabled(detectedDisplayChoices.isEmpty)
        .help("Capture or connect a display before adding this condition.")

        Button("Audio input connected") {
          guard let uid = detectedAudioInputUIDs.first else { return }
          conditionSet.conditions.append(
            ProfileCondition(kind: .audioInputConnected(uid: uid))
          )
        }
        .disabled(detectedAudioInputUIDs.isEmpty)
        .help("No audio input is currently detected.")

        Button("Audio output connected") {
          guard let uid = detectedAudioOutputUIDs.first else { return }
          conditionSet.conditions.append(
            ProfileCondition(kind: .audioOutputConnected(uid: uid))
          )
        }
        .disabled(detectedAudioOutputUIDs.isEmpty)
        .help("No audio output is currently detected.")

        Button("USB or hardware connected") {
          guard let identifier = detectedHardwareIdentifiers.first else { return }
          conditionSet.conditions.append(
            ProfileCondition(kind: .hardwareConnected(identifier: identifier))
          )
        }
        .disabled(detectedHardwareIdentifiers.isEmpty)
        .help("No USB or hardware identifier is currently detected.")

        Button("Wi-Fi network") {
          guard let ssid = nonBlankCurrentWiFiSSID else { return }
          conditionSet.conditions.append(ProfileCondition(kind: .wifiSSID(ssid)))
          if locationPermission.authorizationStatus == .notDetermined {
            showLocationExplanation = true
          }
        }
        .disabled(nonBlankCurrentWiFiSSID == nil)
        .help("No current Wi-Fi network name is available.")

        Button("Ethernet connected") {
          conditionSet.conditions.append(ProfileCondition(kind: .ethernetConnected))
        }

        Button("IP address or CIDR") {
          newConditionInput = .ipAddressOrCIDR(currentAddresses: validCurrentIPAddresses)
        }

        Button("Location region") {
          if locationPermission.authorizationStatus == .notDetermined {
            showLocationEditorAfterExplanation = true
            showLocationExplanation = true
          } else {
            presentLocationEditor()
          }
        }
      } label: {
        Label("Add Condition", systemImage: "plus")
      }
      .accessibilityHint("Adds a readiness condition; it never enables automatic profile switching")

      if detectedDisplayChoices.isEmpty {
        Text("Capture or connect a display before adding a display-connected condition.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text("Conditions only describe readiness. They never apply a profile automatically.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .alert("Allow Location Access?", isPresented: $showLocationExplanation) {
      Button("Not Now", role: .cancel) {
        continueToLocationEditorIfNeeded()
      }
      Button("Continue") {
        locationPermission.requestAccess()
        continueToLocationEditorIfNeeded()
      }
    } message: {
      Text(
        "Location is used only to evaluate readiness when you ask and can also be required by macOS to read the current Wi-Fi name. It is never logged or sent anywhere."
      )
    }
    .sheet(item: $newConditionInput) { input in
      NewConditionValueSheet(input: input, currentLocation: currentLocation) { kind in
        conditionSet.conditions.append(ProfileCondition(kind: kind))
        newConditionInput = nil
      }
    }
  }

  private var detectedAudioInputUIDs: [String] {
    nonBlankUnique(availableAudioInputUIDs)
  }

  private var detectedDisplayChoices: [DisplayConditionChoice] {
    ConditionChoiceBuilder.displayChoices(
      detectedValues: availableDisplays,
      savedValue: nil
    )
  }

  private var detectedAudioOutputUIDs: [String] {
    nonBlankUnique(availableAudioOutputUIDs)
  }

  private var detectedHardwareIdentifiers: [String] {
    nonBlankUnique(availableHardwareIdentifiers)
  }

  private var nonBlankCurrentWiFiSSID: String? {
    guard let currentWiFiSSID, !isBlank(currentWiFiSSID) else { return nil }
    return currentWiFiSSID
  }

  private var validCurrentIPAddresses: [String] {
    nonBlankUnique(currentIPAddresses).compactMap {
      ConditionInputValidator.validateAddressOrCIDR($0).validatedValue
    }
  }

  private func presentLocationEditor() {
    newConditionInput = .location
  }

  private func continueToLocationEditorIfNeeded() {
    guard showLocationEditorAfterExplanation else { return }
    showLocationEditorAfterExplanation = false
    presentLocationEditor()
  }
}

private struct ConditionRow: View {
  @Binding var condition: ProfileCondition
  let availableDisplays: [DisplayIdentity]
  let availableAudioInputUIDs: [String]
  let availableAudioOutputUIDs: [String]
  let availableHardwareIdentifiers: [String]
  let currentWiFiSSID: String?
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(title, systemImage: symbolName)
          .font(.subheadline.bold())
        Spacer()
        Toggle("Require the opposite", isOn: $condition.isInverted)
          .toggleStyle(.checkbox)
          .help("Treat this condition as met when its normal result is not met.")
        Button(role: .destructive, action: remove) {
          Label("Remove Condition", systemImage: "minus.circle")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel(appLocalized("Remove \(title) condition"))
        .help(appLocalized("Remove \(title) condition"))
      }

      editor
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder
  private var editor: some View {
    VStack(alignment: .leading, spacing: 7) {
      switch condition.kind {
      case .displayConnected:
        Picker("Display", selection: displayIdentityBinding) {
          ForEach(displayChoices) { choice in
            Text(displayIdentityLabel(choice)).tag(choice.identity)
          }
        }
        .accessibilityHint("Chooses the stable display identity required by this condition")
        DisclosureGroup("Advanced") {
          Text(displayIdentityTechnicalLabel(displayIdentityBinding.wrappedValue))
            .font(.caption.monospaced())
            .textSelection(.enabled)
        }

      case .audioInputConnected:
        Picker("Input device", selection: stringBinding(for: .audioInput)) {
          ForEach(audioInputChoices) { choice in
            Text(choice.label)
              .tag(choice.value)
          }
        }
        DisclosureGroup("Advanced") {
          TextField("Core Audio input device UID", text: stringBinding(for: .audioInput))
        }

      case .audioOutputConnected:
        Picker("Output device", selection: stringBinding(for: .audioOutput)) {
          ForEach(audioOutputChoices) { choice in
            Text(choice.label)
              .tag(choice.value)
          }
        }
        DisclosureGroup("Advanced") {
          TextField("Core Audio output device UID", text: stringBinding(for: .audioOutput))
        }

      case .hardwareConnected:
        Picker("Detected hardware", selection: stringBinding(for: .hardware)) {
          ForEach(hardwareChoices) { choice in
            Text(choice.label)
              .tag(choice.value)
          }
        }
        DisclosureGroup("Advanced") {
          TextField("Stable hardware identifier", text: stringBinding(for: .hardware))
        }

      case .wifiSSID:
        Picker("Wi-Fi network", selection: stringBinding(for: .ssid)) {
          ForEach(wifiChoices, id: \.self) { value in
            Text(wifiChoiceLabel(value))
              .tag(value)
          }
        }
        DisclosureGroup("Advanced") {
          TextField("Wi-Fi network name", text: stringBinding(for: .ssid))
        }

      case .ethernetConnected:
        Text("Requires an active Ethernet link.")
          .foregroundStyle(.secondary)

      case .ipAddressOrCIDR:
        TextField("Address or CIDR", text: stringBinding(for: .cidr))
          .accessibilityHint("For example 192.168.1.0 slash 24 or a single IPv6 address")

      case .location:
        Grid(alignment: .leading) {
          GridRow {
            Text("Latitude")
            TextField("Latitude", value: locationBinding(\.latitude), format: .number)
          }
          GridRow {
            Text("Longitude")
            TextField("Longitude", value: locationBinding(\.longitude), format: .number)
          }
          GridRow {
            Text("Radius (m)")
            TextField("Radius", value: locationBinding(\.radiusMeters), format: .number)
          }
        }
        Text(
          "Location is evaluated only when permission is granted. Exact coordinates are never written to diagnostics."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let inlineValidationMessage {
        Label(inlineValidationMessage, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityLabel(inlineValidationMessage)
      }
    }
  }

  private enum StringField {
    case audioInput
    case audioOutput
    case hardware
    case ssid
    case cidr
  }

  private var displayChoices: [DisplayConditionChoice] {
    guard case .displayConnected(let selected) = condition.kind else {
      return ConditionChoiceBuilder.displayChoices(
        detectedValues: availableDisplays,
        savedValue: nil
      )
    }
    return ConditionChoiceBuilder.displayChoices(
      detectedValues: availableDisplays,
      savedValue: selected
    )
  }

  private var audioInputChoices: [ConditionValueChoice] {
    conditionChoices(
      for: .audioInput,
      detectedValues: availableAudioInputUIDs,
      baseLabel: appLocalized("Input device")
    )
  }

  private var audioOutputChoices: [ConditionValueChoice] {
    conditionChoices(
      for: .audioOutput,
      detectedValues: availableAudioOutputUIDs,
      baseLabel: appLocalized("Output device")
    )
  }

  private var hardwareChoices: [ConditionValueChoice] {
    conditionChoices(
      for: .hardware,
      detectedValues: availableHardwareIdentifiers,
      baseLabel: appLocalized("Detected hardware")
    )
  }

  private var detectedWiFiValues: [String] {
    guard let currentWiFiSSID, !isBlank(currentWiFiSSID) else { return [] }
    return [currentWiFiSSID]
  }

  private var wifiChoices: [String] {
    var choices = detectedWiFiValues
    let selected = stringBinding(for: .ssid).wrappedValue
    if !choices.contains(selected) {
      choices.insert(selected, at: 0)
    }
    return choices
  }

  private var displayIdentityBinding: Binding<DisplayIdentity> {
    Binding(
      get: {
        guard case .displayConnected(let identity) = condition.kind else {
          return displayChoices.first?.identity ?? DisplayIdentity()
        }
        return identity
      },
      set: { condition.kind = .displayConnected($0) }
    )
  }

  private func displayIdentityLabel(_ choice: DisplayConditionChoice) -> String {
    let identity = choice.identity
    let name = identity.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseLabel: String
    if let name, !name.isEmpty {
      baseLabel = name
    } else if identity.isBuiltIn {
      baseLabel = appLocalized("Built-in display")
    } else if let ordinal = choice.externalOrdinal {
      baseLabel = appLocalizedPresentationText("External display \(ordinal)")
    } else {
      baseLabel = appLocalized("External display")
    }

    guard !choice.isCurrentlyDetected else { return baseLabel }
    return "\(baseLabel) — \(appLocalized("Saved; not currently detected"))"
  }

  private func displayIdentityTechnicalLabel(_ identity: DisplayIdentity) -> String {
    if let serial = identity.serialNumber {
      return appLocalized("Serial number: \(serial)")
    }
    if let uuid = identity.uuid {
      return appLocalized("Display UUID: \(uuid.uuidString)")
    }
    if let vendor = identity.vendorID, let model = identity.modelID {
      return appLocalized("Vendor \(vendor), model \(model)")
    }
    return appLocalized("No stable technical identifier is available.")
  }

  private var title: String {
    switch condition.kind {
    case .displayConnected: appLocalized("Display connected")
    case .audioInputConnected: appLocalized("Audio input connected")
    case .audioOutputConnected: appLocalized("Audio output connected")
    case .hardwareConnected: appLocalized("Hardware connected")
    case .wifiSSID: appLocalized("Wi-Fi network")
    case .ethernetConnected: appLocalized("Ethernet connected")
    case .ipAddressOrCIDR: appLocalized("IP address or CIDR")
    case .location: appLocalized("Location region")
    }
  }

  private var symbolName: String {
    switch condition.kind {
    case .displayConnected: "display"
    case .audioInputConnected: "mic"
    case .audioOutputConnected: "speaker.wave.2"
    case .hardwareConnected: "cable.connector"
    case .wifiSSID: "wifi"
    case .ethernetConnected: "network"
    case .ipAddressOrCIDR: "point.3.connected.trianglepath.dotted"
    case .location: "location"
    }
  }

  private var inlineValidationMessage: String? {
    switch condition.kind {
    case .audioInputConnected(let uid), .audioOutputConnected(let uid):
      isBlank(uid) ? appLocalized("Choose or enter a non-empty device UID.") : nil
    case .hardwareConnected(let identifier):
      isBlank(identifier) ? appLocalized("Choose or enter a non-empty hardware identifier.") : nil
    case .wifiSSID(let ssid):
      isBlank(ssid) ? appLocalized("Choose or enter a non-empty Wi-Fi network name.") : nil
    case .ipAddressOrCIDR(let value):
      addressOrCIDRValidationMessage(value)
    case .location(let region):
      locationInputValidationMessage(
        latitude: region.latitude,
        longitude: region.longitude,
        radiusMeters: region.radiusMeters
      )
    case .displayConnected, .ethernetConnected:
      nil
    }
  }

  private func conditionChoices(
    for field: StringField,
    detectedValues: [String],
    baseLabel: String
  ) -> [ConditionValueChoice] {
    ConditionChoiceBuilder.choices(
      detectedValues: detectedValues,
      savedValue: stringBinding(for: field).wrappedValue,
      baseLabel: baseLabel,
      savedNotDetectedLabel: appLocalized("Saved; not currently detected")
    )
  }

  private func wifiChoiceLabel(_ value: String) -> String {
    if isBlank(value) {
      return appLocalized("No value selected")
    }
    if !detectedWiFiValues.contains(value) {
      return appLocalized("Wi-Fi network — Saved; not currently detected")
    }
    return value
  }

  private func stringBinding(for field: StringField) -> Binding<String> {
    Binding(
      get: {
        switch (field, condition.kind) {
        case (.audioInput, .audioInputConnected(let uid)): uid
        case (.audioOutput, .audioOutputConnected(let uid)): uid
        case (.hardware, .hardwareConnected(let identifier)): identifier
        case (.ssid, .wifiSSID(let value)): value
        case (.cidr, .ipAddressOrCIDR(let value)): value
        default: ""
        }
      },
      set: { value in
        switch field {
        case .audioInput: condition.kind = .audioInputConnected(uid: value)
        case .audioOutput: condition.kind = .audioOutputConnected(uid: value)
        case .hardware: condition.kind = .hardwareConnected(identifier: value)
        case .ssid: condition.kind = .wifiSSID(value)
        case .cidr: condition.kind = .ipAddressOrCIDR(value)
        }
      }
    )
  }

  private func locationBinding(_ keyPath: WritableKeyPath<LocationRegion, Double>) -> Binding<
    Double
  > {
    Binding(
      get: {
        guard case .location(let region) = condition.kind else { return 0 }
        return region[keyPath: keyPath]
      },
      set: { value in
        guard case .location(var region) = condition.kind else { return }
        region[keyPath: keyPath] = value
        condition.kind = .location(region)
      }
    )
  }
}

private struct NewConditionValueSheet: View {
  @Environment(\.dismiss) private var dismiss
  let input: NewConditionInput
  let currentLocation: LocationRegion?
  let add: (ProfileConditionKind) -> Void
  @State private var addressOrCIDR: String
  @State private var latitude: Double?
  @State private var longitude: Double?
  @State private var radiusMeters: Double?

  init(
    input: NewConditionInput,
    currentLocation: LocationRegion?,
    add: @escaping (ProfileConditionKind) -> Void
  ) {
    self.input = input
    self.currentLocation = currentLocation
    self.add = add
    switch input {
    case .ipAddressOrCIDR(let currentAddresses):
      _addressOrCIDR = State(initialValue: currentAddresses.first ?? "")
      _latitude = State(initialValue: nil)
      _longitude = State(initialValue: nil)
      _radiusMeters = State(initialValue: nil)
    case .location:
      _addressOrCIDR = State(initialValue: "")
      _latitude = State(initialValue: currentLocation?.latitude)
      _longitude = State(initialValue: currentLocation?.longitude)
      _radiusMeters = State(initialValue: currentLocation?.radiusMeters)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title)
        .font(.title3.bold())
      Text(detail)
        .foregroundStyle(.secondary)

      switch input {
      case .ipAddressOrCIDR(let currentAddresses):
        if !currentAddresses.isEmpty {
          Menu("Use a Current Address") {
            ForEach(currentAddresses, id: \.self) { address in
              Button(address) {
                addressOrCIDR = address
              }
            }
          }
        }
        TextField("Address or CIDR", text: $addressOrCIDR)
          .accessibilityHint("For example 192.168.1.0 slash 24 or a single IPv6 address")

      case .location:
        if let currentLocation {
          Button("Use Current Location") {
            latitude = currentLocation.latitude
            longitude = currentLocation.longitude
            radiusMeters = currentLocation.radiusMeters
          }
        } else {
          Text("No current location is available. Enter coordinates manually.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Grid(alignment: .leading) {
          GridRow {
            Text("Latitude")
            TextField("Latitude", value: $latitude, format: .number)
          }
          GridRow {
            Text("Longitude")
            TextField("Longitude", value: $longitude, format: .number)
          }
          GridRow {
            Text("Radius (m)")
            TextField("Radius", value: $radiusMeters, format: .number)
          }
        }
      }

      if let validationMessage {
        Label(validationMessage, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityLabel(validationMessage)
      }

      Text("This adds a readiness check only. It never applies or switches profiles.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Divider()

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Button("Add Condition") {
          guard let conditionKind else { return }
          add(conditionKind)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(conditionKind == nil)
      }
    }
    .padding(20)
    .frame(minWidth: 440)
  }

  private var title: String {
    switch input {
    case .ipAddressOrCIDR:
      appLocalized("Add IP Readiness Condition")
    case .location:
      appLocalized("Add Location Readiness Condition")
    }
  }

  private var detail: String {
    switch input {
    case .ipAddressOrCIDR:
      appLocalized("Enter the address or network that must be present for readiness.")
    case .location:
      appLocalized("Enter the center and radius used only to evaluate readiness.")
    }
  }

  private var conditionKind: ProfileConditionKind? {
    switch input {
    case .ipAddressOrCIDR:
      guard
        let value = ConditionInputValidator.validateAddressOrCIDR(addressOrCIDR).validatedValue
      else { return nil }
      return .ipAddressOrCIDR(value)
    case .location:
      guard
        let region = ConditionInputValidator.validateLocation(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: radiusMeters
        ).validatedValue
      else { return nil }
      return .location(region)
    }
  }

  private var validationMessage: String? {
    switch input {
    case .ipAddressOrCIDR:
      return addressOrCIDRValidationMessage(addressOrCIDR)
    case .location:
      return locationInputValidationMessage(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters
      )
    }
  }
}

private func isBlank(_ value: String) -> Bool {
  value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func nonBlankUnique(_ values: [String]) -> [String] {
  var seen = Set<String>()
  return values.filter { value in
    !isBlank(value) && seen.insert(value).inserted
  }
}

private func addressOrCIDRValidationMessage(_ value: String) -> String? {
  switch ConditionInputValidator.validateAddressOrCIDR(value) {
  case .valid:
    nil
  case .invalid(.missingValue):
    appLocalized("Enter an IP address or CIDR.")
  case .invalid(.malformedValue):
    appLocalized(
      "Enter a valid IPv4 or IPv6 address, optionally followed by a CIDR prefix."
    )
  }
}

private func locationInputValidationMessage(
  latitude: Double?,
  longitude: Double?,
  radiusMeters: Double?
) -> String? {
  switch ConditionInputValidator.validateLocation(
    latitude: latitude,
    longitude: longitude,
    radiusMeters: radiusMeters
  ) {
  case .valid:
    return nil
  case .invalid(.missingFields):
    return appLocalized("Enter latitude, longitude, and radius.")
  case .invalid(.nonFinite(.latitude)), .invalid(.outOfRange(.latitude)):
    return appLocalized("Latitude must be between −90 and 90.")
  case .invalid(.nonFinite(.longitude)), .invalid(.outOfRange(.longitude)):
    return appLocalized("Longitude must be between −180 and 180.")
  case .invalid(.nonFinite(.radiusMeters)), .invalid(.outOfRange(.radiusMeters)):
    return appLocalized("Radius must be between 0 and 40,000,000 metres.")
  }
}
