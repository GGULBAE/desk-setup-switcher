import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupSystem)
  import DeskSetupSystem
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

func appLocalized(_ value: String.LocalizationValue) -> String {
  #if SWIFT_PACKAGE
    #if DEBUG
      if let languageCode = ProcessInfo.processInfo.environment["DESK_SETUP_UI_AUDIT_LANGUAGE"],
        let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
        let bundle = Bundle(path: path)
      {
        return String(localized: value, bundle: bundle)
      }
    #endif
    return String(localized: value, bundle: .module)
  #else
    #if DEBUG
      if let languageCode = ProcessInfo.processInfo.environment["DESK_SETUP_UI_AUDIT_LANGUAGE"],
        let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
        let bundle = Bundle(path: path)
      {
        return String(localized: value, bundle: bundle)
      }
    #endif
    return String(localized: value)
  #endif
}

func appReadinessTitle(_ readiness: ProfileReadiness) -> String {
  switch readiness {
  case .ready: appLocalized("Ready")
  case .partial: appLocalized("Partial")
  case .unavailable: appLocalized("Unavailable")
  case .applying: appLocalized("Applying")
  case .applied: appLocalized("Applied")
  case .failed: appLocalized("Failed")
  }
}

func appApplyResultStatusTitle(_ status: ApplyResultOverallStatus) -> String {
  switch status {
  case .success: appLocalized("Applied")
  case .partial: appLocalized("Partially Applied")
  case .failure: appLocalized("Apply Failed")
  case .rolledBack: appLocalized("Rolled Back")
  case .rollbackFailed: appLocalized("Rollback Failed")
  case .notVerified: appLocalized("Not Verified")
  }
}

func appSettingGroupTitle(_ group: SettingGroup) -> String {
  switch group {
  case .display: appLocalized("Displays")
  case .audio: appLocalized("Audio")
  case .network: appLocalized("Network")
  case .input: appLocalized("Mouse & Keyboard")
  }
}

func appApplicationItemStatusTitle(_ status: ApplicationItemStatus) -> String {
  switch status {
  case .succeeded: appLocalized("Succeeded")
  case .failed: appLocalized("Failed")
  case .skipped: appLocalized("Skipped")
  case .unsupported: appLocalized("Unsupported")
  case .rolledBack: appLocalized("Rolled back")
  case .rollbackFailed: appLocalized("Rollback failed")
  }
}

func appApplicationItemTitle(_ key: String) -> String {
  switch key {
  case "display-safety-confirmation": return appLocalized("Display safety confirmation")
  case "high-risk-safety-confirmation": return appLocalized("Protected change confirmation")
  case "display.atomic-configuration": return appLocalized("Complete display configuration")
  case "defaultInput": return appLocalized("Default input device")
  case "defaultOutput": return appLocalized("Default output device")
  case "systemOutput": return appLocalized("System output device")
  case "outputVolume": return appLocalized("Output volume")
  case "outputMute": return appLocalized("Output mute")
  case "wifi.power": return appLocalized("Wi-Fi power")
  case "wifi.ssid": return appLocalized("Wi-Fi network")
  case "network.ipv4": return appLocalized("IPv4 configuration")
  case "network.dns": return appLocalized("DNS servers")
  case "network.webProxy": return appLocalized("Web proxy")
  case "network.secureWebProxy": return appLocalized("Secure web proxy")
  case "com.apple.mouse.scaling": return appLocalized("Pointer speed")
  case "com.apple.swipescrolldirection": return appLocalized("Natural scrolling")
  case "KeyRepeat": return appLocalized("Key repeat")
  case "InitialKeyRepeat": return appLocalized("Initial key repeat delay")
  case "com.apple.keyboard.fnState": return appLocalized("Function-key behavior")
  default:
    if key.hasPrefix("display.") {
      return appLocalized("Display setting")
    }
    return key
  }
}

func appApplicationStatusTitle(
  _ status: ProfileReadiness,
  isAwaitingSafetyConfirmation: Bool
) -> String {
  isAwaitingSafetyConfirmation
    ? appLocalized("Awaiting protected-change confirmation") : appReadinessTitle(status)
}

enum ApplyPreviewReviewReason: Equatable, Sendable {
  case initial
  case refreshedSystemState
}

struct PendingApplyRequest: Identifiable, Sendable {
  let id = UUID()
  let profile: DeskProfile
  let preparation: ApplyPreparation
  let reviewReason: ApplyPreviewReviewReason

  init(
    profile: DeskProfile,
    preparation: ApplyPreparation,
    reviewReason: ApplyPreviewReviewReason = .initial
  ) {
    self.profile = profile
    self.preparation = preparation
    self.reviewReason = reviewReason
  }
}

enum PendingApplyStartFailure: Equatable, Sendable {
  case syntheticMode
  case noPendingRequest
  case transactionLocked

  var defaultMessage: String {
    switch self {
    case .syntheticMode:
      "System access is disabled for this synthetic review."
    case .noPendingRequest:
      "The apply preview is no longer current. Reopen it and try again."
    case .transactionLocked:
      "Another profile or protected-change operation is still in progress."
    }
  }
}

enum PendingApplyStartResult: Equatable, Sendable {
  case started
  case rejected(PendingApplyStartFailure)
}

struct PendingImportRequest: Identifiable, Sendable {
  let id = UUID()
  let imported: ImportedProfileDocument
  let existingProfileCount: Int
}

struct SafetyConfirmationState: Identifiable, Sendable {
  let id: UUID
  let profileID: UUID
  let guardedGroups: [SettingGroup]
  let changeSummaries: [String]
  var secondsRemaining: Int
}

enum ProfileSaveResult: Equatable, Sendable {
  case saved(DeskProfile)
  case rejected(message: String)
}

enum ProfileDeleteResult: Equatable, Sendable {
  case deleted
  case rejected(message: String)
}

enum ProfileSettingsCaptureResult: Equatable, Sendable {
  case captured(snapshot: SystemSnapshotResult, summary: ProfileCaptureSummary)
  case rejected(message: String, summary: ProfileCaptureSummary? = nil)
}

enum ProfileCreationCaptureResult: Equatable, Sendable {
  case created(profile: DeskProfile, summary: ProfileCaptureSummary)
  case rejected(message: String, summary: ProfileCaptureSummary? = nil)
}

private func makeDefaultDiagnosticLog() -> (any DiagnosticLogStoring)? {
  let directory = ProfileStore.defaultDirectoryURL.appendingPathComponent(
    "Diagnostics", isDirectory: true)
  return try? RotatingDiagnosticLogStore(directoryURL: directory)
}

@MainActor
protocol LoginItemServicing: AnyObject {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

@MainActor
private final class SystemLoginItemService: LoginItemServicing {
  var status: SMAppService.Status {
    SMAppService.mainApp.status
  }

  func register() throws {
    try SMAppService.mainApp.register()
  }

  func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}

@MainActor
final class ApplicationModel: ObservableObject {
  @Published private(set) var profiles: [DeskProfile] = []
  @Published private(set) var selectedProfileID: UUID?
  @Published private(set) var lastMessage = appLocalized("No profile has been applied.")
  @Published private(set) var storageStatus = appLocalized("Loading local profiles…")
  @Published private(set) var snapshotStatus = appLocalized(
    "No system snapshot has been captured.")
  @Published private(set) var lastSnapshot: SystemSnapshotResult?
  @Published private(set) var lastConditionContext = ConditionContext()
  @Published private(set) var conditionContextStatus = appLocalized(
    "Readiness facts have not been refreshed yet.")
  @Published private(set) var readinessLastRefreshedAt: Date?
  @Published private(set) var isReadinessRefreshInProgress = false
  @Published private(set) var launchAtLoginDesired = false
  @Published private(set) var loginItemEnabled = false
  @Published private(set) var loginItemStatus = appLocalized("Checking…")
  @Published private(set) var canRetryLoginItemRegistration = false
  @Published private(set) var readinessByProfile: [UUID: ProfileReadiness] = [:]
  @Published private(set) var operationCountByProfile: [UUID: Int] = [:]
  @Published private(set) var forceOperationCountByProfile: [UUID: Int] = [:]
  @Published private(set) var normalApplyAvailableByProfile: [UUID: Bool] = [:]
  @Published private(set) var forceApplyAvailableByProfile: [UUID: Bool] = [:]
  @Published private(set) var normalApplyRejectionReasonsByProfile: [UUID: [ApplyRejectionReason]] =
    [:]
  @Published private(set) var forceApplyRejectionReasonsByProfile: [UUID: [ApplyRejectionReason]] =
    [:]
  @Published private(set) var operationalStatusByProfile: [UUID: ProfileReadiness] = [:]
  @Published private(set) var pendingApply: PendingApplyRequest?
  @Published private(set) var pendingImport: PendingImportRequest?
  @Published private(set) var lastApplyResult: ApplyExecutionResult?
  @Published private(set) var lastApplyVerification: PostApplyVerificationResult?
  @Published private(set) var lastApplySummary: ApplyResultSummary?
  @Published private(set) var lastCaptureSummary: ProfileCaptureSummary?
  @Published private(set) var preparingProfileIDs: Set<UUID> = []
  @Published private(set) var safetyConfirmation: SafetyConfirmationState?
  @Published private(set) var isApplyTransactionInProgress = false
  @Published private(set) var isProfileStoreMutationInProgress = false
  @Published private(set) var diagnosticEntries: [DiagnosticEntry] = []
  @Published private(set) var diagnosticStatus = appLocalized("No local diagnostic events.")

