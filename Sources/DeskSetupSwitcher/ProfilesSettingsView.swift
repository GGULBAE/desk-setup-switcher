import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

struct ProfilesSettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @State private var selection: UUID?
  @State private var draft: DeskProfile?
  @State private var profilePendingDeletion: DeskProfile?

  var body: some View {
    VStack(spacing: 12) {
      HSplitView {
        sidebar
          .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
        editor
          .frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
      }
      .disabled(model.isProfileMutationLocked)

      Divider()

      HStack {
        Text(model.storageStatus)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            appLocalized("Profile storage status: \(model.storageStatus)"))
        Spacer()
        Button("Import…") { model.importProfiles() }
          .disabled(model.isProfileMutationLocked)
          .accessibilityHint("Selects and validates a local profile JSON file")
        Button("Export…") { model.exportProfiles() }
          .disabled(model.profiles.isEmpty || model.isProfileMutationLocked)
          .accessibilityHint("Exports all profiles to a new local JSON file")
      }

      if model.isProfileMutationLocked {
        Label(
          "Profile editing is locked until the current operation is safely recorded.",
          systemImage: "lock"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .onAppear {
      selection = model.selectedProfileID ?? model.profiles.first?.id
      loadDraft()
    }
    .onChange(of: selection) {
      model.selectProfile(id: selection)
      loadDraft()
    }
    .onChange(of: model.profiles) {
      if let selection, !model.profiles.contains(where: { $0.id == selection }) {
        self.selection = model.selectedProfileID ?? model.profiles.first?.id
      }
      loadDraft()
    }
    .confirmationDialog(
      "Delete this profile?",
      isPresented: Binding(
        get: { profilePendingDeletion != nil },
        set: { if !$0 { profilePendingDeletion = nil } }
      ),
      presenting: profilePendingDeletion
    ) { profile in
      Button(appLocalized("Delete \(profile.name)"), role: .destructive) {
        model.deleteProfile(id: profile.id)
        profilePendingDeletion = nil
      }
      Button("Cancel", role: .cancel) {
        profilePendingDeletion = nil
      }
    } message: { profile in
      Text(
        appLocalized(
          "This removes \(profile.name) from local profile storage. This action cannot be undone."))
    }
    .alert(
      "Replace all local profiles?",
      isPresented: Binding(
        get: { model.pendingImport != nil },
        set: { if !$0 { model.cancelImportReplacement() } }
      ),
      presenting: model.pendingImport
    ) { request in
      Button("Cancel", role: .cancel) { model.cancelImportReplacement() }
      Button(
        appLocalized("Replace with \(request.imported.document.profiles.count) Profiles"),
        role: .destructive
      ) {
        model.confirmImportReplacement()
      }
    } message: { request in
      Text(
        appLocalized(
          "The import contains \(request.imported.document.profiles.count) profiles and will replace all \(request.existingProfileCount) local profiles. A last-known-good backup is kept."
        )
      )
    }
  }

  private var sidebar: some View {
    VStack(spacing: 8) {
      List(selection: $selection) {
        ForEach(model.profiles) { profile in
          HStack {
            Image(systemName: profile.symbolName)
              .frame(width: 20)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.name)
              Text(profile.isEnabled ? appLocalized("Enabled") : appLocalized("Disabled"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .tag(Optional(profile.id))
          .accessibilityLabel(
            appLocalized(
              "\(profile.name), \(profile.isEnabled ? appLocalized("enabled") : appLocalized("disabled"))"
            )
          )
        }
      }
      .overlay {
        if model.profiles.isEmpty {
          ContentUnavailableView(
            "No Profiles",
            systemImage: "rectangle.stack.badge.plus",
            description: Text("Create a blank profile, then update it from a safe system snapshot.")
          )
        }
      }

      HStack(spacing: 6) {
        Button {
          model.createProfile()
        } label: {
          Label("New Profile", systemImage: "plus")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Create profile")

        Button {
          if let selection { model.duplicateProfile(id: selection) }
        } label: {
          Label("Duplicate Profile", systemImage: "plus.square.on.square")
        }
        .labelStyle(.iconOnly)
        .disabled(selection == nil)
        .accessibilityLabel("Duplicate selected profile")

        Button {
          if let profile = selectedProfile { profilePendingDeletion = profile }
        } label: {
          Label("Delete Profile", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
        .disabled(selection == nil)
        .accessibilityLabel("Delete selected profile")

        Spacer()

        Button {
          if let selection { model.moveProfile(id: selection, by: -1) }
        } label: {
          Label("Move Up", systemImage: "chevron.up")
        }
        .labelStyle(.iconOnly)
        .disabled(!canMove(by: -1))
        .accessibilityLabel("Move selected profile up")

        Button {
          if let selection { model.moveProfile(id: selection, by: 1) }
        } label: {
          Label("Move Down", systemImage: "chevron.down")
        }
        .labelStyle(.iconOnly)
        .disabled(!canMove(by: 1))
        .accessibilityLabel("Move selected profile down")
      }
    }
  }

  @ViewBuilder
  private var editor: some View {
    if draft != nil {
      ProfileEditorForm(
        profile: draftBinding,
        conditionContext: model.lastConditionContext
      ) {
        if let draft { model.updateProfile(draft) }
      } updateFromCurrentSettings: {
        if let selection { model.updateProfileFromCurrentSettings(id: selection) }
      }
    } else {
      ContentUnavailableView(
        "Select a Profile",
        systemImage: "sidebar.left",
        description: Text("Choose a profile in the sidebar or create a new one.")
      )
    }
  }

  private var draftBinding: Binding<DeskProfile> {
    Binding(
      get: { draft ?? DeskProfile(name: "") },
      set: { draft = $0 }
    )
  }

  private var selectedProfile: DeskProfile? {
    guard let selection else { return nil }
    return model.profiles.first { $0.id == selection }
  }

  private func loadDraft() {
    draft = selectedProfile
  }

  private func canMove(by offset: Int) -> Bool {
    guard let selection,
      let index = model.profiles.firstIndex(where: { $0.id == selection })
    else { return false }
    return model.profiles.indices.contains(index + offset)
  }
}

private struct ProfileEditorForm: View {
  @Binding var profile: DeskProfile
  let conditionContext: ConditionContext
  let save: () -> Void
  let updateFromCurrentSettings: () -> Void

  var body: some View {
    Form {
      Section("Profile") {
        TextField("Name", text: $profile.name)
          .accessibilityLabel("Profile name")
        TextField("Description", text: $profile.profileDescription, axis: .vertical)
          .lineLimit(2...4)
          .accessibilityLabel("Profile description")
        TextField("SF Symbol", text: $profile.symbolName)
          .accessibilityHint("Enter a system symbol name, such as display.2")
        Toggle("Enabled", isOn: $profile.isEnabled)
      }

      Section("Included settings") {
        groupToggle(
          appLocalized("Displays"),
          systemImage: "display.2",
          isOn: $profile.settings.display.isIncluded,
          detail: appLocalized(
            "\(profile.settings.display.value.displays.count) captured displays")
        )
        groupToggle(
          appLocalized("Audio"),
          systemImage: "speaker.wave.2",
          isOn: $profile.settings.audio.isIncluded,
          detail: appLocalized(
            "\(includedOptionCount(profile.settings.audio.value)) included options")
        )
        groupToggle(
          appLocalized("Network"),
          systemImage: "network",
          isOn: $profile.settings.network.isIncluded,
          detail: appLocalized(
            "\(includedOptionCount(profile.settings.network.value)) included options")
        )
        groupToggle(
          appLocalized("Mouse & Keyboard"),
          systemImage: "keyboard",
          isOn: $profile.settings.input.isIncluded,
          detail: appLocalized(
            "\(includedOptionCount(profile.settings.input.value)) included options")
        )

        if profile.settings.display.isIncluded {
          displayOptions
        }
        if profile.settings.audio.isIncluded {
          audioOptions
        }
        if profile.settings.network.isIncluded {
          networkOptions
        }
        if profile.settings.input.isIncluded {
          inputOptions
        }
      }

      Section("Readiness conditions") {
        ConditionEditorView(
          conditionSet: $profile.conditions,
          availableDisplays: profile.settings.display.value.displays.map(\.identity),
          availableAudioInputUIDs: conditionContext.audioInputUIDs.sorted(),
          availableAudioOutputUIDs: conditionContext.audioOutputUIDs.sorted(),
          availableHardwareIdentifiers: conditionContext.hardwareIdentifiers.sorted(),
          currentWiFiSSID: conditionContext.wifiSSID
        )
      }

      if let lastApplication = profile.lastApplication {
        Section("Last application") {
          LabeledContent(
            "Status",
            value: appApplicationStatusTitle(
              lastApplication.status,
              isAwaitingDisplayConfirmation: lastApplication.status == .applying
                && lastApplication.items.contains { $0.key == "display-safety-confirmation" }
            )
          )
          LabeledContent("Time", value: lastApplication.appliedAt.formatted())
          if lastApplication.items.isEmpty {
            Text("No itemized results were recorded.")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            ForEach(Array(lastApplication.items.enumerated()), id: \.offset) { _, item in
              VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                  Text(appSettingGroupTitle(item.group))
                    .font(.caption.bold())
                  Text(appApplicationItemTitle(item.key))
                  Spacer()
                  Text(appApplicationItemStatusTitle(item.status))
                    .font(.caption.bold())
                }
                Text(appLocalizedRuntime(item.message))
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
              }
              .padding(.vertical, 2)
              .accessibilityElement(children: .combine)
            }
          }
        }
      }

      HStack {
        Button("Update from Current Settings", action: updateFromCurrentSettings)
          .accessibilityHint("Reads the current Mac without changing any setting")
        Spacer()
        Button("Save Profile", action: save)
          .keyboardShortcut("s")
          .disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .formStyle(.grouped)
  }

  private var displayOptions: some View {
    DisclosureGroup("Display options") {
      ForEach($profile.settings.display.value.displays) { $display in
        VStack(alignment: .leading, spacing: 6) {
          Text(display.identity.productName ?? appLocalized("Detected display"))
            .font(.subheadline.bold())
          Toggle("Primary display", isOn: $display.isPrimary.isIncluded)
          Toggle("Position", isOn: $display.origin.isIncluded)
          Toggle("Mirroring", isOn: $display.mirroring.isIncluded)
          Toggle("Resolution and refresh rate", isOn: $display.mode.isIncluded)
          Toggle("Rotation", isOn: $display.rotationDegrees.isIncluded)
          Toggle("Active state", isOn: $display.isActive.isIncluded)
        }
        .padding(.leading, 8)
      }
    }
  }

  private var audioOptions: some View {
    DisclosureGroup("Audio options") {
      Toggle("Default input device", isOn: $profile.settings.audio.value.defaultInputUID.isIncluded)
      Toggle(
        "Default output device", isOn: $profile.settings.audio.value.defaultOutputUID.isIncluded)
      Toggle("System output device", isOn: $profile.settings.audio.value.systemOutputUID.isIncluded)
      Toggle("Output volume", isOn: $profile.settings.audio.value.outputVolume.isIncluded)
      Toggle("Output mute", isOn: $profile.settings.audio.value.outputMuted.isIncluded)
    }
  }

  private var networkOptions: some View {
    DisclosureGroup("Network options") {
      Toggle("Wi-Fi power", isOn: $profile.settings.network.value.wifiPower.isIncluded)
      Toggle("Wi-Fi network", isOn: $profile.settings.network.value.wifiSSID.isIncluded)
      Toggle("IPv4 configuration", isOn: $profile.settings.network.value.ipv4.isIncluded)
      Toggle("DNS servers", isOn: $profile.settings.network.value.dnsServers.isIncluded)
      Toggle("Web proxy", isOn: $profile.settings.network.value.webProxy.isIncluded)
      Toggle("Secure web proxy", isOn: $profile.settings.network.value.secureWebProxy.isIncluded)
    }
  }

  private var inputOptions: some View {
    DisclosureGroup("Mouse and keyboard options") {
      Label(
        "Experimental: macOS does not document the stability of these global preference keys.",
        systemImage: "testtube.2"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Toggle("Pointer speed", isOn: $profile.settings.input.value.pointerSpeed.isIncluded)
      Toggle("Natural scrolling", isOn: $profile.settings.input.value.naturalScrolling.isIncluded)
      Toggle("Key repeat", isOn: $profile.settings.input.value.keyRepeatInterval.isIncluded)
      Toggle(
        "Initial key repeat delay",
        isOn: $profile.settings.input.value.initialKeyRepeatDelay.isIncluded
      )
      Toggle(
        "Use F1–F12 as standard function keys",
        isOn: $profile.settings.input.value.useStandardFunctionKeys.isIncluded
      )
    }
  }

  @ViewBuilder
  private func groupToggle(
    _ title: String,
    systemImage: String,
    isOn: Binding<Bool>,
    detail: String
  ) -> some View {
    HStack {
      Label(title, systemImage: systemImage)
      Spacer()
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
      Toggle(title, isOn: isOn)
        .labelsHidden()
        .accessibilityLabel(appLocalized("Include \(title)"))
    }
  }

  private func includedOptionCount(_ settings: AudioProfileSettings) -> String {
    let values = [
      settings.defaultInputUID.isIncluded,
      settings.defaultOutputUID.isIncluded,
      settings.systemOutputUID.isIncluded,
      settings.outputVolume.isIncluded,
      settings.outputMuted.isIncluded,
    ]
    return "\(values.filter { $0 }.count)"
  }

  private func includedOptionCount(_ settings: NetworkProfileSettings) -> String {
    let values = [
      settings.wifiPower.isIncluded,
      settings.wifiSSID.isIncluded,
      settings.ipv4.isIncluded,
      settings.dnsServers.isIncluded,
      settings.webProxy.isIncluded,
      settings.secureWebProxy.isIncluded,
    ]
    return "\(values.filter { $0 }.count)"
  }

  private func includedOptionCount(_ settings: InputProfileSettings) -> String {
    let values = [
      settings.pointerSpeed.isIncluded,
      settings.naturalScrolling.isIncluded,
      settings.keyRepeatInterval.isIncluded,
      settings.initialKeyRepeatDelay.isIncluded,
      settings.useStandardFunctionKeys.isIncluded,
    ]
    return "\(values.filter { $0 }.count)"
  }
}
