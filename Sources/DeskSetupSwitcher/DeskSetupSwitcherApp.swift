import AppKit
import Combine
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

@MainActor
private final class DeskSetupSwitcherAppDelegate: NSObject, NSApplicationDelegate {
  weak var model: ApplicationModel?
  weak var profileEditor: ProfileEditorModel?
  private var terminationObservation: AnyCancellable?
  private var isSavingBeforeTermination = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if isSavingBeforeTermination || terminationObservation != nil {
      return .terminateLater
    }

    if let profileEditor, profileEditor.activity.isBusy {
      terminationObservation = profileEditor.$activity
        .filter { !$0.isBusy }
        .prefix(1)
        .sink { [weak self, weak sender] _ in
          Task { @MainActor in
            self?.terminationObservation = nil
            sender?.reply(toApplicationShouldTerminate: false)
            sender?.terminate(nil)
          }
        }
      return .terminateLater
    }

    if let profileEditor, profileEditor.isDirty {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = appLocalized("Save profile changes before quitting?")
      alert.informativeText = appLocalized(
        "This profile has unsaved changes that will be lost if you quit without saving.")
      alert.addButton(withTitle: appLocalized("Save and Quit"))
      alert.addButton(withTitle: appLocalized("Quit Without Saving"))
      alert.addButton(withTitle: appLocalized("Cancel"))

      switch alert.runModal() {
      case .alertFirstButtonReturn:
        guard let model, let candidate = profileEditor.session.saveCandidate() else {
          return .terminateCancel
        }
        isSavingBeforeTermination = true
        profileEditor.beginSaving()
        Task {
          switch await model.updateProfile(candidate) {
          case .saved(let persisted):
            switch profileEditor.completeSave(with: persisted) {
            case .saved, .savedAndSelected:
              isSavingBeforeTermination = false
              sender.reply(toApplicationShouldTerminate: true)
            case .rejected:
              isSavingBeforeTermination = false
              presentTerminationSaveError(
                appLocalized("The saved profile did not match the active draft."),
                sender: sender
              )
            }
          case .rejected(let message):
            profileEditor.finishWithError(message)
            isSavingBeforeTermination = false
            presentTerminationSaveError(message, sender: sender)
          }
        }
        return .terminateLater
      case .alertSecondButtonReturn:
        profileEditor.revertDraft()
      default:
        return .terminateCancel
      }
    }

    guard model?.shouldDeferTermination == true else { return .terminateNow }
    model?.deferTerminationUntilApplyCompletes()
    return .terminateLater
  }

  private func presentTerminationSaveError(_ message: String, sender: NSApplication) {
    let errorAlert = NSAlert()
    errorAlert.alertStyle = .critical
    errorAlert.messageText = appLocalized("Could Not Save Profile")
    errorAlert.informativeText = message
    errorAlert.runModal()
    sender.reply(toApplicationShouldTerminate: false)
  }
}

@main
@MainActor
struct DeskSetupSwitcherApp: App {
  @NSApplicationDelegateAdaptor(DeskSetupSwitcherAppDelegate.self) private var appDelegate
  @StateObject private var model: ApplicationModel
  @StateObject private var locationPermission: LocationPermissionController
  @StateObject private var profileEditor: ProfileEditorModel
  @State private var selectedSettingsTab: SettingsTab = .profiles

  init() {
    let model = ApplicationModel()
    let locationPermission = LocationPermissionController()
    let profileEditor = ProfileEditorModel()
    _model = StateObject(wrappedValue: model)
    _locationPermission = StateObject(wrappedValue: locationPermission)
    _profileEditor = StateObject(wrappedValue: profileEditor)
    appDelegate.model = model
    appDelegate.profileEditor = profileEditor
    locationPermission.onReadinessFactsChanged = { [weak model] in
      model?.refreshReadinessFacts()
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    model.start()
  }

  var body: some Scene {
    MenuBarExtra {
      MenuContentView(selectedSettingsTab: $selectedSettingsTab)
        .environmentObject(model)
        .environmentObject(locationPermission)
        .environmentObject(profileEditor)
    } label: {
      Label("Desk Setup Switcher", systemImage: "switch.2")
        .labelStyle(.iconOnly)
        .accessibilityLabel("Desk Setup Switcher")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(selectedTab: $selectedSettingsTab)
        .environmentObject(model)
        .environmentObject(locationPermission)
        .environmentObject(profileEditor)
        .frame(minWidth: 680, minHeight: 480)
    }
  }
}

private enum DraftProtectedApplyKind: Equatable {
  case targetDraft
  case otherDraft(openProfileID: UUID, openProfileName: String)
}

private struct DraftProtectedApplyPrompt: Identifiable, Equatable {
  let id = UUID()
  let targetProfileID: UUID
  let targetProfileName: String
  let mode: ApplyMode
  let kind: DraftProtectedApplyKind
}

private struct MenuContentView: View {
  @Environment(\.openSettings) private var openSettings
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var profileEditor: ProfileEditorModel
  @Binding var selectedSettingsTab: SettingsTab
  @State private var isCaptureDraftPromptPresented = false
  @State private var captureDraftSaveError: String?
  @State private var captureOperationError: String?
  @State private var transientCaptureMessage: String?
  @State private var transientCaptureTask: Task<Void, Never>?
  @State private var draftProtectedApply: DraftProtectedApplyPrompt?
  @State private var applyDraftSaveError: String?
  @State private var draftApplyRetryAfterError: DraftProtectedApplyPrompt?
  @State private var deferredApplyAfterPreviewDismissal: PendingApplyRequest?
  @State private var isApplyResultDetailsPresented = false