  private let defaults: UserDefaults
  private let profileStore: ProfileStore
  private let profileImportExport: ProfileImportExport
  private let snapshotCoordinator: SystemSnapshotCoordinator
  private let conditionContextProvider: ConditionContextProvider
  private let applyEngine: ApplyEngine
  private let diagnosticLog: (any DiagnosticLogStoring)?
  private let loginItemService: any LoginItemServicing
  private let launchAtLoginPreferenceKey = "launchAtLoginEnabled"
  private let launchAtLoginPreferenceCreatedKey = "launchAtLoginPreferenceCreated"
  private let highRiskSafetyConfirmationKey = "high-risk-safety-confirmation"
  private var hasStarted = false
  private var safetyCountdownTask: Task<Void, Never>?
  private var loginItemOperationFailure: LoginItemOperationFailure?
  private var terminationRequestIsDeferred = false
  private var preparationGate = ProfilePreparationGate()
  private var preparationRequestTracker = LatestPreparationRequestTracker()
  private var preparationTasks: [UUID: Task<Void, Never>] = [:]
  private var preparationRequestIDsByProfile: [UUID: UUID] = [:]
  private var suppressesLiveSystemAccess = false

  var isProfileMutationLocked: Bool {
    isApplyTransactionInProgress
      || isProfileStoreMutationInProgress
      || safetyConfirmation != nil
  }

  var shouldDeferTermination: Bool {
    isApplyTransactionInProgress || isProfileStoreMutationInProgress
      || safetyConfirmation != nil
  }

  private enum LoginItemOperationFailure: Equatable {
    case invalidSignature
    case deniedByUser
    case registration
    case unregistration

    var diagnosticCode: String {
      switch self {
      case .invalidSignature: "invalid-signature"
      case .deniedByUser: "denied-by-user"
      case .registration: "registration-failed"
      case .unregistration: "unregistration-failed"
      }
    }
  }

  init(
    profileStore: ProfileStore = ProfileStore(),
    profileImportExport: ProfileImportExport = ProfileImportExport(),
    snapshotCoordinator: SystemSnapshotCoordinator? = nil,
    conditionContextProvider: ConditionContextProvider = ConditionContextProvider(),
    applyEngine: ApplyEngine? = nil,
    diagnosticLog: (any DiagnosticLogStoring)? = makeDefaultDiagnosticLog(),
    defaults: UserDefaults = .standard,
    loginItemService: (any LoginItemServicing)? = nil
  ) {
    let adapters: [any SystemSettingsAdapter]
    if snapshotCoordinator == nil || applyEngine == nil {
      adapters = LiveAdapterFactory.makeAdapters()
    } else {
      adapters = []
    }
    self.profileStore = profileStore
    self.profileImportExport = profileImportExport
    self.snapshotCoordinator = snapshotCoordinator ?? SystemSnapshotCoordinator(adapters: adapters)
    self.conditionContextProvider = conditionContextProvider
    self.applyEngine =
      applyEngine
      ?? ApplyEngine(registry: (try? AdapterRegistry(adapters)) ?? AdapterRegistry())
    self.diagnosticLog = diagnosticLog
    self.defaults = defaults
    self.loginItemService = loginItemService ?? SystemLoginItemService()
  }

  #if DEBUG
    func configureForUIAudit(_ fixture: UIAuditFixtureState) {
      suppressesLiveSystemAccess = true
      profiles = fixture.profiles
      selectedProfileID = fixture.selectedProfileID
      lastSnapshot = fixture.snapshot
      storageStatus = appLocalized("Synthetic UI audit mode. Nothing is saved or applied.")
      snapshotStatus = appLocalized("System access is disabled for this synthetic review.")
      lastMessage = appLocalized("Synthetic UI audit mode. Nothing is saved or applied.")
      conditionContextStatus = appLocalized("System access is disabled for this synthetic review.")
      readinessLastRefreshedAt = fixture.snapshot.capturedAt
      launchAtLoginDesired = true
      loginItemEnabled = false
      loginItemStatus = appLocalized(
        "Requested; approval is required in System Settings > General > Login Items.")
      canRetryLoginItemRegistration = false
      readinessByProfile = fixture.readinessByProfile
      operationCountByProfile = fixture.operationCountByProfile
      forceOperationCountByProfile = fixture.availableOperationCountByProfile
      normalApplyAvailableByProfile = Dictionary(
        uniqueKeysWithValues: fixture.readinessByProfile.compactMap { profileID, readiness in
          readiness == .ready ? (profileID, true) : nil
        }
      )
      forceApplyAvailableByProfile = Dictionary(
        uniqueKeysWithValues: fixture.readinessByProfile.compactMap { profileID, readiness in
          readiness == .partial ? (profileID, true) : nil
        }
      )
      lastCaptureSummary = fixture.captureSummary
      lastApplySummary = fixture.applySummary
    }
  #endif

