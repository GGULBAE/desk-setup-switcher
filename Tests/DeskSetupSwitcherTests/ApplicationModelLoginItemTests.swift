import Foundation
import ServiceManagement
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher
@testable import DeskSetupSystem

@Suite("Launch at login opt-in", .serialized)
@MainActor
struct ApplicationModelLoginItemTests {
  @Test("a fresh install starts off and never requests registration")
  func freshInstallStartsOff() async throws {
    let fixture = try makeFixture()

    fixture.model.start()

    #expect(!fixture.model.launchAtLoginDesired)
    #expect(fixture.defaults.object(forKey: "launchAtLoginEnabled") as? Bool == false)
    #expect(fixture.defaults.bool(forKey: "launchAtLoginPreferenceCreated"))
    #expect(fixture.defaults.integer(forKey: "launchAtLoginConsentVersion") == 1)
    #expect(fixture.loginItem.registerCount == 0)
    #expect(fixture.loginItem.unregisterCount == 0)

    await finishAndCleanUp(fixture)
  }

  @Test("a fresh install removes a stale registration without opting in")
  func freshInstallRemovesStaleRegistration() async throws {
    let fixture = try makeFixture(systemStatus: .enabled)

    fixture.model.start()

    #expect(!fixture.model.launchAtLoginDesired)
    #expect(fixture.loginItem.registerCount == 0)
    #expect(fixture.loginItem.unregisterCount == 1)
    #expect(fixture.loginItem.status == .notRegistered)

    await finishAndCleanUp(fixture)
  }

  @Test("registration begins only after the user explicitly turns the option on")
  func explicitOptInRegisters() async throws {
    let fixture = try makeFixture()
    fixture.model.start()
    #expect(fixture.loginItem.registerCount == 0)

    fixture.model.setLaunchAtLogin(true)

    #expect(fixture.model.launchAtLoginDesired)
    #expect(fixture.defaults.bool(forKey: "launchAtLoginEnabled"))
    #expect(fixture.defaults.integer(forKey: "launchAtLoginConsentVersion") == 1)
    #expect(fixture.loginItem.registerCount == 1)
    #expect(fixture.loginItem.status == .enabled)

    await finishAndCleanUp(fixture)
  }

  @Test(
    "a preference recorded under the consent policy remains authoritative",
    arguments: [false, true]
  )
  func consentedPreferenceIsPreserved(enabled: Bool) async throws {
    let fixture = try makeFixture(
      storedPreference: enabled,
      preferenceWasInitialized: true,
      consentVersion: 1
    )

    fixture.model.start()

    #expect(fixture.model.launchAtLoginDesired == enabled)
    #expect(fixture.defaults.bool(forKey: "launchAtLoginEnabled") == enabled)
    #expect(fixture.loginItem.registerCount == (enabled ? 1 : 0))

    await finishAndCleanUp(fixture)
  }

  @Test(
    "a pre-release preference is reset because it cannot prove consent",
    arguments: [false, true]
  )
  func preReleasePreferenceRequiresNewConsent(enabled: Bool) async throws {
    let fixture = try makeFixture(
      storedPreference: enabled,
      preferenceWasInitialized: true
    )

    fixture.model.start()

    #expect(!fixture.model.launchAtLoginDesired)
    #expect(!fixture.defaults.bool(forKey: "launchAtLoginEnabled"))
    #expect(fixture.defaults.bool(forKey: "launchAtLoginPreferenceCreated"))
    #expect(fixture.defaults.integer(forKey: "launchAtLoginConsentVersion") == 1)
    #expect(fixture.loginItem.registerCount == 0)

    await finishAndCleanUp(fixture)
  }

  @Test("the consent migration removes an old automatic registration")
  func preReleaseAutomaticRegistrationIsRemoved() async throws {
    let fixture = try makeFixture(
      storedPreference: true,
      preferenceWasInitialized: true,
      systemStatus: .enabled
    )

    fixture.model.start()

    #expect(!fixture.model.launchAtLoginDesired)
    #expect(fixture.loginItem.registerCount == 0)
    #expect(fixture.loginItem.unregisterCount == 1)
    #expect(fixture.loginItem.status == .notRegistered)

    await finishAndCleanUp(fixture)
  }

  private func makeFixture(
    storedPreference: Bool? = nil,
    preferenceWasInitialized: Bool = false,
    consentVersion: Int? = nil,
    systemStatus: SMAppService.Status = .notRegistered
  ) throws -> LoginItemFixture {
    let identifier = "DeskSetupSwitcherTests.LoginItem.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: identifier) else {
      throw LoginItemFixtureError.couldNotCreateDefaults
    }
    defaults.removePersistentDomain(forName: identifier)
    if let storedPreference {
      defaults.set(storedPreference, forKey: "launchAtLoginEnabled")
    }
    if preferenceWasInitialized {
      defaults.set(true, forKey: "launchAtLoginPreferenceCreated")
    }
    if let consentVersion {
      defaults.set(consentVersion, forKey: "launchAtLoginConsentVersion")
    }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      identifier,
      isDirectory: true
    )
    let loginItem = RecordingLoginItemService(status: systemStatus)
    let conditionReader = LoginItemEmptyConditionReader()
    let model = ApplicationModel(
      profileStore: ProfileStore(directoryURL: directory),
      snapshotCoordinator: SystemSnapshotCoordinator(adapters: []),
      conditionContextProvider: ConditionContextProvider(
        displayReader: conditionReader,
        audioReader: conditionReader,
        networkReader: conditionReader,
        hardwareReader: conditionReader,
        locationReader: conditionReader
      ),
      applyEngine: ApplyEngine(registry: AdapterRegistry()),
      diagnosticLog: nil,
      defaults: defaults,
      loginItemService: loginItem
    )
    return LoginItemFixture(
      model: model,
      defaults: defaults,
      loginItem: loginItem,
      cleanup: {
        defaults.removePersistentDomain(forName: identifier)
        try? FileManager.default.removeItem(at: directory)
      }
    )
  }

  private func finishAndCleanUp(_ fixture: LoginItemFixture) async {
    for _ in 0..<2_000 {
      if !fixture.model.isProfileStoreMutationInProgress {
        break
      }
      await Task.yield()
    }
    fixture.cleanup()
  }
}

private enum LoginItemFixtureError: Error {
  case couldNotCreateDefaults
}

@MainActor
private struct LoginItemFixture {
  let model: ApplicationModel
  let defaults: UserDefaults
  let loginItem: RecordingLoginItemService
  let cleanup: () -> Void
}

@MainActor
private final class RecordingLoginItemService: LoginItemServicing {
  private(set) var status: SMAppService.Status
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  init(status: SMAppService.Status) {
    self.status = status
  }

  func register() throws {
    registerCount += 1
    status = .enabled
  }

  func unregister() throws {
    unregisterCount += 1
    status = .notRegistered
  }
}

private actor LoginItemEmptyConditionReader: ConditionDisplayReading, ConditionAudioReading,
  ConditionNetworkReading, ConditionHardwareReading, ConditionLocationReading
{
  func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity> { [] }
  func readAudioFacts() async throws -> ConditionAudioFacts { .init() }
  func readNetworkFacts() async throws -> ConditionNetworkFacts { .init() }
  func readHardwareIdentifiers() async throws -> Set<String> { [] }
  func readAuthorizedLocation() async throws -> LocationRegion? { nil }
}
