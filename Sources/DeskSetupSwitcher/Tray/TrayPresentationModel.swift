import Combine
import CoreLocation
import Foundation
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

struct MenuProfileDeletionState: Equatable, Sendable {
  private(set) var pendingProfileID: UUID?

  init(pendingProfileID: UUID? = nil) {
    self.pendingProfileID = pendingProfileID
  }

  mutating func request(profileID: UUID) {
    pendingProfileID = profileID
  }

  mutating func cancel() {
    pendingProfileID = nil
  }

  mutating func confirm(profileID: UUID) -> Bool {
    guard pendingProfileID == profileID else { return false }
    pendingProfileID = nil
    return true
  }

  func isPending(profileID: UUID) -> Bool {
    pendingProfileID == profileID
  }
}

enum TrayFocusTarget: Hashable, Sendable {
  case capture
  case delete(UUID)
  case cancelDelete(UUID)
  case profile(UUID)
  case emptyState
}

enum TrayScrollAnchor: Hashable, Sendable {
  case top
}

struct TrayScrollResetRequest: Equatable, Sendable {
  let sessionGeneration: UInt64
  let anchor: TrayScrollAnchor
}

enum TrayCapturePhase: Equatable, Sendable {
  case idle
  case running
  case success(String)
  case partial(String)
  case failure(String)

  var geometryPhase: TrayCaptureGeometryPhase {
    switch self {
    case .idle: .idle
    case .running: .pending
    case .success, .partial: .result
    case .failure: .error
    }
  }
}

enum TrayApplyDraftKind: Equatable, Sendable {
  case targetDraft
  case otherDraft(openProfileID: UUID, openProfileName: String)
}

struct TrayApplyDraftPrompt: Identifiable, Equatable, Sendable {
  let id = UUID()
  let targetProfileID: UUID
  let targetProfileName: String
  let mode: ApplyMode
  let kind: TrayApplyDraftKind
}

@MainActor
protocol TraySessionStateUpdating: AnyObject {
  var geometryContext: TrayGeometryContext { get }
  var statusItemPresentation: TrayStatusItemPresentation { get }
  func setStatusItemPresentationHandler(
    _ handler: @escaping @MainActor (TrayStatusItemPresentation) -> Void)
  func trayDidOpen(sessionGeneration: UInt64, viewport: CGSize)
  func trayDidClose(sessionGeneration: UInt64)
}

extension TraySessionStateUpdating {
  var statusItemPresentation: TrayStatusItemPresentation {
    TrayStatusItemPresentationBuilder().presentation(
      for: TrayStatusItemSnapshot(
        profiles: [],
        selectedProfileID: nil,
        visibleReadinessByProfile: [:],
        operationCountByProfile: [:],
        hasFreshReadiness: false
      )
    )
  }

  func setStatusItemPresentationHandler(
    _ handler: @escaping @MainActor (TrayStatusItemPresentation) -> Void
  ) {}
}