  func start() {
    guard !suppressesLiveSystemAccess else { return }
    guard !hasStarted else { return }
    hasStarted = true

    configureDefaultLaunchPreferenceIfNeeded()
    launchAtLoginDesired = defaults.bool(forKey: launchAtLoginPreferenceKey)
    reconcileLoginItemRegistrationAtStartup()

    refreshDiagnostics()

    guard beginProfileStoreMutation() else { return }
    Task {
      defer { finishProfileStoreMutation() }
      await loadProfiles()
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard !suppressesLiveSystemAccess else { return }
    launchAtLoginDesired = enabled
    defaults.set(enabled, forKey: launchAtLoginPreferenceKey)
    loginItemOperationFailure = nil

    updateLoginItemRegistration(enabled: enabled)
    recordDiagnostic(
      severity: .info,
      component: "login-item",
      code: enabled ? "requested" : "opted-out",
      message: appLocalized("The user login item preference changed.")
    )
  }

  func retryLaunchAtLoginRegistration() {
    guard !suppressesLiveSystemAccess else { return }
    guard launchAtLoginDesired else { return }
    loginItemOperationFailure = nil
    updateLoginItemRegistration(enabled: true)
  }

  func refreshLoginItemStatusFromSystem() {
    guard !suppressesLiveSystemAccess else { return }
    refreshLoginItemStatus()
  }

  private func updateLoginItemRegistration(enabled: Bool) {
    let status = loginItemService.status

    do {
      if enabled {
        if status != .enabled, status != .requiresApproval {
          try loginItemService.register()
        }
      } else if status == .enabled || status == .requiresApproval {
        try loginItemService.unregister()
      }
      loginItemOperationFailure = nil
      refreshLoginItemStatus()
      recordDiagnostic(
        severity: .info,
        component: "login-item",
        code: enabled ? "registration-attempted" : "unregistration-attempted",
        message: appLocalized("The login item request was sent to macOS.")
      )
    } catch {
      loginItemOperationFailure = loginItemFailure(for: error, enabling: enabled)
      refreshLoginItemStatus()
      recordDiagnostic(
        severity: .warning,
        component: "login-item",
        code: loginItemOperationFailure?.diagnosticCode ?? "update-failed",
        message: appLocalized("The login item preference could not be updated.")
      )
    }
  }

  func refreshReadinessFacts() {
    guard !suppressesLiveSystemAccess else { return }
    guard !isProfileMutationLocked, !isReadinessRefreshInProgress else { return }
    isReadinessRefreshInProgress = true
    Task {
      await refreshReadiness()
      isReadinessRefreshInProgress = false
    }
  }

  func createProfile() {
    guard !suppressesLiveSystemAccess else { return }
    guard beginProfileStoreMutation() else { return }
    Task {
      defer { finishProfileStoreMutation() }
      do {
        let profile = DeskProfile(name: appLocalized("New Profile \(profiles.count + 1)"))
        let created = try await profileStore.createProfile(profile, selecting: true)
        await refreshProfiles(message: appLocalized("Created \(created.name)."))
      } catch {
        reportStorageError(error)
      }
    }
  }

  func updateProfile(_ saveCandidate: DeskProfile) async -> ProfileSaveResult {
    if suppressesLiveSystemAccess {
      return .rejected(
        message: appLocalized("System access is disabled for this synthetic review."))
    }
    if let validationError = appProfileDraftValidationError(saveCandidate) {
      reportProfileEditorFailure(code: "save-validation-failed", message: validationError)
      return .rejected(message: validationError)
    }
    guard beginProfileStoreMutation() else {
      return .rejected(message: profileEditingLockedMessage)
    }
    defer { finishProfileStoreMutation() }

    let document = await profileStore.currentDocument()
    guard let authoritativeProfile = document.profiles.first(where: { $0.id == saveCandidate.id })
    else {
      let message = appLocalized("The selected profile no longer exists.")
      reportProfileEditorFailure(code: "save-profile-missing", message: message)
      return .rejected(message: message)
    }

    let mergedCandidate = mergeUserEditableProfileValues(
      from: saveCandidate,
      metadataFrom: authoritativeProfile
    )

    do {
      let updated = try await profileStore.updateProfile(mergedCandidate)
      await refreshProfiles(message: appLocalized("Saved \(updated.name)."))
      return .saved(updated)
    } catch {
      let message = profileStorageUserMessage(for: error)
      reportProfileEditorFailure(code: "save-failed", message: message)
      return .rejected(message: message)
    }
  }

  func duplicateProfile(id: UUID) {
    guard !suppressesLiveSystemAccess else { return }
    guard beginProfileStoreMutation() else { return }
    Task {
      defer { finishProfileStoreMutation() }
      do {
        let duplicate = try await profileStore.duplicateProfile(id: id)
        try await profileStore.selectProfile(id: duplicate.id)
        await refreshProfiles(message: appLocalized("Duplicated \(duplicate.name)."))
      } catch {
        reportStorageError(error)
      }
    }
  }

  func deleteProfile(id: UUID) async -> ProfileDeleteResult {
    if suppressesLiveSystemAccess {
      return .rejected(
        message: appLocalized("System access is disabled for this synthetic review."))
    }
    guard beginProfileStoreMutation() else {
      return .rejected(message: profileEditingLockedMessage)
    }
    defer { finishProfileStoreMutation() }

    do {
      try await profileStore.deleteProfile(id: id)
      await refreshProfiles(message: appLocalized("Deleted the profile."))
      return .deleted
    } catch {
      let message = profileStorageUserMessage(for: error)
      reportProfileEditorFailure(code: "delete-failed", message: message)
      return .rejected(message: message)
    }
  }

  func moveProfile(id: UUID, by offset: Int) {
    guard !suppressesLiveSystemAccess else { return }
    guard let currentIndex = profiles.firstIndex(where: { $0.id == id }) else { return }
    let destination = currentIndex + offset
    guard profiles.indices.contains(destination) else { return }
    guard beginProfileStoreMutation() else { return }

    Task {
      defer { finishProfileStoreMutation() }
      do {
        try await profileStore.moveProfile(id: id, toIndex: destination)
        await refreshProfiles(message: appLocalized("Reordered profiles."))
      } catch {
        reportStorageError(error)
      }
    }
  }

  func selectProfile(id: UUID?) {
    if suppressesLiveSystemAccess {
      selectedProfileID = id
      return
    }
    guard beginProfileStoreMutation() else { return }
    selectedProfileID = id
    Task {
      defer { finishProfileStoreMutation() }
      do {
        try await profileStore.selectProfile(id: id)
      } catch {
        await refreshProfiles()
        reportStorageError(error)
      }
    }
  }

  /// Persists a selection before a protected cross-profile apply continues.
  /// The awaited variant prevents the apply plan from racing a pending store
  /// mutation and keeps the process-lifetime editor selection authoritative.
  func selectProfileAndWait(id: UUID?) async -> Bool {
    if suppressesLiveSystemAccess {
      selectedProfileID = id
      return true
    }
    guard beginProfileStoreMutation() else { return false }
    defer { finishProfileStoreMutation() }
    selectedProfileID = id
    do {
      try await profileStore.selectProfile(id: id)
      return true
    } catch {
      await refreshProfiles()
      reportStorageError(error)
      return false
    }
  }

  func importProfiles() {
    guard !suppressesLiveSystemAccess else { return }
    guard !isProfileMutationLocked else { return }
    let panel = NSOpenPanel()
    panel.title = appLocalized("Import Desk Setup Profiles")
    panel.prompt = appLocalized("Import")
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
    guard beginProfileStoreMutation() else { return }

    Task {
      defer { finishProfileStoreMutation() }
      do {
        let importer = profileImportExport
        let imported = try await Task.detached {
          try importer.importDocument(from: sourceURL)
        }.value
        pendingImport = PendingImportRequest(
          imported: imported,
          existingProfileCount: profiles.count
        )
      } catch {
        reportStorageError(error)
      }
    }
  }

  func confirmImportReplacement() {
    guard !suppressesLiveSystemAccess else {
      pendingImport = nil
      return
    }
    guard let request = pendingImport, beginProfileStoreMutation() else { return }
    pendingImport = nil
    Task {
      defer { finishProfileStoreMutation() }
      do {
        try await profileStore.replaceAll(with: request.imported.document)
        await refreshProfiles(
          message: appLocalized(
            "Imported \(request.imported.document.profiles.count) profiles."))
      } catch {
        reportStorageError(error)
      }
    }
  }

  func cancelImportReplacement() {
    pendingImport = nil
  }

  func exportProfiles() {
    guard !suppressesLiveSystemAccess else { return }
    let panel = NSSavePanel()
    panel.title = appLocalized("Export Desk Setup Profiles")
    panel.prompt = appLocalized("Export")
    panel.nameFieldStringValue = "Desk-Setup-Profiles.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

    Task {
      do {
        let document = await profileStore.currentDocument()
        let exporter = profileImportExport
        try await Task.detached {
          try exporter.export(document, to: destinationURL)
        }.value
        storageStatus = appLocalized("Exported profiles to a user-selected file.")
      } catch {
        reportStorageError(error)
      }
    }
  }

  func createProfileFromCurrentSettings() async -> ProfileCreationCaptureResult {
    if suppressesLiveSystemAccess {
      return .rejected(
        message: appLocalized("System access is disabled for this synthetic review."),
        summary: lastCaptureSummary
      )
    }
    guard beginProfileStoreMutation() else {
      return .rejected(message: profileEditingLockedMessage)
    }
    defer { finishProfileStoreMutation() }
    lastCaptureSummary = nil
    snapshotStatus = appLocalized("Reading current settings without changing them…")

    let snapshot = await snapshotCoordinator.capture()
    lastSnapshot = snapshot
    snapshotStatus = snapshotSummary(snapshot)
    recordSnapshotDiagnostic(snapshot)
    let captureSummary = profileCaptureSummary(snapshot)

    guard
      captureSummary.canCreateProfile,
      SettingGroup.safeApplicationSequence.contains(where: {
        snapshot.profileSettings.payload(for: $0) != nil
      })
    else {
      lastCaptureSummary = captureSummary
      return .rejected(
        message: appLocalized("No settings could be added safely from this snapshot."),
        summary: captureSummary
      )
    }

    do {
      let profile = DeskProfile(
        name: appLocalized("Current Setup \(profiles.count + 1)"),
        profileDescription: appLocalized("Created from a read-only system snapshot."),
        settings: snapshot.profileSettings
      )
      let created = try await profileStore.createProfile(profile, selecting: true)
      await refreshProfiles(
        message: appLocalized("Created \(created.name) from the current settings."))
      lastCaptureSummary = captureSummary
      return .created(profile: created, summary: captureSummary)
    } catch {
      let message = profileStorageUserMessage(for: error)
      reportStorageError(error)
      return .rejected(message: message)
    }
  }

  func captureCurrentProfileSettings() async -> ProfileSettingsCaptureResult {
    if suppressesLiveSystemAccess {
      return .rejected(
        message: appLocalized("System access is disabled for this synthetic review."),
        summary: lastCaptureSummary
      )
    }
    guard beginProfileStoreMutation() else {
      return .rejected(message: profileEditingLockedMessage)
    }
    defer { finishProfileStoreMutation() }
    lastCaptureSummary = nil
    snapshotStatus = appLocalized("Reading current settings without changing them…")

    let snapshot = await snapshotCoordinator.capture()
    lastSnapshot = snapshot
    snapshotStatus = snapshotSummary(snapshot)
    recordSnapshotDiagnostic(snapshot)
    let captureSummary = profileCaptureSummary(snapshot)
    guard captureSummary.canCreateProfile else {
      lastCaptureSummary = captureSummary
      return .rejected(
        message: appLocalized("No settings could be added safely from this snapshot."),
        summary: captureSummary
      )
    }
    lastCaptureSummary = captureSummary
    return .captured(snapshot: snapshot, summary: captureSummary)
  }

  func dismissCaptureSummary() {
    lastCaptureSummary = nil
  }

  func dismissApplySummary() {
    lastApplySummary = nil
    lastApplyVerification = nil
  }

  func readiness(for profile: DeskProfile) -> ProfileReadiness {
    ProfileStatusLifetime.visibleReadiness(
      calculated: readinessByProfile[profile.id],
      operational: operationalStatusByProfile[profile.id]
    )
  }

  func isPreparingApply(for profile: DeskProfile) -> Bool {
    preparingProfileIDs.contains(profile.id)
  }

  func canApplyNormally(_ profile: DeskProfile) -> Bool {
    readinessByProfile[profile.id] == .ready
      && normalApplyAvailableByProfile[profile.id] == true
      && operationalStatusByProfile[profile.id] != .applying
      && !isProfileMutationLocked
  }

  func canForceApply(_ profile: DeskProfile) -> Bool {
    readinessByProfile[profile.id] == .partial
      && forceApplyAvailableByProfile[profile.id] == true
      && operationalStatusByProfile[profile.id] != .applying
      && !isProfileMutationLocked
  }

  func prepareApply(profile: DeskProfile, mode: ApplyMode) {
    guard !suppressesLiveSystemAccess else { return }
    guard !isProfileMutationLocked, preparationGate.begin(profileID: profile.id) else { return }
    let requestID = UUID()
    preparationRequestTracker.begin(requestID: requestID)
    preparationRequestIDsByProfile[profile.id] = requestID
    preparingProfileIDs = preparationGate.activeProfileIDs
    operationalStatusByProfile[profile.id] = nil
    lastMessage = appLocalized("Calculating a read-only change plan for \(profile.name)…")
    preparationTasks[profile.id] = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        finishPreparationTask(profileID: profile.id, requestID: requestID)
      }
      let preparation = await applyEngine.prepare(
        profile: profile,
        mode: mode,
        conditionsSatisfied: true
      )
      guard !Task.isCancelled,
        preparationRequestTracker.shouldPresent(requestID: requestID),
        preparationRequestIDsByProfile[profile.id] == requestID
      else { return }
      pendingApply = PendingApplyRequest(
        profile: profile,
        preparation: preparation
      )
      readinessByProfile[profile.id] = preparation.readiness.status
      let isAvailable = preparation.canExecute && !preparation.operations.isEmpty
      if mode == .normal {
        operationCountByProfile[profile.id] = preparation.operations.count
        normalApplyAvailableByProfile[profile.id] = isAvailable
        normalApplyRejectionReasonsByProfile[profile.id] = preparation.rejectionReasons
      } else {
        forceOperationCountByProfile[profile.id] = preparation.operations.count
        forceApplyAvailableByProfile[profile.id] = isAvailable
        forceApplyRejectionReasonsByProfile[profile.id] = preparation.rejectionReasons
      }
      lastMessage =
        preparation.canExecute
        ? appLocalized("Review the planned changes before applying \(profile.name).")
        : appLocalized("The change plan explains why \(profile.name) cannot be applied.")
    }
  }