  var body: some View {
    Group {
      if let safety = model.safetyConfirmation {
        SafetyConfirmationView(state: safety)
          .environmentObject(model)
      } else {
        menuBody
      }
    }
    .sheet(
      item: Binding(
        get: { model.pendingApply },
        set: { if $0 == nil { model.cancelPendingApply() } }
      ),
      onDismiss: resumeDeferredApplyAfterPreviewDismissal
    ) { request in
      ApplyPreviewView(
        request: request,
        onConfirm: { confirmPendingApply(request) }
      )
      .environmentObject(model)
    }
    .sheet(isPresented: $isApplyResultDetailsPresented) {
      if let summary = model.lastApplySummary,
        let result = model.lastApplyResult
      {
        ApplyResultDetailsView(
          summary: summary,
          result: result,
          verification: model.lastApplyVerification
        )
      } else {
        ContentUnavailableView(
          "No Apply Result",
          systemImage: "clock.arrow.circlepath",
          description: Text("Apply a profile to see itemized results.")
        )
        .frame(width: 440, height: 260)
      }
    }
    .confirmationDialog(
      "Save changes before capturing a new profile?",
      isPresented: $isCaptureDraftPromptPresented
    ) {
      Button("Save and Capture") {
        Task { await saveDraftThenCaptureCurrentSettings() }
      }
      .disabled(!openDraftIsValid)
      Button("Discard Changes and Capture", role: .destructive) {
        profileEditor.revertDraft()
        Task { await performCapture() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The open profile has changes that have not been saved.")
    }
    .confirmationDialog(
      draftApplyDialogTitle,
      isPresented: Binding(
        get: { draftProtectedApply != nil },
        set: { if !$0 { cancelDraftProtectedApply() } }
      )
    ) {
      if let prompt = draftProtectedApply {
        switch prompt.kind {
        case .targetDraft:
          Button("Save and Apply") {
            beginSaveDraftThenApply(prompt)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!openDraftIsValid)
        case .otherDraft(let openProfileID, let openProfileName):
          Button(appLocalized("Save \(openProfileName) and Apply \(prompt.targetProfileName)")) {
            beginSaveDraftThenApply(prompt)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!openDraftIsValid)
          Button(
            appLocalized(
              "Discard Changes to \(openProfileName) and Apply \(prompt.targetProfileName)"
            ),
            role: .destructive
          ) {
            beginDiscardDraftThenApply(
              prompt,
              expectedOpenProfileID: openProfileID
            )
          }
        }
        Button("Cancel", role: .cancel) {
          cancelDraftProtectedApply()
        }
        .keyboardShortcut(.cancelAction)
      }
    } message: {
      Text(draftApplyDialogMessage)
    }
    .alert(
      "Could Not Save Profile",
      isPresented: Binding(
        get: { captureDraftSaveError != nil },
        set: { if !$0 { captureDraftSaveError = nil } }
      )
    ) {
      Button("OK") { captureDraftSaveError = nil }
    } message: {
      Text(captureDraftSaveError ?? "")
    }
    .alert(
      "Could Not Capture Current Settings",
      isPresented: Binding(
        get: { captureOperationError != nil },
        set: { if !$0 { captureOperationError = nil } }
      )
    ) {
      Button("OK") { captureOperationError = nil }
    } message: {
      Text(captureOperationError ?? "")
    }
    .alert(
      "Could Not Save Before Applying",
      isPresented: Binding(
        get: { applyDraftSaveError != nil },
        set: { if !$0 { dismissApplyDraftSaveError() } }
      )
    ) {
      Button("OK") { dismissApplyDraftSaveError() }
    } message: {
      Text(applyDraftSaveError ?? "")
    }
    .onAppear {
      // Opening the menu is an explicit, read-only refresh point so hot-plugged
      // devices and network changes do not leave readiness permanently stale.
      model.refreshReadinessFacts()
    }
    .onDisappear {
      transientCaptureTask?.cancel()
      transientCaptureTask = nil
      transientCaptureMessage = nil
    }
  }

  private var menuBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Label("Desk Setup Switcher", systemImage: "switch.2")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)

        Spacer()

        Button {
          requestCaptureCurrentSettings()
        } label: {
          Label("Capture", systemImage: "camera.metering.center.weighted")
        }
        .disabled(
          model.isProfileMutationLocked || profileEditor.session.pendingSelection != nil
        )
        .accessibilityLabel("Capture Current Settings")
        .help("Reads current settings without changing the Mac and creates a profile.")

        Button {
          presentSettings()
        } label: {
          Label("Settings", systemImage: "gearshape")
            .labelStyle(.iconOnly)
        }
        .keyboardShortcut(",")
        .accessibilityLabel("Settings")
        .help("Settings")

        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Label("Quit Desk Setup Switcher", systemImage: "power")
            .labelStyle(.iconOnly)
        }
        .keyboardShortcut("q")
        .disabled(model.isProfileMutationLocked)
        .accessibilityLabel("Quit Desk Setup Switcher")
        .help(
          model.isProfileMutationLocked
            ? "Quit becomes available after the current apply transaction is safely recorded."
            : "Quit Desk Setup Switcher"
        )
      }

      Divider()

