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

enum ProfileWorkspaceLayoutMode: Equatable, Sendable {
  case compact
  case regular

  static let compactBreakpoint: CGFloat = 760

  init(width: CGFloat) {
    self = width < Self.compactBreakpoint ? .compact : .regular
  }

  var isCompact: Bool { self == .compact }
}

enum ProfileEditorSurfacePolicy {
  static let visibleGroups: Set<SettingGroup> = [.display, .audio, .network]
  static let showsDescription = false
  static let showsConditions = false
}

struct ProfilesSettingsView: View {
  @Environment(\.uiAuditConfiguration) private var uiAuditConfiguration
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

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          storageStatusLabel
          Spacer(minLength: 12)
          importExportButtons
        }

        VStack(alignment: .leading, spacing: 8) {
          storageStatusLabel
          HStack(spacing: 8) {
            Spacer()
            importExportButtons
          }
        }
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
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
      profileEditor.initialize(
        profiles: model.profiles,
        preferredProfileID: model.selectedProfileID
      )
      if profileEditor.session.pendingSelection != nil {
        isUnsavedPromptPresented = true
      }
      #if DEBUG
        if uiAuditConfiguration.isEnabled,
          uiAuditConfiguration.variant == .editorPolish
        {
          profileEditor.finishWithMessage(appLocalized("Profile saved."))
        }
      #endif
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
      let layoutMode = ProfileWorkspaceLayoutMode(width: geometry.size.width)
      let usesCompactLayout = layoutMode.isCompact

      // The fixed breakpoint intentionally replaces the draggable HSplitView.
      // AnyLayout keeps the sidebar/editor identity stable while the window is resized.
      let layout =
        usesCompactLayout
        ? AnyLayout(VStackLayout(spacing: 0))
        : AnyLayout(HStackLayout(spacing: 0))

      layout {
        sidebar
          .frame(
            minWidth: usesCompactLayout ? 0 : 210,
            idealWidth: usesCompactLayout ? nil : 230,
            maxWidth: usesCompactLayout ? .infinity : 260,
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
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
          .accessibilityIdentifier("profile-row")
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

  private var storageStatusLabel: some View {
    Label(model.storageStatus, systemImage: "externaldrive")
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(
        appLocalized("Profile storage status: \(model.storageStatus)"))
  }

  private var importExportButtons: some View {
    HStack(spacing: 8) {
      Button("Import…") { requestDeferredAction(.importProfiles) }
        .disabled(model.isProfileMutationLocked)
        .accessibilityHint("Selects and validates a local profile JSON file")
      Button("Export…") { model.exportProfiles() }
        .disabled(model.profiles.isEmpty || model.isProfileMutationLocked)
        .accessibilityHint("Exports all profiles to a new local JSON file")
    }
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
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
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
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        profileDetailsCard

        if !validation.isValid {
          validationSummary
        }

        settingsIntroduction

        if ProfileEditorSurfacePolicy.visibleGroups.contains(.display) {
          settingGroupEditor(
            "Displays",
            group: .display,
            systemImage: "display.2",
            isOn: $profile.settings.display.isIncluded,
            summary: summaryPreview(for: .display)
          ) {
            displayOptions
          }
        }

        if ProfileEditorSurfacePolicy.visibleGroups.contains(.audio) {
          settingGroupEditor(
            "Audio",
            group: .audio,
            systemImage: "speaker.wave.2",
            isOn: $profile.settings.audio.isIncluded,
            summary: summaryPreview(for: .audio)
          ) {
            audioOptions
          }
        }

        if ProfileEditorSurfacePolicy.visibleGroups.contains(.network) {
          settingGroupEditor(
            "Network",
            group: .network,
            systemImage: "network",
            isOn: $profile.settings.network.isIncluded,
            summary: summaryPreview(for: .network)
          ) {
            networkOptions
          }
        }

        if let lastApplication = profile.lastApplication {
          lastApplicationCard(lastApplication)
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 16)
      .frame(maxWidth: 860)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .background(Color(nsColor: .windowBackgroundColor))
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

  private var profileDetailsCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            profileNameField
            profileIconPicker
            profileEnabledToggle
          }
          VStack(alignment: .leading, spacing: 10) {
            profileNameField
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              profileIconPicker
              profileEnabledToggle
            }
          }
        }
        if let issue = validation.issue(for: .profileName) {
          inlineValidationMessage(
            validationMessage(for: issue),
            fieldID: .profileName
          )
        }
        if !profileIconChoices.contains(where: { $0.symbolName == profile.symbolName }) {
          DisclosureGroup("Technical Information") {
            LabeledContent("Imported symbol name") {
              Text(profile.symbolName)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
          }
        }
      }
      .padding(8)
    } label: {
      Label("Profile", systemImage: "person.crop.rectangle")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
    }
  }

  private var profileNameField: some View {
    TextField("Name", text: $profile.name)
      .accessibilityLabel("Profile name")
      .accessibilityIdentifier("profile-name-field")
      .focused($focusedField, equals: .profileName)
      .accessibilityHint(validationAccessibilityHint(for: .profileName))
      .accessibilityInvalid(validation.issue(for: .profileName) != nil)
      .frame(minWidth: 220)
  }

  private var profileIconPicker: some View {
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
    .frame(width: 190)
  }

  private var profileEnabledToggle: some View {
    Toggle("Enabled", isOn: $profile.isEnabled)
      .fixedSize()
  }

  private var settingsIntroduction: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label("Settings", systemImage: "slider.horizontal.3")
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
      Text(
        "Use Include to choose what this profile applies. Expand a category to review or edit its saved values."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 4)
  }

  private func lastApplicationCard(_ lastApplication: ApplicationSummary) -> some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
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
      .padding(8)
    } label: {
      Text("Last application")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
    }
  }

  private var validationSummary: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
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
      }
      .padding(8)
    } label: {
      Text("Review Before Saving")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
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
      optionEditor(
        "Output mode",
        id: .init(group: .display, key: "output-mode"),
        isOn: displayOutputModeIncludedBinding,
        summary: displayOutputMode.title
      ) {
        Picker("Output mode", selection: displayOutputModeBinding) {
          ForEach(DisplayOutputMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .disabled(profile.settings.display.value.displays.count < 2)
        Text("Choose an extended desktop or mirror secondary displays to the primary display.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

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

      ForEach($profile.settings.display.value.displays) { $display in
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
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

            GroupBox {
              VStack(alignment: .leading, spacing: 7) {
                LabeledContent(
                  "Current Core Graphics color space",
                  value: currentColorSpaceName(for: display)
                )
                Label(
                  "This read-only color-space name is not a ColorSync profile, HDR mode, or pixel encoding. Color changes are unavailable because no public apply and rollback contract is defined.",
                  systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            } label: {
              Label("Color mode", systemImage: "paintpalette")
                .font(.subheadline.bold())
            }
          }
        } label: {
          HStack {
            Label(displayName(display), systemImage: "display")
            Spacer()
            Text(display.isPrimary.value ? "Primary" : "Secondary")
              .font(.caption.bold())
              .foregroundStyle(.secondary)
          }
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
    audioVolumeOption(
      "Input volume",
      key: "input-volume",
      snapshotKey: "inputVolume",
      option: $profile.settings.audio.value.inputVolume,
      suggestedValue: systemSnapshot?.profileSettings.audio.value.inputVolume.value,
      fieldID: .audio(.inputVolume)
    )
    audioVolumeOption(
      "Output volume",
      key: "output-volume",
      snapshotKey: "outputVolume",
      option: $profile.settings.audio.value.outputVolume,
      suggestedValue: systemSnapshot?.profileSettings.audio.value.outputVolume.value,
      fieldID: .audio(.outputVolume)
    )
  }

  @ViewBuilder
  private var networkOptions: some View {
    let savedWiFiNetworks = systemSnapshot?.savedWiFiNetworkNames ?? []

    GroupBox {
      serviceIPv4Section(kind: .ethernet)
        .padding(8)
    } label: {
      Label("Ethernet", systemImage: "cable.connector")
        .font(.headline)
    }

    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
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
              profile.settings.network.value.wifiSSID.value = savedWiFiNetworks.first
            }
          }
        ) {
          if savedWiFiNetworks.isEmpty {
            LabeledContent(
              "Saved network",
              value: profile.settings.network.value.wifiSSID.value
                ?? appLocalized("Not detected")
            )
            Label(
              "No saved Wi-Fi network choices are available in the current read-only snapshot.",
              systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          } else {
            Picker(
              "Saved network",
              selection: savedWiFiSelection(
                $profile.settings.network.value.wifiSSID.value,
                choices: savedWiFiNetworks
              )
            ) {
              Text("Choose a saved network").tag(Optional<String>.none)
              ForEach(savedWiFiNetworks, id: \.self) { networkName in
                Text(networkName).tag(Optional(networkName))
              }
            }
            .focused($focusedField, equals: .network(.wifiSSID))
            .accessibilityHint(validationAccessibilityHint(for: .network(.wifiSSID)))
            .accessibilityInvalid(validation.issue(for: .network(.wifiSSID)) != nil)
          }
          if let currentSSID = conditionContext.wifiSSID {
            LabeledContent("Current network", value: currentSSID)
          }
          if let selected = profile.settings.network.value.wifiSSID.value,
            !savedWiFiNetworks.isEmpty,
            !savedWiFiNetworks.contains(selected)
          {
            Label(
              "The saved profile target is not in the current macOS saved-network list. Choose an available saved network before applying.",
              systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Label(
            "Only networks already saved in macOS can be joined. This profile does not store a Wi-Fi password.",
            systemImage: "key.horizontal"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Divider()
        serviceIPv4Section(kind: .wifi)
      }
      .padding(8)
    } label: {
      Label("Wi-Fi", systemImage: "wifi")
        .font(.headline)
    }
  }

  @ViewBuilder
  private func serviceIPv4Section(kind: NetworkServiceKind) -> some View {
    let targets = profile.settings.network.value.serviceIPv4.filter {
      $0.identity.kind == kind
    }
    VStack(alignment: .leading, spacing: 9) {
      Text("IP configuration")
        .font(.subheadline.bold())
      if targets.isEmpty {
        LabeledContent("Service", value: appLocalized("Not detected"))
        Label(
          "Capture current settings to identify this network service with public metadata.",
          systemImage: "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
          VStack(alignment: .leading, spacing: 7) {
            LabeledContent("Service", value: target.identity.serviceName)
            Picker(
              "IPv4 mode",
              selection: Binding.constant(ipv4Mode(target.configuration.value))
            ) {
              ForEach(NetworkIPv4Mode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
              }
            }
            .disabled(true)
            if case .manual(let address, let subnetMask, let router)? =
              target.configuration.value
            {
              LabeledContent("IP address", value: address)
              LabeledContent("Subnet mask", value: subnetMask)
              LabeledContent("Router", value: router ?? appLocalized("None"))
            }
            Label(
              serviceIPv4CapabilityReason(for: target, among: targets),
              systemImage: "lock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .contain)
        }
      }
    }
  }

  private func ipv4Mode(_ configuration: IPv4Configuration?) -> NetworkIPv4Mode {
    guard case .manual = configuration else { return .dhcp }
    return .manual
  }

  private func serviceIPv4CapabilityReason(
    for target: NetworkServiceIPv4Settings,
    among targets: [NetworkServiceIPv4Settings]
  ) -> String {
    if targets.count(where: { $0.identity == target.identity }) > 1 {
      return appLocalized(
        "Multiple services match this portable identity; IPv4 changes are disabled.")
    }
    return appLocalized(
      "IPv4 changes are disabled until authorized apply and rollback support is available."
    )
  }

  private func savedWiFiSelection(
    _ value: Binding<String?>,
    choices: [String]
  ) -> Binding<String?> {
    Binding(
      get: {
        guard let selected = value.wrappedValue, choices.contains(selected) else { return nil }
        return selected
      },
      set: { value.wrappedValue = $0 }
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

    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 12) {
          Button {
            withAnimation(.easeInOut(duration: 0.16)) {
              toggleExpandedGroup(group)
            }
          } label: {
            HStack(spacing: 8) {
              Label(localizedTitle, systemImage: systemImage)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .layoutPriority(1)
              Spacer(minLength: 8)
              Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity, alignment: .leading)
          .layoutPriority(1)
          .accessibilityLabel(localizedTitle)
          .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
          .accessibilityHint("Expands or collapses this settings category")
          .accessibilityIdentifier("profile-group-\(group.rawValue)")
          .accessibilityInvalid(firstValidationIssue(in: group) != nil)
          .focused($focusedField, equals: .group(group))

          compactIncludeToggle(
            isOn: isOn,
            accessibilityLabel: appLocalized("Include \(localizedTitle)")
          )
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
          Divider()
          VStack(alignment: .leading, spacing: 14) {
            content()
          }
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
      .padding(8)
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
              .lineLimit(2)
              .multilineTextAlignment(.leading)
              .layoutPriority(1)
            Spacer(minLength: 8)
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption.bold())
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .accessibilityLabel(localizedTitle)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint("Expands or collapses this setting's target value")
        .accessibilityInvalid(!validationIssues(for: validationFields).isEmpty)

        compactIncludeToggle(
          isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
              isOn.wrappedValue = newValue
              onIncludeChange?.perform(newValue)
            }
          ),
          accessibilityLabel: appLocalized("Include \(localizedTitle)")
        )
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
    .padding(12)
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(0.7),
      in: RoundedRectangle(cornerRadius: 10)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.secondary.opacity(0.12))
    }
  }

  private func compactIncludeToggle(
    isOn: Binding<Bool>,
    accessibilityLabel: String
  ) -> some View {
    HStack(spacing: 8) {
      Text("Include")
        .font(.subheadline)
        .fixedSize()
        .accessibilityHidden(true)
      Toggle(isOn: isOn) {
        EmptyView()
      }
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.regular)
      .fixedSize()
      .accessibilityLabel(accessibilityLabel)
      .accessibilityValue(isOn.wrappedValue ? Text("Included") : Text("Excluded"))
    }
    .fixedSize(horizontal: true, vertical: false)
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

  @ViewBuilder
  private func audioVolumeOption(
    _ title: String.LocalizationValue,
    key: String,
    snapshotKey: String,
    option: Binding<SettingOption<Double?>>,
    suggestedValue: Double?,
    fieldID: DraftFieldIdentifier
  ) -> some View {
    let capability = audioVolumeCapability(snapshotKey: snapshotKey)
    VStack(alignment: .leading, spacing: 7) {
      optionEditor(
        title,
        id: .init(group: .audio, key: key),
        isOn: option.isIncluded,
        summary: percentageSummary(option.wrappedValue.value),
        hasSavedValue: option.wrappedValue.value != nil,
        validationFields: [fieldID],
        onIncludeChange: IncludeChangeAction { isIncluded in
          if isIncluded, option.wrappedValue.value == nil {
            option.wrappedValue.value = suggestedValue ?? 0.5
          }
        }
      ) {
        if option.wrappedValue.value == nil {
          chooseSuggestedValueButton(fieldID: fieldID) {
            option.wrappedValue.value = suggestedValue ?? 0.5
          }
        } else {
          HStack(spacing: 10) {
            Slider(
              value: percentageSliderBinding(option.value),
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
              value: percentageBinding(option.value),
              format: .number.precision(.fractionLength(0...1))
            )
            .frame(width: 58)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: fieldID)
            .accessibilityHint(validationAccessibilityHint(for: fieldID))
            Text("%")
              .foregroundStyle(.secondary)
          }
          .accessibilityInvalid(validation.issue(for: fieldID) != nil)
        }
        Text("Enter a value from 0 to 100 percent.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .disabled(!capability.isWritable)

      if !capability.isWritable {
        Label(capability.reason, systemImage: "exclamationmark.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel(capability.reason)
      }
    }
  }

  private func audioVolumeCapability(snapshotKey: String) -> AudioVolumeCapability {
    guard
      let item = systemSnapshot?.result(for: .audio)?.items.first(where: {
        $0.key == snapshotKey
      })
    else {
      return AudioVolumeCapability(
        isWritable: false,
        reason: appLocalized("Capture current settings to check software volume support.")
      )
    }
    if item.state == .storable, item.detail == "Readable and writable" {
      return AudioVolumeCapability(isWritable: true, reason: "")
    }
    return AudioVolumeCapability(
      isWritable: false,
      reason: appLocalizedRuntime(item.detail)
    )
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
    case .editor, .editorPolish:
      groupDisclosure.expand(.audio)
      optionDisclosure.expand(.init(group: .audio, key: "default-input-device"))
      optionDisclosure.expand(.init(group: .audio, key: "default-output-device"))
    case .editorAudio:
      groupDisclosure.expand(.audio)
      optionDisclosure.expand(.init(group: .audio, key: "input-volume"))
      optionDisclosure.expand(.init(group: .audio, key: "output-volume"))
    case .editorDisplay:
      groupDisclosure.expand(.display)
      optionDisclosure.expand(.init(group: .display, key: "output-mode"))
      optionDisclosure.expand(.init(group: .display, key: "primary"))
    case .editorNetwork:
      groupDisclosure.expand(.network)
    case .validation:
      if let firstValidationItem {
        revealAndFocus(firstValidationItem.fieldID)
      }
    case .overview, .menuPolish, .trayEmpty, .traySingle, .trayOverflow, .trayDelete,
      .trayCapturePermission, .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult,
      .permissions, .diagnostics:
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
      (.audio(.inputVolume), .init(group: .audio, key: "input-volume")),
      (.audio(.outputVolume), .init(group: .audio, key: "output-volume")),
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
      return profile.settings.display.value.displays.count * 2 + 2
    case .audio:
      let audio = profile.settings.audio.value
      return [
        audio.defaultInputUID.value,
        audio.defaultOutputUID.value,
      ].compactMap { $0 }.count
        + [
          audio.inputVolume.value.map { _ in 1 },
          audio.outputVolume.value.map { _ in 1 },
        ].compactMap { $0 }.count
    case .network:
      let network = profile.settings.network.value
      return [
        network.wifiPower.value.map { _ in 1 },
        network.wifiSSID.value.map { _ in 1 },
      ].compactMap { $0 }.count
        + network.serviceIPv4.count
    case .input:
      return 0
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

  private var displayOutputModeIncludedBinding: Binding<Bool> {
    Binding(
      get: {
        let options = profile.settings.display.value.displays.map(\.mirroring)
        return !options.isEmpty && options.allSatisfy(\.isIncluded)
      },
      set: { isIncluded in
        for index in profile.settings.display.value.displays.indices {
          profile.settings.display.value.displays[index].mirroring.isIncluded = isIncluded
        }
        if isIncluded {
          setDisplayOutputMode(displayOutputMode)
        }
      }
    )
  }

  private var displayOutputMode: DisplayOutputMode {
    profile.settings.display.value.displays.contains {
      if case .mirrors = $0.mirroring.value { return true }
      return false
    } ? .mirrored : .extended
  }

  private var displayOutputModeBinding: Binding<DisplayOutputMode> {
    Binding(
      get: { displayOutputMode },
      set: { mode in setDisplayOutputMode(mode) }
    )
  }

  private func setDisplayOutputMode(_ mode: DisplayOutputMode) {
    let displays = profile.settings.display.value.displays
    guard let primary = displays.first(where: { $0.isPrimary.value }) ?? displays.first else {
      return
    }
    for index in profile.settings.display.value.displays.indices {
      let isPrimary = profile.settings.display.value.displays[index].id == primary.id
      profile.settings.display.value.displays[index].mirroring.isIncluded = true
      profile.settings.display.value.displays[index].mirroring.value =
        mode == .mirrored && !isPrimary ? .mirrors(primary.identity) : .extended
    }
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
        if displayOutputMode == .mirrored {
          setDisplayOutputMode(.mirrored)
        }
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

  private func currentColorSpaceName(for display: DisplayTargetSettings) -> String {
    let entries = systemSnapshot?.displayColorEvidence ?? []
    guard
      case .matched(let matchedIdentity) = DisplayIdentityMatcher().match(
        display.identity,
        among: entries.map(\.identity)
      ), let entry = entries.first(where: { $0.identity == matchedIdentity })
    else {
      return appLocalized("Unavailable")
    }
    return entry.colorSpaceName
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

private enum DisplayOutputMode: String, CaseIterable {
  case extended
  case mirrored

  var title: String {
    switch self {
    case .extended: appLocalized("Extended desktop")
    case .mirrored: appLocalized("Mirror displays")
    }
  }
}

private enum NetworkIPv4Mode: String, CaseIterable {
  case dhcp
  case manual

  var title: String {
    switch self {
    case .dhcp: appLocalized("DHCP")
    case .manual: appLocalized("Manual IPv4")
    }
  }
}

private struct AudioDeviceChoice: Identifiable {
  let uid: String
  let name: String
  let scopes: Set<AudioDeviceScope>

  var id: String { uid }
}

private struct AudioVolumeCapability {
  let isWritable: Bool
  let reason: String
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