  func cancelPendingApply() {
    preparationRequestTracker.invalidate()
    for task in preparationTasks.values {
      task.cancel()
    }
    preparationTasks.removeAll()
    preparationRequestIDsByProfile.removeAll()
    preparationGate = ProfilePreparationGate()
    preparingProfileIDs = []
    pendingApply = nil
  }

  private func finishPreparationTask(profileID: UUID, requestID: UUID) {
    guard preparationRequestIDsByProfile[profileID] == requestID else { return }
    preparationRequestIDsByProfile[profileID] = nil
    preparationTasks[profileID] = nil
    preparationGate.end(profileID: profileID)
    preparingProfileIDs = preparationGate.activeProfileIDs
  }

  @discardableResult
  func executePendingApply() -> PendingApplyStartResult {
    guard !suppressesLiveSystemAccess else { return .rejected(.syntheticMode) }
    guard let request = pendingApply else { return .rejected(.noPendingRequest) }
    guard !isProfileMutationLocked else { return .rejected(.transactionLocked) }
    pendingApply = nil
    lastApplySummary = nil
    lastApplyVerification = nil
    isApplyTransactionInProgress = true
    operationalStatusByProfile[request.profile.id] = .applying
    lastMessage = appLocalized(
      "Checking current system state before applying \(request.profile.name)…")

    Task {
      defer { finishApplyTransaction() }
      guard let currentProfile = profiles.first(where: { $0.id == request.profile.id }) else {
        let message = appLocalized("The profile was removed before it could be applied.")
        let result = ApplyRequestFailureResultBuilder().result(
          preparation: request.preparation,
          completedAt: Date(),
          message: message
        )
        lastApplyResult = result
        lastApplyVerification = nil
        publishApplySummary(
          ApplyResultSummary(
            profileID: request.profile.id,
            profileName: request.profile.name,
            appliedAt: result.completedAt,
            itemResults: result.itemResults
          )
        )
        operationalStatusByProfile[request.profile.id] = nil
        lastMessage = message
        recordDiagnostic(
          severity: .warning,
          component: "apply",
          code: "profile-removed-before-execution",
          message: appLocalized("An apply request ended before any setting was changed.")
        )
        return
      }

      let currentPreparation = await applyEngine.prepare(
        profile: currentProfile,
        mode: request.preparation.mode,
        conditionsSatisfied: true
      )

      guard currentProfile == request.profile,
        currentPreparation.isExecutionEquivalent(to: request.preparation)
      else {
        operationalStatusByProfile[request.profile.id] = nil
        pendingApply = PendingApplyRequest(
          profile: currentProfile,
          preparation: currentPreparation,
          reviewReason: .refreshedSystemState
        )
        readinessByProfile[currentProfile.id] = currentPreparation.readiness.status
        let isAvailable =
          currentPreparation.canExecute && !currentPreparation.operations.isEmpty
        if currentPreparation.mode == .normal {
          operationCountByProfile[currentProfile.id] = currentPreparation.operations.count
          normalApplyAvailableByProfile[currentProfile.id] = isAvailable
          normalApplyRejectionReasonsByProfile[currentProfile.id] =
            currentPreparation.rejectionReasons
        } else {
          forceOperationCountByProfile[currentProfile.id] = currentPreparation.operations.count
          forceApplyAvailableByProfile[currentProfile.id] = isAvailable
          forceApplyRejectionReasonsByProfile[currentProfile.id] =
            currentPreparation.rejectionReasons
        }
        lastMessage = appLocalized(
          "The system or profile changed. Review the refreshed plan before applying.")
        recordDiagnostic(
          severity: .info,
          component: "apply",
          code: "plan-refreshed-before-execution",
          message: appLocalized(
            "The read-only apply plan was refreshed before any setting was changed.")
        )
        return
      }

      lastMessage = appLocalized("Applying \(currentProfile.name)…")
      let result = await applyEngine.execute(currentPreparation)
      let safetyConfirmationID = result.safetyConfirmationID
      var presentedResult = result
      var verification: PostApplyVerificationResult?
      if safetyConfirmationID != nil {
        presentedResult.status = .applying
        presentedResult.itemResults.append(
          makeSafetyOutcomeItem(
            status: .succeeded,
            message: appLocalized(
              "Protected changes are temporary and are waiting for confirmation.")
          )
        )
      } else if result.didExecute {
        verification = await verifySuccessfulOperations(
          in: result,
          against: currentProfile
        )
        if verification?.notVerifiedCount ?? 0 > 0,
          presentedResult.status == .applied
        {
          presentedResult.status = .partial
        }
      }
      lastApplyResult = presentedResult
      if safetyConfirmationID == nil {
        if let finalStatus = updateLastApplyPresentation(
          profile: currentProfile,
          verification: verification
        ) {
          presentedResult.status = finalStatus
          lastApplyResult?.status = finalStatus
        }
      }
      operationalStatusByProfile[currentProfile.id] = presentedResult.status
      if let safetyConfirmationID {
        armSafetyCountdown(
          confirmationID: safetyConfirmationID,
          profileID: currentProfile.id,
          operations: currentPreparation.operations
        )
      }

      if result.didExecute {
        if safetyConfirmationID != nil {
          lastMessage = appLocalized(
            "Protected changes for \(currentProfile.name) are temporary. Confirm or revert them within 15 seconds."
          )
        } else {
          if let count = verification?.notVerifiedCount, count > 0 {
            lastMessage = appLocalized(
              "Applied \(currentProfile.name), but \(count) settings could not be verified by read-back."
            )
          } else {
            lastMessage =
              presentedResult.status == .applied
              ? appLocalized("Applied \(currentProfile.name).")
              : presentedResult.status == .partial
                ? appLocalized(
                  "\(currentProfile.name) finished with failed, skipped, unavailable, or unverified settings."
                )
                : appLocalized("\(currentProfile.name) finished with failures.")
          }
        }
        await persistApplicationSummary(
          presentedResult.applicationSummary,
          profileID: currentProfile.id
        )
      } else {
        lastMessage = appLocalized("\(currentProfile.name) was not applied.")
      }

      if safetyConfirmationID == nil {
        await refreshReadiness()
      }
      recordDiagnostic(
        severity:
          presentedResult.status == .failed
          ? .error
          : verification?.notVerifiedCount ?? 0 > 0 ? .warning : .info,
        component: "apply-engine",
        code:
          verification?.notVerifiedCount ?? 0 > 0
          ? "read-back-not-verified" : presentedResult.status.rawValue,
        message:
          appLocalized(
            "Apply completed with \(result.itemResults.count) item results and \(result.rollbackResults.count) immediate rollback results."
          )
      )
    }
    return .started
  }

