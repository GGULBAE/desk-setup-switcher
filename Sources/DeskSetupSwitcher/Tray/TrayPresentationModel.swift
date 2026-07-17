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
  func trayContentDidAttach(sessionGeneration: UInt64)
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

  func trayContentDidAttach(sessionGeneration: UInt64) {}
}

/// App-lifetime surface state. Profiles and domain results remain authoritative
/// in ApplicationModel; this model owns only presentation workflow, focus, and
/// task lifetime that must survive SwiftUI view recreation.
@MainActor
final class TrayPresentationModel: ObservableObject, TrayActionExecuting,
  TraySessionStateUpdating
{
  typealias CaptureOperation = @MainActor () async -> ProfileCreationCaptureResult
  typealias DeleteOperation = @MainActor (UUID) async -> ProfileDeleteResult
  typealias SaveOperation = @MainActor (DeskProfile) async -> ProfileSaveResult

  @Published private(set) var deletion = MenuProfileDeletionState()
  @Published private(set) var deletionInFlightProfileID: UUID?
  @Published private(set) var focusTarget: TrayFocusTarget?
  @Published private(set) var capturePhase: TrayCapturePhase = .idle
  @Published private(set) var permissionWorkflowNotice: String?
  @Published private(set) var permissionWorkflowError: String?
  @Published private(set) var isWorkflowTaskInFlight = false
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
  private let deleteOperation: DeleteOperation
  private let saveOperation: SaveOperation
  private let successMessageDismissalDelay: Duration
  private var captureTask: Task<Void, Never>?
  private var captureTaskID: UUID?
  private var transientMessageTask: Task<Void, Never>?
  private var permissionTask: Task<Void, Never>?
  private var permissionTaskID: UUID?
  private var workflowTask: Task<Void, Never>?
  private var workflowTaskGeneration: UInt64 = 0
  private var inFlightApplyDraftPrompt: TrayApplyDraftPrompt?
  private var applyDraftRetryAfterError: TrayApplyDraftPrompt?
  private var surfaceDismissRequest: (@MainActor (UInt64) -> Void)?
  private var statusItemPresentationHandler: (@MainActor (TrayStatusItemPresentation) -> Void)?
  private var modelStatusObservation: AnyCancellable?
  private var locationAuthorizationObservation: AnyCancellable?

  init(
    model: ApplicationModel,
    locationPermission: LocationPermissionController,
    profileEditor: ProfileEditorModel,
    initialDeletionProfileID: UUID? = nil,
    captureOperation: CaptureOperation? = nil,
    deleteOperation: DeleteOperation? = nil,
    saveOperation: SaveOperation? = nil,
    successMessageDismissalDelay: Duration = .seconds(3)
  ) {
    self.model = model
    self.locationPermission = locationPermission
    self.profileEditor = profileEditor
    self.successMessageDismissalDelay = successMessageDismissalDelay
    deletion = MenuProfileDeletionState(pendingProfileID: initialDeletionProfileID)
    self.captureOperation =
      captureOperation ?? { [weak model] in
        guard let model else {
          return .rejected(message: appLocalized("The capture service is unavailable."))
        }
        return await model.createProfileFromCurrentSettings()
      }
    self.deleteOperation =
      deleteOperation ?? { [weak model] profileID in
        guard let model else {
          return .rejected(
            message: appLocalized("A local profile storage operation failed."))
        }
        return await model.deleteProfile(id: profileID)
      }
    self.saveOperation =
      saveOperation ?? { [weak model] profile in
        guard let model else {
          return .rejected(message: appLocalized("A local profile storage operation failed."))
        }
        return await model.updateProfile(profile)
      }
    modelStatusObservation = model.objectWillChange.sink { [weak self] in
      DispatchQueue.main.async { [weak self] in
        self?.publishStatusItemPresentation()
      }
    }
    locationAuthorizationObservation = locationPermission.$authorizationStatus
      .dropFirst()
      .sink { [weak self] status in
        guard status == .authorized || status == .authorizedAlways else { return }
        self?.permissionWorkflowNotice = nil
        self?.permissionWorkflowError = nil
        self?.handoffError = nil
      }
  }

  var geometryContext: TrayGeometryContext {
    TrayGeometryContext(
      profileCount: model.profiles.count,
      deletionConfirmationVisible: deletion.pendingProfileID != nil,
      capturePhase: capturePhase.geometryPhase,
      applyBannerVisible: model.lastApplySummary != nil
    )
  }

  var hasCaptureTask: Bool {
    captureTask != nil
  }

  var hasPermissionTask: Bool {
    permissionTask != nil
  }

  var hasWorkflowTask: Bool {
    isWorkflowTaskInFlight
  }

  func isDeletionInFlight(profileID: UUID) -> Bool {
    deletionInFlightProfileID == profileID
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
        // A background refresh must not temporarily discard the last confirmed
        // match. Doing so changes the status-item width exactly while it anchors
        // the open popover.
        hasFreshReadiness: model.readinessLastRefreshedAt != nil
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
    self.viewport = viewport
    isTrayVisible = true
    model.refreshReadinessFacts()
  }

  func trayContentDidAttach(sessionGeneration: UInt64) {
    guard activeSessionGeneration == sessionGeneration else { return }
    scrollResetRequest = TrayScrollResetRequest(
      sessionGeneration: sessionGeneration,
      anchor: .top
    )
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
      if isDeletionInFlight(profileID: profileID) {
        guard let activeSessionGeneration else { return }
        surfaceDismissRequest?(activeSessionGeneration)
        return
      }
      cancelDeletion(profileID: profileID)
      return
    }
    guard let activeSessionGeneration else { return }
    surfaceDismissRequest?(activeSessionGeneration)
  }

  func executeStayOpen(_ action: TrayAction) async {
    switch action {
    case .requestDelete(let profileID):
      guard deletionInFlightProfileID == nil else { return }
      deletion.request(profileID: profileID)
      focusTarget = .cancelDelete(profileID)

    case .cancelDelete(let profileID):
      cancelDeletion(profileID: profileID)

    case .confirmDelete(let profileID):
      await confirmDeletion(profileID: profileID)

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
      permissionWorkflowNotice = nil
      permissionWorkflowError = nil
    }
  }

  /// Starts a new permission workflow from the tray. A result from an earlier
  /// capture belongs to that completed session and must not replace the new
  /// session's actionable permission choices. In-session SwiftUI re-renders do
  /// not call this method, so their running or terminal result remains stable.
  func beginPermissionWorkflow(_ workflow: TrayPermissionWorkflow) {
    consumeTerminalCapturePhase()
    permissionWorkflowNotice = nil
    permissionWorkflowError = nil
    handoffError = nil
    setWorkflowDestination(.permission(workflow))
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
    if case .rejected(let reason) = model.executePendingApply() {
      applyDraftError = appLocalizedRuntime(reason.defaultMessage)
    }
  }

  func cancelApplyWorkflow() {
    cancelInFlightWorkflowTask()
    model.cancelPendingApply()
    abandonApplyDraftDecision()
  }

  /// Closes an errored apply workflow without pretending to retry it. A saved
  /// retry prompt is intentionally discarded; choosing Apply again rebuilds a
  /// fresh decision from the authoritative profile and current editor state.
  func closeApplyWorkflowAfterError() {
    cancelApplyWorkflow()
    setWorkflowDestination(nil)
  }

  /// Gives every native workflow-window close path the same domain cleanup as
  /// its visible Cancel, Close, or Done action. Capture work that has already
  /// started remains app-lifetime work; only the window-scoped permission wait
  /// and terminal presentation state are consumed.
  func handleWorkflowWindowClose() {
    cancelInFlightWorkflowTask()
    switch workflowDestination {
    case .permission:
      cancelPermissionWorkflow()
      consumeTerminalCapturePhase()

    case .applyPreview:
      if model.safetyConfirmation != nil {
        model.revertHighRiskChanges()
      } else if !model.isApplyTransactionInProgress {
        cancelApplyWorkflow()
      }

    case .resultDetails, .settings, .profileEditor, .none:
      break
    }
    setWorkflowDestination(nil)
  }

  func saveDraftThenApply(_ prompt: TrayApplyDraftPrompt) {
    guard workflowTask == nil else { return }
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
    inFlightApplyDraftPrompt = prompt
    profileEditor.beginSaving()
    let generation = beginWorkflowTaskGeneration()
    workflowTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await persistDraftAndApply(
        candidate,
        prompt: prompt,
        expectsSelectionChange: expectsSelectionChange,
        workflowGeneration: generation
      )
      finishWorkflowTask(generation: generation)
    }
  }

  func discardDraftThenApply(
    _ prompt: TrayApplyDraftPrompt,
    expectedOpenProfileID: UUID
  ) {
    guard workflowTask == nil else { return }
    guard profileEditor.selectedProfileID == expectedOpenProfileID,
      case .selected(let target) = profileEditor.resolvePendingSelection(.discard),
      target.profileID == prompt.targetProfileID
    else {
      applyDraftError = appLocalized(
        "The open profile decision changed before the draft could be discarded.")
      return
    }
    applyDraftPrompt = nil
    let generation = beginWorkflowTaskGeneration()
    workflowTask = Task { @MainActor [weak self] in
      guard let self else { return }
      guard isCurrentWorkflowTask(generation: generation) else { return }
      let selected = await model.selectProfileAndWait(id: prompt.targetProfileID)
      guard isCurrentWorkflowTask(generation: generation) else { return }
      guard selected,
        let targetProfile = model.profiles.first(where: { $0.id == prompt.targetProfileID })
      else {
        applyDraftError = appLocalized("The target profile is no longer available to apply.")
        finishWorkflowTask(generation: generation)
        return
      }
      model.prepareApply(profile: targetProfile, mode: prompt.mode)
      finishWorkflowTask(generation: generation)
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

  private func abandonApplyDraftDecision() {
    let hasOtherDraftDecision = {
      if case .otherDraft? = applyDraftPrompt?.kind {
        return true
      }
      if case .otherDraft? = applyDraftRetryAfterError?.kind {
        return true
      }
      if case .otherDraft? = inFlightApplyDraftPrompt?.kind {
        return true
      }
      return false
    }()
    if hasOtherDraftDecision {
      _ = profileEditor.resolvePendingSelection(.cancel)
    }
    applyDraftPrompt = nil
    applyDraftRetryAfterError = nil
    inFlightApplyDraftPrompt = nil
    applyDraftError = nil
  }

  func saveDraftThenCapture() {
    guard workflowTask == nil else { return }
    permissionWorkflowError = nil
    handoffError = nil
    let generation = beginWorkflowTaskGeneration()
    workflowTask = Task { @MainActor [weak self] in
      guard let self else { return }
      guard isCurrentWorkflowTask(generation: generation) else { return }
      guard profileEditor.session.pendingSelection == nil,
        let candidate = profileEditor.session.saveCandidate()
      else {
        finishWorkflowTask(generation: generation)
        return
      }
      if let validationError = appProfileDraftValidationError(candidate) {
        reportPermissionWorkflowError(validationError)
        finishWorkflowTask(generation: generation)
        return
      }
      profileEditor.beginSaving()
      let result = await saveOperation(candidate)
      guard isCurrentWorkflowTask(generation: generation) else { return }
      switch result {
      case .saved(let persisted):
        guard case .saved = profileEditor.completeSave(with: persisted) else {
          reportPermissionWorkflowError(
            appLocalized("The saved profile did not match the active draft."))
          finishWorkflowTask(generation: generation)
          return
        }
        startCapture()
      case .rejected(let message):
        profileEditor.finishWithError(message)
        reportPermissionWorkflowError(message)
      }
      finishWorkflowTask(generation: generation)
    }
  }

  func discardDraftThenCapture() {
    guard workflowTask == nil else { return }
    profileEditor.revertDraft()
    startCapture()
  }

  func requestLocationAccessAndCapture() {
    guard permissionTask == nil else { return }
    permissionWorkflowNotice = nil
    permissionWorkflowError = nil
    handoffError = nil
    let taskID = UUID()
    permissionTaskID = taskID
    permissionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      guard ownsPermissionTask(taskID), !Task.isCancelled else { return }
      locationPermission.requestAccess()
      if let error = locationPermission.lastError {
        guard ownsPermissionTask(taskID), !Task.isCancelled else { return }
        if locationPermission.authorizationStatus == .denied
          || locationPermission.authorizationStatus == .restricted
        {
          transitionToDeniedLocationWorkflow()
        } else {
          reportPermissionWorkflowError(error)
        }
        finishPermissionTask(taskID)
        return
      }
      for await status in locationPermission.$authorizationStatus.values {
        guard ownsPermissionTask(taskID), !Task.isCancelled else { break }
        switch status {
        case .notDetermined:
          continue
        case .authorizedAlways, .authorized:
          startCapture()
          finishPermissionTask(taskID)
          return
        case .denied, .restricted:
          transitionToDeniedLocationWorkflow()
          finishPermissionTask(taskID)
          return
        @unknown default:
          let message = appLocalized(
            "The location permission state is unknown. Choose Capture Without Wi-Fi or open System Settings."
          )
          permissionWorkflowNotice = message
          setWorkflowDestination(.permission(.captureDenied))
          AccessibilityNotification.Announcement(message).post()
          finishPermissionTask(taskID)
          return
        }
      }
      finishPermissionTask(taskID)
    }
  }

  func openLocationSystemSettings() {
    permissionWorkflowError = nil
    handoffError = nil
    locationPermission.openSystemSettings()
    if let error = locationPermission.lastError {
      reportPermissionWorkflowError(error)
    }
  }

  func cancelPermissionWorkflow() {
    permissionTask?.cancel()
    permissionTask = nil
    permissionTaskID = nil
  }

  func startCapture() {
    guard captureTask == nil else { return }
    permissionWorkflowNotice = nil
    permissionWorkflowError = nil
    handoffError = nil
    transientMessageTask?.cancel()
    transientMessageTask = nil
    capturePhase = .running
    let taskID = UUID()
    captureTaskID = taskID
    captureTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let result = await captureOperation()
      guard ownsCaptureTask(taskID), !Task.isCancelled else {
        finishCaptureTask(taskID)
        return
      }
      finishCapture(result)
      finishCaptureTask(taskID)
    }
  }

  func cancelCapture() {
    captureTask?.cancel()
    captureTask = nil
    captureTaskID = nil
    capturePhase = .idle
  }

  private func cancelDeletion(profileID: UUID) {
    guard deletion.isPending(profileID: profileID) else { return }
    guard !isDeletionInFlight(profileID: profileID) else { return }
    deletion.cancel()
    focusTarget = .delete(profileID)
  }

  private func confirmDeletion(profileID: UUID) async {
    let profiles = model.profiles
    guard let index = profiles.firstIndex(where: { $0.id == profileID }),
      deletion.isPending(profileID: profileID),
      deletionInFlightProfileID == nil
    else { return }

    deletionInFlightProfileID = profileID
    defer {
      if deletionInFlightProfileID == profileID {
        deletionInFlightProfileID = nil
      }
    }

    switch await deleteOperation(profileID) {
    case .deleted:
      guard deletion.confirm(profileID: profileID) else { return }
      if profileEditor.selectedProfileID == profileID {
        if profileEditor.isDirty {
          profileEditor.revertDraft()
        }
        profileEditor.synchronize(
          profiles: model.profiles,
          preferredProfileID: model.selectedProfileID
        )
      }
      let remaining = profiles.filter { $0.id != profileID }
      if remaining.isEmpty {
        focusTarget = .emptyState
      } else {
        focusTarget = .profile(remaining[min(index, remaining.count - 1)].id)
      }
      handoffError = nil

    case .rejected(let message):
      reportHandoffFailure(message)
    }
  }

  private func finishCapture(_ result: ProfileCreationCaptureResult) {
    switch result {
    case .created(_, let summary):
      let message: String
      if summary.status == .complete {
        message = appLocalized("Captured current settings without changing the Mac.")
        capturePhase = .success(message)
        if case .permission? = workflowDestination {
          transientMessageTask?.cancel()
          transientMessageTask = nil
        } else {
          scheduleSuccessMessageDismissal()
        }
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
    let delay = successMessageDismissalDelay
    transientMessageTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard let self, !Task.isCancelled else { return }
      if case .permission? = workflowDestination {
        transientMessageTask = nil
        return
      }
      if case .success = capturePhase {
        capturePhase = .idle
      }
      transientMessageTask = nil
    }
  }

  private func consumeTerminalCapturePhase() {
    switch capturePhase {
    case .success, .partial, .failure:
      transientMessageTask?.cancel()
      transientMessageTask = nil
      capturePhase = .idle
    case .idle, .running:
      break
    }
  }

  private func transitionToDeniedLocationWorkflow() {
    let message = appLocalized(
      "Location access was not granted. Choose Capture Without Wi-Fi or open System Settings."
    )
    handoffError = nil
    permissionWorkflowNotice = message
    permissionWorkflowError = nil
    setWorkflowDestination(.permission(.captureDenied))
    AccessibilityNotification.Announcement(message).post()
  }

  private func reportPermissionWorkflowError(_ message: String) {
    permissionWorkflowNotice = nil
    permissionWorkflowError = message
    reportHandoffFailure(message)
  }

  private func ownsPermissionTask(_ taskID: UUID) -> Bool {
    permissionTaskID == taskID
  }

  private func finishPermissionTask(_ taskID: UUID) {
    guard ownsPermissionTask(taskID) else { return }
    permissionTask = nil
    permissionTaskID = nil
  }

  private func ownsCaptureTask(_ taskID: UUID) -> Bool {
    captureTaskID == taskID
  }

  private func finishCaptureTask(_ taskID: UUID) {
    guard ownsCaptureTask(taskID) else { return }
    captureTask = nil
    captureTaskID = nil
  }

  private func beginWorkflowTaskGeneration() -> UInt64 {
    workflowTaskGeneration &+= 1
    isWorkflowTaskInFlight = true
    return workflowTaskGeneration
  }

  private func isCurrentWorkflowTask(generation: UInt64) -> Bool {
    workflowTaskGeneration == generation && workflowTask != nil && !Task.isCancelled
  }

  private func finishWorkflowTask(generation: UInt64) {
    guard workflowTaskGeneration == generation else { return }
    workflowTask = nil
    isWorkflowTaskInFlight = false
    inFlightApplyDraftPrompt = nil
  }

  private func cancelInFlightWorkflowTask() {
    guard let workflowTask else { return }
    workflowTaskGeneration &+= 1
    workflowTask.cancel()
    self.workflowTask = nil
    isWorkflowTaskInFlight = false
    profileEditor.cancelWorkflowSavingPresentation()
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
    expectsSelectionChange: Bool,
    workflowGeneration: UInt64
  ) async {
    var coordinator = DirtyApplySaveCoordinator(
      targetProfileID: prompt.targetProfileID,
      mode: prompt.mode,
      destination: expectsSelectionChange
        ? .selectedTarget(profileID: prompt.targetProfileID)
        : .persistedTarget
    )
    let result = await saveOperation(candidate)
    guard isCurrentWorkflowTask(generation: workflowGeneration) else { return }
    switch result {
    case .saved(let persisted):
      let completion = profileEditor.completeSave(with: persisted)
      switch coordinator.handle(.saveSucceeded(profile: persisted, completion: completion)) {
      case .prepare(let profile, let mode):
        model.prepareApply(profile: profile, mode: mode)
      case .selectAndPrepare(let profileID, let mode):
        let selected = await model.selectProfileAndWait(id: profileID)
        guard isCurrentWorkflowTask(generation: workflowGeneration) else { return }
        guard selected,
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
