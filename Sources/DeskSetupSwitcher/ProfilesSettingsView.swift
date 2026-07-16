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

enum ProfileWorkspaceLayoutPolicy {
  static let sidebarWidth: CGFloat = 210
  static let minimumEditorWidth: CGFloat = 390
  static let dividerWidth: CGFloat = 1
  static let minimumContentWidth = sidebarWidth + dividerWidth + minimumEditorWidth
}

struct ProfileEditorCatalogSession: Equatable, Sendable {
  private(set) var generation: UInt64?
  private(set) var snapshot: SystemSnapshotResult?
  private(set) var isAwaitingRefresh = false
  private(set) var hasConsumedRefresh = false

  mutating func beginPresentation(
    generation: UInt64,
    snapshot: SystemSnapshotResult?,
    isRefreshInProgress: Bool
  ) {
    guard self.generation != generation else {
      if isRefreshInProgress {
        beginRefresh()
      } else {
        observe(snapshot: snapshot)
      }
      return
    }
    self.generation = generation
    self.snapshot = snapshot
    isAwaitingRefresh = isRefreshInProgress
    hasConsumedRefresh = false
  }

  mutating func beginRefresh() {
    guard !hasConsumedRefresh else { return }
    isAwaitingRefresh = true
  }

  mutating func observe(snapshot: SystemSnapshotResult?) {
    guard let snapshot else { return }
    if self.snapshot == nil {
      self.snapshot = snapshot
      if isAwaitingRefresh {
        isAwaitingRefresh = false
        hasConsumedRefresh = true
      }
      return
    }
    guard isAwaitingRefresh, !hasConsumedRefresh else { return }
    self.snapshot = snapshot
    isAwaitingRefresh = false
    hasConsumedRefresh = true
  }

  mutating func finishRefresh(snapshot: SystemSnapshotResult?) {
    guard isAwaitingRefresh, !hasConsumedRefresh else {
      isAwaitingRefresh = false
      return
    }
    if let snapshot {
      self.snapshot = snapshot
    }
    isAwaitingRefresh = false
    hasConsumedRefresh = true
  }
}

enum ProfileEditorSavePolicy {
  static func canAttemptSave(hasDraft: Bool, isDirty: Bool, isBusy: Bool) -> Bool {
    hasDraft && isDirty && !isBusy
  }
}

enum UnsavedPromptValidationAction: Equatable, Sendable {
  case none
  case cancelDeferredActionAndDismiss
  case focusAndShowValidationSummary(DraftFieldIdentifier)
}

struct UnsavedPromptValidationHandoff: Equatable, Sendable {
  private var pendingFocus: DraftFieldIdentifier?

  mutating func rejectInvalidSave(
    firstInvalidField: DraftFieldIdentifier?
  ) -> UnsavedPromptValidationAction {
    pendingFocus = firstInvalidField
    return .cancelDeferredActionAndDismiss
  }

  mutating func presentationChanged(
    isPresented: Bool
  ) -> UnsavedPromptValidationAction {
    guard !isPresented, let pendingFocus else { return .none }
    self.pendingFocus = nil
    return .focusAndShowValidationSummary(pendingFocus)
  }
}

enum ProfileEditorSurfacePolicy {
  static let visibleGroups: Set<SettingGroup> = [.display, .audio, .network]
  static let showsActivationControl = false
  static let showsUnsupportedControls = false
  static let showsDescription = false
  static let showsConditions = false
  static let showsCurrentSettingsDraftRefresh = false
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
  @State private var unsavedPromptValidationHandoff = UnsavedPromptValidationHandoff()
  @State private var catalogSession = ProfileEditorCatalogSession()
  let presentationGeneration: UInt64

  init(presentationGeneration: UInt64 = 0) {
    self.presentationGeneration = presentationGeneration
  }