  func deferTerminationUntilApplyCompletes() {
    guard shouldDeferTermination else { return }
    terminationRequestIsDeferred = true
    lastMessage = appLocalized(
      "Quit is waiting for the current protected operation to be safely recorded.")
    if !isApplyTransactionInProgress, safetyConfirmation != nil {
      revertHighRiskChanges()
    }
  }

  func confirmHighRiskChanges() {
    guard !suppressesLiveSystemAccess else { return }
    guard let state = safetyConfirmation, !isApplyTransactionInProgress else { return }
    safetyCountdownTask?.cancel()
    safetyCountdownTask = nil
    isApplyTransactionInProgress = true

    Task {
      defer { finishApplyTransaction() }
      let resolution = await applyEngine.confirmSafetyRollback(state.id)
      let outcome: SafetyOutcome
      switch resolution.status {
      case .confirmed:
        safetyConfirmation = nil
        operationalStatusByProfile[state.profileID] = .applied
        lastMessage = appLocalized("Kept the protected changes.")
        outcome = SafetyOutcome(
          profileStatus: .applied,
          itemStatus: .succeeded,
          message: appLocalized("The user confirmed and kept the protected changes.")
        )
      case .confirmationFailed:
        safetyConfirmation = nil
        operationalStatusByProfile[state.profileID] = .partial
        lastMessage = appLocalized(
          "The protected settings could not be committed, so the previous configuration was restored."
        )
        outcome = SafetyOutcome(
          profileStatus: .partial,
          itemStatus: .rolledBack,
          message: appLocalized(
            "Confirmation failed and the previous configuration was restored.")
        )
      case .rollbackFailed:
        safetyConfirmation = nil
        operationalStatusByProfile[state.profileID] = .failed
        lastMessage = appLocalized(
          "The protected settings could not be committed or fully restored. Review diagnostics immediately."
        )
        outcome = SafetyOutcome(
          profileStatus: .failed,
          itemStatus: .rollbackFailed,
          message: appLocalized(
            "Confirmation failed and the previous configuration could not be fully restored."
          )
        )
      case .unknownOrExpired:
        safetyConfirmation = nil
        operationalStatusByProfile[state.profileID] = .partial
        lastMessage = appLocalized("The protected-change confirmation had already expired.")
        outcome = SafetyOutcome(
          profileStatus: .partial,
          itemStatus: .skipped,
          message: appLocalized(
            "The confirmation outcome was unavailable. Verify the current system configuration."
          )
        )
      case .transactionInProgress:
        armSafetyCountdown(confirmationID: state.id, profileID: state.profileID)
        lastMessage = appLocalized(
          "Protected-change confirmation is busy; the safety timer was restarted.")
        return
      case .reverted:
        safetyConfirmation = nil
        operationalStatusByProfile[state.profileID] = .partial
        lastMessage = appLocalized("Restored the previous configuration.")
        outcome = SafetyOutcome(
          profileStatus: .partial,
          itemStatus: .rolledBack,
          message: appLocalized("The previous configuration was restored.")
        )
      }

      var summary = resolveSafetyOutcome(
        outcome,
        rollbackResults: resolution.rollbackResults,
        profileID: state.profileID
      )
      var verification: PostApplyVerificationResult?
      if resolution.status == .confirmed,
        let profile = profiles.first(where: { $0.id == state.profileID }),
        let result = lastApplyResult
      {
        verification = await verifySuccessfulOperations(in: result, against: profile)
        if verification?.notVerifiedCount ?? 0 > 0 {
          if lastApplyResult?.status == .applied {
            lastApplyResult?.status = .partial
          }
          if summary.status == .applied {
            summary.status = .partial
          }
        }
      }
      if let profile = profiles.first(where: { $0.id == state.profileID }) {
        if let finalStatus = updateLastApplyPresentation(
          profile: profile,
          verification: verification
        ) {
          summary.status = finalStatus
          lastApplyResult?.status = finalStatus
        }
      }
      if resolution.status == .confirmed {
        switch ConfirmedSafetyMessageKind(
          status: summary.status,
          notVerifiedCount: verification?.notVerifiedCount ?? 0
        ) {
        case .kept:
          lastMessage = appLocalized("Kept the protected changes.")
        case .partial:
          lastMessage = appLocalized(
            "The protected changes were kept, but some settings failed, were skipped, or were unavailable."
          )
        case .failed:
          lastMessage = appLocalized(
            "The protected changes were kept, but one or more other profile items failed."
          )
        case .notVerified:
          lastMessage = appLocalized(
            "The protected changes were kept, but read-back could not verify every applied setting."
          )
        }
      }
      operationalStatusByProfile[state.profileID] = summary.status
      await persistApplicationSummary(summary, profileID: state.profileID)
      recordDiagnostic(
        severity: resolution.status == .confirmed ? .info : .warning,
        component: "high-risk-safety",
        code: resolution.status.rawValue,
        message: appLocalized("The guarded high-risk change confirmation was resolved.")
      )
      await refreshReadiness()
    }
  }

  func revertHighRiskChanges() {
    guard !suppressesLiveSystemAccess else { return }
    guard let state = safetyConfirmation else { return }
    safetyCountdownTask?.cancel()
    safetyCountdownTask = nil
    Task {
      await revertHighRiskChanges(state)
    }
  }

  private func loadProfiles() async {
    do {
      let result = try await profileStore.load()
      profiles = result.document.profiles
      selectedProfileID = result.document.selectedProfileID
      storageStatus = storageMessage(for: result.status)
      recordDiagnostic(
        severity: .info,
        component: "profile-storage",
        code: "loaded",
        message: storageDiagnosticMessage(for: result.status)
      )
      let recoveredInterruptedConfirmation = await reconcileInterruptedSafetyConfirmation()
      if profiles.isEmpty {
        let snapshot = await snapshotCoordinator.capture()
        lastSnapshot = snapshot
        snapshotStatus = snapshotSummary(snapshot)
        lastMessage = appLocalized(
          "No profiles yet. Capture the current settings to create the first profile.")
        recordSnapshotDiagnostic(snapshot)
      } else if recoveredInterruptedConfirmation {
        lastMessage = appLocalized(
          "A protected-change confirmation was interrupted. Temporary app-scoped changes should have reverted; verify the current system configuration."
        )
      }
      await refreshReadiness()
    } catch {
      reportStorageError(error)
    }
  }

