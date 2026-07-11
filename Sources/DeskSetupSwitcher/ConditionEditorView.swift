import CoreLocation
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

struct ConditionEditorView: View {
  @EnvironmentObject private var locationPermission: LocationPermissionController
  @Binding var conditionSet: ProfileConditionSet
  let availableDisplays: [DisplayIdentity]
  let availableAudioInputUIDs: [String]
  let availableAudioOutputUIDs: [String]
  let availableHardwareIdentifiers: [String]
  let currentWiFiSSID: String?
  @State private var showLocationExplanation = false

  init(
    conditionSet: Binding<ProfileConditionSet>,
    availableDisplays: [DisplayIdentity],
    availableAudioInputUIDs: [String] = [],
    availableAudioOutputUIDs: [String] = [],
    availableHardwareIdentifiers: [String] = [],
    currentWiFiSSID: String? = nil
  ) {
    _conditionSet = conditionSet
    self.availableDisplays = availableDisplays
    self.availableAudioInputUIDs = availableAudioInputUIDs
    self.availableAudioOutputUIDs = availableAudioOutputUIDs
    self.availableHardwareIdentifiers = availableHardwareIdentifiers
    self.currentWiFiSSID = currentWiFiSSID
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

        Toggle("Invert set", isOn: $conditionSet.isInverted)
          .toggleStyle(.checkbox)
          .help("Invert the result after all or any matching is evaluated.")
      }

      ForEach($conditionSet.conditions) { $condition in
        ConditionRow(condition: $condition, availableDisplays: availableDisplays) {
          conditionSet.conditions.removeAll { $0.id == condition.id }
        }
      }

      Menu {
        Button("Display connected") {
          guard let display = availableDisplays.first else { return }
          conditionSet.conditions.append(
            ProfileCondition(
              kind: .displayConnected(display)
            )
          )
        }
        .disabled(availableDisplays.isEmpty)
        .help("Capture or connect a display before adding this condition.")
        Button("Audio input connected") {
          conditionSet.conditions.append(
            ProfileCondition(kind: .audioInputConnected(uid: availableAudioInputUIDs.first ?? ""))
          )
        }
        Button("Audio output connected") {
          conditionSet.conditions.append(
            ProfileCondition(
              kind: .audioOutputConnected(uid: availableAudioOutputUIDs.first ?? "")
            )
          )
        }
        Button("USB or hardware connected") {
          conditionSet.conditions.append(
            ProfileCondition(
              kind: .hardwareConnected(identifier: availableHardwareIdentifiers.first ?? "")
            )
          )
        }
        Button("Wi-Fi network") {
          conditionSet.conditions.append(ProfileCondition(kind: .wifiSSID(currentWiFiSSID ?? "")))
          if locationPermission.authorizationStatus == .notDetermined {
            showLocationExplanation = true
          }
        }
        Button("Ethernet connected") {
          conditionSet.conditions.append(ProfileCondition(kind: .ethernetConnected))
        }
        Button("IP address or CIDR") {
          conditionSet.conditions.append(
            ProfileCondition(kind: .ipAddressOrCIDR("192.168.1.0/24"))
          )
        }
        Button("Location region") {
          conditionSet.conditions.append(
            ProfileCondition(
              kind: .location(
                LocationRegion(latitude: 0, longitude: 0, radiusMeters: 100)
              )
            )
          )
          if locationPermission.authorizationStatus == .notDetermined {
            showLocationExplanation = true
          }
        }
      } label: {
        Label("Add Condition", systemImage: "plus")
      }
      .accessibilityHint("Adds a readiness condition; it never enables automatic profile switching")

      if availableDisplays.isEmpty {
        Text("Capture or connect a display before adding a display-connected condition.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text("Conditions only describe readiness. They never apply a profile automatically.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .alert("Allow Location Access?", isPresented: $showLocationExplanation) {
      Button("Not Now", role: .cancel) {}
      Button("Continue") { locationPermission.requestAccess() }
    } message: {
      Text(
        "Location is used only to evaluate readiness when you ask and can also be required by macOS to read the current Wi-Fi name. It is never logged or sent anywhere."
      )
    }
  }
}

private struct ConditionRow: View {
  @Binding var condition: ProfileCondition
  let availableDisplays: [DisplayIdentity]
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(title, systemImage: symbolName)
          .font(.subheadline.bold())
        Spacer()
        Toggle("Not", isOn: $condition.isInverted)
          .toggleStyle(.checkbox)
          .help("Invert only this condition.")
        Button(role: .destructive, action: remove) {
          Label("Remove Condition", systemImage: "minus.circle")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel(appLocalized("Remove \(title) condition"))
      }

      editor
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder
  private var editor: some View {
    switch condition.kind {
    case .displayConnected:
      Picker("Display", selection: displayIdentityBinding) {
        ForEach(displayChoices, id: \.self) { identity in
          Text(displayIdentityLabel(identity)).tag(identity)
        }
      }
      .accessibilityHint("Chooses the stable display identity required by this condition")
    case .audioInputConnected:
      TextField("Core Audio input device UID", text: stringBinding(for: .audioInput))
    case .audioOutputConnected:
      TextField("Core Audio output device UID", text: stringBinding(for: .audioOutput))
    case .hardwareConnected:
      TextField("Stable hardware identifier", text: stringBinding(for: .hardware))
    case .wifiSSID:
      TextField("Wi-Fi network name", text: stringBinding(for: .ssid))
    case .ethernetConnected:
      Text("Requires an active Ethernet link.")
        .foregroundStyle(.secondary)
    case .ipAddressOrCIDR:
      TextField("Address or CIDR", text: stringBinding(for: .cidr))
        .accessibilityHint("For example 192.168.1.0 slash 24 or a single IPv6 address")
    case .location(let region):
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
      .onAppear {
        condition.kind = .location(region)
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

  private var displayChoices: [DisplayIdentity] {
    guard case .displayConnected(let selected) = condition.kind else {
      return availableDisplays
    }

    var choices = availableDisplays
    if !choices.contains(selected) {
      choices.insert(selected, at: 0)
    }
    return choices
  }

  private var displayIdentityBinding: Binding<DisplayIdentity> {
    Binding(
      get: {
        guard case .displayConnected(let identity) = condition.kind else {
          return displayChoices.first ?? DisplayIdentity()
        }
        return identity
      },
      set: { condition.kind = .displayConnected($0) }
    )
  }

  private func displayIdentityLabel(_ identity: DisplayIdentity) -> String {
    let name = identity.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let stableSuffix: String
    if let serial = identity.serialNumber {
      stableSuffix = appLocalized("serial \(serial)")
    } else if let uuid = identity.uuid {
      stableSuffix = String(uuid.uuidString.prefix(8))
    } else if let vendor = identity.vendorID, let model = identity.modelID {
      stableSuffix = appLocalized("vendor \(vendor), model \(model)")
    } else {
      stableSuffix = appLocalized("Stable display fingerprint")
    }

    if let name, !name.isEmpty {
      return "\(name) — \(stableSuffix)"
    }
    return identity.isBuiltIn
      ? appLocalized("Built-in display — \(stableSuffix)")
      : appLocalized("Display — \(stableSuffix)")
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