      if model.profiles.isEmpty {
        ContentUnavailableView(
          "No Profiles",
          systemImage: "rectangle.stack.badge.plus",
          description: Text("Capture the current Mac to create your first editable profile.")
        )
        .frame(width: 340, height: 150)
      } else if enabledProfiles.isEmpty {
        VStack(spacing: 10) {
          ContentUnavailableView(
            "No Enabled Profiles",
            systemImage: "pause.rectangle",
            description: Text("Enable a profile in Settings before applying it.")
          )
          Button {
            presentSettings()
          } label: {
            Label("Manage Profiles", systemImage: "slider.horizontal.3")
          }
        }
        .frame(width: 340, height: 170)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(enabledProfiles) { profile in
              profileRow(profile)
            }
          }
          .padding(.trailing, 2)
        }
        .frame(width: 340, height: profileListHeight)
      }

      if let transientCaptureMessage {
        Label(transientCaptureMessage, systemImage: "checkmark.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
          .transition(.opacity)
      }

      if let summary = model.lastCaptureSummary, summary.status != .complete {
        captureResultBanner(summary)
      }

      if let summary = model.lastApplySummary {
        applyResultCard(summary)
      }
    }
    .padding(14)
  }

  private var enabledProfiles: [DeskProfile] {
    model.profiles.filter(\.isEnabled)
  }

  private func requestCaptureCurrentSettings() {
    guard profileEditor.session.pendingSelection == nil else { return }
    guard profileEditor.isDirty else {
      Task { await performCapture() }
      return
    }
    isCaptureDraftPromptPresented = true
  }

  private func editProfile(_ profile: DeskProfile) {
    switch profileEditor.requestSelection(profile) {
    case .selected(let target):
      model.selectProfile(id: target.profileID)
    case .requiresDecision, .unchanged:
      break
    }
    presentSettings()
  }

  private func requestApply(_ profile: DeskProfile, mode: ApplyMode) {
    let decision = DirtyApplyProtectionDecision.evaluate(
      targetProfileID: profile.id,
      openDraftProfileID: profileEditor.selectedProfileID,
      isDraftDirty: profileEditor.isDirty,
      hasPendingSelection: profileEditor.session.pendingSelection != nil
    )

    switch decision {
    case .applyNow:
      model.prepareApply(profile: profile, mode: mode)

    case .saveTargetBeforeApply:
      draftProtectedApply = DraftProtectedApplyPrompt(
        targetProfileID: profile.id,
        targetProfileName: profile.name,
        mode: mode,
        kind: .targetDraft
      )

    case .resolveOtherDraft(let openProfileID):
      let openName = profileEditor.draft?.name ?? appLocalized("Open profile")
      switch profileEditor.requestSelection(profile) {
      case .requiresDecision:
        draftProtectedApply = DraftProtectedApplyPrompt(
          targetProfileID: profile.id,
          targetProfileName: profile.name,
          mode: mode,
          kind: .otherDraft(
            openProfileID: openProfileID,
            openProfileName: openName
          )
        )
      case .selected:
        model.prepareApply(profile: profile, mode: mode)
      case .unchanged:
        applyDraftSaveError = appLocalized(
          "The open draft changed before the apply decision. Try again."
        )
      }

    case .blockedByPendingSelection:
      applyDraftSaveError = appLocalized(
        "Finish the open profile decision before applying another profile."
      )
    }
  }

  /// The editor can remain open while a preview is visible. Re-evaluate draft
  /// protection at the final confirmation boundary so edits made after the
  /// preview cannot be bypassed by applying the older persisted profile.
  private func confirmPendingApply(_ request: PendingApplyRequest) {
    let decision = DirtyApplyProtectionDecision.evaluate(
      targetProfileID: request.profile.id,
      openDraftProfileID: profileEditor.selectedProfileID,
      isDraftDirty: profileEditor.isDirty,
      hasPendingSelection: profileEditor.session.pendingSelection != nil
    )
    guard decision == .applyNow else {
      deferredApplyAfterPreviewDismissal = request
      model.cancelPendingApply()
      return
    }
    model.executePendingApply()
  }

  private func resumeDeferredApplyAfterPreviewDismissal() {
    guard let request = deferredApplyAfterPreviewDismissal else { return }
    deferredApplyAfterPreviewDismissal = nil
    requestApply(request.profile, mode: request.preparation.mode)
  }

  private var draftApplyDialogTitle: String {
    guard let prompt = draftProtectedApply else {
      return appLocalized("Unsaved Profile Changes")
    }
    switch prompt.kind {
    case .targetDraft:
      return appLocalized("Save changes before applying this profile?")
    case .otherDraft:
      return appLocalized("Resolve unsaved changes before applying another profile?")
    }
  }

  private var draftApplyDialogMessage: String {
    guard let prompt = draftProtectedApply else { return "" }
    switch prompt.kind {
    case .targetDraft:
      return appLocalized(
        "\(prompt.targetProfileName) has unsaved changes. Save those exact values before building the apply preview."
      )
    case .otherDraft(_, let openProfileName):
      return appLocalized(
        "Choose what to do with \(openProfileName) before applying \(prompt.targetProfileName)."
      )
    }
  }

  private func beginSaveDraftThenApply(_ prompt: DraftProtectedApplyPrompt) {
    let candidate: DeskProfile
    let expectsSelectionChange: Bool
    switch prompt.kind {
    case .targetDraft:
      guard let saveCandidate = profileEditor.session.saveCandidate() else {
        applyDraftSaveError = appLocalized("The open profile could not be prepared for saving.")
        return
      }
      candidate = saveCandidate
      expectsSelectionChange = false

    case .otherDraft:
      guard
        case .saveRequired(let saveCandidate, let target) =
          profileEditor.resolvePendingSelection(.save),
        target.profileID == prompt.targetProfileID
      else {
        applyDraftSaveError = appLocalized(
          "The open profile decision changed before it could be saved."
        )
        return
      }
      candidate = saveCandidate
      expectsSelectionChange = true
    }

    let validation = ProfileDraftValidator().validate(candidate)
    guard !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      validation.isValid
    else {
      applyDraftSaveError =
        validation.issues.first.map {
          appLocalizedDraftValidationMessage($0.message)
        } ?? appLocalized("Enter a profile name before saving and applying.")
      return
    }

    draftProtectedApply = nil
    profileEditor.beginSaving()
    Task {
      await persistDraftAndApply(
        candidate,
        prompt: prompt,
        expectsSelectionChange: expectsSelectionChange
      )
    }
  }

  private var openDraftIsValid: Bool {
    guard let draft = profileEditor.draft else { return false }
    return !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && ProfileDraftValidator().validate(draft).isValid
  }

  private func persistDraftAndApply(
    _ candidate: DeskProfile,
    prompt: DraftProtectedApplyPrompt,
    expectsSelectionChange: Bool
  ) async {
    var coordinator = DirtyApplySaveCoordinator(
      targetProfileID: prompt.targetProfileID,
      mode: prompt.mode,
      destination:
        expectsSelectionChange
        ? .selectedTarget(profileID: prompt.targetProfileID)
        : .persistedTarget
    )
    switch await model.updateProfile(candidate) {
    case .saved(let persisted):
      let completion = profileEditor.completeSave(with: persisted)
      switch coordinator.handle(
        .saveSucceeded(profile: persisted, completion: completion)
      ) {
      case .prepare(let profile, let mode):
        model.prepareApply(profile: profile, mode: mode)

      case .selectAndPrepare(let profileID, let mode):
        guard await model.selectProfileAndWait(id: profileID),
          let targetProfile = model.profiles.first(where: { $0.id == profileID })
        else {
          applyDraftSaveError = appLocalized(
            "The target profile changed before the apply preview could be prepared."
          )
          return
        }
        model.prepareApply(profile: targetProfile, mode: mode)

      case .none:
        if expectsSelectionChange {
          applyDraftSaveError = appLocalized(
            "The target profile changed before the apply preview could be prepared."
          )
        } else {
          applyDraftSaveError = appLocalized(
            "The saved profile did not match the active draft."
          )
        }
      }

    case .rejected(let message):
      _ = coordinator.handle(.saveRejected)
      profileEditor.finishWithError(message)
      draftApplyRetryAfterError = prompt
      applyDraftSaveError = message
    }
  }

  private func beginDiscardDraftThenApply(
    _ prompt: DraftProtectedApplyPrompt,
    expectedOpenProfileID: UUID
  ) {
    guard profileEditor.selectedProfileID == expectedOpenProfileID,
      case .selected(let target) = profileEditor.resolvePendingSelection(.discard),
      target.profileID == prompt.targetProfileID
    else {
      applyDraftSaveError = appLocalized(
        "The open profile decision changed before the draft could be discarded."
      )
      return
    }
    draftProtectedApply = nil
    Task {
      guard await model.selectProfileAndWait(id: prompt.targetProfileID),
        let targetProfile = model.profiles.first(where: {
          $0.id == prompt.targetProfileID
        })
      else {
        applyDraftSaveError = appLocalized(
          "The target profile is no longer available to apply."
        )
        return
      }
      model.prepareApply(profile: targetProfile, mode: prompt.mode)
    }
  }

  private func cancelDraftProtectedApply() {
    if case .otherDraft? = draftProtectedApply?.kind {
      _ = profileEditor.resolvePendingSelection(.cancel)
    }
    draftProtectedApply = nil
  }

  private func dismissApplyDraftSaveError() {
    applyDraftSaveError = nil
    if let retry = draftApplyRetryAfterError {
      draftApplyRetryAfterError = nil
      draftProtectedApply = retry
    }
  }

  private func presentSettings() {
    selectedSettingsTab = .profiles
    NSApplication.shared.activate(ignoringOtherApps: true)
    openSettings()
  }

  private func presentPermissions() {
    selectedSettingsTab = .permissions
    NSApplication.shared.activate(ignoringOtherApps: true)
    openSettings()
  }

  private func saveDraftThenCaptureCurrentSettings() async {
    guard profileEditor.session.pendingSelection == nil,
      let candidate = profileEditor.session.saveCandidate()
    else { return }

    if let validationError = appProfileDraftValidationError(candidate) {
      captureDraftSaveError = validationError
      return
    }

    profileEditor.beginSaving()
    switch await model.updateProfile(candidate) {
    case .saved(let persisted):
      guard case .saved = profileEditor.completeSave(with: persisted) else {
        captureDraftSaveError = appLocalized(
          "The saved profile did not match the active draft."
        )
        return
      }
      await performCapture()
    case .rejected(let message):
      profileEditor.finishWithError(message)
      captureDraftSaveError = message
    }
  }

  private func performCapture() async {
    transientCaptureTask?.cancel()
    transientCaptureTask = nil
    transientCaptureMessage = nil

    switch await model.createProfileFromCurrentSettings() {
    case .created(_, let summary):
      let message =
        summary.status == .complete
        ? appLocalized("Captured current settings without changing the Mac.")
        : appLocalized(
          "Captured \(summary.applicableCount) applicable settings with \(summary.excludedCount) snapshot-only and \(summary.omittedCount) unavailable items."
        )
      if summary.status == .complete {
        transientCaptureMessage = message
      }
      AccessibilityNotification.Announcement(message).post()
      if summary.status == .complete {
        transientCaptureTask = Task { @MainActor in
          try? await Task.sleep(for: .seconds(3))
          guard !Task.isCancelled else { return }
          transientCaptureMessage = nil
          transientCaptureTask = nil
        }
      }
    case .rejected(let message, let summary):
      if let summary {
        AccessibilityNotification.Announcement(
          captureResultAnnouncement(summary)
        ).post()
      }
      captureOperationError = message
    }
  }

  private var profileListHeight: CGFloat {
    min(max(CGFloat(enabledProfiles.count) * 132, 124), 360)
  }

  private func captureResultBanner(_ summary: ProfileCaptureSummary) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        Label(
          summary.status == .failure
            ? appLocalized("Capture Failed") : appLocalized("Partial Capture"),
          systemImage: summary.status == .failure
            ? "xmark.octagon" : "exclamationmark.triangle"
        )
        .font(.caption.bold())
        Spacer()
        Button {
          model.dismissCaptureSummary()
        } label: {
          Label("Dismiss Capture Result", systemImage: "xmark")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss Capture Result")
        .help("Dismiss Capture Result")
      }
      Text(
        appLocalized(
          "\(summary.applicableCount) applicable · \(summary.excludedCount) snapshot only"
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Text(
        appLocalized(
          "\(summary.unreadableCount) unreadable · \(summary.permissionRequiredCount) permission required · \(summary.unsupportedCount) unsupported"
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      if summary.wifiNetworkWasNotCaptured {
        Label("Wi-Fi network was not captured.", systemImage: "location.slash")
          .font(.caption)
        Button("Review Permissions") {
          presentPermissions()
        }
        .font(.caption)
      }
    }
    .padding(10)
    .background(
      (summary.status == .failure ? Color.red : Color.orange).opacity(0.12),
      in: RoundedRectangle(cornerRadius: 9)
    )
    .accessibilityElement(children: .contain)
  }

  private func captureResultAnnouncement(_ summary: ProfileCaptureSummary) -> String {
    appLocalized(
      "\(summary.applicableCount) applicable, \(summary.excludedCount) snapshot only, \(summary.unreadableCount) unreadable, \(summary.permissionRequiredCount) permission required, and \(summary.unsupportedCount) unsupported."
    )
  }

  private func applyResultCard(_ summary: ApplyResultSummary) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        Label(
          appApplyResultStatusTitle(summary.status),
          systemImage: applyResultStatusSymbol(summary.status)
        )
        .font(.caption.bold())
        Spacer()
        Button {
          model.dismissApplySummary()
        } label: {
          Label("Dismiss Apply Result", systemImage: "xmark")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss Apply Result")
        .help("Dismiss Apply Result")
      }

      Text(summary.profileName)
        .font(.caption)
        .lineLimit(1)
      Text(
        appLocalized(
          "\(summary.succeededCount) succeeded · \(summary.failedCount) failed · \(summary.skippedCount) skipped · \(summary.unsupportedCount) unsupported"
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      if summary.notVerifiedCount > 0 || summary.rollbackFailedCount > 0 {
        Text(
          appLocalized(
            "\(summary.notVerifiedCount) not verified · \(summary.rollbackFailedCount) rollback failed"
          )
        )
        .font(.caption2.bold())
      }
      HStack {
        Text(summary.appliedAt.formatted(date: .omitted, time: .shortened))
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Details") {
          isApplyResultDetailsPresented = true
        }
        .font(.caption)
        .accessibilityHint("Shows itemized apply and read-back results")
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .contain)
  }

  private func applyResultStatusSymbol(_ status: ApplyResultOverallStatus) -> String {
    switch status {
    case .success: "checkmark.circle"
    case .partial: "exclamationmark.circle"
    case .failure: "xmark.octagon"
    case .rolledBack: "arrow.uturn.backward.circle"
    case .rollbackFailed: "exclamationmark.arrow.triangle.2.circlepath"
    case .notVerified: "questionmark.circle"
    }
  }

  private func profileRow(_ profile: DeskProfile) -> some View {
    let readiness = model.readiness(for: profile)
    let action = primaryApplyActionState(profile, readiness: readiness)

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(profile.name, systemImage: appResolvedProfileSymbolName(profile.symbolName))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Label(readinessTitle(readiness), systemImage: readinessSymbol(readiness))
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            appLocalized("Profile status: \(readinessTitle(readiness))"))
      }

      if let reason = action.disabledReason {
        Label(appLocalizedRuntime(reason.defaultMessage), systemImage: reason.symbolName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Button(appLocalizedRuntime(action.defaultLabel)) {
          requestApply(profile, mode: action.mode)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!action.isEnabled)
        .accessibilityLabel(
          appLocalized("\(appLocalizedRuntime(action.defaultLabel)) \(profile.name)")
        )
        .help(
          action.disabledReason.map { appLocalizedRuntime($0.defaultMessage) }
            ?? (action.kind == .availableItems
              ? appLocalized("Preview and apply only the currently available settings.")
              : appLocalized("Preview and apply this complete profile.")))

        Spacer()

        Button {
          editProfile(profile)
        } label: {
          Label("Edit Profile", systemImage: "pencil")
        }
        .disabled(model.isProfileMutationLocked || profileEditor.activity.isBusy)
        .accessibilityLabel(appLocalized("Edit \(profile.name)"))
        .help("Edit Profile")

      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .contain)
  }

  private func primaryApplyActionState(
    _ profile: DeskProfile,
    readiness: ProfileReadiness
  ) -> PrimaryApplyActionState {
    PrimaryApplyActionState(
      profile: profile,
      readiness: readiness,
      normalOperationCount: model.operationCountByProfile[profile.id] ?? 0,
      availableOperationCount: model.forceOperationCountByProfile[profile.id] ?? 0,
      isPreparing: model.isPreparingApply(for: profile),
      isRefreshing: model.isReadinessRefreshInProgress,
      hasUsableCachedReadiness: model.readinessByProfile[profile.id] != nil,
      isTransactionLocked:
        model.isApplyTransactionInProgress || model.isProfileStoreMutationInProgress,
      isDisplayConfirmationPending: model.safetyConfirmation != nil
    )
  }

  private func readinessTitle(_ readiness: ProfileReadiness) -> String {
    appReadinessTitle(readiness)
  }

  private func readinessSymbol(_ readiness: ProfileReadiness) -> String {
    switch readiness {
    case .ready: "checkmark.circle"
    case .partial: "exclamationmark.circle"
    case .unavailable: "xmark.circle"
    case .applying: "hourglass"
    case .applied: "checkmark.seal"
    case .failed: "exclamationmark.triangle"
    }
  }
}