  private func refreshProfiles(message: String? = nil) async {
    let document = await profileStore.currentDocument()
    profiles = document.profiles
    selectedProfileID = document.selectedProfileID
    if let message {
      storageStatus = message
    }
    await refreshReadiness()
  }

  private func refreshReadiness() async {
    _ = await captureReadinessContext()
    // Editor choices such as friendly audio names and supported display modes
    // come from a separate read-only snapshot. The profile plans below remain
    // authoritative for execution and never reuse this UI catalog as host state.
    let editorSnapshot = await snapshotCoordinator.capture()
    lastSnapshot = editorSnapshot
    snapshotStatus = snapshotSummary(editorSnapshot)
    guard !profiles.isEmpty else {
      readinessByProfile = [:]
      operationCountByProfile = [:]
      forceOperationCountByProfile = [:]
      normalApplyAvailableByProfile = [:]
      forceApplyAvailableByProfile = [:]
      normalApplyRejectionReasonsByProfile = [:]
      forceApplyRejectionReasonsByProfile = [:]
      operationalStatusByProfile = [:]
      return
    }

    var statuses: [UUID: ProfileReadiness] = [:]
    var operationCounts: [UUID: Int] = [:]
    var forceOperationCounts: [UUID: Int] = [:]
    var normalAvailability: [UUID: Bool] = [:]
    var forceAvailability: [UUID: Bool] = [:]
    var normalRejectionReasons: [UUID: [ApplyRejectionReason]] = [:]
    var forceRejectionReasons: [UUID: [ApplyRejectionReason]] = [:]
    for profile in profiles {
      let preparation = await applyEngine.prepare(
        profile: profile,
        mode: .normal,
        conditionsSatisfied: true
      )
      statuses[profile.id] = preparation.readiness.status
      operationCounts[profile.id] = preparation.operations.count
      normalAvailability[profile.id] =
        preparation.canExecute && !preparation.operations.isEmpty
      normalRejectionReasons[profile.id] = preparation.rejectionReasons
      if preparation.readiness.status == .partial {
        let forcePreparation = await applyEngine.prepare(
          profile: profile,
          mode: .force,
          conditionsSatisfied: true
        )
        forceAvailability[profile.id] =
          forcePreparation.canExecute && !forcePreparation.operations.isEmpty
        forceOperationCounts[profile.id] = forcePreparation.operations.count
        forceRejectionReasons[profile.id] = forcePreparation.rejectionReasons
      } else {
        forceAvailability[profile.id] = false
        forceOperationCounts[profile.id] = 0
        forceRejectionReasons[profile.id] = preparation.rejectionReasons
      }
    }
    readinessByProfile = statuses
    operationCountByProfile = operationCounts
    forceOperationCountByProfile = forceOperationCounts
    normalApplyAvailableByProfile = normalAvailability
    forceApplyAvailableByProfile = forceAvailability
    normalApplyRejectionReasonsByProfile = normalRejectionReasons
    forceApplyRejectionReasonsByProfile = forceRejectionReasons
    operationalStatusByProfile = ProfileStatusLifetime.retainingActiveOperations(
      operationalStatusByProfile
    )
  }

  private func captureReadinessContext() async -> ConditionContext {
    let result = await conditionContextProvider.discover()
    lastConditionContext = result.context
    conditionContextStatus =
      result.unavailableSources.isEmpty
      ? appLocalized("Readiness facts are current.")
      : appLocalized(
        "Readiness facts were refreshed with \(result.unavailableSources.count) unavailable sources."
      )
    readinessLastRefreshedAt = Date()
    return result.context
  }

  private func persistApplicationSummary(
    _ summary: ApplicationSummary,
    profileID: UUID
  ) async {
    guard var profile = profiles.first(where: { $0.id == profileID }) else { return }
    profile.lastApplication = summary
    do {
      _ = try await profileStore.updateProfile(profile)
      profiles = await profileStore.currentDocument().profiles
    } catch {
      reportStorageError(error)
    }
  }

  private func verifySuccessfulOperations(
    in result: ApplyExecutionResult,
    against profile: DeskProfile
  ) async -> PostApplyVerificationResult {
    let successfulOperations = PostApplyVerificationResult.readBackTargets(in: result)
    guard !successfulOperations.isEmpty else {
      return PostApplyVerificationResult.classify(
        executedOperations: [],
        readBackPreparation: result.preparation,
        intentionalOmissions:
          result.preparation.mode == .force ? result.preparation.omissions : []
      )
    }

    // `prepare` performs fresh read-only snapshots before planning. Reusing the
    // same mode keeps force omissions intentional while detecting any executed
    // target that still appears as a required operation.
    let readBackPreparation = await applyEngine.prepare(
      profile: profile,
      mode: result.preparation.mode,
      conditionsSatisfied: true
    )
    return PostApplyVerificationResult.classify(
      executedOperations: successfulOperations,
      readBackPreparation: readBackPreparation,
      intentionalOmissions:
        result.preparation.mode == .force ? result.preparation.omissions : []
    )
  }

  private func updateLastApplyPresentation(
    profile: DeskProfile,
    verification: PostApplyVerificationResult?
  ) -> ProfileReadiness? {
    lastApplyVerification = verification
    guard let result = lastApplyResult, result.preparation.profileID == profile.id else {
      lastApplySummary = nil
      return nil
    }
    let summary = ApplyResultSummary(
      profileID: profile.id,
      profileName: profile.name,
      appliedAt: result.completedAt,
      itemResults: result.itemResults,
      rollbackResults: result.rollbackResults,
      verification: verification
    )
    publishApplySummary(summary)
    return summary.status.profileReadiness
  }

  private func publishApplySummary(_ summary: ApplyResultSummary) {
    lastApplySummary = summary
    let announcement = appLocalized(
      "\(appApplyResultStatusTitle(summary.status)) for \(summary.profileName). \(summary.succeededCount) succeeded, \(summary.failedCount) failed, \(summary.notVerifiedCount) not verified."
    )
    AccessibilityNotification.Announcement(announcement).post()
  }

  private func armSafetyCountdown(
    confirmationID: UUID,
    profileID: UUID,
    operations: [PlannedOperation]? = nil
  ) {
    safetyCountdownTask?.cancel()
    let existing = safetyConfirmation?.id == confirmationID ? safetyConfirmation : nil
    let highRiskOperations = (operations ?? lastApplyResult?.preparation.operations ?? [])
      .filter { $0.risk == .high }
    let guardedGroups =
      existing?.guardedGroups
      ?? Array(Set(highRiskOperations.map(\.group))).sorted { $0.rawValue < $1.rawValue }
    let changeSummaries =
      existing?.changeSummaries
      ?? highRiskOperations.map(\.summary)
    safetyConfirmation = SafetyConfirmationState(
      id: confirmationID,
      profileID: profileID,
      guardedGroups: guardedGroups,
      changeSummaries: changeSummaries,
      secondsRemaining: 15
    )

    safetyCountdownTask = Task { [weak self] in
      for remaining in stride(from: 14, through: 0, by: -1) {
        do {
          try await Task.sleep(for: .seconds(1))
        } catch {
          return
        }
        guard let self, self.safetyConfirmation?.id == confirmationID else { return }
        self.safetyConfirmation?.secondsRemaining = remaining
      }
      guard let self, let state = self.safetyConfirmation, state.id == confirmationID else {
        return
      }
      await self.revertHighRiskChanges(state)
    }
  }

