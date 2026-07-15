import Foundation
import ServiceManagement
import SwiftUI
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher
@testable import DeskSetupSystem

#if DEBUG
  @Suite("Synthetic UI audit safety", .serialized)
  @MainActor
  struct UIAuditSafetyTests {
    @Test("public audit actions never reach adapters, stores, diagnostics, or login items")
    func publicActionsRemainSideEffectFree() async throws {
      let identifier = "DeskSetupSwitcherTests.UIAudit.\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: identifier))
      defaults.removePersistentDomain(forName: identifier)
      defer { defaults.removePersistentDomain(forName: identifier) }

      let storeDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(identifier, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: storeDirectory) }

      let adapter = MockSystemSettingsAdapter(group: .display)
      let conditionReaders = RecordingConditionReaders()
      let conditionProvider = ConditionContextProvider(
        displayReader: conditionReaders,
        audioReader: conditionReaders,
        networkReader: conditionReaders,
        hardwareReader: conditionReaders,
        locationReader: conditionReaders
      )
      let loginItem = RecordingLoginItemService()
      let diagnosticLog = RecordingDiagnosticLog()
      let model = ApplicationModel(
        profileStore: ProfileStore(directoryURL: storeDirectory),
        snapshotCoordinator: SystemSnapshotCoordinator(adapters: [adapter]),
        conditionContextProvider: conditionProvider,
        applyEngine: ApplyEngine(registry: try AdapterRegistry([adapter])),
        diagnosticLog: diagnosticLog,
        defaults: defaults,
        loginItemService: loginItem
      )
      let fixture = UIAuditFixtures.fixture(.editor)
      model.configureForUIAudit(fixture)
      let selected = try #require(fixture.profiles.first)

      model.start()
      model.refreshReadinessFacts()
      model.createProfile()
      model.duplicateProfile(id: selected.id)
      model.deleteProfile(id: selected.id)
      model.moveProfile(id: selected.id, by: 1)
      model.setLaunchAtLogin(false)
      model.retryLaunchAtLoginRegistration()
      model.refreshLoginItemStatusFromSystem()
      model.refreshDiagnostics()
      model.clearDiagnostics()
      model.prepareApply(profile: selected, mode: .normal)
      model.executePendingApply()
      model.confirmHighRiskChanges()
      model.revertHighRiskChanges()

      let saveResult = await model.updateProfile(selected)
      let createResult = await model.createProfileFromCurrentSettings()
      let captureResult = await model.captureCurrentProfileSettings()

      #expect(
        saveResult
          == .rejected(
            message: appLocalized("System access is disabled for this synthetic review."))
      )
      #expect(
        createResult
          == .rejected(
            message: appLocalized("System access is disabled for this synthetic review."),
            summary: fixture.captureSummary
          )
      )
      #expect(
        captureResult
          == .rejected(
            message: appLocalized("System access is disabled for this synthetic review."),
            summary: fixture.captureSummary
          )
      )
      #expect(model.profiles == fixture.profiles)
      #expect(model.launchAtLoginDesired)
      #expect(await adapter.recordedInvocations().isEmpty)
      #expect(await conditionReaders.invocationCount == 0)
      #expect(loginItem.invocations.isEmpty)
      #expect(await diagnosticLog.invocations.isEmpty)
      #expect(defaults.persistentDomain(forName: identifier) == nil)
      #expect(!FileManager.default.fileExists(atPath: storeDirectory.path))
    }

    @Test("synthetic permission requests never call Core Location request closures")
    func permissionRequestRemainsSideEffectFree() {
      let recorder = PermissionRequestRecorder()
      let controller = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .notDetermined,
        requestWhenInUseAuthorization: recorder.requestAuthorization,
        requestLocation: recorder.requestLocation
      )

      controller.requestAccess()

      #expect(recorder.invocations.isEmpty)
      #expect(
        controller.lastError
          == appLocalized("System access is disabled for this synthetic review."))
    }

    @Test("explicit capture permission action calls the injected macOS request")
    func explicitPermissionRequestUsesInjectedClosure() {
      let recorder = PermissionRequestRecorder()
      let controller = LocationPermissionController(
        allowsSystemRequests: true,
        syntheticAuthorizationStatus: .notDetermined,
        requestWhenInUseAuthorization: recorder.requestAuthorization,
        requestLocation: recorder.requestLocation,
        openSystemSettingsApplication: recorder.openSystemSettings
      )

      controller.requestAccess()

      #expect(recorder.invocations == ["authorization"])
    }

    @Test("denied capture permission opens only the injected System Settings action")
    func deniedPermissionUsesInjectedSystemSettingsAction() {
      let recorder = PermissionRequestRecorder()
      let controller = LocationPermissionController(
        allowsSystemRequests: true,
        syntheticAuthorizationStatus: .denied,
        requestWhenInUseAuthorization: recorder.requestAuthorization,
        requestLocation: recorder.requestLocation,
        openSystemSettingsApplication: recorder.openSystemSettings
      )

      controller.openSystemSettings()

      #expect(recorder.invocations == ["settings"])
      #expect(controller.lastError == nil)
    }

    @Test("tray permission actions establish a stable settings window before system UI")
    func permissionActionUsesStableSettingsWindow() async {
      var events: [String] = []
      let coordinator = StablePermissionActionCoordinator(
        presentSettings: {
          events.append("app-settings")
        },
        waitForPresentation: {
          events.append("presentation-settled")
        }
      )

      let task = coordinator.perform {
        events.append("system-permission-action")
      }

      #expect(events == ["app-settings"])
      await task.value
      #expect(
        events == ["app-settings", "presentation-settled", "system-permission-action"])
    }

    @Test("tray deletion request, cancel, and confirmation are deterministic")
    func trayDeletionStateTransitions() {
      let first = UUID()
      let second = UUID()
      var state = MenuProfileDeletionState()

      state.request(profileID: first)
      #expect(state.isPending(profileID: first))
      let wrongConfirmation = state.confirm(profileID: second)
      #expect(!wrongConfirmation)
      #expect(state.pendingProfileID == first)

      state.cancel()
      #expect(state.pendingProfileID == nil)

      state.request(profileID: first)
      let matchingConfirmation = state.confirm(profileID: first)
      #expect(matchingConfirmation)
      #expect(state.pendingProfileID == nil)
    }

    @Test("tray deletion layout reserves a complete confirmation region")
    func trayDeletionLayoutHeight() {
      let normalOne = MenuProfileListLayout.height(
        profileCount: 1,
        hasDeletionConfirmation: false
      )
      let confirmingOne = MenuProfileListLayout.height(
        profileCount: 1,
        hasDeletionConfirmation: true
      )
      let normalThree = MenuProfileListLayout.height(
        profileCount: 3,
        hasDeletionConfirmation: false
      )
      let confirmingThree = MenuProfileListLayout.height(
        profileCount: 3,
        hasDeletionConfirmation: true
      )
      let confirmingMany = MenuProfileListLayout.height(
        profileCount: 20,
        hasDeletionConfirmation: true
      )

      #expect(normalOne == MenuProfileListLayout.minimumHeight)
      #expect(confirmingOne >= 190)
      #expect(confirmingOne - normalOne >= 70)
      #expect(confirmingThree > normalThree)
      #expect(confirmingMany == MenuProfileListLayout.confirmationMaximumHeight)
    }

    @Test("settings layout changes only at the documented breakpoint")
    func responsiveSettingsBreakpoint() {
      #expect(ProfileWorkspaceLayoutMode(width: 759.9) == .compact)
      #expect(ProfileWorkspaceLayoutMode(width: 760) == .regular)
      #expect(ProfileWorkspaceLayoutMode(width: 980) == .regular)
      #expect(ProfileWorkspaceLayoutMode(width: 680) == .compact)
    }

    @Test("runtime settings window exposes stable resizable geometry")
    func runtimeSettingsWindowGeometry() throws {
      let controller = RuntimeSettingsWindowController(rootView: Color.clear)
      let window = try #require(controller.window)

      #expect(window.styleMask.contains(.resizable))
      #expect(window.contentMinSize == CGSize(width: 680, height: 480))
      #expect(window.contentView?.bounds.width == 900)
      #expect(window.contentView?.bounds.height == 568)
      #expect(!window.isReleasedWhenClosed)
    }
  }

  private actor RecordingConditionReaders: ConditionDisplayReading, ConditionAudioReading,
    ConditionNetworkReading, ConditionHardwareReading, ConditionLocationReading
  {
    private(set) var invocationCount = 0

    func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity> {
      invocationCount += 1
      return []
    }

    func readAudioFacts() async throws -> ConditionAudioFacts {
      invocationCount += 1
      return .init()
    }

    func readNetworkFacts() async throws -> ConditionNetworkFacts {
      invocationCount += 1
      return .init()
    }

    func readHardwareIdentifiers() async throws -> Set<String> {
      invocationCount += 1
      return []
    }

    func readAuthorizedLocation() async throws -> LocationRegion? {
      invocationCount += 1
      return nil
    }
  }

  private actor RecordingDiagnosticLog: DiagnosticLogStoring {
    enum Invocation: Equatable {
      case append
      case entries
      case removeAll
    }

    private(set) var invocations: [Invocation] = []

    func append(_ entry: DiagnosticEntry) async throws {
      invocations.append(.append)
    }

    func entries() async throws -> [DiagnosticEntry] {
      invocations.append(.entries)
      return []
    }

    func removeAll() async throws {
      invocations.append(.removeAll)
    }
  }

  @MainActor
  private final class RecordingLoginItemService: LoginItemServicing {
    private(set) var invocations: [String] = []

    var status: SMAppService.Status {
      invocations.append("status")
      return .notRegistered
    }

    func register() throws {
      invocations.append("register")
    }

    func unregister() throws {
      invocations.append("unregister")
    }
  }

  @MainActor
  private final class PermissionRequestRecorder {
    private(set) var invocations: [String] = []

    func requestAuthorization() {
      invocations.append("authorization")
    }

    func requestLocation() {
      invocations.append("location")
    }

    func openSystemSettings() -> Bool {
      invocations.append("settings")
      return true
    }
  }
#endif
