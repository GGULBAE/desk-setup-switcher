import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif
#if canImport(DeskSetupSystem)
  import DeskSetupSystem
#endif

struct ProfilesSettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var profileEditor: ProfileEditorModel
  @State private var profilePendingDeletion: DeskProfile?
  @State private var deferredAction: DeferredProfileAction?
  @State private var isUnsavedPromptPresented = false
  @State private var isResolvingUnsavedPrompt = false

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
        Button("Import…") { requestDeferredAction(.importProfiles) }
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
      profileEditor.initialize(
        profiles: model.profiles,
        preferredProfileID: model.selectedProfileID
      )
      if profileEditor.session.pendingSelection != nil {
        isUnsavedPromptPresented = true
      }
    }
    .onChange(of: model.profiles) {
      synchronizeEditor()
    }
    .onChange(of: model.selectedProfileID) {
      synchronizeEditor()
    }
    .onChange(of: profileEditor.session.pendingSelection) {
      if profileEditor.session.pendingSelection != nil {
        isUnsavedPromptPresented = true
      }
    }
    .confirmationDialog(
      "Save changes before continuing?",
      isPresented: $isUnsavedPromptPresented
    ) {
      Button("Save and Continue") {
        isResolvingUnsavedPrompt = true
        Task {
          await saveAndContinue()
          isResolvingUnsavedPrompt = false
          if profileEditor.session.pendingSelection != nil || deferredAction != nil {
            isUnsavedPromptPresented = true
          }
        }
      }
      Button("Discard Changes", role: .destructive) {
        isResolvingUnsavedPrompt = true
        discardAndContinue()
        isResolvingUnsavedPrompt = false
      }
      Button("Cancel", role: .cancel) {
        cancelDeferredAction()
      }
    } message: {
      Text("This profile has changes that have not been saved.")
    }
    .onChange(of: isUnsavedPromptPresented) {
      if !isUnsavedPromptPresented, !isResolvingUnsavedPrompt,
        profileEditor.session.pendingSelection != nil || deferredAction != nil
      {
        cancelDeferredAction()
      }
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
      List(selection: selectionBinding) {
        ForEach(model.profiles) { profile in
          HStack {
            Image(systemName: appResolvedProfileSymbolName(profile.symbolName))
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
          requestDeferredAction(.create)
        } label: {
          Label("New Profile", systemImage: "plus")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Create profile")
        .help("Create profile")

        Button {
          if let selection = profileEditor.selectedProfileID {
            requestDeferredAction(.duplicate(selection))
          }
        } label: {
          Label("Duplicate Profile", systemImage: "plus.square.on.square")
        }
        .labelStyle(.iconOnly)
        .disabled(profileEditor.selectedProfileID == nil)
        .accessibilityLabel("Duplicate selected profile")
        .help("Duplicate selected profile")

        Button {
          if let profile = selectedProfile {
            requestDeferredAction(.delete(profile))
          }
        } label: {
          Label("Delete Profile", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
        .disabled(profileEditor.selectedProfileID == nil)
        .accessibilityLabel("Delete selected profile")
        .help("Delete selected profile")

        Spacer()

        Button {
          if let selection = profileEditor.selectedProfileID {
            model.moveProfile(id: selection, by: -1)
          }
        } label: {
          Label("Move Up", systemImage: "chevron.up")
        }
        .labelStyle(.iconOnly)
        .disabled(!canMove(by: -1))
        .accessibilityLabel("Move selected profile up")
        .help("Move selected profile up")

        Button {
          if let selection = profileEditor.selectedProfileID {
            model.moveProfile(id: selection, by: 1)
          }
        } label: {
          Label("Move Down", systemImage: "chevron.down")
        }
        .labelStyle(.iconOnly)
        .disabled(!canMove(by: 1))
        .accessibilityLabel("Move selected profile down")
        .help("Move selected profile down")
      }
    }
  }

  @ViewBuilder
  private var editor: some View {
    VStack(spacing: 0) {
      if profileEditor.draft != nil {
        ProfileEditorForm(
          profile: draftBinding,
          conditionContext: model.lastConditionContext,
          systemSnapshot: model.lastSnapshot
        )
        Divider()
        editorActionBar
      } else {
        ContentUnavailableView(
          "Select a Profile",
          systemImage: "sidebar.left",
          description: Text("Choose a profile in the sidebar or create a new one.")
        )
      }
    }
  }

  private var draftBinding: Binding<DeskProfile> {
    Binding(
      get: { profileEditor.draft ?? DeskProfile(name: "") },
      set: { profileEditor.replaceDraft($0) }
    )
  }

  private var selectedProfile: DeskProfile? {
    guard let selection = profileEditor.selectedProfileID else { return nil }
    return model.profiles.first { $0.id == selection }
  }

  private func canMove(by offset: Int) -> Bool {
    guard let selection = profileEditor.selectedProfileID,
      let index = model.profiles.firstIndex(where: { $0.id == selection })
    else { return false }
    return model.profiles.indices.contains(index + offset)
  }

  private var selectionBinding: Binding<UUID?> {
    Binding(
      get: { profileEditor.selectedProfileID },
      set: { requestedID in
        let requestedProfile = requestedID.flatMap { id in
          model.profiles.first { $0.id == id }
        }
        switch profileEditor.requestSelection(requestedProfile) {
        case .selected(let target):
          persistSelection(target)
        case .requiresDecision:
          isUnsavedPromptPresented = true
        case .unchanged:
          break
        }
      }
    )
  }

  private var editorActionBar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(editorActivityTitle, systemImage: editorActivitySymbol)
          .font(.caption)
          .foregroundStyle(editorActivityIsError ? .red : .secondary)
          .accessibilityLabel(editorActivityAccessibilityLabel)
        Spacer()
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          captureSettingsButton
          Spacer()
          revertDraftButton
          saveDraftButton
        }

        VStack(alignment: .trailing, spacing: 6) {
          HStack {
            Spacer()
            captureSettingsButton
          }
          HStack(spacing: 10) {
            Spacer()
            revertDraftButton
            saveDraftButton
          }
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private var captureSettingsButton: some View {
    Button("Update Draft from Current Settings") {
      requestDeferredAction(.captureCurrentSettings)
    }
    .accessibilityHint("Reads the current Mac and updates only this unsaved draft")
    .disabled(profileEditor.activity.isBusy)
  }

  private var revertDraftButton: some View {
    Button("Revert Changes") {
      profileEditor.revertDraft()
    }
    .disabled(!profileEditor.isDirty || profileEditor.activity.isBusy)
  }

  private var saveDraftButton: some View {
    Button("Save Profile") {
      Task { await saveCurrentDraft() }
    }
    .keyboardShortcut("s")
    .buttonStyle(.borderedProminent)
    .disabled(!canSaveDraft)
  }

  private var canSaveDraft: Bool {
    guard let draft = profileEditor.draft else { return false }
    return profileEditor.isDirty
      && !profileEditor.activity.isBusy
      && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var editorActivityIsError: Bool {
    if case .error = profileEditor.activity { return true }
    return false
  }

  private var editorActivityTitle: String {
    switch profileEditor.activity {
    case .saved:
      appLocalized("All changes are saved.")
    case .changed:
      appLocalized("Unsaved changes")
    case .saving:
      appLocalized("Saving profile…")
    case .capturing:
      appLocalized("Reading current settings…")
    case .message(let message), .error(let message):
      message
    }
  }

  private var editorActivitySymbol: String {
    switch profileEditor.activity {
    case .saved: "checkmark.circle"
    case .changed: "pencil.circle"
    case .saving, .capturing: "hourglass"
    case .message: "info.circle"
    case .error: "exclamationmark.triangle"
    }
  }

  private var editorActivityAccessibilityLabel: String {
    appLocalized("Profile editor status: \(editorActivityTitle)")
  }

  private func synchronizeEditor() {
    profileEditor.synchronize(
      profiles: model.profiles,
      preferredProfileID: model.selectedProfileID
    )
  }

  private func requestDeferredAction(_ action: DeferredProfileAction) {
    guard profileEditor.isDirty else {
      performDeferredAction(action)
      return
    }
    deferredAction = action
    isUnsavedPromptPresented = true
  }

  private func cancelDeferredAction() {
    if profileEditor.session.pendingSelection != nil {
      profileEditor.resolvePendingSelection(.cancel)
    }
    deferredAction = nil
    isUnsavedPromptPresented = false
  }

  private func discardAndContinue() {
    if profileEditor.session.pendingSelection != nil {
      if case .selected(let target) = profileEditor.resolvePendingSelection(.discard) {
        persistSelection(target)
      }
      return
    }

    let action = deferredAction
    deferredAction = nil
    profileEditor.revertDraft()
    if let action {
      performDeferredAction(action)
    }
  }

  private func saveAndContinue() async {
    if profileEditor.session.pendingSelection != nil {
      guard
        case .saveRequired(let candidate, _) =
          profileEditor.resolvePendingSelection(.save)
      else { return }
      profileEditor.beginSaving()
      switch await model.updateProfile(candidate) {
      case .saved(let persisted):
        switch profileEditor.completeSave(with: persisted) {
        case .savedAndSelected(let target):
          persistSelection(target)
        case .saved:
          profileEditor.finishWithError(
            appLocalized("The pending profile selection was no longer available."))
        case .rejected:
          profileEditor.finishWithError(
            appLocalized("The saved profile did not match the active draft."))
        }
      case .rejected(let message):
        profileEditor.finishWithError(message)
      }
      return
    }

    guard let action = deferredAction else { return }
    deferredAction = nil
    guard await saveCurrentDraft() else {
      deferredAction = action
      return
    }
    performDeferredAction(action)
  }

  @discardableResult
  private func saveCurrentDraft() async -> Bool {
    guard let candidate = profileEditor.session.saveCandidate() else { return false }
    profileEditor.beginSaving()
    switch await model.updateProfile(candidate) {
    case .saved(let persisted):
      switch profileEditor.completeSave(with: persisted) {
      case .saved:
        return true
      case .savedAndSelected(let target):
        persistSelection(target)
        return true
      case .rejected:
        profileEditor.finishWithError(
          appLocalized("The saved profile did not match the active draft."))
        return false
      }
    case .rejected(let message):
      profileEditor.finishWithError(message)
      return false
    }
  }

  private func captureCurrentSettingsIntoDraft() async {
    guard let targetID = profileEditor.draft?.id else { return }
    profileEditor.beginCapture()
    switch await model.captureCurrentProfileSettings() {
    case .captured(let snapshot):
      guard profileEditor.draft?.id == targetID else {
        profileEditor.finishWithError(
          appLocalized("The selected profile changed before the snapshot finished."))
        return
      }
      guard
        SettingGroup.safeApplicationSequence.contains(where: {
          snapshot.profileSettings.payload(for: $0) != nil
        })
      else {
        profileEditor.finishWithError(
          appLocalized("No settings could be added safely from this snapshot."))
        return
      }
      let previousSettings = profileEditor.draft?.settings
      profileEditor.replaceSettingsFromSnapshot(
        snapshot.profileSettings,
        expectedProfileID: targetID
      )
      profileEditor.finishWithMessage(
        previousSettings == snapshot.profileSettings
          ? appLocalized("The draft already matches the current settings.")
          : appLocalized("Current settings were added to the draft. Review and save them."))
    case .rejected(let message):
      profileEditor.finishWithError(message)
    }
  }

  private func persistSelection(_ target: ProfileSelectionTarget) {
    model.selectProfile(id: target.profileID)
  }

  private func performDeferredAction(_ action: DeferredProfileAction) {
    switch action {
    case .create:
      model.createProfile()
    case .duplicate(let id):
      model.duplicateProfile(id: id)
    case .delete(let profile):
      profilePendingDeletion = model.profiles.first(where: { $0.id == profile.id }) ?? profile
    case .importProfiles:
      model.importProfiles()
    case .captureCurrentSettings:
      Task { await captureCurrentSettingsIntoDraft() }
    }
  }
}

private enum DeferredProfileAction: Identifiable {
  case create
  case duplicate(UUID)
  case delete(DeskProfile)
  case importProfiles
  case captureCurrentSettings

  var id: String {
    switch self {
    case .create: "create"
    case .duplicate(let id): "duplicate-\(id.uuidString)"
    case .delete(let profile): "delete-\(profile.id.uuidString)"
    case .importProfiles: "import"
    case .captureCurrentSettings: "capture-current-settings"
    }
  }
}

private struct ProfileEditorForm: View {
  @Binding var profile: DeskProfile
  let conditionContext: ConditionContext
  let systemSnapshot: SystemSnapshotResult?

  var body: some View {
    Form {
      Section("Profile") {
        TextField("Name", text: $profile.name)
          .accessibilityLabel("Profile name")
        TextField("Description", text: $profile.profileDescription, axis: .vertical)
          .lineLimit(2...4)
          .accessibilityLabel("Profile description")
        Picker("Icon", selection: $profile.symbolName) {
          ForEach(iconChoices, id: \.symbolName) { choice in
            Label(appLocalizedRuntime(choice.title), systemImage: choice.symbolName)
              .tag(choice.symbolName)
          }
          if !profileIconChoices.contains(where: { $0.symbolName == profile.symbolName }) {
            Label(
              appLocalized("Imported icon"),
              systemImage: appResolvedProfileSymbolName(profile.symbolName)
            )
            .tag(profile.symbolName)
          }
        }
        .accessibilityLabel("Profile icon")
        if !profileIconChoices.contains(where: { $0.symbolName == profile.symbolName }) {
          DisclosureGroup("Technical Information") {
            LabeledContent("Imported symbol name") {
              Text(profile.symbolName)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
          }
        }
        Toggle("Enabled", isOn: $profile.isEnabled)
      }

      Section("Settings") {
        Text("Turn on a category to edit the values this profile will apply.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      settingGroupEditor(
        "Displays",
        systemImage: "display.2",
        isOn: $profile.settings.display.isIncluded,
        summary: summaryPreview(for: .display)
      ) {
        displayOptions
      }

      settingGroupEditor(
        "Audio",
        systemImage: "speaker.wave.2",
        isOn: $profile.settings.audio.isIncluded,
        summary: summaryPreview(for: .audio)
      ) {
        audioOptions
      }

      settingGroupEditor(
        "Network",
        systemImage: "network",
        isOn: $profile.settings.network.isIncluded,
        summary: summaryPreview(for: .network)
      ) {
        networkOptions
      }

      settingGroupEditor(
        "Mouse & Keyboard",
        systemImage: "keyboard",
        isOn: $profile.settings.input.isIncluded,
        summary: summaryPreview(for: .input)
      ) {
        inputOptions
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

    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var displayOptions: some View {
    if profile.settings.display.value.displays.isEmpty {
      Label(
        "Capture current settings to add detected displays before editing this category.",
        systemImage: "display.badge.exclamationmark"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    } else {
      ForEach($profile.settings.display.value.displays) { $display in
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            optionEditor("Primary display", isOn: $display.isPrimary.isIncluded) {
              Picker("Primary display value", selection: $display.isPrimary.value) {
                Text("Primary").tag(true)
                Text("Not primary").tag(false)
              }
              .pickerStyle(.segmented)
            }

            optionEditor("Position", isOn: $display.origin.isIncluded) {
              HStack {
                TextField("X position", value: $display.origin.value.x, format: .number)
                TextField("Y position", value: $display.origin.value.y, format: .number)
              }
            }

            optionEditor("Mirroring", isOn: $display.mirroring.isIncluded) {
              Picker(
                "Display arrangement",
                selection: mirroredDisplayBinding($display.mirroring.value)
              ) {
                Text("Extended desktop").tag(Optional<DisplayIdentity>.none)
                ForEach(mirrorTargets(excluding: display.id)) { target in
                  Text(displayName(target))
                    .tag(Optional(target.identity))
                }
                if let savedMirror = mirroredIdentity(display.mirroring.value),
                  !mirrorTargets(excluding: display.id).contains(where: {
                    $0.identity == savedMirror
                  })
                {
                  Text("Saved display — currently disconnected")
                    .tag(Optional(savedMirror))
                }
              }
            }

            optionEditor("Resolution and refresh rate", isOn: $display.mode.isIncluded) {
              Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                  Text("Logical width")
                  TextField("Logical width", value: $display.mode.value.width, format: .number)
                }
                GridRow {
                  Text("Logical height")
                  TextField("Logical height", value: $display.mode.value.height, format: .number)
                }
                GridRow {
                  Text("Pixel width")
                  TextField("Pixel width", value: $display.mode.value.pixelWidth, format: .number)
                }
                GridRow {
                  Text("Pixel height")
                  TextField("Pixel height", value: $display.mode.value.pixelHeight, format: .number)
                }
                GridRow {
                  Text("Refresh rate")
                  HStack {
                    TextField(
                      "Refresh rate",
                      value: $display.mode.value.refreshRate,
                      format: .number.precision(.fractionLength(0...2))
                    )
                    Text("Hz")
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }

            optionEditor("Rotation", isOn: $display.rotationDegrees.isIncluded) {
              Picker("Rotation", selection: $display.rotationDegrees.value) {
                Text("0°").tag(0)
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
              }
              .pickerStyle(.segmented)
              unsupportedDisplayOptionNotice
            }

            optionEditor("Active state", isOn: $display.isActive.isIncluded) {
              Picker("Active state value", selection: $display.isActive.value) {
                Text("Active").tag(true)
                Text("Inactive").tag(false)
              }
              .pickerStyle(.segmented)
              unsupportedDisplayOptionNotice
            }
          }
        } label: {
          Label(displayName(display), systemImage: "display")
            .font(.headline)
        }
      }
    }
  }

  @ViewBuilder
  private var audioOptions: some View {
    audioDeviceOption(
      "Default input device",
      option: $profile.settings.audio.value.defaultInputUID,
      scope: .input
    )
    audioDeviceOption(
      "Default output device",
      option: $profile.settings.audio.value.defaultOutputUID,
      scope: .output
    )
    audioDeviceOption(
      "System output device",
      option: $profile.settings.audio.value.systemOutputUID,
      scope: .output
    )

    optionEditor("Output volume", isOn: $profile.settings.audio.value.outputVolume.isIncluded) {
      HStack {
        TextField(
          "Volume percent",
          value: percentageBinding($profile.settings.audio.value.outputVolume.value),
          format: .number.precision(.fractionLength(0...1))
        )
        Text("%")
          .foregroundStyle(.secondary)
      }
      Text("Enter a value from 0 to 100 percent.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    optionEditor("Output mute", isOn: $profile.settings.audio.value.outputMuted.isIncluded) {
      optionalBooleanPicker(
        "Output mute value",
        selection: $profile.settings.audio.value.outputMuted.value
      )
    }
  }

  @ViewBuilder
  private var networkOptions: some View {
    optionEditor("Wi-Fi power", isOn: $profile.settings.network.value.wifiPower.isIncluded) {
      optionalBooleanPicker(
        "Wi-Fi power value",
        selection: $profile.settings.network.value.wifiPower.value
      )
    }

    optionEditor("Wi-Fi network", isOn: $profile.settings.network.value.wifiSSID.isIncluded) {
      TextField(
        "Network name",
        text: optionalStringBinding($profile.settings.network.value.wifiSSID.value)
      )
      if let currentSSID = conditionContext.wifiSSID,
        currentSSID != profile.settings.network.value.wifiSSID.value
      {
        Button("Use Current Wi-Fi Network") {
          profile.settings.network.value.wifiSSID.value = currentSSID
        }
      }
    }

    optionEditor("IPv4 configuration", isOn: $profile.settings.network.value.ipv4.isIncluded) {
      Picker(
        "IPv4 method",
        selection: ipv4ModeBinding($profile.settings.network.value.ipv4.value)
      ) {
        Text("Choose").tag(Optional<IPv4EditorMode>.none)
        Text("DHCP").tag(Optional(IPv4EditorMode.dhcp))
        Text("Manual").tag(Optional(IPv4EditorMode.manual))
      }
      .pickerStyle(.segmented)

      if ipv4ModeBinding($profile.settings.network.value.ipv4.value).wrappedValue == .manual {
        TextField(
          "IP address",
          text: manualIPv4AddressBinding($profile.settings.network.value.ipv4.value)
        )
        TextField(
          "Subnet mask",
          text: manualIPv4SubnetBinding($profile.settings.network.value.ipv4.value)
        )
        TextField(
          "Router (optional)",
          text: manualIPv4RouterBinding($profile.settings.network.value.ipv4.value)
        )
      }
      unsupportedNetworkOptionNotice
    }

    optionEditor("DNS servers", isOn: $profile.settings.network.value.dnsServers.isIncluded) {
      TextField(
        "DNS servers, separated by commas or new lines",
        text: stringListBinding($profile.settings.network.value.dnsServers.value),
        axis: .vertical
      )
      .lineLimit(2...5)
      unsupportedNetworkOptionNotice
    }

    proxyOptionEditor(
      "Web proxy",
      option: $profile.settings.network.value.webProxy
    )
    proxyOptionEditor(
      "Secure web proxy",
      option: $profile.settings.network.value.secureWebProxy
    )
  }

  @ViewBuilder
  private var inputOptions: some View {
    Label(
      "Experimental: macOS does not document the stability of these global preference keys.",
      systemImage: "testtube.2"
    )
    .font(.caption)
    .foregroundStyle(.secondary)

    optionEditor("Pointer speed", isOn: $profile.settings.input.value.pointerSpeed.isIncluded) {
      optionalNumberField(
        "Pointer speed value",
        value: $profile.settings.input.value.pointerSpeed.value,
        rangeDescription: "Allowed range: −1 to 10."
      )
    }

    optionEditor(
      "Natural scrolling",
      isOn: $profile.settings.input.value.naturalScrolling.isIncluded
    ) {
      optionalBooleanPicker(
        "Natural scrolling value",
        selection: $profile.settings.input.value.naturalScrolling.value
      )
    }

    optionEditor("Key repeat", isOn: $profile.settings.input.value.keyRepeatInterval.isIncluded) {
      optionalNumberField(
        "Key repeat value",
        value: $profile.settings.input.value.keyRepeatInterval.value,
        rangeDescription: "Allowed range: 1 to 120. Lower values repeat faster."
      )
    }

    optionEditor(
      "Initial key repeat delay",
      isOn: $profile.settings.input.value.initialKeyRepeatDelay.isIncluded
    ) {
      optionalNumberField(
        "Initial key repeat delay value",
        value: $profile.settings.input.value.initialKeyRepeatDelay.value,
        rangeDescription: "Allowed range: 1 to 300."
      )
    }

    optionEditor(
      "Use F1–F12 as standard function keys",
      isOn: $profile.settings.input.value.useStandardFunctionKeys.isIncluded
    ) {
      optionalBooleanPicker(
        "Function key value",
        selection: $profile.settings.input.value.useStandardFunctionKeys.value
      )
    }
  }

  @ViewBuilder
  private func settingGroupEditor<Content: View>(
    _ title: LocalizedStringKey,
    systemImage: String,
    isOn: Binding<Bool>,
    summary: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Section {
      Toggle(isOn: isOn) {
        Label(title, systemImage: systemImage)
          .font(.headline)
      }

      if isOn.wrappedValue {
        content()
          .padding(.leading, 4)
      } else {
        Text(summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
    }
  }

  @ViewBuilder
  private func optionEditor<Content: View>(
    _ title: LocalizedStringKey,
    isOn: Binding<Bool>,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(title, isOn: isOn)
      if isOn.wrappedValue {
        VStack(alignment: .leading, spacing: 8) {
          content()
        }
        .padding(.leading, 20)
      }
    }
    .padding(.vertical, 3)
  }

  @ViewBuilder
  private func audioDeviceOption(
    _ title: LocalizedStringKey,
    option: Binding<SettingOption<String?>>,
    scope: AudioDeviceScope
  ) -> some View {
    optionEditor(title, isOn: option.isIncluded) {
      let choices = audioDeviceChoices.filter { $0.scopes.contains(scope) }
      Picker("Device", selection: option.value) {
        Text("Choose a device").tag(Optional<String>.none)
        ForEach(choices) { choice in
          Text(choice.name).tag(Optional(choice.uid))
        }
        if let savedUID = option.wrappedValue.value,
          !choices.contains(where: { $0.uid == savedUID })
        {
          Text("Saved device — currently disconnected")
            .tag(Optional(savedUID))
        }
      }

      DisclosureGroup("Advanced") {
        TextField("Device UID", text: optionalStringBinding(option.value))
          .font(.caption.monospaced())
      }
    }
  }

  private func optionalBooleanPicker(
    _ title: LocalizedStringKey,
    selection: Binding<Bool?>
  ) -> some View {
    Picker(title, selection: selection) {
      Text("Choose").tag(Optional<Bool>.none)
      Text("On").tag(Optional(true))
      Text("Off").tag(Optional(false))
    }
    .pickerStyle(.segmented)
  }

  @ViewBuilder
  private func optionalNumberField(
    _ title: LocalizedStringKey,
    value: Binding<Double?>,
    rangeDescription: LocalizedStringKey
  ) -> some View {
    TextField(
      title,
      value: value,
      format: .number.precision(.fractionLength(0...2))
    )
    Text(rangeDescription)
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private func proxyOptionEditor(
    _ title: LocalizedStringKey,
    option: Binding<SettingOption<ProxyConfiguration?>>
  ) -> some View {
    optionEditor(title, isOn: option.isIncluded) {
      Picker("Proxy mode", selection: proxyModeBinding(option.value)) {
        Text("Choose").tag(Optional<ProxyEditorMode>.none)
        Text("Disabled").tag(Optional(ProxyEditorMode.disabled))
        Text("Enabled").tag(Optional(ProxyEditorMode.enabled))
      }
      .pickerStyle(.segmented)

      if proxyModeBinding(option.value).wrappedValue == .enabled {
        TextField("Proxy host", text: proxyHostBinding(option.value))
        TextField("Proxy port", value: proxyPortBinding(option.value), format: .number)
      }
      unsupportedNetworkOptionNotice
    }
  }

  private var unsupportedDisplayOptionNotice: some View {
    Label(
      "This display value is preserved for snapshots, but the current adapter does not apply it.",
      systemImage: "exclamationmark.circle"
    )
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private var unsupportedNetworkOptionNotice: some View {
    Label(
      "This network value is preserved for snapshots, but the current adapter does not apply administrative network settings.",
      systemImage: "exclamationmark.circle"
    )
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private func summaryPreview(for group: SettingGroup) -> String {
    guard let summary = presentationBuilder.summary(for: group, in: profile.settings),
      !summary.items.isEmpty
    else {
      return appLocalized("No included values")
    }

    let visible = summary.items.prefix(2).map(appProfileSummaryValue)
    let remaining = summary.items.count - visible.count
    if remaining > 0 {
      return appLocalized("\(visible.joined(separator: " · ")) and \(remaining) more")
    }
    return visible.joined(separator: " · ")
  }

  private var presentationBuilder: ProfilePresentationBuilder {
    ProfilePresentationBuilder()
  }

  private func displayName(_ display: DisplayTargetSettings) -> String {
    let name = display.identity.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let name, !name.isEmpty {
      return name
    }
    return display.identity.isBuiltIn
      ? appLocalized("Built-in display") : appLocalized("External display")
  }

  private func mirrorTargets(excluding id: UUID) -> [DisplayTargetSettings] {
    profile.settings.display.value.displays.filter { $0.id != id }
  }

  private func mirroredIdentity(_ mirroring: DisplayMirroring) -> DisplayIdentity? {
    guard case .mirrors(let identity) = mirroring else { return nil }
    return identity
  }

  private func mirroredDisplayBinding(
    _ mirroring: Binding<DisplayMirroring>
  ) -> Binding<DisplayIdentity?> {
    Binding(
      get: { mirroredIdentity(mirroring.wrappedValue) },
      set: { identity in
        mirroring.wrappedValue = identity.map(DisplayMirroring.mirrors) ?? .extended
      }
    )
  }

  private var audioDeviceChoices: [AudioDeviceChoice] {
    var choicesByUID: [String: AudioDeviceChoice] = [:]
    for item in systemSnapshot?.result(for: .audio)?.items ?? [] {
      let prefix = "device:"
      guard item.state == .detected, item.key.hasPrefix(prefix) else { continue }
      let uid = String(item.key.dropFirst(prefix.count))
      guard !uid.isEmpty else { continue }
      var scopes = Set<AudioDeviceScope>()
      if item.detail.contains("Input") { scopes.insert(.input) }
      if item.detail.contains("Output") { scopes.insert(.output) }
      choicesByUID[uid] = AudioDeviceChoice(uid: uid, name: item.label, scopes: scopes)
    }

    let detectedUIDs = conditionContext.audioInputUIDs.union(conditionContext.audioOutputUIDs)
      .sorted()
    for (index, uid) in detectedUIDs.enumerated() {
      var scopes = choicesByUID[uid]?.scopes ?? []
      if conditionContext.audioInputUIDs.contains(uid) { scopes.insert(.input) }
      if conditionContext.audioOutputUIDs.contains(uid) { scopes.insert(.output) }
      let fallbackRole: String
      switch (scopes.contains(.input), scopes.contains(.output)) {
      case (true, true): fallbackRole = appLocalized("Detected audio device")
      case (true, false): fallbackRole = appLocalized("Detected input device")
      case (false, true): fallbackRole = appLocalized("Detected output device")
      case (false, false): continue
      }
      choicesByUID[uid] = AudioDeviceChoice(
        uid: uid,
        name: choicesByUID[uid]?.name ?? "\(fallbackRole) \(index + 1)",
        scopes: scopes
      )
    }

    return choicesByUID.values
      .sorted {
        let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
        return nameOrder == .orderedSame ? $0.uid < $1.uid : nameOrder == .orderedAscending
      }
  }

  private func optionalStringBinding(_ value: Binding<String?>) -> Binding<String> {
    Binding(
      get: { value.wrappedValue ?? "" },
      set: { updated in
        value.wrappedValue = updated.isEmpty ? nil : updated
      }
    )
  }

  private func percentageBinding(_ value: Binding<Double?>) -> Binding<Double?> {
    Binding(
      get: { value.wrappedValue.map { $0 * 100 } },
      set: { value.wrappedValue = $0.map { $0 / 100 } }
    )
  }

  private func stringListBinding(_ values: Binding<[String]>) -> Binding<String> {
    Binding(
      get: { values.wrappedValue.joined(separator: ", ") },
      set: { text in
        values.wrappedValue =
          text
          .split(whereSeparator: { $0 == "," || $0 == "\n" })
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      }
    )
  }

  private func ipv4ModeBinding(
    _ configuration: Binding<IPv4Configuration?>
  ) -> Binding<IPv4EditorMode?> {
    Binding(
      get: {
        switch configuration.wrappedValue {
        case .dhcp?: .dhcp
        case .manual?: .manual
        case nil: nil
        }
      },
      set: { mode in
        switch mode {
        case .dhcp?:
          configuration.wrappedValue = .dhcp
        case .manual?:
          if case .manual? = configuration.wrappedValue { return }
          configuration.wrappedValue = .manual(address: "", subnetMask: "", router: nil)
        case nil:
          configuration.wrappedValue = nil
        }
      }
    )
  }

  private func manualIPv4AddressBinding(
    _ configuration: Binding<IPv4Configuration?>
  ) -> Binding<String> {
    Binding(
      get: {
        guard case .manual(let address, _, _)? = configuration.wrappedValue else { return "" }
        return address
      },
      set: { address in
        guard case .manual(_, let subnet, let router)? = configuration.wrappedValue else { return }
        configuration.wrappedValue = .manual(
          address: address,
          subnetMask: subnet,
          router: router
        )
      }
    )
  }

  private func manualIPv4SubnetBinding(
    _ configuration: Binding<IPv4Configuration?>
  ) -> Binding<String> {
    Binding(
      get: {
        guard case .manual(_, let subnet, _)? = configuration.wrappedValue else { return "" }
        return subnet
      },
      set: { subnet in
        guard case .manual(let address, _, let router)? = configuration.wrappedValue else { return }
        configuration.wrappedValue = .manual(
          address: address,
          subnetMask: subnet,
          router: router
        )
      }
    )
  }

  private func manualIPv4RouterBinding(
    _ configuration: Binding<IPv4Configuration?>
  ) -> Binding<String> {
    Binding(
      get: {
        guard case .manual(_, _, let router)? = configuration.wrappedValue else { return "" }
        return router ?? ""
      },
      set: { router in
        guard case .manual(let address, let subnet, _)? = configuration.wrappedValue else { return }
        configuration.wrappedValue = .manual(
          address: address,
          subnetMask: subnet,
          router: router.isEmpty ? nil : router
        )
      }
    )
  }

  private func proxyModeBinding(
    _ configuration: Binding<ProxyConfiguration?>
  ) -> Binding<ProxyEditorMode?> {
    Binding(
      get: {
        guard let proxy = configuration.wrappedValue else { return nil }
        return proxy.enabled ? .enabled : .disabled
      },
      set: { mode in
        guard let mode else {
          configuration.wrappedValue = nil
          return
        }
        var proxy =
          configuration.wrappedValue
          ?? ProxyConfiguration(enabled: false, host: "", port: 8080)
        proxy.enabled = mode == .enabled
        configuration.wrappedValue = proxy
      }
    )
  }

  private func proxyHostBinding(
    _ configuration: Binding<ProxyConfiguration?>
  ) -> Binding<String> {
    Binding(
      get: { configuration.wrappedValue?.host ?? "" },
      set: { host in
        var proxy =
          configuration.wrappedValue
          ?? ProxyConfiguration(enabled: true, host: "", port: 8080)
        proxy.host = host
        configuration.wrappedValue = proxy
      }
    )
  }

  private func proxyPortBinding(
    _ configuration: Binding<ProxyConfiguration?>
  ) -> Binding<Int> {
    Binding(
      get: { configuration.wrappedValue?.port ?? 8080 },
      set: { port in
        var proxy =
          configuration.wrappedValue
          ?? ProxyConfiguration(enabled: true, host: "", port: 8080)
        proxy.port = port
        configuration.wrappedValue = proxy
      }
    )
  }

  private var iconChoices: [ProfileIconChoice] {
    profileIconChoices
  }
}

private enum AudioDeviceScope: Hashable {
  case input
  case output
}

private struct AudioDeviceChoice: Identifiable {
  let uid: String
  let name: String
  let scopes: Set<AudioDeviceScope>

  var id: String { uid }
}

private enum IPv4EditorMode: Hashable {
  case dhcp
  case manual
}

private enum ProxyEditorMode: Hashable {
  case disabled
  case enabled
}

private struct ProfileIconChoice {
  let symbolName: String
  let title: String
}

private let profileIconChoices: [ProfileIconChoice] = [
  .init(symbolName: "display.2", title: "Displays"),
  .init(symbolName: "laptopcomputer.and.iphone", title: "Devices"),
  .init(symbolName: "house", title: "Home"),
  .init(symbolName: "building.2", title: "Office"),
  .init(symbolName: "gamecontroller", title: "Gaming"),
  .init(symbolName: "headphones", title: "Audio"),
  .init(symbolName: "video", title: "Video calls"),
  .init(symbolName: "keyboard", title: "Mouse & Keyboard"),
]