  private func revertHighRiskChanges(_ state: SafetyConfirmationState) async {
    guard !isApplyTransactionInProgress else {
      armSafetyCountdown(confirmationID: state.id, profileID: state.profileID)
      return
    }
    isApplyTransactionInProgress = true
    defer { finishApplyTransaction() }

    let resolution = await applyEngine.revertSafetyRollback(state.id)

    if resolution.status == .transactionInProgress {
      armSafetyCountdown(confirmationID: state.id, profileID: state.profileID)
      lastMessage = appLocalized(
        "Protected-change confirmation is busy; the safety timer was restarted.")
      return
    }

    safetyConfirmation = nil
    safetyCountdownTask = nil

    if resolution.status == .unknownOrExpired {
      operationalStatusByProfile[state.profileID] = .partial
      lastMessage = appLocalized("The protected-change confirmation had already expired.")
      var summary = resolveSafetyOutcome(
        SafetyOutcome(
          profileStatus: .partial,
          itemStatus: .skipped,
          message: appLocalized(
            "The rollback outcome was unavailable. Verify the current system configuration.")
        ),
        rollbackResults: [],
        profileID: state.profileID
      )
      operationalStatusByProfile[state.profileID] = summary.status
      if let profile = profiles.first(where: { $0.id == state.profileID }) {
        if let finalStatus = updateLastApplyPresentation(profile: profile, verification: nil) {
          summary.status = finalStatus
          lastApplyResult?.status = finalStatus
          operationalStatusByProfile[state.profileID] = finalStatus
        }
      }
      await persistApplicationSummary(summary, profileID: state.profileID)
      await refreshReadiness()
      return
    }

    let failed = resolution.status == .rollbackFailed
    operationalStatusByProfile[state.profileID] = failed ? .failed : .partial
    lastMessage =
      failed
      ? appLocalized(
        "Automatic protected-change rollback failed; review the itemized result immediately.")
      : appLocalized("Restored the previous configuration.")

    var summary = resolveSafetyOutcome(
      SafetyOutcome(
        profileStatus: failed ? .failed : .partial,
        itemStatus: failed ? .rollbackFailed : .rolledBack,
        message:
          failed
          ? appLocalized("The previous configuration could not be fully restored.")
          : appLocalized("The previous configuration was restored.")
      ),
      rollbackResults: resolution.rollbackResults,
      profileID: state.profileID
    )
    operationalStatusByProfile[state.profileID] = summary.status
    if let profile = profiles.first(where: { $0.id == state.profileID }) {
      if let finalStatus = updateLastApplyPresentation(profile: profile, verification: nil) {
        summary.status = finalStatus
        lastApplyResult?.status = finalStatus
        operationalStatusByProfile[state.profileID] = finalStatus
      }
    }
    await persistApplicationSummary(summary, profileID: state.profileID)
    recordDiagnostic(
      severity: failed ? .error : .warning,
      component: "high-risk-safety",
      code: resolution.status.rawValue,
      message:
        appLocalized(
          "The guarded high-risk rollback completed with \(resolution.rollbackResults.count) item results."
        )
    )
    await refreshReadiness()
  }

  func refreshDiagnostics() {
    guard !suppressesLiveSystemAccess else {
      diagnosticEntries = []
      diagnosticStatus = appLocalized("System access is disabled for this synthetic review.")
      return
    }
    guard let diagnosticLog else {
      diagnosticEntries = []
      diagnosticStatus = appLocalized("Local diagnostic storage is unavailable.")
      return
    }

    Task {
      do {
        let entries = try await diagnosticLog.entries()
        diagnosticEntries = Array(entries.suffix(200).reversed())
        diagnosticStatus =
          entries.isEmpty
          ? appLocalized("No local diagnostic events.")
          : appLocalized(
            "Showing the most recent \(min(entries.count, 200)) redacted local events.")
      } catch {
        diagnosticEntries = []
        diagnosticStatus = appLocalized("Local diagnostic events could not be read.")
      }
    }
  }

  func clearDiagnostics() {
    guard !suppressesLiveSystemAccess else { return }
    guard let diagnosticLog else { return }
    Task {
      do {
        try await diagnosticLog.removeAll()
        diagnosticEntries = []
        diagnosticStatus = appLocalized("Local diagnostic events were removed.")
      } catch {
        diagnosticStatus = appLocalized("Local diagnostic events could not be removed.")
      }
    }
  }

  private func storageMessage(for status: ProfileLoadStatus) -> String {
    switch status {
    case .loaded:
      appLocalized("Loaded local profiles.")
    case .createdEmpty:
      appLocalized("Created secure local profile storage.")
    case .migrated(let version):
      appLocalized(
        "Migrated profile schema \(version) to \(ProfileDocument.currentSchemaVersion).")
    case .recoveredFromBackup:
      appLocalized(
        "Recovered profiles from the last known-good backup; the corrupt file was quarantined.")
    case .resetAfterCorruption:
      appLocalized(
        "Both profile files were corrupt and quarantined; storage was safely reset.")
    }
  }

  private func snapshotSummary(_ snapshot: SystemSnapshotResult) -> String {
    let items = snapshot.groups.flatMap(\.items)
    let stored = items.filter { $0.state == .storable }.count
    let detected = items.filter { $0.state == .detected }.count
    let unreadable = items.filter { $0.state == .unreadable }.count
    let permission = items.filter { $0.state == .permissionRequired }.count
    let unsupported = items.filter { $0.state == .unsupported }.count
    return appLocalized(
      "Snapshot: \(detected) detected, \(stored) storable, \(unreadable) unreadable, \(permission) permission required, \(unsupported) unsupported."
    )
  }

  private func profileCaptureSummary(
    _ snapshot: SystemSnapshotResult
  ) -> ProfileCaptureSummary {
    let evidence = snapshot.groups.flatMap { group in
      let itemEvidence = group.items.map {
        CaptureSnapshotEvidence(group: group.group, key: $0.key, state: $0.state)
      }
      let failureEvidence = group.failures.map {
        CaptureSnapshotEvidence(
          group: group.group,
          key:
            $0.stage == .snapshot || $0.stage == .snapshotContract
            ? "snapshot" : "capture.\($0.stage.rawValue)",
          state: .unreadable
        )
      }
      return itemEvidence + failureEvidence
    }
    return ProfileCaptureSummaryBuilder().summary(
      settings: snapshot.profileSettings,
      evidence: evidence
    )
  }

  private func recordSnapshotDiagnostic(_ snapshot: SystemSnapshotResult) {
    let items = snapshot.groups.flatMap(\.items)
    recordDiagnostic(
      severity: items.contains(where: { $0.state == .unreadable }) ? .warning : .info,
      component: "snapshot",
      code: "read-only-complete",
      message: appLocalized(
        "Read-only snapshot completed with \(items.count) classified items across \(snapshot.groups.count) groups."
      )
    )
  }

  private func recordDiagnostic(
    severity: DiagnosticSeverity,
    component: String,
    code: String,
    message: String
  ) {
    guard let diagnosticLog else { return }
    let entry = DiagnosticEntry(
      severity: severity,
      component: component,
      code: code,
      message: message
    )
    Task {
      do {
        try await diagnosticLog.append(entry)
        refreshDiagnostics()
      } catch {
        diagnosticStatus = appLocalized("A local diagnostic event could not be saved.")
      }
    }
  }

  private func storageDiagnosticMessage(for status: ProfileLoadStatus) -> String {
    switch status {
    case .loaded:
      appLocalized("Local profile storage loaded.")
    case .createdEmpty:
      appLocalized("Empty local profile storage was created.")
    case .migrated(let version):
      appLocalized("Local profile storage migrated from schema \(version).")
    case .recoveredFromBackup:
      appLocalized("Local profile storage recovered from a backup.")
    case .resetAfterCorruption:
      appLocalized("Corrupt local profile storage was quarantined and reset.")
    }
  }

  private var profileEditingLockedMessage: String {
    appLocalized("Profile editing is locked until the current operation is safely recorded.")
  }

  private var sanitizedProfileStorageFailureMessage: String {
    appLocalized("A local profile storage operation failed.")
  }

  private func profileStorageUserMessage(for error: Error) -> String {
    if error is ProfileValidationError {
      return appLocalized("The profile contains an invalid value. Review the edited fields.")
    }
    guard let storageError = error as? ProfileStorageError else {
      return sanitizedProfileStorageFailureMessage
    }
    switch storageError {
    case .fileTooLarge:
      return appLocalized("The profile file is too large to open safely.")
    case .invalidJSON:
      return appLocalized("The selected profile file is not valid JSON.")
    case .unsupportedSchema:
      return appLocalized("The profile file was created by an unsupported app version.")
    case .missingMigration, .invalidMigration:
      return appLocalized("The profile file could not be migrated safely.")
    case .profileNotFound:
      return appLocalized("The selected profile no longer exists.")
    case .profileAlreadyExists:
      return appLocalized("A profile with the same identifier already exists.")
    case .invalidReorderIndex:
      return appLocalized("The profile order changed before this move could be saved.")
    case .destinationExists:
      return appLocalized("The export destination already exists. Choose a new file name.")
    case .importSourceOverwrite:
      return appLocalized("Choose a different export destination from the imported file.")
    case .io:
      return sanitizedProfileStorageFailureMessage
    }
  }

