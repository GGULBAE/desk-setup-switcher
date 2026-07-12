import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
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
          conditionContext: model.lastConditionContext
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

      Section("Included settings") {
        groupToggle(
          appLocalized("Displays"),
          systemImage: "display.2",
          isOn: $profile.settings.display.isIncluded,
          detail: summaryPreview(for: .display)
        )
        groupToggle(
          appLocalized("Audio"),
          systemImage: "speaker.wave.2",
          isOn: $profile.settings.audio.isIncluded,
          detail: summaryPreview(for: .audio)
        )
        groupToggle(
          appLocalized("Network"),
          systemImage: "network",
          isOn: $profile.settings.network.isIncluded,
          detail: summaryPreview(for: .network)
        )
        groupToggle(
          appLocalized("Mouse & Keyboard"),
          systemImage: "keyboard",
          isOn: $profile.settings.input.isIncluded,
          detail: summaryPreview(for: .input)
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
          availableDisplays: detectedConditionDisplays,
          availableAudioInputUIDs: conditionContext.audioInputUIDs.sorted(),
          availableAudioOutputUIDs: conditionContext.audioOutputUIDs.sorted(),
          availableHardwareIdentifiers: conditionContext.hardwareIdentifiers.sorted(),
          currentWiFiSSID: conditionContext.wifiSSID,
          currentIPAddresses: conditionContext.ipAddresses.sorted(),
          currentLocation: conditionContext.location
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

    }
    .formStyle(.grouped)
  }

  private var displayOptions: some View {
    DisclosureGroup("Display options") {
      summaryRows(for: .display)
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
      summaryRows(for: .audio)
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
      summaryRows(for: .network)
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
      summaryRows(for: .input)
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

  @ViewBuilder
  private func summaryRows(for group: SettingGroup) -> some View {
    if let summary = presentationBuilder.summary(for: group, in: profile.settings) {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(summary.items.enumerated()), id: \.offset) { _, item in
          LabeledContent {
            Text(appProfileSummaryValue(item))
              .multilineTextAlignment(.trailing)
          } label: {
            Text(appLocalizedPresentationText(item.label))
          }
          .accessibilityElement(children: .combine)
        }

        if !summary.technicalDetails.isEmpty {
          DisclosureGroup("Technical Information") {
            ForEach(Array(summary.technicalDetails.enumerated()), id: \.offset) { _, detail in
              LabeledContent(appLocalizedRuntime(detail.label)) {
                Text(detail.value)
                  .font(.caption.monospaced())
                  .textSelection(.enabled)
              }
            }
          }
        }
      }
      .padding(.vertical, 4)
    }
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

  private var detectedConditionDisplays: [DisplayIdentity] {
    conditionContext.displays.sorted {
      displayChoiceSortKey($0) < displayChoiceSortKey($1)
    }
  }

  private func displayChoiceSortKey(_ identity: DisplayIdentity) -> String {
    let name = identity.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let builtInOrder = identity.isBuiltIn ? "0" : "1"
    let technicalTieBreaker =
      identity.uuid?.uuidString
      ?? [identity.vendorID, identity.modelID, identity.serialNumber]
      .map { $0.map(String.init) ?? "" }
      .joined(separator: ":")
    return "\(builtInOrder)|\(name)|\(technicalTieBreaker)"
  }

  private var iconChoices: [ProfileIconChoice] {
    profileIconChoices
  }
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