private struct ApplyPreviewView: View {
  @EnvironmentObject private var model: ApplicationModel
  let request: PendingApplyRequest
  let onConfirm: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(
          request.preparation.mode == .force
            ? appLocalized("Available Settings Preview") : appLocalized("Apply Preview"),
          systemImage: request.preparation.mode == .force
            ? "exclamationmark.shield" : "list.bullet.clipboard"
        )
        .font(.title2.bold())
        Spacer()
        Text(request.profile.name)
          .foregroundStyle(.secondary)
      }

      if request.preparation.mode == .force {
        Label(
          "Only available operations will run. Review every skipped item before continuing.",
          systemImage: "exclamationmark.triangle"
        )
        .padding(10)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
      }

      if request.preparation.operations.contains(where: { $0.risk == .high }) {
        Label(
          "Display changes remain temporary and will be restored if the app exits or you do not confirm within 15 seconds.",
          systemImage: "display.trianglebadge.exclamationmark"
        )
        .padding(10)
        .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          previewSection(
            appLocalized("Planned changes"),
            systemImage: "arrow.triangle.2.circlepath"
          ) {
            if request.preparation.operations.isEmpty {
              Text("No setting needs to change.")
                .foregroundStyle(.secondary)
            } else {
              ForEach(request.preparation.operations) { operation in
                VStack(alignment: .leading, spacing: 5) {
                  HStack(alignment: .firstTextBaseline) {
                    Text(appSettingGroupTitle(operation.group))
                      .font(.caption.bold())
                      .frame(width: 70, alignment: .leading)
                    Text(appLocalizedRuntime(operation.summary))
                    Spacer()
                    Text(
                      operation.risk == .high
                        ? appLocalized("High risk")
                        : operation.risk == .moderate
                          ? appLocalized("Review") : appLocalized("Low risk")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  if let preview = presentationBuilder.operationPreview(for: operation) {
                    operationPreview(preview, operation: operation)
                      .padding(.leading, 80)
                  }
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
              }
            }
          }

          if !request.preparation.omissions.isEmpty {
            previewSection(
              appLocalized("Skipped or unsupported"),
              systemImage: "forward.end"
            ) {
              ForEach(request.preparation.omissions) { omission in
                Label(appLocalizedRuntime(omission.reason), systemImage: "minus.circle")
              }
            }
          }

          if !request.preparation.validationIssues.isEmpty {
            previewSection(
              appLocalized("Validation"),
              systemImage: "exclamationmark.bubble"
            ) {
              ForEach(request.preparation.validationIssues) { issue in
                Label(
                  appLocalizedRuntime(issue.message),
                  systemImage: issue.isFatal ? "xmark.octagon" : "exclamationmark.circle"
                )
              }
            }
          }

          if !request.preparation.rejectionReasons.isEmpty {
            previewSection(appLocalized("Cannot apply"), systemImage: "hand.raised") {
              ForEach(request.preparation.rejectionReasons, id: \.self) { reason in
                Text(rejectionText(reason))
              }
            }
          }
        }
      }

      Divider()
      HStack {
        Button("Cancel") {
          model.cancelPendingApply()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button(
          request.preparation.mode == .force
            ? appLocalized("Apply Available Settings") : appLocalized("Apply Profile")
        ) {
          onConfirm()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(!request.preparation.canExecute || model.isProfileMutationLocked)
      }
    }
    .padding(20)
    .frame(
      minWidth: 560,
      idealWidth: 620,
      minHeight: 320,
      idealHeight: 420,
      maxHeight: 620
    )
  }

  @ViewBuilder
  private func operationPreview(
    _ preview: FriendlyOperationPreview,
    operation: PlannedOperation
  ) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
      GridRow {
        Text("Current")
          .font(.caption.bold())
        Text(
          appOperationPreviewValue(
            preview.previousValue.compactText,
            operation: operation,
            isPreviousValue: true
          )
        )
      }
      GridRow {
        Text("After apply")
          .font(.caption.bold())
        Text(
          appOperationPreviewValue(
            preview.desiredValue.compactText,
            operation: operation,
            isPreviousValue: false
          )
        )
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .textSelection(.enabled)

    let previousDetails = preview.previousValue.technicalDetails
    let desiredDetails = preview.desiredValue.technicalDetails
    if !previousDetails.isEmpty || !desiredDetails.isEmpty {
      DisclosureGroup("Technical Information") {
        ForEach(Array(previousDetails.enumerated()), id: \.offset) { _, detail in
          LabeledContent(
            appLocalized("Current \(appLocalizedPresentationText(detail.label))")
          ) {
            Text(detail.value)
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
        }
        ForEach(Array(desiredDetails.enumerated()), id: \.offset) { _, detail in
          LabeledContent(
            appLocalized("After apply \(appLocalizedPresentationText(detail.label))")
          ) {
            Text(detail.value)
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
        }
      }
      .font(.caption)
    }
  }

  private var presentationBuilder: ProfilePresentationBuilder {
    ProfilePresentationBuilder()
  }

  private func previewSection<Content: View>(
    _ title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: systemImage)
        .font(.headline)
      content()
        .padding(.leading, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func rejectionText(_ reason: ApplyRejectionReason) -> String {
    switch reason {
    case .profileDisabled: appLocalized("The profile is disabled.")
    case .noIncludedSettings: appLocalized("The profile has no included settings.")
    case .conditionsUnsatisfied:
      appLocalized("One or more readiness conditions are not satisfied.")
    case .unavailableItems:
      appLocalized("Normal apply requires every included item to be available.")
    case .fatalValidationIssues:
      appLocalized("The profile contains a setting that cannot be applied safely.")
    case .noOperations: appLocalized("There is no available operation to apply.")
    case .transactionInProgress: appLocalized("Another apply transaction is running.")
    case .safetyConfirmationCapacityReached:
      appLocalized(
        "Confirm or revert the previous display change before starting another high-risk change.")
    }
  }
}

private struct ApplyResultDetailsView: View {
  @Environment(\.dismiss) private var dismiss
  let summary: ApplyResultSummary
  let result: ApplyExecutionResult
  let verification: PostApplyVerificationResult?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Label(statusTitle, systemImage: statusSymbol)
          .font(.title2.bold())
        Spacer()
        Text(summary.profileName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Text(recoveryGuidance)
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

      Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
        resultCount("Succeeded", summary.succeededCount)
        resultCount("Failed", summary.failedCount)
        resultCount("Skipped", summary.skippedCount)
        resultCount("Unsupported", summary.unsupportedCount)
        resultCount("Not verified", summary.notVerifiedCount)
        resultCount("Rolled back", summary.rolledBackCount)
        resultCount("Rollback failed", summary.rollbackFailedCount)
      }
      .font(.caption)

      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          resultSection("Apply Results", items: result.itemResults)
          if !result.rollbackResults.isEmpty {
            resultSection("Rollback Results", items: result.rollbackResults)
          }

          if let unexpected = verification?.unexpectedRemainingOperations,
            !unexpected.isEmpty
          {
            VStack(alignment: .leading, spacing: 6) {
              Label("Additional Read-back Changes", systemImage: "questionmark.circle")
                .font(.headline)
              Text(
                "Read-back found additional changes that were not part of the completed operation. Refresh readiness before applying again."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              ForEach(Array(unexpected.enumerated()), id: \.offset) { _, reference in
                Label(
                  appLocalized(
                    "\(appSettingGroupTitle(reference.group)): \(appApplicationItemTitle(reference.key))"
                  ),
                  systemImage: "arrow.clockwise"
                )
                .font(.caption)
              }
            }
          }
        }
      }

      Divider()
      HStack {
        Text(summary.appliedAt.formatted())
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Close") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(minWidth: 520, idealWidth: 600, minHeight: 380, idealHeight: 500)
  }

  @ViewBuilder
  private func resultCount(_ title: LocalizedStringKey, _ count: Int) -> some View {
    GridRow {
      Text(title)
      Text(count, format: .number)
        .monospacedDigit()
    }
  }

  @ViewBuilder
  private func resultSection(
    _ title: LocalizedStringKey,
    items: [ApplicationItemSummary]
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.headline)
      if items.isEmpty {
        Text("No item results were recorded.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          resultItem(item)
        }
      }
    }
  }

  private func resultItem(_ item: ApplicationItemSummary) -> some View {
    let operation = ApplyOperationReference(item)
    let verificationFailure = verification?.failureReason(for: operation)
    let rollbackOperationIDs = Set(result.rollbackResults.map(\.id))
    let isNotVerified =
      item.status == .succeeded
      && !rollbackOperationIDs.contains(item.id)
      && verificationFailure != nil
    return VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline) {
        Text(appSettingGroupTitle(item.group))
          .font(.caption.bold())
        Text(appApplicationItemTitle(item.key))
        Spacer()
        Label(
          isNotVerified
            ? appLocalized("Not Verified") : appApplicationItemStatusTitle(item.status),
          systemImage: isNotVerified ? "questionmark.circle" : itemStatusSymbol(item.status)
        )
        .font(.caption.bold())
      }
      Text(
        isNotVerified
          ? verificationFailure == .readBackUnavailable
            ? appLocalized(
              "The write completed, but the current setting could not be read back safely."
            )
            : appLocalized("The write completed, but read-back still requires this change.")
          : appLocalizedRuntime(item.message)
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
  }

  private var statusTitle: String {
    switch summary.status {
    case .success: appLocalized("Applied")
    case .partial: appLocalized("Partially Applied")
    case .failure: appLocalized("Apply Failed")
    case .rolledBack: appLocalized("Rolled Back")
    case .rollbackFailed: appLocalized("Rollback Failed")
    case .notVerified: appLocalized("Not Verified")
    }
  }

  private var statusSymbol: String {
    switch summary.status {
    case .success: "checkmark.circle"
    case .partial: "exclamationmark.circle"
    case .failure: "xmark.octagon"
    case .rolledBack: "arrow.uturn.backward.circle"
    case .rollbackFailed: "exclamationmark.arrow.triangle.2.circlepath"
    case .notVerified: "questionmark.circle"
    }
  }

  private var recoveryGuidance: String {
    switch summary.status {
    case .success:
      appLocalized("All completed operations were confirmed by their result and read-back.")
    case .partial:
      appLocalized(
        "Some settings were skipped, failed, or not verified. Review the items below before trying again."
      )
    case .failure:
      appLocalized(
        "No complete result was confirmed. Review failed items and current permissions before trying again."
      )
    case .rolledBack:
      appLocalized(
        "The previous configuration was restored. Review the rollback items before applying again.")
    case .rollbackFailed:
      appLocalized(
        "The previous configuration may not be fully restored. Verify the affected settings in macOS now."
      )
    case .notVerified:
      appLocalized(
        "The write completed, but read-back could not confirm the requested state. Refresh and inspect the current settings."
      )
    }
  }

  private func itemStatusSymbol(_ status: ApplicationItemStatus) -> String {
    switch status {
    case .succeeded: "checkmark.circle"
    case .failed: "xmark.octagon"
    case .skipped: "forward.end"
    case .unsupported: "nosign"
    case .rolledBack: "arrow.uturn.backward.circle"
    case .rollbackFailed: "exclamationmark.arrow.triangle.2.circlepath"
    }
  }
}

private struct SafetyConfirmationView: View {
  @EnvironmentObject private var model: ApplicationModel
  let state: SafetyConfirmationState

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "display.trianglebadge.exclamationmark")
        .font(.system(size: 42))
        .accessibilityHidden(true)
      Text("Keep these display settings?")
        .font(.headline)
      Text(
        appLocalized(
          "The previous display configuration will return in \(state.secondsRemaining) seconds.")
      )
      .multilineTextAlignment(.center)
      .accessibilityLabel(
        appLocalized("Automatic rollback in \(state.secondsRemaining) seconds"))

      ProgressView(value: Double(state.secondsRemaining), total: 15)
        .accessibilityLabel("Display confirmation time remaining")
        .accessibilityValue(appLocalized("\(state.secondsRemaining) seconds remaining"))

      HStack {
        Button("Revert Now") { model.revertHighRiskChanges() }
          .keyboardShortcut(.cancelAction)
          .disabled(model.isApplyTransactionInProgress)
        Button("Keep Changes") { model.confirmHighRiskChanges() }
          .keyboardShortcut(.defaultAction)
          .disabled(model.isApplyTransactionInProgress)
      }
    }
    .padding(20)
    .frame(width: 340)
  }
}

