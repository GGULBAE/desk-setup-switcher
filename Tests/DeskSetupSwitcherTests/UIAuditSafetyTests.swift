import Foundation
import ServiceManagement
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
