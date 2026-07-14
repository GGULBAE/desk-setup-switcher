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
  @State private var requestedValidationFocus: DraftFieldIdentifier?

  var body: some View {
    VStack(spacing: 12) {
      profileWorkspace
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
      .disabled(!draftCanBePersisted)
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

  private var profileWorkspace: some View {
    GeometryReader { geometry in
      let usesCompactLayout = geometry.size.width < 760

      // The fixed breakpoint intentionally replaces the draggable HSplitView.
      // AnyLayout keeps the sidebar/editor identity stable while the window is resized.
      let layout =
        usesCompactLayout
        ? AnyLayout(VStackLayout(spacing: 0))
        : AnyLayout(HStackLayout(spacing: 0))

      layout {
        sidebar
          .frame(
            minWidth: usesCompactLayout ? 0 : 220,
            idealWidth: usesCompactLayout ? nil : 250,
            maxWidth: usesCompactLayout ? .infinity : 300,
            minHeight: usesCompactLayout ? 120 : 0,
            idealHeight: usesCompactLayout ? 150 : nil,
            maxHeight: usesCompactLayout ? 170 : .infinity
          )
        Divider()
        editor
          .frame(
            minWidth: usesCompactLayout ? 0 : 390,
            maxWidth: .infinity,
            minHeight: usesCompactLayout ? 190 : 0,
            maxHeight: .infinity
          )
      }
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
          .accessibilityElement(children: .ignore)
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
          systemSnapshot: model.lastSnapshot,
          validation: currentDraftValidation,
          requestedValidationFocus: $requestedValidationFocus
        )
        .disabled(profileEditor.activity.isBusy)
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
    return profileEditor.isDirty
      && !profileEditor.activity.isBusy
      && draftCanBePersisted
  }

  private var currentDraftValidation: ProfileDraftValidation {
    guard let draft = profileEditor.draft else {
      return ProfileDraftValidation(issues: [])
    }
    return ProfileDraftValidator().validate(draft)
  }

  private var draftNameIsValid: Bool {
    profileEditor.draft != nil
      && currentDraftValidation.issue(for: .profileName) == nil
  }

  private var draftCanBePersisted: Bool {
    profileEditor.draft != nil && draftNameIsValid && currentDraftValidation.isValid
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
    guard validateDraftBeforeSaving() else { return }

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
    guard validateDraftBeforeSaving() else { return false }
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

  @discardableResult
  private func validateDraftBeforeSaving() -> Bool {
    guard draftCanBePersisted else {
      requestedValidationFocus =
        currentDraftValidation.firstInvalidField
      AccessibilityNotification.Announcement(
        appLocalized("Fix the highlighted fields before saving.")
      )
      .post()
      return false
    }
    return true
  }

  private func captureCurrentSettingsIntoDraft() async {
    guard let targetID = profileEditor.draft?.id else { return }
    profileEditor.beginCapture()
    switch await model.captureCurrentProfileSettings() {
    case .captured(let snapshot, let summary):
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
          : summary.status == .partial
            ? appLocalized(
              "Current settings replaced the draft settings with \(summary.excludedCount) snapshot-only and \(summary.omittedCount) unavailable items. Review and save them."
            )
            : appLocalized(
              "Current settings replaced the draft settings. Review and save them."))
    case .rejected(let message, _):
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
  @Environment(\.uiAuditConfiguration) private var uiAuditConfiguration
  @Binding var profile: DeskProfile
  let conditionContext: ConditionContext
  let systemSnapshot: SystemSnapshotResult?
  let validation: ProfileDraftValidation
  @Binding var requestedValidationFocus: DraftFieldIdentifier?
  @State private var groupDisclosure = DisclosureState<SettingGroup>()
  @State private var optionDisclosure = DisclosureState<OptionDisclosureID>()
  @State private var advancedNumberDisclosure = DisclosureState<DraftFieldIdentifier>()
  @FocusState private var focusedField: DraftFieldIdentifier?

  var body: some View {
    Form {
      Section("Profile") {
        TextField("Name", text: $profile.name)
          .accessibilityLabel("Profile name")
          .focused($focusedField, equals: .profileName)
          .accessibilityHint(validationAccessibilityHint(for: .profileName))
          .accessibilityInvalid(validation.issue(for: .profileName) != nil)
        if let issue = validation.issue(for: .profileName) {
          inlineValidationMessage(
            validationMessage(for: issue),
            fieldID: .profileName
          )
        }
        TextField("Description", text: $profile.profileDescription, axis: .vertical)
          .lineLimit(2...4)
          .accessibilityLabel("Profile description")
          .focused($focusedField, equals: .profileDescription)
          .accessibilityHint(validationAccessibilityHint(for: .profileDescription))
          .accessibilityInvalid(validation.issue(for: .profileDescription) != nil)
        if let issue = validation.issue(for: .profileDescription) {
          inlineValidationMessage(
            validationMessage(for: issue),
            fieldID: .profileDescription
          )
        }
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

      if !validation.isValid {
        validationSummary
      }

      Section("Settings") {
        Text(
          "Use Include to choose what this profile applies. Expand a category to review or edit its saved values."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      settingGroupEditor(
        "Displays",
        group: .display,
        systemImage: "display.2",
        isOn: $profile.settings.display.isIncluded,
        summary: summaryPreview(for: .display)
      ) {
        displayOptions
      }

      settingGroupEditor(
        "Audio",
        group: .audio,
        systemImage: "speaker.wave.2",
        isOn: $profile.settings.audio.isIncluded,
        summary: summaryPreview(for: .audio)
      ) {
        audioOptions
      }

      settingGroupEditor(
        "Network",
        group: .network,
        systemImage: "network",
        isOn: $profile.settings.network.isIncluded,
        summary: summaryPreview(for: .network)
      ) {
        networkOptions
      }

      settingGroupEditor(
        "Mouse & Keyboard",
        group: .input,
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
    .onChange(of: profile.id) {
      groupDisclosure.reset()
      optionDisclosure.reset()
      advancedNumberDisclosure.reset()
      focusedField = nil
      requestedValidationFocus = nil
    }
    .onChange(of: requestedValidationFocus) {
      guard let fieldID = requestedValidationFocus else { return }
      revealAndFocus(fieldID)
    }
    .onAppear {
      configureSyntheticAuditDisclosure()
    }
  }

  private var validationSummary: some View {
    Section {
      Label(
        "Fix the highlighted fields before saving.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(.red)
      .accessibilityLabel("Profile validation failed")
      .accessibilityHint("Review the first issue or choose a highlighted field")

      if let item = firstValidationItem {
        Button {
          revealAndFocus(item.fieldID)
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.message)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "arrow.forward.circle")
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          "\(appLocalized("First validation issue")): \(item.message)"
        )
        .accessibilityHint("Moves keyboard focus to the invalid field")
      }
    } header: {
      Text("Review Before Saving")
    }
  }

  private var firstValidationItem: EditorValidationItem? {
    guard let issue = validation.issues.first else { return nil }
    return EditorValidationItem(
      fieldID: issue.fieldID,
      message: validationMessage(for: issue)
    )
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
      if !profile.settings.display.value.displays.isEmpty {
        optionEditor(
          "Primary display",
          id: .init(group: .display, key: "primary"),
          isOn: primaryDisplayIncludedBinding,
          summary: primaryDisplaySummary,
          validationFields: [.displayPrimary]
        ) {
          Picker(
            "Primary display",
            selection: primaryDisplaySelectionBinding()
          ) {
            if primaryDisplaySelectionIsAmbiguous {
              Text("Choose a display").tag(invalidPrimaryDisplaySelectionID)
            }
            ForEach(profile.settings.display.value.displays) { display in
              Text(displayName(display)).tag(display.id)
            }
          }
          .accessibilityValue(primaryDisplaySummary)
          .accessibilityHint(validationAccessibilityHint(for: .displayPrimary))
          .accessibilityInvalid(validation.issue(for: .displayPrimary) != nil)
          .focused($focusedField, equals: .displayPrimary)
          Text("Select the display that should anchor the desktop.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      ForEach($profile.settings.display.value.displays) { $display in
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            optionEditor(
              "Position",
              id: .init(group: .display, ownerID: display.id, key: "position"),
              isOn: $display.origin.isIncluded,
              summary: "\(display.origin.value.x), \(display.origin.value.y)",
              validationFields: [
                .display(display.id, .originX),
                .display(display.id, .originY),
              ]
            ) {
              HStack {
                TextField("X position", value: $display.origin.value.x, format: .number)
                  .focused(
                    $focusedField,
                    equals: .display(display.id, .originX)
                  )
                  .accessibilityHint(
                    validationAccessibilityHint(
                      for: .display(display.id, .originX)
                    )
                  )
                  .accessibilityInvalid(
                    validation.issue(for: .display(display.id, .originX)) != nil
                  )
                TextField("Y position", value: $display.origin.value.y, format: .number)
                  .focused(
                    $focusedField,
                    equals: .display(display.id, .originY)
                  )
                  .accessibilityHint(
                    validationAccessibilityHint(
                      for: .display(display.id, .originY)
                    )
                  )
                  .accessibilityInvalid(
                    validation.issue(for: .display(display.id, .originY)) != nil
                  )
              }
            }

            optionEditor(
              "Mirroring",
              id: .init(group: .display, ownerID: display.id, key: "mirroring"),
              isOn: $display.mirroring.isIncluded,
              summary: mirroringSummary(display.mirroring.value)
            ) {
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

            optionEditor(
              "Resolution and refresh rate",
              id: .init(group: .display, ownerID: display.id, key: "mode"),
              isOn: $display.mode.isIncluded,
              summary: displayModeSummary(display.mode.value),
              validationFields: [
                .display(display.id, .modeWidth),
                .display(display.id, .modeHeight),
                .display(display.id, .modePixelWidth),
                .display(display.id, .modePixelHeight),
                .display(display.id, .modeRefreshRate),
              ]
            ) {
              let supportedModes = supportedDisplayModes(for: display)
              if supportedModes.isEmpty {
                LabeledContent("Saved mode", value: displayModeSummary(display.mode.value))
                Label(
                  "Supported display modes are unavailable. The saved mode is preserved.",
                  systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              } else {
                Picker(
                  "Supported mode",
                  selection: supportedDisplayModeBinding(
                    $display.mode.value,
                    supportedModes: supportedModes
                  )
                ) {
                  ForEach(supportedModes, id: \.self) { mode in
                    Text(displayModeSummary(mode)).tag(mode)
                  }
                  if DisplayModeMatcher().match(
                    display.mode.value,
                    among: supportedModes
                  ) == nil {
                    Text("Saved mode — currently unavailable")
                      .tag(display.mode.value)
                  }
                }
                .focused(
                  $focusedField,
                  equals: .display(display.id, .modeWidth)
                )
                .accessibilityLabel("Display mode")
                .accessibilityValue(displayModeSummary(display.mode.value))
                .accessibilityHint(
                  validationAccessibilityHint(
                    for: .display(display.id, .modeWidth)
                  )
                )
                .accessibilityInvalid(
                  validationIssues(for: [
                    .display(display.id, .modeWidth),
                    .display(display.id, .modeHeight),
                    .display(display.id, .modePixelWidth),
                    .display(display.id, .modePixelHeight),
                    .display(display.id, .modeRefreshRate),
                  ]).isEmpty == false
                )
              }
            }

            snapshotOnlyDisplayValues(display)
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
      key: "default-input-device",
      option: $profile.settings.audio.value.defaultInputUID,
      scope: .input,
      fieldID: .audio(.defaultInputDevice)
    )
    audioDeviceOption(
      "Default output device",
      key: "default-output-device",
      option: $profile.settings.audio.value.defaultOutputUID,
      scope: .output,
      fieldID: .audio(.defaultOutputDevice)
    )
    audioDeviceOption(
      "System output device",
      key: "system-output-device",
      option: $profile.settings.audio.value.systemOutputUID,
      scope: .output,
      fieldID: .audio(.systemOutputDevice)
    )

    optionEditor(
      "Output volume",
      id: .init(group: .audio, key: "output-volume"),
      isOn: $profile.settings.audio.value.outputVolume.isIncluded,
      summary: percentageSummary(profile.settings.audio.value.outputVolume.value),
      hasSavedValue: profile.settings.audio.value.outputVolume.value != nil,
      validationFields: [.audio(.outputVolume)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.audio.value.outputVolume.value == nil {
          profile.settings.audio.value.outputVolume.value =
            systemSnapshot?.profileSettings.audio.value.outputVolume.value ?? 0.5
        }
      }
    ) {
      if profile.settings.audio.value.outputVolume.value == nil {
        chooseSuggestedValueButton(fieldID: .audio(.outputVolume)) {
          profile.settings.audio.value.outputVolume.value =
            systemSnapshot?.profileSettings.audio.value.outputVolume.value ?? 0.5
        }
      } else {
        HStack(spacing: 10) {
          Slider(
            value: percentageSliderBinding($profile.settings.audio.value.outputVolume.value),
            in: 0...100,
            step: 1
          ) {
            Text("Volume percent")
          } minimumValueLabel: {
            Text("0")
          } maximumValueLabel: {
            Text("100")
          }
          TextField(
            "Volume percent",
            value: percentageBinding($profile.settings.audio.value.outputVolume.value),
            format: .number.precision(.fractionLength(0...1))
          )
          .frame(width: 58)
          .multilineTextAlignment(.trailing)
          .focused($focusedField, equals: .audio(.outputVolume))
          .accessibilityHint(
            validationAccessibilityHint(for: .audio(.outputVolume))
          )
          Text("%")
            .foregroundStyle(.secondary)
        }
        .accessibilityInvalid(validation.issue(for: .audio(.outputVolume)) != nil)
      }
      Text("Enter a value from 0 to 100 percent.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    optionEditor(
      "Output mute",
      id: .init(group: .audio, key: "output-mute"),
      isOn: $profile.settings.audio.value.outputMuted.isIncluded,
      summary: booleanTargetSummary(profile.settings.audio.value.outputMuted.value),
      hasSavedValue: profile.settings.audio.value.outputMuted.value != nil,
      validationFields: [.audio(.outputMute)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.audio.value.outputMuted.value == nil {
          profile.settings.audio.value.outputMuted.value =
            systemSnapshot?.profileSettings.audio.value.outputMuted.value
        }
      }
    ) {
      optionalBooleanPicker(
        "Output mute value",
        selection: $profile.settings.audio.value.outputMuted.value,
        fieldID: .audio(.outputMute)
      )
    }
  }

  @ViewBuilder
  private var networkOptions: some View {
    optionEditor(
      "Wi-Fi power",
      id: .init(group: .network, key: "wifi-power"),
      isOn: $profile.settings.network.value.wifiPower.isIncluded,
      summary: booleanTargetSummary(profile.settings.network.value.wifiPower.value),
      hasSavedValue: profile.settings.network.value.wifiPower.value != nil,
      validationFields: [.network(.wifiPower)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.network.value.wifiPower.value == nil {
          profile.settings.network.value.wifiPower.value =
            systemSnapshot?.profileSettings.network.value.wifiPower.value
        }
      }
    ) {
      optionalBooleanPicker(
        "Wi-Fi power value",
        selection: $profile.settings.network.value.wifiPower.value,
        fieldID: .network(.wifiPower)
      )
    }

    optionEditor(
      "Wi-Fi network",
      id: .init(group: .network, key: "wifi-network"),
      isOn: $profile.settings.network.value.wifiSSID.isIncluded,
      summary: wifiNetworkSummary(profile.settings.network.value.wifiSSID.value),
      hasSavedValue: profile.settings.network.value.wifiSSID.value != nil,
      validationFields: [.network(.wifiSSID)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.network.value.wifiSSID.value == nil {
          profile.settings.network.value.wifiSSID.value =
            systemSnapshot?.profileSettings.network.value.wifiSSID.value
            ?? conditionContext.wifiSSID
        }
      }
    ) {
      TextField(
        "Network name",
        text: optionalStringBinding($profile.settings.network.value.wifiSSID.value)
      )
      .focused($focusedField, equals: .network(.wifiSSID))
      .accessibilityHint(
        validationAccessibilityHint(for: .network(.wifiSSID))
      )
      .accessibilityInvalid(validation.issue(for: .network(.wifiSSID)) != nil)
      if let currentSSID = conditionContext.wifiSSID,
        currentSSID != profile.settings.network.value.wifiSSID.value
      {
        Button("Use Current Wi-Fi Network") {
          profile.settings.network.value.wifiSSID.value = currentSSID
        }
      }
      Label(
        "Only networks already saved in macOS can be joined. This profile does not store a Wi-Fi password.",
        systemImage: "key.horizontal"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }

    snapshotOnlyNetworkValues
  }

  @ViewBuilder
  private var inputOptions: some View {
    Label(
      "Experimental: macOS does not document the stability of these global preference keys.",
      systemImage: "testtube.2"
    )
    .font(.caption)
    .foregroundStyle(.secondary)

    optionEditor(
      "Pointer speed",
      id: .init(group: .input, key: "pointer-speed"),
      isOn: $profile.settings.input.value.pointerSpeed.isIncluded,
      summary: numberSummary(profile.settings.input.value.pointerSpeed.value),
      hasSavedValue: profile.settings.input.value.pointerSpeed.value != nil,
      validationFields: [.input(.pointerSpeed)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.input.value.pointerSpeed.value == nil {
          profile.settings.input.value.pointerSpeed.value =
            systemSnapshot?.profileSettings.input.value.pointerSpeed.value ?? 4.5
        }
      }
    ) {
      optionalNumberSlider(
        "Pointer speed value",
        value: $profile.settings.input.value.pointerSpeed.value,
        range: -1...10,
        step: 0.25,
        fallback: 4.5,
        minimumLabel: "Slow",
        maximumLabel: "Fast",
        rangeDescription: "Allowed range: −1 to 10.",
        fieldID: .input(.pointerSpeed)
      )
    }

    optionEditor(
      "Natural scrolling",
      id: .init(group: .input, key: "natural-scrolling"),
      isOn: $profile.settings.input.value.naturalScrolling.isIncluded,
      summary: booleanTargetSummary(profile.settings.input.value.naturalScrolling.value),
      hasSavedValue: profile.settings.input.value.naturalScrolling.value != nil,
      validationFields: [.input(.naturalScrolling)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.input.value.naturalScrolling.value == nil {
          profile.settings.input.value.naturalScrolling.value =
            systemSnapshot?.profileSettings.input.value.naturalScrolling.value
        }
      }
    ) {
      optionalBooleanPicker(
        "Natural scrolling value",
        selection: $profile.settings.input.value.naturalScrolling.value,
        fieldID: .input(.naturalScrolling)
      )
    }

    optionEditor(
      "Key repeat",
      id: .init(group: .input, key: "key-repeat"),
      isOn: $profile.settings.input.value.keyRepeatInterval.isIncluded,
      summary: numberSummary(profile.settings.input.value.keyRepeatInterval.value),
      hasSavedValue: profile.settings.input.value.keyRepeatInterval.value != nil,
      validationFields: [.input(.keyRepeatInterval)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.input.value.keyRepeatInterval.value == nil {
          profile.settings.input.value.keyRepeatInterval.value =
            systemSnapshot?.profileSettings.input.value.keyRepeatInterval.value ?? 60
        }
      }
    ) {
      optionalNumberSlider(
        "Key repeat value",
        value: $profile.settings.input.value.keyRepeatInterval.value,
        range: 1...120,
        step: 1,
        fallback: 60,
        minimumLabel: "Fast",
        maximumLabel: "Slow",
        rangeDescription: "Allowed range: 1 to 120. Lower values repeat faster.",
        fieldID: .input(.keyRepeatInterval)
      )
    }

    optionEditor(
      "Initial key repeat delay",
      id: .init(group: .input, key: "initial-key-repeat-delay"),
      isOn: $profile.settings.input.value.initialKeyRepeatDelay.isIncluded,
      summary: numberSummary(profile.settings.input.value.initialKeyRepeatDelay.value),
      hasSavedValue: profile.settings.input.value.initialKeyRepeatDelay.value != nil,
      validationFields: [.input(.initialKeyRepeatDelay)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.input.value.initialKeyRepeatDelay.value == nil {
          profile.settings.input.value.initialKeyRepeatDelay.value =
            systemSnapshot?.profileSettings.input.value.initialKeyRepeatDelay.value ?? 150
        }
      }
    ) {
      optionalNumberSlider(
        "Initial key repeat delay value",
        value: $profile.settings.input.value.initialKeyRepeatDelay.value,
        range: 1...300,
        step: 1,
        fallback: 150,
        minimumLabel: "Short",
        maximumLabel: "Long",
        rangeDescription: "Allowed range: 1 to 300.",
        fieldID: .input(.initialKeyRepeatDelay)
      )
    }

    optionEditor(
      "Use F1–F12 as standard function keys",
      id: .init(group: .input, key: "function-keys"),
      isOn: $profile.settings.input.value.useStandardFunctionKeys.isIncluded,
      summary: booleanTargetSummary(profile.settings.input.value.useStandardFunctionKeys.value),
      hasSavedValue: profile.settings.input.value.useStandardFunctionKeys.value != nil,
      validationFields: [.input(.standardFunctionKeys)],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, profile.settings.input.value.useStandardFunctionKeys.value == nil {
          profile.settings.input.value.useStandardFunctionKeys.value =
            systemSnapshot?.profileSettings.input.value.useStandardFunctionKeys.value
        }
      }
    ) {
      optionalBooleanPicker(
        "Function key value",
        selection: $profile.settings.input.value.useStandardFunctionKeys.value,
        fieldID: .input(.standardFunctionKeys)
      )
    }
  }

  @ViewBuilder
  private func settingGroupEditor<Content: View>(
    _ title: String.LocalizationValue,
    group: SettingGroup,
    systemImage: String,
    isOn: Binding<Bool>,
    summary: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let localizedTitle = appLocalized(title)
    let isExpanded = groupDisclosure.isExpanded(group)

    Section {
      HStack(spacing: 12) {
        Button {
          withAnimation(.easeInOut(duration: 0.16)) {
            toggleExpandedGroup(group)
          }
        } label: {
          HStack(spacing: 8) {
            Label(localizedTitle, systemImage: systemImage)
              .font(.headline)
            Spacer(minLength: 8)
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption.bold())
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedTitle)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint("Expands or collapses this settings category")
        .accessibilityInvalid(firstValidationIssue(in: group) != nil)
        .focused($focusedField, equals: .group(group))

        Toggle("Include", isOn: isOn)
          .toggleStyle(.switch)
          .controlSize(.small)
          .fixedSize()
          .accessibilityLabel(appLocalized("Include \(localizedTitle)"))
          .accessibilityValue(isOn.wrappedValue ? Text("Included") : Text("Excluded"))
      }

      if let issue = validation.issue(for: .group(group)) {
        inlineValidationMessage(
          validationMessage(for: issue),
          fieldID: issue.fieldID
        )
      } else if !isExpanded, let issue = firstValidationIssue(in: group) {
        inlineValidationMessage(
          validationMessage(for: issue),
          fieldID: issue.fieldID
        )
      }

      if isExpanded {
        content()
          .padding(.leading, 4)
      } else {
        Text(groupStateSummary(group, isIncluded: isOn.wrappedValue, summary: summary))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .accessibilityLabel(
            groupStateSummary(group, isIncluded: isOn.wrappedValue, summary: summary)
          )
      }
    }
  }

  @ViewBuilder
  private func optionEditor<Content: View>(
    _ title: String.LocalizationValue,
    id: OptionDisclosureID,
    isOn: Binding<Bool>,
    summary: String,
    hasSavedValue: Bool = true,
    validationFields: [DraftFieldIdentifier] = [],
    onIncludeChange: IncludeChangeAction? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let localizedTitle = appLocalized(title)
    let isExpanded = optionDisclosure.isExpanded(id)

    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Button {
          withAnimation(.easeInOut(duration: 0.16)) {
            toggleExpandedOption(id)
          }
        } label: {
          HStack(spacing: 8) {
            Text(localizedTitle)
              .fontWeight(.medium)
            Spacer(minLength: 8)
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption.bold())
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedTitle)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint("Expands or collapses this setting's target value")
        .accessibilityInvalid(!validationIssues(for: validationFields).isEmpty)

        Toggle(
          "Include",
          isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
              isOn.wrappedValue = newValue
              onIncludeChange?.perform(newValue)
            }
          )
        )
        .toggleStyle(.switch)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(appLocalized("Include \(localizedTitle)"))
        .accessibilityValue(isOn.wrappedValue ? Text("Included") : Text("Excluded"))
      }

      if isExpanded {
        VStack(alignment: .leading, spacing: 8) {
          content()
        }
        .padding(.leading, 20)
      } else {
        Text(
          optionStateSummary(
            isIncluded: isOn.wrappedValue,
            valueSummary: summary,
            hasSavedValue: hasSavedValue
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 20)
        .lineLimit(2)
      }

      ForEach(validationIssues(for: validationFields)) { issue in
        inlineValidationMessage(
          validationMessage(for: issue),
          fieldID: issue.fieldID
        )
      }
    }
    .padding(.vertical, 3)
  }

  @ViewBuilder
  private func audioDeviceOption(
    _ title: String.LocalizationValue,
    key: String,
    option: Binding<SettingOption<String?>>,
    scope: AudioDeviceScope,
    fieldID: DraftFieldIdentifier
  ) -> some View {
    let rawChoices = audioDeviceChoices.filter { $0.scopes.contains(scope) }
    let labels = FriendlyNameDisambiguator().labels(
      for: rawChoices.map { (id: $0.uid, name: $0.name) }
    )
    let choices = rawChoices.map { choice in
      AudioDeviceChoice(
        uid: choice.uid,
        name: labels[choice.uid] ?? choice.name,
        scopes: choice.scopes
      )
    }
    let currentValue: String? =
      if fieldID == .audio(.defaultInputDevice) {
        systemSnapshot?.profileSettings.audio.value.defaultInputUID.value
      } else if fieldID == .audio(.defaultOutputDevice) {
        systemSnapshot?.profileSettings.audio.value.defaultOutputUID.value
      } else {
        systemSnapshot?.profileSettings.audio.value.systemOutputUID.value
      }
    optionEditor(
      title,
      id: .init(group: .audio, key: key),
      isOn: option.isIncluded,
      summary: audioDeviceSummary(option.wrappedValue.value, choices: choices),
      hasSavedValue: option.wrappedValue.value != nil,
      validationFields: [fieldID],
      onIncludeChange: IncludeChangeAction { isIncluded in
        if isIncluded, option.wrappedValue.value == nil {
          option.wrappedValue.value = currentValue
        }
      }
    ) {
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
      .focused($focusedField, equals: fieldID)
      .accessibilityHint(validationAccessibilityHint(for: fieldID))
      .accessibilityInvalid(validation.issue(for: fieldID) != nil)

      DisclosureGroup("Advanced") {
        TextField("Device UID", text: optionalStringBinding(option.value))
          .font(.caption.monospaced())
      }
    }
  }

  private func optionalBooleanPicker(
    _ title: LocalizedStringKey,
    selection: Binding<Bool?>,
    fieldID: DraftFieldIdentifier
  ) -> some View {
    Picker(title, selection: selection) {
      Text("Choose").tag(Optional<Bool>.none)
      Text("On").tag(Optional(true))
      Text("Off").tag(Optional(false))
    }
    .pickerStyle(.segmented)
    .accessibilityLabel(title)
    .accessibilityValue(booleanTargetSummary(selection.wrappedValue))
    .accessibilityHint(validationAccessibilityHint(for: fieldID))
    .accessibilityInvalid(validation.issue(for: fieldID) != nil)
    .focused($focusedField, equals: fieldID)
  }

  @ViewBuilder
  private func optionalNumberSlider(
    _ title: LocalizedStringKey,
    value: Binding<Double?>,
    range: ClosedRange<Double>,
    step: Double,
    fallback: Double,
    minimumLabel: LocalizedStringKey,
    maximumLabel: LocalizedStringKey,
    rangeDescription: LocalizedStringKey,
    fieldID: DraftFieldIdentifier
  ) -> some View {
    if value.wrappedValue == nil {
      chooseSuggestedValueButton(fieldID: fieldID) {
        value.wrappedValue = fallback
      }
    } else {
      HStack(spacing: 8) {
        Text(minimumLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        Slider(
          value: sliderBinding(value, fallback: fallback),
          in: range,
          step: step
        )
        .accessibilityLabel(title)
        .accessibilityHint(validationAccessibilityHint(for: fieldID))
        .accessibilityInvalid(validation.issue(for: fieldID) != nil)
        .focused($focusedField, equals: fieldID)
        Text(maximumLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      DisclosureGroup(
        isExpanded: Binding(
          get: { advancedNumberDisclosure.isExpanded(fieldID) },
          set: { advancedNumberDisclosure.setExpanded($0, for: fieldID) }
        )
      ) {
        LabeledContent {
          TextField(
            title,
            value: value,
            format: .number.precision(.fractionLength(0...2))
          )
          .frame(width: 66)
          .multilineTextAlignment(.trailing)
          .accessibilityHint(validationAccessibilityHint(for: fieldID))
          .accessibilityInvalid(validation.issue(for: fieldID) != nil)
        } label: {
          Text(title)
        }
      } label: {
        Text("Advanced")
      }
      .accessibilityHint("Expands or collapses the exact numeric value")
    }
    Text(rangeDescription)
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  private func chooseSuggestedValueButton(
    fieldID: DraftFieldIdentifier,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Label("Choose a value.", systemImage: "questionmark.circle")
        .foregroundStyle(.secondary)
      Spacer()
      Button("Use Suggested Value", action: action)
        .focused($focusedField, equals: fieldID)
        .accessibilityHint(validationAccessibilityHint(for: fieldID))
        .accessibilityInvalid(validation.issue(for: fieldID) != nil)
    }
  }

  @ViewBuilder
  private func snapshotOnlyDisplayValues(_ display: DisplayTargetSettings) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 7) {
        snapshotOnlyValue("Rotation", value: "\(display.rotationDegrees.value)°")
        snapshotOnlyValue(
          "Active state",
          value: display.isActive.value ? appLocalized("Active") : appLocalized("Inactive")
        )
        Label(
          "This display value is preserved for snapshots, but the current adapter does not apply it.",
          systemImage: "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        if let issue = validation.issue(
          for: .display(display.id, .rotationDegrees)
        ) {
          inlineValidationMessage(
            validationMessage(for: issue),
            fieldID: issue.fieldID
          )
        }
      }
    } label: {
      Label("Snapshot only", systemImage: "camera")
        .font(.subheadline.bold())
    }
    .accessibilityElement(children: .contain)
  }

  private var snapshotOnlyNetworkValues: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 7) {
        snapshotOnlyValue(
          "IPv4 configuration",
          value: ipv4SnapshotSummary(profile.settings.network.value.ipv4.value)
        )
        snapshotOnlyValue(
          "DNS servers",
          value: dnsSnapshotSummary(profile.settings.network.value.dnsServers.value)
        )
        snapshotOnlyValue(
          "Web proxy",
          value: proxySnapshotSummary(profile.settings.network.value.webProxy.value)
        )
        snapshotOnlyValue(
          "Secure web proxy",
          value: proxySnapshotSummary(profile.settings.network.value.secureWebProxy.value)
        )
        Label(
          "This network value is preserved for snapshots, but the current adapter does not apply administrative network settings.",
          systemImage: "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        ForEach(snapshotOnlyNetworkValidationIssues) { issue in
          inlineValidationMessage(
            validationMessage(for: issue),
            fieldID: issue.fieldID
          )
        }
      }
    } label: {
      Label("Snapshot only", systemImage: "camera")
        .font(.subheadline.bold())
    }
    .accessibilityElement(children: .contain)
  }

  private func snapshotOnlyValue(
    _ title: LocalizedStringKey,
    value: String
  ) -> some View {
    LabeledContent {
      Text(value)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    } label: {
      Text(title)
    }
  }

  private var snapshotOnlyNetworkValidationIssues: [DraftValidationIssue] {
    validation.issues.filter { issue in
      issue.group == .network
        && issue.fieldID != .group(.network)
        && issue.fieldID != .network(.wifiPower)
        && issue.fieldID != .network(.wifiSSID)
    }
  }

  private func validationIssues(
    for fields: [DraftFieldIdentifier]
  ) -> [DraftValidationIssue] {
    fields.compactMap { validation.issue(for: $0) }
  }

  private func firstValidationIssue(in group: SettingGroup) -> DraftValidationIssue? {
    validation.issues.first { $0.group == group }
  }

  private func validationMessage(for issue: DraftValidationIssue) -> String {
    appLocalizedDraftValidationMessage(issue.message)
  }

  private func validationAccessibilityHint(for fieldID: DraftFieldIdentifier) -> Text {
    guard let issue = validation.issue(for: fieldID) else { return Text(verbatim: "") }
    return Text(
      "\(appLocalized("Invalid value.")) \(validationMessage(for: issue))"
    )
  }

  private func inlineValidationMessage(
    _ message: String,
    fieldID: DraftFieldIdentifier
  ) -> some View {
    Button {
      revealAndFocus(fieldID)
    } label: {
      Label(message, systemImage: "exclamationmark.circle.fill")
        .font(.caption)
        .multilineTextAlignment(.leading)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.red)
    .accessibilityLabel("\(appLocalized("Validation error")): \(message)")
    .accessibilityHint("Moves keyboard focus to the invalid field")
  }

  private func revealAndFocus(_ fieldID: DraftFieldIdentifier) {
    if let group = validationGroup(for: fieldID) {
      groupDisclosure.expand(group)
    }
    if let option = disclosureOption(for: fieldID) {
      optionDisclosure.expand(option)
    }

    let focusTarget = focusTarget(for: fieldID)
    Task { @MainActor in
      await Task.yield()
      focusedField = focusTarget
      requestedValidationFocus = nil
    }
  }

  private func configureSyntheticAuditDisclosure() {
    guard uiAuditConfiguration.isEnabled else { return }
    switch uiAuditConfiguration.variant {
    case .editor:
      groupDisclosure.expand(.display)
      optionDisclosure.expand(.init(group: .display, key: "primary"))
    case .validation:
      if let firstValidationItem {
        revealAndFocus(firstValidationItem.fieldID)
      }
    case .overview, .permissions, .diagnostics:
      break
    }
  }

  private func validationGroup(for fieldID: DraftFieldIdentifier) -> SettingGroup? {
    for group in SettingGroup.safeApplicationSequence {
      if fieldID == .group(group)
        || fieldID.rawValue.hasPrefix("settings.\(group.rawValue).")
      {
        return group
      }
    }
    return nil
  }

  private func disclosureOption(
    for fieldID: DraftFieldIdentifier
  ) -> OptionDisclosureID? {
    if fieldID == .displayPrimary {
      return .init(group: .display, key: "primary")
    }
    for display in profile.settings.display.value.displays {
      if fieldID == .display(display.id, .originX)
        || fieldID == .display(display.id, .originY)
      {
        return .init(group: .display, ownerID: display.id, key: "position")
      }
      if [
        DisplayDraftField.modeWidth,
        .modeHeight,
        .modePixelWidth,
        .modePixelHeight,
        .modeRefreshRate,
      ].contains(where: { fieldID == .display(display.id, $0) }) {
        return .init(group: .display, ownerID: display.id, key: "mode")
      }
    }

    let mappings: [(DraftFieldIdentifier, OptionDisclosureID)] = [
      (.audio(.defaultInputDevice), .init(group: .audio, key: "default-input-device")),
      (.audio(.defaultOutputDevice), .init(group: .audio, key: "default-output-device")),
      (.audio(.systemOutputDevice), .init(group: .audio, key: "system-output-device")),
      (.audio(.outputVolume), .init(group: .audio, key: "output-volume")),
      (.audio(.outputMute), .init(group: .audio, key: "output-mute")),
      (.network(.wifiPower), .init(group: .network, key: "wifi-power")),
      (.network(.wifiSSID), .init(group: .network, key: "wifi-network")),
      (.input(.pointerSpeed), .init(group: .input, key: "pointer-speed")),
      (.input(.naturalScrolling), .init(group: .input, key: "natural-scrolling")),
      (.input(.keyRepeatInterval), .init(group: .input, key: "key-repeat")),
      (
        .input(.initialKeyRepeatDelay),
        .init(group: .input, key: "initial-key-repeat-delay")
      ),
      (.input(.standardFunctionKeys), .init(group: .input, key: "function-keys")),
    ]
    return mappings.first { $0.0 == fieldID }?.1
  }

  private func focusTarget(
    for fieldID: DraftFieldIdentifier
  ) -> DraftFieldIdentifier {
    for display in profile.settings.display.value.displays
    where [
      DisplayDraftField.modeWidth,
      .modeHeight,
      .modePixelWidth,
      .modePixelHeight,
      .modeRefreshRate,
    ].contains(where: { fieldID == .display(display.id, $0) }) {
      return .display(display.id, .modeWidth)
    }
    if fieldID == .profileName || fieldID == .profileDescription
      || disclosureOption(for: fieldID) != nil
    {
      return fieldID
    }
    return validationGroup(for: fieldID).map(DraftFieldIdentifier.group) ?? fieldID
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

  private func toggleExpandedGroup(_ group: SettingGroup) {
    groupDisclosure.toggle(group)
  }

  private func toggleExpandedOption(_ option: OptionDisclosureID) {
    optionDisclosure.toggle(option)
  }

  private func groupStateSummary(
    _ group: SettingGroup,
    isIncluded: Bool,
    summary: String
  ) -> String {
    if isIncluded {
      return "\(appLocalized("Included")) · \(summary)"
    }

    let count = savedValueCount(for: group)
    if count == 0 {
      return "\(appLocalized("Excluded")) · \(appLocalized("No saved values"))"
    }
    if count == 1 {
      return appLocalized("Excluded · 1 saved value")
    }
    return appLocalized("Excluded · \(count) saved values")
  }

  private func optionStateSummary(
    isIncluded: Bool,
    valueSummary: String,
    hasSavedValue: Bool
  ) -> String {
    let state = isIncluded ? appLocalized("Included") : appLocalized("Excluded")
    guard hasSavedValue else {
      return "\(state) · \(appLocalized("No saved value"))"
    }
    return "\(state) · \(valueSummary)"
  }

  private func savedValueCount(for group: SettingGroup) -> Int {
    switch group {
    case .display:
      return profile.settings.display.value.displays.count * 6
    case .audio:
      let audio = profile.settings.audio.value
      return [
        audio.defaultInputUID.value,
        audio.defaultOutputUID.value,
        audio.systemOutputUID.value,
      ].compactMap { $0 }.count
        + [
          audio.outputVolume.value.map { _ in 1 },
          audio.outputMuted.value.map { _ in 1 },
        ].compactMap { $0 }.count
    case .network:
      let network = profile.settings.network.value
      return [
        network.wifiPower.value.map { _ in 1 },
        network.wifiSSID.value.map { _ in 1 },
        network.ipv4.value.map { _ in 1 },
        network.dnsServers.value.isEmpty ? nil : 1,
        network.webProxy.value.map { _ in 1 },
        network.secureWebProxy.value.map { _ in 1 },
      ].compactMap { $0 }.count
    case .input:
      let input = profile.settings.input.value
      return [
        input.pointerSpeed.value,
        input.naturalScrolling.value.map { $0 ? 1.0 : 0.0 },
        input.keyRepeatInterval.value,
        input.initialKeyRepeatDelay.value,
        input.useStandardFunctionKeys.value.map { $0 ? 1.0 : 0.0 },
      ].compactMap { $0 }.count
    }
  }

  private func mirroringSummary(_ mirroring: DisplayMirroring) -> String {
    switch mirroring {
    case .extended:
      return appLocalized("Extended desktop")
    case .mirrors(let identity):
      if let target = profile.settings.display.value.displays.first(where: {
        $0.identity == identity
      }) {
        return appLocalized("Mirrors \(displayName(target))")
      }
      return appLocalized("Saved display — currently disconnected")
    }
  }

  private func displayModeSummary(_ mode: DisplayMode) -> String {
    let refreshRate = mode.refreshRate.formatted(
      .number.precision(.fractionLength(0...2))
    )
    let base = "\(mode.width)×\(mode.height) · \(refreshRate) \(appLocalized("Hz"))"
    guard mode.hasDistinctPixelDimensions else { return base }
    let pixels = appLocalized("\(mode.pixelWidth)×\(mode.pixelHeight) pixels")
    return "\(base) · \(pixels)"
  }

  private var primaryDisplayIncludedBinding: Binding<Bool> {
    Binding(
      get: {
        let options = profile.settings.display.value.displays.map(\.isPrimary)
        return !options.isEmpty && options.allSatisfy(\.isIncluded)
      },
      set: { isIncluded in
        let selectedID =
          profile.settings.display.value.displays.first(where: {
            $0.isPrimary.value
          })?.id ?? profile.settings.display.value.displays.first?.id
        for index in profile.settings.display.value.displays.indices {
          profile.settings.display.value.displays[index].isPrimary.isIncluded = isIncluded
          if isIncluded {
            profile.settings.display.value.displays[index].isPrimary.value =
              profile.settings.display.value.displays[index].id == selectedID
          }
        }
      }
    )
  }

  private func primaryDisplaySelectionBinding() -> Binding<UUID> {
    Binding(
      get: {
        let selected = profile.settings.display.value.displays.filter { $0.isPrimary.value }
        return selected.count == 1 ? selected[0].id : invalidPrimaryDisplaySelectionID
      },
      set: { selectedID in
        profile.settings.display.value.displays = DisplayPrimarySelectionEditor.selecting(
          selectedID,
          in: profile.settings.display.value.displays
        )
      }
    )
  }

  private var primaryDisplaySummary: String {
    let selected = profile.settings.display.value.displays.filter { $0.isPrimary.value }
    guard selected.count == 1 else {
      return appLocalized("Choose a display")
    }
    return displayName(selected[0])
  }

  private var primaryDisplaySelectionIsAmbiguous: Bool {
    profile.settings.display.value.displays.count(where: { $0.isPrimary.value }) != 1
  }

  private func supportedDisplayModes(for display: DisplayTargetSettings) -> [DisplayMode] {
    let entries = systemSnapshot?.displayModeCatalog ?? []
    let identities = entries.map(\.identity)
    guard
      case .matched(let matchedIdentity) = DisplayIdentityMatcher().match(
        display.identity,
        among: identities
      ), let entry = entries.first(where: { $0.identity == matchedIdentity })
    else {
      return []
    }

    return DisplayModeMatcher().deduplicated(entry.modes)
  }

  private func supportedDisplayModeBinding(
    _ savedMode: Binding<DisplayMode>,
    supportedModes: [DisplayMode]
  ) -> Binding<DisplayMode> {
    let matcher = DisplayModeMatcher()
    return Binding(
      get: {
        matcher.match(savedMode.wrappedValue, among: supportedModes)
          ?? savedMode.wrappedValue
      },
      set: { savedMode.wrappedValue = $0 }
    )
  }

  private func audioDeviceSummary(
    _ uid: String?,
    choices: [AudioDeviceChoice]
  ) -> String {
    guard let uid, !uid.isEmpty else { return appLocalized("Choose a device") }
    return choices.first(where: { $0.uid == uid })?.name
      ?? appLocalized("Saved device — currently disconnected")
  }

  private func percentageSummary(_ value: Double?) -> String {
    guard let value else { return appLocalized("Choose") }
    return "\((value * 100).formatted(.number.precision(.fractionLength(0...1))))%"
  }

  private func numberSummary(_ value: Double?) -> String {
    guard let value else { return appLocalized("Choose") }
    return value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private func booleanTargetSummary(_ value: Bool?) -> String {
    guard let value else { return appLocalized("Choose") }
    return value ? appLocalized("On") : appLocalized("Off")
  }

  private func wifiNetworkSummary(_ value: String?) -> String {
    FriendlyValueFormatter.wifiNetworkName(value) ?? appLocalized("Choose")
  }

  private func ipv4SnapshotSummary(_ configuration: IPv4Configuration?) -> String {
    switch configuration {
    case .dhcp?: return appLocalized("DHCP")
    case .manual?: return appLocalized("Manual")
    case nil: return appLocalized("Not captured")
    }
  }

  private func dnsSnapshotSummary(_ servers: [String]) -> String {
    if servers.isEmpty { return appLocalized("Not captured") }
    if servers.count == 1 { return appLocalized("1 server saved") }
    return appLocalized("\(servers.count) servers saved")
  }

  private func proxySnapshotSummary(_ proxy: ProxyConfiguration?) -> String {
    guard let proxy else { return appLocalized("Not captured") }
    return proxy.enabled ? appLocalized("Enabled") : appLocalized("Disabled")
  }

  private var presentationBuilder: ProfilePresentationBuilder {
    ProfilePresentationBuilder()
  }

  private func displayName(_ display: DisplayTargetSettings) -> String {
    let candidates = profile.settings.display.value.displays.map {
      (id: $0.id, name: baseDisplayName($0))
    }
    return FriendlyNameDisambiguator().labels(for: candidates)[display.id]
      ?? baseDisplayName(display)
  }

  private func baseDisplayName(_ display: DisplayTargetSettings) -> String {
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

  private func percentageSliderBinding(_ value: Binding<Double?>) -> Binding<Double> {
    Binding(
      get: { min(max((value.wrappedValue ?? 0) * 100, 0), 100) },
      set: { value.wrappedValue = $0 / 100 }
    )
  }

  private func sliderBinding(
    _ value: Binding<Double?>,
    fallback: Double
  ) -> Binding<Double> {
    Binding(
      get: { value.wrappedValue ?? fallback },
      set: { value.wrappedValue = $0 }
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

private struct OptionDisclosureID: Hashable, Sendable {
  let group: SettingGroup
  var ownerID: UUID? = nil
  let key: String
}

private struct IncludeChangeAction {
  let perform: (Bool) -> Void

  init(_ perform: @escaping (Bool) -> Void) {
    self.perform = perform
  }
}

private struct EditorValidationItem {
  let fieldID: DraftFieldIdentifier
  let message: String
}

private let invalidPrimaryDisplaySelectionID = UUID(
  uuidString: "00000000-0000-0000-0000-000000000000"
)!

extension View {
  /// SwiftUI has no dedicated macOS invalid-field modifier. Expose the same
  /// semantic as high-priority custom accessibility content while the inline
  /// hint supplies the localized corrective message.
  @ViewBuilder
  fileprivate func accessibilityInvalid(_ isInvalid: Bool) -> some View {
    if isInvalid {
      accessibilityCustomContent(
        "Validation status",
        "Invalid",
        importance: .high
      )
    } else {
      self
    }
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