  private func mergeUserEditableProfileValues(
    from saveCandidate: DeskProfile,
    metadataFrom authoritativeProfile: DeskProfile
  ) -> DeskProfile {
    var merged = authoritativeProfile
    merged.name = saveCandidate.name
    merged.profileDescription = saveCandidate.profileDescription
    merged.symbolName = saveCandidate.symbolName
    merged.isEnabled = true
    merged.settings = saveCandidate.settings
    merged.conditions = saveCandidate.conditions
    return merged
  }

  private func reportProfileEditorFailure(code: String, message: String) {
    storageStatus = message
    recordDiagnostic(
      severity: .error,
      component: "profile-storage",
      code: code,
      message: appLocalized("A local profile storage operation failed.")
    )
  }

  private func reportStorageError(_ error: Error) {
    storageStatus = profileStorageUserMessage(for: error)
    recordDiagnostic(
      severity: .error,
      component: "profile-storage",
      code: "operation-failed",
      message: appLocalized("A local profile storage operation failed.")
    )
  }

  private func configureDefaultLaunchPreferenceIfNeeded() {
    guard !defaults.bool(forKey: launchAtLoginPreferenceCreatedKey) else { return }
    defaults.set(true, forKey: launchAtLoginPreferenceKey)
    defaults.set(true, forKey: launchAtLoginPreferenceCreatedKey)
  }

  private func finishApplyTransaction() {
    isApplyTransactionInProgress = false
    if terminationRequestIsDeferred, safetyConfirmation != nil {
      revertHighRiskChanges()
      return
    }
    completeDeferredTerminationIfPossible()
  }

  private func beginProfileStoreMutation() -> Bool {
    guard !isProfileMutationLocked else { return false }
    isProfileStoreMutationInProgress = true
    return true
  }

  private func finishProfileStoreMutation() {
    isProfileStoreMutationInProgress = false
    completeDeferredTerminationIfPossible()
  }

  private func completeDeferredTerminationIfPossible() {
    guard terminationRequestIsDeferred, !shouldDeferTermination else { return }
    terminationRequestIsDeferred = false
    NSApplication.shared.reply(toApplicationShouldTerminate: true)
  }

  private func reconcileLoginItemRegistrationAtStartup() {
    let status = loginItemService.status
    if launchAtLoginDesired {
      if status == .notRegistered || status == .notFound {
        updateLoginItemRegistration(enabled: true)
      } else {
        refreshLoginItemStatus()
      }
    } else if status == .enabled || status == .requiresApproval {
      updateLoginItemRegistration(enabled: false)
    } else {
      refreshLoginItemStatus()
    }
  }

  private func refreshLoginItemStatus() {
    let status = loginItemService.status
    switch status {
    case .enabled:
      loginItemEnabled = true
      loginItemOperationFailure = nil
    case .requiresApproval:
      loginItemEnabled = false
    case .notFound:
      loginItemEnabled = false
    case .notRegistered:
      loginItemEnabled = false
    @unknown default:
      loginItemEnabled = false
    }

    canRetryLoginItemRegistration =
      launchAtLoginDesired && status != .enabled && status != .requiresApproval

    if launchAtLoginDesired {
      switch status {
      case .enabled:
        loginItemStatus = appLocalized("Requested and enabled by macOS.")
      case .requiresApproval:
        loginItemStatus = appLocalized(
          "Requested; approval is required in System Settings > General > Login Items.")
      case .notFound:
        loginItemStatus = registrationFailureStatus(
          fallback: appLocalized(
            "Requested, but macOS cannot find an eligible installed app bundle. Retry after installing a properly signed build."
          )
        )
      case .notRegistered:
        loginItemStatus = registrationFailureStatus(
          fallback: appLocalized("Requested, but not registered with macOS yet.")
        )
      @unknown default:
        loginItemStatus = appLocalized("Requested; the effective macOS status is unknown.")
      }
    } else {
      switch status {
      case .notRegistered, .notFound:
        loginItemStatus = appLocalized("Off; not registered with macOS.")
      case .enabled:
        loginItemStatus =
          loginItemOperationFailure == .unregistration
          ? appLocalized("Turned off in the app, but macOS rejected the removal request.")
          : appLocalized("Turned off in the app, but still enabled by macOS.")
      case .requiresApproval:
        loginItemStatus = appLocalized(
          "Turned off in the app, but macOS still reports a registration awaiting approval.")
      @unknown default:
        loginItemStatus = appLocalized("Turned off; the effective macOS status is unknown.")
      }
    }
  }

  private struct SafetyOutcome {
    var profileStatus: ProfileReadiness
    var itemStatus: ApplicationItemStatus
    var message: String
  }

  private func loginItemFailure(for error: Error, enabling: Bool) -> LoginItemOperationFailure {
    guard enabling else { return .unregistration }
    let code = (error as NSError).code
    if code == kSMErrorInvalidSignature {
      return .invalidSignature
    }
    if code == kSMErrorLaunchDeniedByUser {
      return .deniedByUser
    }
    return .registration
  }

  private func registrationFailureStatus(fallback: String) -> String {
    switch loginItemOperationFailure {
    case .invalidSignature:
      appLocalized(
        "Requested, but macOS rejected this build’s code signature. Install a properly signed build or turn this preference off."
      )
    case .deniedByUser:
      appLocalized(
        "Requested, but macOS denied registration. Review Login Items in System Settings or turn this preference off."
      )
    case .registration:
      appLocalized(
        "Requested, but macOS rejected registration. This build or install location may not be eligible."
      )
    case .unregistration, .none:
      fallback
    }
  }

  private func makeSafetyOutcomeItem(
    status: ApplicationItemStatus,
    message: String
  ) -> ApplicationItemSummary {
    ApplicationItemSummary(
      group: .display,
      key: highRiskSafetyConfirmationKey,
      status: status,
      message: message
    )
  }

  private func resolveSafetyOutcome(
    _ outcome: SafetyOutcome,
    rollbackResults: [ApplicationItemSummary],
    profileID: UUID
  ) -> ApplicationSummary {
    let completedAt = Date()
    var items: [ApplicationItemSummary]
    var updatedResult: ApplyExecutionResult?

    if var result = lastApplyResult, result.preparation.profileID == profileID {
      result.completedAt = completedAt
      result.safetyConfirmationID = nil
      result.itemResults.removeAll { $0.key == highRiskSafetyConfirmationKey }
      result.itemResults.append(
        makeSafetyOutcomeItem(status: outcome.itemStatus, message: outcome.message)
      )
      result.rollbackResults.append(contentsOf: rollbackResults)
      items = result.itemResults + result.rollbackResults
      updatedResult = result
    } else {
      items = rollbackResults
      items.append(makeSafetyOutcomeItem(status: outcome.itemStatus, message: outcome.message))
    }

    let finalStatus: ProfileReadiness =
      items.contains(where: isFailedApplicationItem) ? .failed : outcome.profileStatus
    if var updatedResult {
      updatedResult.status = finalStatus
      lastApplyResult = updatedResult
    }

    return ApplicationSummary(
      appliedAt: completedAt,
      status: finalStatus,
      items: items
    )
  }

  private func isFailedApplicationItem(_ item: ApplicationItemSummary) -> Bool {
    item.status == .failed || item.status == .rollbackFailed
  }

  private func reconcileInterruptedSafetyConfirmation() async -> Bool {
    var didReconcile = false
    for profile in profiles where profile.lastApplication?.status == .applying {
      guard var summary = profile.lastApplication else { continue }
      var updated = profile
      summary.status =
        summary.items.contains(where: isFailedApplicationItem) ? .failed : .partial
      summary.appliedAt = Date()
      summary.items.removeAll { $0.key == highRiskSafetyConfirmationKey }
      summary.items.append(
        makeSafetyOutcomeItem(
          status: .skipped,
          message: appLocalized(
            "The app exited before the confirmation outcome was recorded. Verify the current display configuration."
          )
        )
      )
      updated.lastApplication = summary
      do {
        _ = try await profileStore.updateProfile(updated)
        didReconcile = true
      } catch {
        reportStorageError(error)
      }
    }
    if didReconcile {
      profiles = await profileStore.currentDocument().profiles
    }
    return didReconcile
  }
}