private enum SettingsTab: Hashable {
  case profiles
  case permissions
  case diagnostics
  case about
}

private struct SettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @Binding var selectedTab: SettingsTab

  var body: some View {
    TabView(selection: $selectedTab) {
      ProfilesSettingsView()
        .tabItem { Label("Profiles", systemImage: "rectangle.stack") }
        .tag(SettingsTab.profiles)

      PermissionsSettingsView()
        .environmentObject(model)
        .tabItem { Label("Permissions", systemImage: "lock.shield") }
        .tag(SettingsTab.permissions)

      DiagnosticsSettingsView()
        .environmentObject(model)
        .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        .tag(SettingsTab.diagnostics)

      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
        .tag(SettingsTab.about)
    }
    .padding(20)
  }
}

private struct PermissionsSettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var locationPermission: LocationPermissionController

  var body: some View {
    Form {
      Section("Login") {
        Toggle(
          "Launch Desk Setup Switcher at login",
          isOn: Binding(
            get: { model.launchAtLoginDesired },
            set: { model.setLaunchAtLogin($0) }
          )
        )

        LabeledContent(
          "App setting",
          value: model.launchAtLoginDesired ? appLocalized("On") : appLocalized("Off")
        )
        LabeledContent(
          "macOS registration",
          value: model.loginItemEnabled ? appLocalized("Enabled") : appLocalized("Not enabled")
        )

        if loginItemStatesDiffer || model.canRetryLoginItemRegistration {
          Label(model.loginItemStatus, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(appLocalized("Login item status: \(model.loginItemStatus)"))
        } else {
          Label(
            "The app setting matches the macOS registration state.", systemImage: "checkmark.circle"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        HStack {
          if model.canRetryLoginItemRegistration {
            Button("Retry Registration") {
              model.retryLaunchAtLoginRegistration()
            }
          }
          Button("Refresh Status") {
            model.refreshLoginItemStatusFromSystem()
          }
        }

        DisclosureGroup("Why can these states differ?") {
          Text(
            "macOS accepts login-item registration only for an eligible installed and code-signed app. The app setting does not guarantee registration."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Section("System permissions") {
        Text(
          "macOS can require Location Services to reveal a Wi-Fi network name and evaluate a location readiness condition. Desk Setup Switcher does not track location continuously."
        )
        LabeledContent("Location", value: locationPermission.statusText)
        Button(
          locationPermission.isAuthorized
            ? appLocalized("Refresh Current Location") : appLocalized("Request Location Access")
        ) {
          locationPermission.requestAccess()
        }
        .accessibilityHint("Shows the macOS permission prompt only after this explanation")
      }
    }
    .formStyle(.grouped)
  }

  private var loginItemStatesDiffer: Bool {
    model.launchAtLoginDesired != model.loginItemEnabled
  }
}

private struct DiagnosticsSettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @State private var confirmClear = false

  var body: some View {
    Form {
      LabeledContent("Last result", value: model.lastMessage)
      LabeledContent("Last snapshot", value: model.snapshotStatus)
      LabeledContent("Storage", value: appLocalized("Local Application Support only"))
      LabeledContent("Telemetry", value: appLocalized("None"))
      LabeledContent("Live mutations", value: appLocalized("User-confirmed only"))
      Section("Readiness facts") {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(model.conditionContextStatus)
              .font(.caption)
              .foregroundStyle(.secondary)
            if let refreshedAt = model.readinessLastRefreshedAt {
              Text(appLocalized("Last refreshed \(refreshedAt.formatted())"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          Spacer()
          Button("Refresh Readiness") { model.refreshReadinessFacts() }
            .disabled(model.isApplyTransactionInProgress)
            .accessibilityHint("Reads current system facts without changing any setting")
        }

        LabeledContent(
          "Connected displays",
          value: appLocalized("\(model.lastConditionContext.displays.count) detected")
        )
        LabeledContent(
          "Wi-Fi SSID",
          value: model.lastConditionContext.wifiSSID ?? appLocalized("Unavailable")
        )
        LabeledContent(
          "Ethernet",
          value: model.lastConditionContext.ethernetConnected
            ? appLocalized("Connected") : appLocalized("Not connected")
        )
        LabeledContent(
          "Cached location",
          value: model.lastConditionContext.location == nil
            ? appLocalized("Unavailable") : appLocalized("Available; coordinates hidden")
        )

        factList(
          appLocalized("Audio input UIDs"),
          values: model.lastConditionContext.audioInputUIDs.sorted()
        )
        factList(
          appLocalized("Audio output UIDs"),
          values: model.lastConditionContext.audioOutputUIDs.sorted()
        )
        factList(
          appLocalized("USB hardware identifiers"),
          values: model.lastConditionContext.hardwareIdentifiers.sorted()
        )
        factList(
          appLocalized("Local IP addresses"),
          values: model.lastConditionContext.ipAddresses.sorted()
        )
      }
      if let snapshot = model.lastSnapshot {
        Section("Snapshot details") {
          LabeledContent("Captured", value: snapshot.capturedAt.formatted())
          ForEach(snapshot.groups, id: \.group) { group in
            DisclosureGroup(appSettingGroupTitle(group.group)) {
              Text(appLocalizedRuntime(group.capability.reason))
                .font(.caption)
                .foregroundStyle(.secondary)
              ForEach(group.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                  Label(appSnapshotItemLabel(item), systemImage: snapshotSymbol(item.state))
                  Text(snapshotStateTitle(item.state))
                    .font(.caption.bold())
                  if !item.detail.isEmpty {
                    Text(appLocalizedRuntime(item.detail))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
                .accessibilityElement(children: .combine)
              }
              ForEach(group.failures, id: \.stage) { failure in
                Label(
                  appLocalizedRuntime(failure.message),
                  systemImage: "exclamationmark.triangle"
                )
              }
            }
          }
        }
      }
      if let result = model.lastApplyResult {
        Section("Last apply details") {
          LabeledContent(
            "Status",
            value: appApplicationStatusTitle(
              result.status,
              isAwaitingDisplayConfirmation: result.safetyConfirmationID != nil
            )
          )
          LabeledContent(
            "Executed",
            value: result.didExecute ? appLocalized("Yes") : appLocalized("No")
          )
          ForEach(
            Array((result.itemResults + result.rollbackResults).enumerated()),
            id: \.offset
          ) { _, item in
            applicationItemRow(item)
          }
        }
      }

      Section("Redacted local events") {
        Text(model.diagnosticStatus)
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          Button("Refresh") { model.refreshDiagnostics() }
          Button("Clear Events…", role: .destructive) { confirmClear = true }
            .disabled(model.diagnosticEntries.isEmpty)
        }

        if !model.diagnosticEntries.isEmpty {
          ForEach(model.diagnosticEntries) { entry in
            VStack(alignment: .leading, spacing: 3) {
              Label(
                appLocalized(
                  "\(diagnosticSeverityTitle(entry.severity)): \(entry.component): \(entry.code)"),
                systemImage: diagnosticSymbol(entry.severity)
              )
              .font(.caption.bold())
              Text(entry.message)
                .font(.caption)
              Text(entry.timestamp.formatted())
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
    .formStyle(.grouped)
    .confirmationDialog("Remove all local diagnostic events?", isPresented: $confirmClear) {
      Button("Remove Events", role: .destructive) { model.clearDiagnostics() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes only Desk Setup Switcher’s rotated, redacted diagnostic files.")
    }
  }

  private func diagnosticSymbol(_ severity: DiagnosticSeverity) -> String {
    switch severity {
    case .debug: "ladybug"
    case .info: "info.circle"
    case .warning: "exclamationmark.triangle"
    case .error: "xmark.octagon"
    }
  }

  private func diagnosticSeverityTitle(_ severity: DiagnosticSeverity) -> String {
    switch severity {
    case .debug: appLocalized("Debug")
    case .info: appLocalized("Information")
    case .warning: appLocalized("Warning")
    case .error: appLocalized("Error")
    }
  }

  private func applicationItemRow(_ item: ApplicationItemSummary) -> some View {
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

  @ViewBuilder
  private func factList(_ title: String, values: [String]) -> some View {
    DisclosureGroup(appLocalized("\(title) (\(values.count))")) {
      if values.isEmpty {
        Text("None detected")
          .foregroundStyle(.secondary)
      } else {
        ForEach(values, id: \.self) { value in
          Text(value)
            .font(.caption.monospaced())
            .textSelection(.enabled)
        }
      }
    }
  }

  private func snapshotSymbol(_ state: SnapshotItemState) -> String {
    switch state {
    case .detected: "sensor"
    case .storable: "checkmark.circle"
    case .unreadable: "eye.slash"
    case .permissionRequired: "lock.trianglebadge.exclamationmark"
    case .unsupported: "nosign"
    }
  }

  private func snapshotStateTitle(_ state: SnapshotItemState) -> String {
    switch state {
    case .detected: appLocalized("Detected")
    case .storable: appLocalized("Storable")
    case .unreadable: appLocalized("Unreadable")
    case .permissionRequired: appLocalized("Permission required")
    case .unsupported: appLocalized("Unsupported")
    }
  }
}

private struct AboutSettingsView: View {
  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "switch.2")
        .font(.system(size: 56))
        .accessibilityHidden(true)
      Text("Desk Setup Switcher")
        .font(.title2.bold())
      Text(appLocalized("Version \(appVersion)"))
        .foregroundStyle(.secondary)
      Text("Free and open source under the MIT License")
        .font(.caption)

      Divider()
        .frame(maxWidth: 360)

      HStack(spacing: 16) {
        Link(destination: repositoryURL) {
          Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
        }
        Link(destination: issuesURL) {
          Label("Report an Issue", systemImage: "exclamationmark.bubble")
        }
      }

      HStack(spacing: 16) {
        Link(destination: licenseURL) {
          Label("MIT License", systemImage: "doc.text")
        }
        Link(destination: privacyURL) {
          Label("Privacy Principles", systemImage: "hand.raised")
        }
      }

      Text("Links open only when you choose them and use your default browser.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
  }

  private let repositoryURL = URL(string: "https://github.com/GGULBAE/desk-setup-switcher")!
  private let issuesURL = URL(string: "https://github.com/GGULBAE/desk-setup-switcher/issues")!
  private let licenseURL = URL(
    string: "https://github.com/GGULBAE/desk-setup-switcher/blob/master/LICENSE")!
  private let privacyURL = URL(
    string: "https://github.com/GGULBAE/desk-setup-switcher/blob/master/docs/PRIVACY.md")!
}