/// App-lifetime surface state. Profiles and domain results remain authoritative
/// in ApplicationModel; this model owns only presentation workflow, focus, and
/// task lifetime that must survive SwiftUI view recreation.
@MainActor
final class TrayPresentationModel: ObservableObject, TrayActionExecuting,
  TraySessionStateUpdating
{
  typealias CaptureOperation = @MainActor () async -> ProfileCreationCaptureResult

  @Published private(set) var deletion = MenuProfileDeletionState()
  @Published private(set) var focusTarget: TrayFocusTarget?
  @Published private(set) var capturePhase: TrayCapturePhase = .idle
  @Published private(set) var handoffError: String?
  @Published private(set) var activeSessionGeneration: UInt64?
  @Published private(set) var scrollResetRequest: TrayScrollResetRequest?
  @Published private(set) var viewport: CGSize = .zero
  @Published private(set) var isTrayVisible = false
  @Published private(set) var workflowDestination: TrayDestination?
  @Published private(set) var applyDraftPrompt: TrayApplyDraftPrompt?
  @Published private(set) var applyDraftError: String?

  let model: ApplicationModel
  let locationPermission: LocationPermissionController
  let profileEditor: ProfileEditorModel

  private let captureOperation: CaptureOperation
  private var captureTask: Task<Void, Never>?
  private var transientMessageTask: Task<Void, Never>?
  private var permissionTask: Task<Void, Never>?
  private var workflowTask: Task<Void, Never>?
  private var applyDraftRetryAfterError: TrayApplyDraftPrompt?
  private var surfaceDismissRequest: (@MainActor (UInt64) -> Void)?
  private var statusItemPresentationHandler: (@MainActor (TrayStatusItemPresentation) -> Void)?
  private var modelStatusObservation: AnyCancellable?

  init(
    model: ApplicationModel,
    locationPermission: LocationPermissionController,
    profileEditor: ProfileEditorModel,
    initialDeletionProfileID: UUID? = nil,
    captureOperation: CaptureOperation? = nil
  ) {
    self.model = model
    self.locationPermission = locationPermission
    self.profileEditor = profileEditor
    deletion = MenuProfileDeletionState(pendingProfileID: initialDeletionProfileID)
    self.captureOperation =
      captureOperation ?? { [weak model] in
        guard let model else {
          return .rejected(message: appLocalized("The capture service is unavailable."))
        }
        return await model.createProfileFromCurrentSettings()
      }
    modelStatusObservation = model.objectWillChange.sink { [weak self] in
      DispatchQueue.main.async { [weak self] in
        self?.publishStatusItemPresentation()
      }
    }
  }

  var geometryContext: TrayGeometryContext {
    TrayGeometryContext(
      profileCount: model.profiles.filter(\.isEnabled).count,
      deletionConfirmationVisible: deletion.pendingProfileID != nil,
      capturePhase: capturePhase.geometryPhase,
      applyBannerVisible: model.lastApplySummary != nil
    )
  }

  var hasCaptureTask: Bool {
    captureTask != nil
  }

  var statusItemPresentation: TrayStatusItemPresentation {
    TrayStatusItemPresentationBuilder().presentation(
      for: TrayStatusItemSnapshot(
        profiles: model.profiles,
        selectedProfileID: model.selectedProfileID,
        visibleReadinessByProfile: Dictionary(
          uniqueKeysWithValues: model.profiles.map { ($0.id, model.readiness(for: $0)) }
        ),
        operationCountByProfile: model.operationCountByProfile,
        hasFreshReadiness:
          model.readinessLastRefreshedAt != nil && !model.isReadinessRefreshInProgress
      )
    )
  }

  var captureAction: TrayAction {
    if profileEditor.isDirty || profileEditor.session.pendingSelection != nil {
      return .openPermissionWorkflow(.captureDirtyDraft)
    }
    switch locationPermission.authorizationStatus {
    case .notDetermined:
      return .openPermissionWorkflow(.captureExplanation)
    case .denied, .restricted:
      return .openPermissionWorkflow(.captureDenied)
    case .authorizedAlways, .authorized:
      return .capture
    @unknown default:
      return .capture
    }
  }

  var openDraftIsValid: Bool {
    guard let draft = profileEditor.draft else { return false }
    return !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && ProfileDraftValidator().validate(draft).isValid
  }

  var applyDraftTitle: String {
    guard let prompt = applyDraftPrompt else {
      return appLocalized("Unsaved Profile Changes")
    }
    switch prompt.kind {
    case .targetDraft:
      return appLocalized("Save changes before applying this profile?")
    case .otherDraft:
      return appLocalized("Resolve unsaved changes before applying another profile?")
    }
  }

  var applyDraftMessage: String {
    guard let prompt = applyDraftPrompt else { return "" }
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

  func setSurfaceDismissRequest(_ request: @escaping @MainActor (UInt64) -> Void) {
    surfaceDismissRequest = request
  }

  func setStatusItemPresentationHandler(
    _ handler: @escaping @MainActor (TrayStatusItemPresentation) -> Void
  ) {
    statusItemPresentationHandler = handler
    handler(statusItemPresentation)
  }

  private func publishStatusItemPresentation() {
    statusItemPresentationHandler?(statusItemPresentation)
  }

  #if DEBUG
    func configureForUIAudit(capturePhase: TrayCapturePhase) {
      self.capturePhase = capturePhase
    }
  #endif

  func trayDidOpen(sessionGeneration: UInt64, viewport: CGSize) {
    activeSessionGeneration = sessionGeneration
    scrollResetRequest = TrayScrollResetRequest(
      sessionGeneration: sessionGeneration,
      anchor: .top
    )
    self.viewport = viewport
    isTrayVisible = true
    model.refreshReadinessFacts()
  }

  func trayDidClose(sessionGeneration: UInt64) {
    guard activeSessionGeneration == sessionGeneration else { return }
    isTrayVisible = false
    activeSessionGeneration = nil
    viewport = .zero
    // Capture and refresh work intentionally continue. They are app-lifetime
    // operations and are cancelled only by an explicit workflow decision.
  }

  func requestEscape() {
    if let profileID = deletion.pendingProfileID {
      cancelDeletion(profileID: profileID)
      return
    }
    guard let activeSessionGeneration else { return }
    surfaceDismissRequest?(activeSessionGeneration)
  }

  func executeStayOpen(_ action: TrayAction) async {
    switch action {
    case .requestDelete(let profileID):
      deletion.request(profileID: profileID)
      focusTarget = .cancelDelete(profileID)

    case .cancelDelete(let profileID):
      cancelDeletion(profileID: profileID)

    case .confirmDelete(let profileID):
      confirmDeletion(profileID: profileID)

    case .capture:
      startCapture()

    case .refresh:
      model.refreshReadinessFacts()

    case .dismissCaptureBanner:
      model.dismissCaptureSummary()
      if case .partial = capturePhase {
        capturePhase = .idle
      } else if case .failure = capturePhase {
        capturePhase = .idle
      }

    case .dismissApplyBanner:
      model.dismissApplySummary()

    case .disabled:
      break

    case .openSettings, .editProfile, .openPermissionWorkflow, .openApplyPreview,
      .openResultDetails, .quit:
      assertionFailure("Only stay-open actions may reach the stay-open executor.")
    }
  }

  func reportHandoffFailure(_ message: String) {
    handoffError = message
    AccessibilityNotification.Announcement(message).post()
  }

  func dismissHandoffError() {
    handoffError = nil
  }

  func setWorkflowDestination(_ destination: TrayDestination?) {
    workflowDestination = destination
    if destination == nil {
      applyDraftPrompt = nil
      applyDraftError = nil
    }
  }

  func beginApplyWorkflow(profileID: UUID, mode: ApplyMode) {
    guard let profile = model.profiles.first(where: { $0.id == profileID }) else {
      applyDraftError = appLocalized("The target profile is no longer available to apply.")
      return
    }
    requestApply(profile, mode: mode)
  }

  func confirmPendingApply(_ request: PendingApplyRequest) {
    let decision = DirtyApplyProtectionDecision.evaluate(
      targetProfileID: request.profile.id,
      openDraftProfileID: profileEditor.selectedProfileID,
      isDraftDirty: profileEditor.isDirty,
      hasPendingSelection: profileEditor.session.pendingSelection != nil
    )
    guard decision == .applyNow else {
      model.cancelPendingApply()
      requestApply(request.profile, mode: request.preparation.mode)
      return
    }
    model.executePendingApply()
  }

  func cancelApplyWorkflow() {
    model.cancelPendingApply()
    cancelApplyDraftPrompt()
  }

  func saveDraftThenApply(_ prompt: TrayApplyDraftPrompt) {
    let candidate: DeskProfile
    let expectsSelectionChange: Bool
    switch prompt.kind {
    case .targetDraft:
      guard let saveCandidate = profileEditor.session.saveCandidate() else {
        applyDraftError = appLocalized("The open profile could not be prepared for saving.")
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
        applyDraftError = appLocalized(
          "The open profile decision changed before it could be saved.")
        return
      }
      candidate = saveCandidate
      expectsSelectionChange = true
    }

    let validation = ProfileDraftValidator().validate(candidate)
    guard !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      validation.isValid
    else {
      applyDraftError =
        validation.issues.first.map {
          appLocalizedDraftValidationMessage($0.message)
        } ?? appLocalized("Enter a profile name before saving and applying.")
      return
    }

    applyDraftPrompt = nil
    profileEditor.beginSaving()
    workflowTask?.cancel()
    workflowTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await persistDraftAndApply(
        candidate,
        prompt: prompt,
        expectsSelectionChange: expectsSelectionChange
      )
      workflowTask = nil
    }
  }

  func discardDraftThenApply(
    _ prompt: TrayApplyDraftPrompt,
    expectedOpenProfileID: UUID
  ) {
    guard profileEditor.selectedProfileID == expectedOpenProfileID,
      case .selected(let target) = profileEditor.resolvePendingSelection(.discard),
      target.profileID == prompt.targetProfileID
    else {
      applyDraftError = appLocalized(
        "The open profile decision changed before the draft could be discarded.")
      return
    }
    applyDraftPrompt = nil
    workflowTask?.cancel()
    workflowTask = Task { @MainActor [weak self] in
      guard let self else { return }
      guard await model.selectProfileAndWait(id: prompt.targetProfileID),
        let targetProfile = model.profiles.first(where: { $0.id == prompt.targetProfileID })
      else {
        applyDraftError = appLocalized("The target profile is no longer available to apply.")
        workflowTask = nil
        return
      }
      model.prepareApply(profile: targetProfile, mode: prompt.mode)
      workflowTask = nil
    }
  }

  func cancelApplyDraftPrompt() {
    if case .otherDraft? = applyDraftPrompt?.kind {
      _ = profileEditor.resolvePendingSelection(.cancel)
    }
    applyDraftPrompt = nil
  }

  func dismissApplyDraftError() {
    applyDraftError = nil
    if let retry = applyDraftRetryAfterError {
      applyDraftRetryAfterError = nil
      applyDraftPrompt = retry
    }
  }

  func saveDraftThenCapture() {
    guard workflowTask == nil else { return }
    workflowTask = Task { @MainActor [weak self] in
      guard let self else { return }
      guard profileEditor.session.pendingSelection == nil,
        let candidate = profileEditor.session.saveCandidate()
      else {
        workflowTask = nil
        return
      }
      if let validationError = appProfileDraftValidationError(candidate) {
        reportHandoffFailure(validationError)
        workflowTask = nil
        return
      }
      profileEditor.beginSaving()
      switch await model.updateProfile(candidate) {
      case .saved(let persisted):
        guard case .saved = profileEditor.completeSave(with: persisted) else {
          reportHandoffFailure(appLocalized("The saved profile did not match the active draft."))
          workflowTask = nil
          return
        }
        startCapture()
      case .rejected(let message):
        profileEditor.finishWithError(message)
        reportHandoffFailure(message)
      }
      workflowTask = nil
    }
  }

  func discardDraftThenCapture() {
    profileEditor.revertDraft()
    startCapture()
  }

  func requestLocationAccessAndCapture() {
    guard permissionTask == nil else { return }
    permissionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      locationPermission.requestAccess()
      guard locationPermission.lastError == nil else {
        reportHandoffFailure(
          locationPermission.lastError ?? appLocalized("Location access was not granted."))
        permissionTask = nil
        return
      }
      for await status in locationPermission.$authorizationStatus.values {
        guard !Task.isCancelled else { break }
        guard status != .notDetermined else { continue }
        startCapture()
        break
      }
      permissionTask = nil
    }
  }

  func openLocationSystemSettings() {
    locationPermission.openSystemSettings()
    if let error = locationPermission.lastError {
      reportHandoffFailure(error)
    }
  }

  func cancelPermissionWorkflow() {
    permissionTask?.cancel()
    permissionTask = nil
  }

  func startCapture() {
    guard captureTask == nil else { return }
    transientMessageTask?.cancel()
    transientMessageTask = nil
    capturePhase = .running
    captureTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let result = await captureOperation()
      guard !Task.isCancelled else {
        captureTask = nil
        return
      }
      finishCapture(result)
      captureTask = nil
    }
  }

  func cancelCapture() {
    captureTask?.cancel()
    captureTask = nil
    capturePhase = .idle
  }

  private func cancelDeletion(profileID: UUID) {
    guard deletion.isPending(profileID: profileID) else { return }
    deletion.cancel()
    focusTarget = .delete(profileID)
  }

  private func confirmDeletion(profileID: UUID) {
    let enabledProfiles = model.profiles.filter(\.isEnabled)
    guard let index = enabledProfiles.firstIndex(where: { $0.id == profileID }),
      deletion.confirm(profileID: profileID)
    else { return }

    if profileEditor.isDirty, profileEditor.selectedProfileID == profileID {
      profileEditor.revertDraft()
    }
    let remaining = enabledProfiles.filter { $0.id != profileID }
    if remaining.isEmpty {
      focusTarget = .emptyState
    } else {
      focusTarget = .profile(remaining[min(index, remaining.count - 1)].id)
    }
    model.deleteProfile(id: profileID)
  }

  private func finishCapture(_ result: ProfileCreationCaptureResult) {
    switch result {
    case .created(_, let summary):
      let message: String
      if summary.status == .complete {
        message = appLocalized("Captured current settings without changing the Mac.")
        capturePhase = .success(message)
        scheduleSuccessMessageDismissal()
      } else if summary.permissionRequiredCount > 0 {
        message = appLocalized(
          "Captured \(summary.applicableCount) applicable settings. Location access is needed to include the current Wi-Fi network."
        )
        capturePhase = .partial(message)
      } else {
        message = appLocalized("Captured \(summary.applicableCount) applicable settings.")
        capturePhase = .partial(message)
      }
      AccessibilityNotification.Announcement(message).post()

    case .rejected(let message, let summary):
      if let summary, summary.permissionRequiredCount > 0 {
        capturePhase = .partial(message)
      } else {
        capturePhase = .failure(message)
      }
      AccessibilityNotification.Announcement(message).post()
    }
  }

  private func scheduleSuccessMessageDismissal() {
    transientMessageTask?.cancel()
    transientMessageTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(3))
      guard let self, !Task.isCancelled else { return }
      if case .success = capturePhase {
        capturePhase = .idle
      }
      transientMessageTask = nil
    }
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
      applyDraftPrompt = TrayApplyDraftPrompt(
        targetProfileID: profile.id,
        targetProfileName: profile.name,
        mode: mode,
        kind: .targetDraft
      )
    case .resolveOtherDraft(let openProfileID):
      let openName = profileEditor.draft?.name ?? appLocalized("Open profile")
      switch profileEditor.requestSelection(profile) {
      case .requiresDecision:
        applyDraftPrompt = TrayApplyDraftPrompt(
          targetProfileID: profile.id,
          targetProfileName: profile.name,
          mode: mode,
          kind: .otherDraft(openProfileID: openProfileID, openProfileName: openName)
        )
      case .selected:
        model.prepareApply(profile: profile, mode: mode)
      case .unchanged:
        applyDraftError = appLocalized(
          "The open draft changed before the apply decision. Try again.")
      }
    case .blockedByPendingSelection:
      applyDraftError = appLocalized(
        "Finish the open profile decision before applying another profile.")
    }
  }

  private func persistDraftAndApply(
    _ candidate: DeskProfile,
    prompt: TrayApplyDraftPrompt,
    expectsSelectionChange: Bool
  ) async {
    var coordinator = DirtyApplySaveCoordinator(
      targetProfileID: prompt.targetProfileID,
      mode: prompt.mode,
      destination: expectsSelectionChange
        ? .selectedTarget(profileID: prompt.targetProfileID)
        : .persistedTarget
    )
    switch await model.updateProfile(candidate) {
    case .saved(let persisted):
      let completion = profileEditor.completeSave(with: persisted)
      switch coordinator.handle(.saveSucceeded(profile: persisted, completion: completion)) {
      case .prepare(let profile, let mode):
        model.prepareApply(profile: profile, mode: mode)
      case .selectAndPrepare(let profileID, let mode):
        guard await model.selectProfileAndWait(id: profileID),
          let targetProfile = model.profiles.first(where: { $0.id == profileID })
        else {
          applyDraftError = appLocalized(
            "The target profile changed before the apply preview could be prepared.")
          return
        }
        model.prepareApply(profile: targetProfile, mode: mode)
      case .none:
        applyDraftError =
          expectsSelectionChange
          ? appLocalized("The target profile changed before the apply preview could be prepared.")
          : appLocalized("The saved profile did not match the active draft.")
      }
    case .rejected(let message):
      _ = coordinator.handle(.saveRejected)
      profileEditor.finishWithError(message)
      applyDraftRetryAfterError = prompt
      applyDraftError = message
    }
  }
}