  var body: some View {
    VStack(spacing: 12) {
      profileWorkspace
        .disabled(model.isProfileMutationLocked)

      Divider()

      HStack(spacing: 10) {
        storageStatusLabel
        Spacer(minLength: 12)
        importExportButtons
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
      profileEditor.initialize(
        profiles: model.profiles,
        preferredProfileID: model.selectedProfileID
      )
      catalogSession.beginPresentation(
        generation: presentationGeneration,
        snapshot: model.lastSnapshot,
        isRefreshInProgress: model.isReadinessRefreshInProgress
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
    .onChange(of: model.lastSnapshot) { _, snapshot in
      catalogSession.observe(snapshot: snapshot)
    }
    .onChange(of: model.isReadinessRefreshInProgress) { _, isRefreshing in
      if isRefreshing {
        catalogSession.beginRefresh()
      } else {
        catalogSession.finishRefresh(snapshot: model.lastSnapshot)
      }
    }
    .onChange(of: presentationGeneration) { _, generation in
      catalogSession.beginPresentation(
        generation: generation,
        snapshot: model.lastSnapshot,
        isRefreshInProgress: model.isReadinessRefreshInProgress
      )
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
        guard draftCanBePersisted else {
          rejectInvalidSaveAndReturnToEditor()
          return
        }
        isResolvingUnsavedPrompt = true
        Task {
          await saveAndContinue()
          isResolvingUnsavedPrompt = false
          if profileEditor.session.pendingSelection != nil || deferredAction != nil {
            isUnsavedPromptPresented = true
          }
        }
      }
      .disabled(!canSaveDraft)
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
    .onChange(of: isUnsavedPromptPresented) { _, isPresented in
      if case .focusAndShowValidationSummary(let fieldID) =
        unsavedPromptValidationHandoff.presentationChanged(isPresented: isPresented)
      {
        Task { @MainActor in
          // Let SwiftUI complete the native dialog-dismissal transition before
          // routing focus back into the editor. The form performs one further
          // run-loop yield before assigning its FocusState.
          await Task.yield()
          requestedValidationFocus = fieldID
        }
      }
      if !isPresented, !isResolvingUnsavedPrompt,
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
    HStack(spacing: 0) {
      sidebar
        .frame(width: ProfileWorkspaceLayoutPolicy.sidebarWidth)
      Divider()
      editor
        .frame(
          minWidth: ProfileWorkspaceLayoutPolicy.minimumEditorWidth,
          maxWidth: .infinity,
          maxHeight: .infinity
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            }
          }
          .tag(Optional(profile.id))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(profile.name)
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
          systemSnapshot: catalogSession.snapshot,
          validation: currentDraftValidation,
          requestedValidationFocus: $requestedValidationFocus,
          presentationGeneration: presentationGeneration
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
    Label(
      model.isProfileMutationLocked
        ? appLocalized("Profile editing is locked until the current operation is safely recorded.")
        : model.storageStatus,
      systemImage: model.isProfileMutationLocked ? "lock" : "externaldrive"
    )
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .truncationMode(.tail)
    .help(
      model.isProfileMutationLocked
        ? appLocalized("Profile editing is locked until the current operation is safely recorded.")
        : model.storageStatus
    )
    .accessibilityLabel(
      model.isProfileMutationLocked
        ? appLocalized("Profile editing is locked until the current operation is safely recorded.")
        : appLocalized("Profile storage status: \(model.storageStatus)"))
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
    HStack(spacing: 10) {
      Label(editorActivityTitle, systemImage: editorActivitySymbol)
        .font(.caption)
        .foregroundStyle(editorActivityIsError ? .red : .secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .help(editorActivityTitle)
        .accessibilityLabel(editorActivityAccessibilityLabel)
      Spacer(minLength: 8)
      revertDraftButton
      saveDraftButton
    }
    .padding(.horizontal, 16)
    .frame(height: 52)
    .background(.bar)
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
    ProfileEditorSavePolicy.canAttemptSave(
      hasDraft: profileEditor.draft != nil,
      isDirty: profileEditor.isDirty,
      isBusy: profileEditor.activity.isBusy
    )
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

  private func rejectInvalidSaveAndReturnToEditor() {
    let action = unsavedPromptValidationHandoff.rejectInvalidSave(
      firstInvalidField: currentDraftValidation.firstInvalidField
    )
    AccessibilityNotification.Announcement(
      appLocalized("Fix the highlighted fields before saving.")
    )
    .post()
    guard action == .cancelDeferredActionAndDismiss else { return }
    // Returning to the editor cancels the pending selection/import action. The
    // user can request it again after correcting the draft.
    cancelDeferredAction()
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
    }
  }
}

private enum DeferredProfileAction: Identifiable {
  case create
  case duplicate(UUID)
  case delete(DeskProfile)
  case importProfiles

  var id: String {
    switch self {
    case .create: "create"
    case .duplicate(let id): "duplicate-\(id.uuidString)"
    case .delete(let profile): "delete-\(profile.id.uuidString)"
    case .importProfiles: "import"
    }
  }
}

private struct ProfileEditorForm: View {
  @Environment(\.uiAuditConfiguration) private var uiAuditConfiguration
  @Binding var profile: DeskProfile
  let systemSnapshot: SystemSnapshotResult?
  let validation: ProfileDraftValidation
  @Binding var requestedValidationFocus: DraftFieldIdentifier?
  let presentationGeneration: UInt64
  @FocusState private var focusedField: DraftFieldIdentifier?
  @State private var showsValidationSummary = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        profileDetailsCard

        if showsValidationSummary, !validation.isValid {
          validationSummary
        }

        settingsIntroduction

        ForEach(orderedVisibleGroups, id: \.self) { group in
          visibleGroupEditor(group)
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
    .id(
      ProfileEditorScrollIdentity(
        profileID: profile.id,
        presentationGeneration: presentationGeneration
      )
    )
    .defaultScrollAnchor(.top)
    .scrollBounceBehavior(.basedOnSize)
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: profile.id) {
      focusedField = nil
      requestedValidationFocus = nil
      showsValidationSummary = false
    }
    .onChange(of: presentationGeneration) {
      focusedField = nil
      requestedValidationFocus = nil
      showsValidationSummary = false
    }
    .onChange(of: requestedValidationFocus) {
      guard let fieldID = requestedValidationFocus else { return }
      showsValidationSummary = true
      revealAndFocus(fieldID)
    }
    .onAppear { configureSyntheticAuditFocus() }
  }

  private var profileDetailsCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            profileNameField
            profileIconPicker
          }
          VStack(alignment: .leading, spacing: 10) {
            profileNameField
            profileIconPicker
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

  private var settingsIntroduction: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(appLocalized("Settings"), systemImage: "slider.horizontal.3")
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
      Text(
        appLocalized(
          "Use each setting's Include switch to choose what this profile applies. Supported values are ready to edit below."
        )
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
            isAwaitingSafetyConfirmation: lastApplication.status == .applying
              && lastApplication.items.contains {
                $0.key == "high-risk-safety-confirmation"
                  || $0.key == "display-safety-confirmation"
              }
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
    if !profile.settings.display.value.displays.isEmpty {
      if isVisible(.displayOutputMode) {
        optionEditor(
          "Output mode",
          isOn: displayOutputModeIncludedBinding
        ) {
          Picker(appLocalized("Output mode"), selection: displayOutputModeBinding) {
            ForEach(DisplayOutputMode.allCases, id: \.self) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .accessibilityLabel(appLocalized("Display output mode"))
          .accessibilityValue(displayOutputMode.title)
          .accessibilityHint(
            appLocalized("Choose an extended desktop or mirror secondary displays")
          )
        }
      }

      if isVisible(.displayPrimary) {
        optionEditor(
          "Primary display",
          isOn: primaryDisplayIncludedBinding,
          validationFields: [.displayPrimary]
        ) {
          Picker(
            appLocalized("Primary display"),
            selection: primaryDisplaySelectionBinding()
          ) {
            if primaryDisplaySelectionIsAmbiguous {
              Text(appLocalized("Choose a display")).tag(invalidPrimaryDisplaySelectionID)
            }
            ForEach(profile.settings.display.value.displays) { display in
              Text(displayName(display)).tag(display.id)
            }
          }
          .accessibilityValue(primaryDisplaySummary)
          .accessibilityHint(
            validationAccessibilityHint(
              for: .displayPrimary,
              fallback: "Choose the display that should anchor the desktop"
            )
          )
          .accessibilityInvalid(validation.issue(for: .displayPrimary) != nil)
          .focused($focusedField, equals: .displayPrimary)
          Text(appLocalized("Select the display that should anchor the desktop."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      ForEach($profile.settings.display.value.displays) { $display in
        let supportedModes = supportedDisplayModes(for: display)
        let colorProfiles = supportedColorProfiles(for: display)
        if !supportedModes.isEmpty || !colorProfiles.isEmpty {
          GroupBox {
            VStack(alignment: .leading, spacing: 10) {
              if !supportedModes.isEmpty {
                optionEditor(
                  "Resolution and refresh rate",
                  isOn: $display.mode.isIncluded,
                  validationFields: [
                    .display(display.id, .modeWidth),
                    .display(display.id, .modeHeight),
                    .display(display.id, .modePixelWidth),
                    .display(display.id, .modePixelHeight),
                    .display(display.id, .modeRefreshRate),
                  ]
                ) {
                  Picker(
                    appLocalized("Supported mode"),
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
                      Text(appLocalized("Saved mode — currently unavailable"))
                        .tag(display.mode.value)
                    }
                  }
                  .focused(
                    $focusedField,
                    equals: .display(display.id, .modeWidth)
                  )
                  .accessibilityLabel(appLocalized("Display mode"))
                  .accessibilityValue(displayModeSummary(display.mode.value))
                  .accessibilityHint(
                    validationAccessibilityHint(
                      for: .display(display.id, .modeWidth),
                      fallback: "Choose a supported resolution and refresh rate"
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

              if !colorProfiles.isEmpty {
                optionEditor(
                  "Color profile",
                  isOn: $display.colorProfile.isIncluded,
                  validationFields: [.display(display.id, .colorProfile)],
                  onIncludeChange: IncludeChangeAction { isIncluded in
                    if isIncluded, display.colorProfile.value == nil {
                      display.colorProfile.value = colorProfiles.first
                    }
                  }
                ) {
                  Picker(
                    appLocalized("ColorSync ICC profile"),
                    selection: $display.colorProfile.value
                  ) {
                    Text(appLocalized("Choose a color profile"))
                      .tag(Optional<ColorSyncProfileTarget>.none)
                    ForEach(colorProfiles, id: \.self) { profile in
                      Text(profile.displayName).tag(Optional(profile))
                    }
                  }
                  .accessibilityLabel(appLocalized("Display color profile"))
                  .accessibilityValue(
                    display.colorProfile.value?.displayName ?? appLocalized("Choose")
                  )
                  .accessibilityHint(
                    appLocalized("Choose a ColorSync ICC profile available for this display")
                  )
                  .focused($focusedField, equals: .display(display.id, .colorProfile))
                  .accessibilityInvalid(
                    validation.issue(for: .display(display.id, .colorProfile)) != nil
                  )
                }
              }
            }
          } label: {
            HStack {
              Label(displayName(display), systemImage: "display")
              Spacer()
              Text(appLocalized(display.isPrimary.value ? "Primary" : "Secondary"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            }
            .font(.headline)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var audioOptions: some View {
    audioDeviceOption(
      "Default input device",
      option: $profile.settings.audio.value.defaultInputUID,
      scope: .input,
      fieldID: .audio(.defaultInputDevice)
    )
    audioDeviceOption(
      "Default output device",
      option: $profile.settings.audio.value.defaultOutputUID,
      scope: .output,
      fieldID: .audio(.defaultOutputDevice)
    )
    audioVolumeOption(
      "Input volume",
      snapshotKey: "inputVolume",
      option: $profile.settings.audio.value.inputVolume,
      suggestedValue: systemSnapshot?.profileSettings.audio.value.inputVolume.value,
      fieldID: .audio(.inputVolume)
    )
    audioVolumeOption(
      "Output volume",
      snapshotKey: "outputVolume",
      option: $profile.settings.audio.value.outputVolume,
      suggestedValue: systemSnapshot?.profileSettings.audio.value.outputVolume.value,
      fieldID: .audio(.outputVolume)
    )
  }

  @ViewBuilder
  private var networkOptions: some View {
    ForEach(NetworkServiceKind.allCases, id: \.self) { kind in
      if !availableNetworkServices(kind: kind).isEmpty {
        GroupBox {
          serviceIPv4Section(kind: kind)
            .padding(8)
        } label: {
          Label(
            kind == .ethernet ? appLocalized("Ethernet") : appLocalized("Wi-Fi"),
            systemImage: kind == .ethernet ? "cable.connector" : "wifi"
          )
          .font(.headline)
        }
      }
    }
  }

  @ViewBuilder
  private func serviceIPv4Section(kind: NetworkServiceKind) -> some View {
    let targets = availableNetworkServices(kind: kind)
    let selectedIdentity = selectedNetworkServiceIdentity(kind: kind)
    VStack(alignment: .leading, spacing: 9) {
      Picker(appLocalized("Service"), selection: networkServiceSelectionBinding(kind: kind)) {
        ForEach(targets, id: \.identity) { target in
          Text(target.identity.serviceName).tag(Optional(target.identity))
        }
      }
      .accessibilityLabel(
        appLocalized(kind == .ethernet ? "Ethernet service" : "Wi-Fi service")
      )
      .accessibilityHint(
        appLocalized("Choose the network service whose IPv4 settings this profile applies")
      )

      if let selectedIdentity {
        let option = networkServiceConfigurationBinding(identity: selectedIdentity)
        let validationFields = networkValidationFields(for: selectedIdentity)
        let ipv4Field = validationFields[0]
        let addressField = validationFields[1]
        let subnetField = validationFields[2]
        let routerField = validationFields[3]
        optionEditor(
          "IPv4 configuration",
          isOn: option.isIncluded,
          validationFields: validationFields,
          onIncludeChange: IncludeChangeAction { isIncluded in
            if isIncluded, option.wrappedValue.value == nil {
              option.wrappedValue.value = .dhcp
            }
          }
        ) {
          Picker(
            appLocalized("IPv4 mode"),
            selection: ipv4ModeBinding(option.value)
          ) {
            ForEach(NetworkIPv4Mode.allCases, id: \.self) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .accessibilityLabel(appLocalized("IPv4 configuration method"))
          .accessibilityValue(ipv4Mode(option.wrappedValue.value).title)
          .accessibilityHint(appLocalized("Choose DHCP or enter a manual IPv4 configuration"))
          .focused($focusedField, equals: ipv4Field)

          if case .manual = option.wrappedValue.value {
            TextField(appLocalized("IP address"), text: manualIPv4AddressBinding(option.value))
              .accessibilityLabel(appLocalized("Manual IPv4 address"))
              .accessibilityHint(
                validationAccessibilityHint(
                  for: addressField,
                  fallback: "Enter the IPv4 address for this service"
                )
              )
              .focused($focusedField, equals: addressField)
              .accessibilityInvalid(validation.issue(for: addressField) != nil)
            TextField(appLocalized("Subnet mask"), text: manualIPv4SubnetMaskBinding(option.value))
              .accessibilityLabel(appLocalized("Manual IPv4 subnet mask"))
              .accessibilityHint(
                validationAccessibilityHint(
                  for: subnetField,
                  fallback: "Enter a contiguous IPv4 subnet mask"
                )
              )
              .focused($focusedField, equals: subnetField)
              .accessibilityInvalid(validation.issue(for: subnetField) != nil)
            TextField(appLocalized("Router"), text: manualIPv4RouterBinding(option.value))
              .accessibilityLabel(appLocalized("Manual IPv4 router"))
              .accessibilityHint(
                validationAccessibilityHint(
                  for: routerField,
                  fallback: "Enter the optional IPv4 router address"
                )
              )
              .focused($focusedField, equals: routerField)
              .accessibilityInvalid(validation.issue(for: routerField) != nil)
          }
        }
      }
    }
  }

  private func ipv4Mode(_ configuration: IPv4Configuration?) -> NetworkIPv4Mode {
    guard case .manual = configuration else { return .dhcp }
    return .manual
  }

  private var orderedVisibleGroups: [SettingGroup] {
    guard uiAuditConfiguration.isEnabled else { return [.display, .audio, .network] }
    switch uiAuditConfiguration.variant {
    case .editorAudio, .editorAudioUnsupported:
      return [.audio, .display, .network]
    case .editorNetwork, .editorNetworkEthernetDHCP, .editorNetworkEthernetManual,
      .editorNetworkWiFiDHCP, .editorNetworkWiFiManual:
      return [.network, .display, .audio]
    case .overview, .menuPolish, .trayEmpty, .traySingle, .trayOverflow, .trayDelete,
      .trayCapturePermission, .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult,
      .editor, .editorPolish, .editorDisplay, .editorDisplayColor, .validation, .permissions,
      .diagnostics:
      return [.display, .audio, .network]
    }
  }

  @ViewBuilder
  private func visibleGroupEditor(_ group: SettingGroup) -> some View {
    switch group {
    case .display:
      if ProfileEditorSurfacePolicy.visibleGroups.contains(.display), hasVisibleDisplayFields {
        settingGroupEditor("Displays", group: .display, systemImage: "display.2") {
          displayOptions
        }
      }
    case .audio:
      if ProfileEditorSurfacePolicy.visibleGroups.contains(.audio), hasVisibleAudioFields {
        settingGroupEditor("Audio", group: .audio, systemImage: "speaker.wave.2") {
          audioOptions
        }
      }
    case .network:
      if ProfileEditorSurfacePolicy.visibleGroups.contains(.network), hasVisibleNetworkFields {
        settingGroupEditor("Network", group: .network, systemImage: "network") {
          networkOptions
        }
      }
    case .input:
      EmptyView()
    }
  }

  @ViewBuilder
  private func settingGroupEditor<Content: View>(
    _ title: String.LocalizationValue,
    group: SettingGroup,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let localizedTitle = appLocalized(title)

    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        Label(localizedTitle, systemImage: systemImage)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("profile-group-\(group.rawValue)")
          .accessibilityInvalid(firstValidationIssue(in: group) != nil)
          .focused($focusedField, equals: .group(group))

        if let issue = validation.issue(for: .group(group)) {
          inlineValidationMessage(
            validationMessage(for: issue),
            fieldID: issue.fieldID
          )
        }

        Divider()
        VStack(alignment: .leading, spacing: 14) {
          content()
        }
      }
      .padding(8)
    }
  }

  @ViewBuilder
  private func optionEditor<Content: View>(
    _ title: String.LocalizationValue,
    isOn: Binding<Bool>,
    validationFields: [DraftFieldIdentifier] = [],
    onIncludeChange: IncludeChangeAction? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let localizedTitle = appLocalized(title)

    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Text(localizedTitle)
          .fontWeight(.medium)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .accessibilityAddTraits(.isHeader)
          .frame(maxWidth: .infinity, alignment: .leading)
          .layoutPriority(1)
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

      VStack(alignment: .leading, spacing: 8) {
        content()
      }
      .padding(.leading, 20)

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
      Text(appLocalized("Include"))
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
    if !choices.isEmpty {
      optionEditor(
        title,
        isOn: option.isIncluded,
        validationFields: [fieldID],
        onIncludeChange: IncludeChangeAction { isIncluded in
          if isIncluded, option.wrappedValue.value == nil {
            option.wrappedValue.value = currentValue ?? choices.first?.uid
          }
        }
      ) {
        Picker(appLocalized("Device"), selection: option.value) {
          Text(appLocalized("Choose a device")).tag(Optional<String>.none)
          ForEach(choices) { choice in
            Text(choice.name).tag(Optional(choice.uid))
          }
          if let savedUID = option.wrappedValue.value,
            !choices.contains(where: { $0.uid == savedUID })
          {
            Text(appLocalized("Saved device — currently disconnected"))
              .tag(Optional(savedUID))
          }
        }
        .focused($focusedField, equals: fieldID)
        .accessibilityLabel(
          appLocalized(scope == .input ? "Default input device" : "Default output device")
        )
        .accessibilityValue(audioDeviceSummary(option.wrappedValue.value, choices: choices))
        .accessibilityHint(
          validationAccessibilityHint(
            for: fieldID,
            fallback: scope == .input
              ? "Choose the default input device" : "Choose the default output device"
          )
        )
        .accessibilityInvalid(validation.issue(for: fieldID) != nil)
      }
    }
  }

  @ViewBuilder
  private func audioVolumeOption(
    _ title: String.LocalizationValue,
    snapshotKey: String,
    option: Binding<SettingOption<Double?>>,
    suggestedValue: Double?,
    fieldID: DraftFieldIdentifier
  ) -> some View {
    let capability = audioVolumeCapability(snapshotKey: snapshotKey)
    if capability.isWritable {
      optionEditor(
        title,
        isOn: option.isIncluded,
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
              Text(appLocalized("Volume percent"))
            } minimumValueLabel: {
              Text("0")
            } maximumValueLabel: {
              Text("100")
            }
            TextField(
              appLocalized("Volume percent"),
              value: percentageBinding(option.value),
              format: .number.precision(.fractionLength(0...1))
            )
            .frame(width: 58)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: fieldID)
            .accessibilityHint(
              validationAccessibilityHint(
                for: fieldID,
                fallback: "Set volume from 0 to 100 percent"
              )
            )
            Text("%")
              .foregroundStyle(.secondary)
          }
          .accessibilityInvalid(validation.issue(for: fieldID) != nil)
        }
        Text(appLocalized("Enter a value from 0 to 100 percent."))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func audioVolumeCapability(snapshotKey: String) -> AudioVolumeCapability {
    let role: AudioVolumeCatalogRole = snapshotKey == "inputVolume" ? .input : .output
    guard
      let entry = systemSnapshot?.audioVolumeControlCatalog.first(where: {
        $0.role == role
      })
    else {
      return AudioVolumeCapability(
        isWritable: false,
        reason: ""
      )
    }
    if entry.canApply, entry.currentValue != nil, entry.deviceUID != nil {
      return AudioVolumeCapability(isWritable: true, reason: "")
    }
    return AudioVolumeCapability(isWritable: false, reason: "")
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

  private func validationAccessibilityHint(
    for fieldID: DraftFieldIdentifier,
    fallback: LocalizedStringKey
  ) -> Text {
    guard let issue = validation.issue(for: fieldID) else { return Text(fallback) }
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
    let focusTarget = focusTarget(for: fieldID)
    Task { @MainActor in
      await Task.yield()
      focusedField = focusTarget
      requestedValidationFocus = nil
    }
  }

  private func configureSyntheticAuditFocus() {
    guard uiAuditConfiguration.isEnabled else { return }
    switch uiAuditConfiguration.variant {
    case .validation:
      if let firstValidationItem {
        showsValidationSummary = true
        revealAndFocus(firstValidationItem.fieldID)
      }
    case .editor, .editorPolish, .editorAudio, .editorAudioUnsupported, .editorDisplay,
      .editorDisplayColor,
      .editorNetwork, .editorNetworkEthernetDHCP, .editorNetworkEthernetManual,
      .editorNetworkWiFiDHCP, .editorNetworkWiFiManual,
      .overview, .menuPolish, .trayEmpty, .traySingle, .trayOverflow, .trayDelete,
      .trayCapturePermission, .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult,
      .permissions, .diagnostics:
      break
    }
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
    if fieldID == .profileName || fieldID == .profileDescription {
      return fieldID
    }
    return fieldID
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

  private func supportedColorProfiles(
    for display: DisplayTargetSettings
  ) -> [ColorSyncProfileTarget] {
    let entries = systemSnapshot?.displayColorProfileCatalog ?? []
    guard
      case .matched(let matchedIdentity) = DisplayIdentityMatcher().match(
        display.identity,
        among: entries.map(\.identity)
      ), let entry = entries.first(where: { $0.identity == matchedIdentity }),
      entry.canApply
    else {
      return []
    }
    return entry.profiles
  }

  private var hasVisibleDisplayFields: Bool {
    visibleSettingFields.contains { $0.contract.group == .display }
  }

  private var hasVisibleAudioFields: Bool {
    visibleSettingFields.contains { $0.contract.group == .audio }
  }

  private var hasVisibleNetworkFields: Bool {
    visibleSettingFields.contains { $0.contract.group == .network }
  }

  private var visibleSettingFields: [VisibleSettingField] {
    VisibleSettingRegistry().fields(
      snapshots: systemSnapshot?.groups.compactMap(\.snapshot) ?? []
    )
  }

  private func isVisible(_ kind: VisibleSettingKind) -> Bool {
    visibleSettingFields.contains { $0.contract.kind == kind }
  }

  private func availableNetworkServices(
    kind: NetworkServiceKind
  ) -> [NetworkServiceIPv4Settings] {
    let rollbackCatalog =
      systemSnapshot?.result(for: .network)?.snapshot?.networkIPv4RollbackCatalog ?? []
    let identityCounts = Dictionary(grouping: rollbackCatalog, by: \.identity).mapValues(\.count)
    var seen = Set<NetworkServiceIdentity>()
    return (systemSnapshot?.profileSettings.network.value.serviceIPv4 ?? [])
      .filter {
        $0.identity.kind == kind
          && identityCounts[$0.identity] == 1
          && seen.insert($0.identity).inserted
      }
      .sorted {
        $0.identity.serviceName.localizedCaseInsensitiveCompare(
          $1.identity.serviceName
        ) == .orderedAscending
      }
  }

  private func selectedNetworkServiceIdentity(
    kind: NetworkServiceKind
  ) -> NetworkServiceIdentity? {
    let choices = availableNetworkServices(kind: kind).map(\.identity)
    return profile.settings.network.value.serviceIPv4.first {
      $0.identity.kind == kind
        && $0.configuration.isIncluded
        && choices.contains($0.identity)
    }?.identity
      ?? profile.settings.network.value.serviceIPv4.first {
        $0.identity.kind == kind && choices.contains($0.identity)
      }?.identity
      ?? choices.first
  }

  private func networkServiceSelectionBinding(
    kind: NetworkServiceKind
  ) -> Binding<NetworkServiceIdentity?> {
    Binding(
      get: { selectedNetworkServiceIdentity(kind: kind) },
      set: { selected in
        guard let selected else { return }
        for index in profile.settings.network.value.serviceIPv4.indices
        where profile.settings.network.value.serviceIPv4[index].identity.kind == kind {
          profile.settings.network.value.serviceIPv4[index].configuration.isIncluded = false
        }
        if let index = profile.settings.network.value.serviceIPv4.firstIndex(where: {
          $0.identity == selected
        }) {
          profile.settings.network.value.serviceIPv4[index].configuration.isIncluded = true
        } else if let runtime = availableNetworkServices(kind: kind).first(where: {
          $0.identity == selected
        }) {
          var selectedTarget = runtime
          selectedTarget.configuration.isIncluded = true
          profile.settings.network.value.serviceIPv4.append(selectedTarget)
        }
      }
    )
  }

  private func networkServiceConfigurationBinding(
    identity: NetworkServiceIdentity
  ) -> Binding<SettingOption<IPv4Configuration?>> {
    Binding(
      get: {
        profile.settings.network.value.serviceIPv4.first {
          $0.identity == identity
        }?.configuration
          ?? availableNetworkServices(kind: identity.kind).first {
            $0.identity == identity
          }?.configuration
          ?? .init(isIncluded: false, value: nil)
      },
      set: { updated in
        if let index = profile.settings.network.value.serviceIPv4.firstIndex(where: {
          $0.identity == identity
        }) {
          profile.settings.network.value.serviceIPv4[index].configuration = updated
        } else {
          profile.settings.network.value.serviceIPv4.append(
            NetworkServiceIPv4Settings(
              identity: identity,
              configuration: updated
            )
          )
        }
      }
    )
  }

  private func networkValidationFields(
    for identity: NetworkServiceIdentity
  ) -> [DraftFieldIdentifier] {
    let index = profile.settings.network.value.serviceIPv4.firstIndex(where: {
      $0.identity == identity
    })
    return [
      index.map { .networkService(at: $0, .ipv4) } ?? .network(.ipv4),
      index.map { .networkService(at: $0, .ipv4Address) } ?? .network(.ipv4Address),
      index.map { .networkService(at: $0, .ipv4SubnetMask) } ?? .network(.ipv4SubnetMask),
      index.map { .networkService(at: $0, .ipv4Router) } ?? .network(.ipv4Router),
    ]
  }

  private func ipv4ModeBinding(
    _ configuration: Binding<IPv4Configuration?>
  ) -> Binding<NetworkIPv4Mode> {
    Binding(
      get: { ipv4Mode(configuration.wrappedValue) },
      set: { mode in
        switch mode {
        case .dhcp:
          configuration.wrappedValue = .dhcp
        case .manual:
          if case .manual = configuration.wrappedValue { return }
          configuration.wrappedValue = .manual(
            address: "",
            subnetMask: "",
            router: nil
          )
        }
      }
    )
  }

  private func manualIPv4AddressBinding(
    _ configuration: Binding<IPv4Configuration?>
  ) -> Binding<String> {
    Binding(
      get: {
        guard case .manual(let address, _, _) = configuration.wrappedValue else { return "" }
        return address
      },
      set: { value in updateManualIPv4(configuration, address: value) }
    )
  }

  private func manualIPv4SubnetMaskBinding(
    _ configuration: Binding<IPv4Configuration?>
  ) -> Binding<String> {
    Binding(
      get: {
        guard case .manual(_, let subnetMask, _) = configuration.wrappedValue else { return "" }
        return subnetMask
      },
      set: { value in updateManualIPv4(configuration, subnetMask: value) }
    )
  }

  private func manualIPv4RouterBinding(
    _ configuration: Binding<IPv4Configuration?>
  ) -> Binding<String> {
    Binding(
      get: {
        guard case .manual(_, _, let router) = configuration.wrappedValue else { return "" }
        return router ?? ""
      },
      set: { value in
        updateManualIPv4(configuration, router: value.isEmpty ? .some(nil) : .some(value))
      }
    )
  }

  private func updateManualIPv4(
    _ configuration: Binding<IPv4Configuration?>,
    address: String? = nil,
    subnetMask: String? = nil,
    router: String?? = nil
  ) {
    let currentAddress: String
    let currentMask: String
    let currentRouter: String?
    if case .manual(let savedAddress, let savedMask, let savedRouter) =
      configuration.wrappedValue
    {
      currentAddress = savedAddress
      currentMask = savedMask
      currentRouter = savedRouter
    } else {
      currentAddress = ""
      currentMask = ""
      currentRouter = nil
    }
    configuration.wrappedValue = .manual(
      address: address ?? currentAddress,
      subnetMask: subnetMask ?? currentMask,
      router: router ?? currentRouter
    )
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
    for item in systemSnapshot?.audioDeviceCatalog ?? [] {
      var scopes = Set<AudioDeviceScope>()
      if item.supportsInput { scopes.insert(.input) }
      if item.supportsOutput { scopes.insert(.output) }
      choicesByUID[item.uid] = AudioDeviceChoice(
        uid: item.uid,
        name: item.name,
        scopes: scopes
      )
    }

    return choicesByUID.values
      .sorted {
        let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
        return nameOrder == .orderedSame ? $0.uid < $1.uid : nameOrder == .orderedAscending
      }
  }

  private func percentageBinding(_ value: Binding<Double?>) -> Binding<Double?> {
    Binding(
      get: { value.wrappedValue.map(AudioVolumePresentation.percent) },
      set: { value.wrappedValue = $0.map(AudioVolumePresentation.scalar) }
    )
  }

  private func percentageSliderBinding(_ value: Binding<Double?>) -> Binding<Double> {
    Binding(
      get: {
        min(
          max(AudioVolumePresentation.percent(fromScalar: value.wrappedValue ?? 0), 0),
          100
        )
      },
      set: { value.wrappedValue = AudioVolumePresentation.scalar(fromPercent: $0) }
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
  /// semantic as custom accessibility content while keeping one modifier
  /// hierarchy as validation changes, so a text field retains focus/caret.
  /// Empty content is intended to remain silent for valid controls; native
  /// VoiceOver confirmation remains part of the manual accessibility pass.
  /// The inline hint supplies the localized corrective message for invalid
  /// controls.
  fileprivate func accessibilityInvalid(_ isInvalid: Bool) -> some View {
    accessibilityCustomContent(
      Text(verbatim: isInvalid ? appLocalized("Validation status") : ""),
      Text(verbatim: isInvalid ? appLocalized("Invalid") : ""),
      importance: isInvalid ? .high : .default
    )
  }
}

private struct ProfileEditorScrollIdentity: Hashable {
  let profileID: UUID
  let presentationGeneration: UInt64
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
