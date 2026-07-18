import Foundation
import ServiceManagement
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher
@testable import DeskSetupSystem

@Suite("Persisted settings lifecycle", .serialized)
@MainActor
struct SettingsLifecycleIntegrationTests {
  @Test("edited output volume reloads and reaches verified apply")
  func editedOutputVolumeReloadsAndApplies() async throws {
    let identifier = "DeskSetupSwitcherTests.SettingsLifecycle.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      identifier,
      isDirectory: true
    )
    let defaults = try #require(UserDefaults(suiteName: identifier))
    defaults.removePersistentDomain(forName: identifier)
    defaults.set(true, forKey: "launchAtLoginPreferenceCreated")
    defaults.set(false, forKey: "launchAtLoginEnabled")
    defer {
      defaults.removePersistentDomain(forName: identifier)
      try? FileManager.default.removeItem(at: directory)
    }

    let seededVolume = 0.2
    let editedVolume = 0.73
    let store = ProfileStore(directoryURL: directory)
    _ = try await store.load()
    let seededProfile = try await store.createProfile(
      DeskProfile(
        name: "Synthetic lifecycle",
        settings: ProfileSettings(
          audio: SettingGroupConfiguration(
            isIncluded: true,
            value: AudioProfileSettings(
              outputVolume: SettingOption(isIncluded: true, value: seededVolume)
            )
          )
        )
      ),
      selecting: true
    )

    let adapter = SettingsLifecycleAudioAdapter(currentVolume: 0.4)
    let conditionReader = SettingsLifecycleConditionReader()
    let model = ApplicationModel(
      profileStore: store,
      snapshotCoordinator: SystemSnapshotCoordinator(adapters: [adapter]),
      conditionContextProvider: ConditionContextProvider(
        displayReader: conditionReader,
        audioReader: conditionReader,
        networkReader: conditionReader,
        hardwareReader: conditionReader
      ),
      applyEngine: ApplyEngine(registry: try AdapterRegistry([adapter])),
      diagnosticLog: nil,
      defaults: defaults,
      loginItemService: SettingsLifecycleLoginItemService()
    )

    model.start()
    #expect(
      await waitForLifecycle {
        model.profiles.count == 1 && !model.isProfileMutationLocked
      }
    )
    let loadedProfile = try #require(model.profiles.first)
    #expect(loadedProfile.id == seededProfile.id)
    #expect(loadedProfile.settings.audio.value.outputVolume.isIncluded)
    #expect(loadedProfile.settings.audio.value.outputVolume.value == seededVolume)

    let editor = ProfileEditorModel()
    editor.initialize(
      profiles: model.profiles,
      preferredProfileID: model.selectedProfileID
    )
    #expect(
      editor.updateDraft {
        $0.settings.audio.value.outputVolume = SettingOption(
          isIncluded: true,
          value: editedVolume
        )
      }
    )
    #expect(editor.isDirty)
    let saveCandidate = try #require(editor.session.saveCandidate())
    #expect(saveCandidate.settings.audio.value.outputVolume.isIncluded)
    #expect(saveCandidate.settings.audio.value.outputVolume.value == editedVolume)

    let persistedProfile: DeskProfile
    switch await model.updateProfile(saveCandidate) {
    case .saved(let profile):
      persistedProfile = profile
    case .rejected(let message):
      Issue.record("Expected lifecycle save to succeed: \(message)")
      return
    }
    #expect(editor.completeSave(with: persistedProfile) == .saved)
    #expect(!editor.isDirty)
    #expect(editor.draft?.settings.audio.value.outputVolume.value == editedVolume)

    let reloadedDocument = try await ProfileStore(directoryURL: directory).load().document
    let reloadedProfile = try #require(
      reloadedDocument.profiles.first(where: { $0.id == seededProfile.id })
    )
    #expect(reloadedDocument.selectedProfileID == seededProfile.id)
    #expect(reloadedProfile.settings.audio.isIncluded)
    #expect(reloadedProfile.settings.audio.value.outputVolume.isIncluded)
    #expect(reloadedProfile.settings.audio.value.outputVolume.value == editedVolume)

    let profileToApply = try #require(
      model.profiles.first(where: { $0.id == seededProfile.id })
    )
    #expect(profileToApply.settings.audio.value.outputVolume.isIncluded)
    #expect(profileToApply.settings.audio.value.outputVolume.value == editedVolume)
    model.prepareApply(profile: profileToApply, mode: .normal)
    #expect(await waitForLifecycle { model.pendingApply != nil })
    #expect(model.pendingApply?.preparation.operations.map(\.key) == ["outputVolume"])
    #expect(model.executePendingApply() == .started)
    #expect(
      await waitForLifecycle {
        model.lastApplyVerification != nil && !model.isApplyTransactionInProgress
      }
    )

    #expect(await adapter.appliedVolumes == [editedVolume])
    #expect(await adapter.currentVolume == editedVolume)
    let verification = try #require(model.lastApplyVerification)
    #expect(verification.notVerifiedCount == 0)
    #expect(verification.unexpectedRemainingOperations.isEmpty)
    #expect(verification.executedOperations.count == 1)
    #expect(verification.executedOperations.first?.operation.group == .audio)
    #expect(verification.executedOperations.first?.operation.key == "outputVolume")
    #expect(verification.executedOperations.first?.status == .verified)
    #expect(model.lastApplyResult?.status == .applied)
  }

  private func waitForLifecycle(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<4_000 {
      if condition() { return true }
      await Task.yield()
    }
    return condition()
  }
}

private struct SettingsLifecycleVolumePayload: Codable, Equatable, Sendable {
  let volume: Double
}

private enum SettingsLifecycleAdapterError: Error {
  case invalidDesiredPayload
}

private actor SettingsLifecycleAudioAdapter: SystemSettingsAdapter {
  nonisolated let group: SettingGroup = .audio
  private(set) var currentVolume: Double
  private(set) var appliedVolumes: [Double] = []

  init(currentVolume: Double) {
    self.currentVolume = currentVolume
  }

  func capability() async -> AdapterCapability {
    AdapterCapability(
      group: group,
      state: .supported,
      reason: "Synthetic output volume is available."
    )
  }

  func snapshot() async throws -> AdapterSnapshot {
    AdapterSnapshot(
      group: group,
      capturedAt: Date(timeIntervalSince1970: 0),
      payload: .audio(
        AudioProfileSettings(
          outputVolume: SettingOption(isIncluded: true, value: currentVolume)
        )
      ),
      items: [],
      audioDeviceCatalog: [
        AudioDeviceCatalogEntry(
          uid: "synthetic-output",
          name: "Synthetic Output",
          supportsInput: false,
          supportsOutput: true
        )
      ],
      audioVolumeControlCatalog: [
        AudioVolumeControlCatalogEntry(
          role: .output,
          deviceUID: "synthetic-output",
          currentValue: currentVolume,
          canApply: true
        )
      ]
    )
  }

  func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue] {
    guard case .audio(let audio) = desired,
      audio.outputVolume.isIncluded,
      let volume = audio.outputVolume.value,
      (0...1).contains(volume)
    else {
      return [
        ValidationIssue(
          group: group,
          key: "outputVolume",
          severity: .error,
          isFatal: true,
          message: "Synthetic output volume is invalid."
        )
      ]
    }
    return []
  }

  func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan {
    guard case .audio(let audio) = desired,
      audio.outputVolume.isIncluded,
      let desiredVolume = audio.outputVolume.value
    else {
      throw SettingsLifecycleAdapterError.invalidDesiredPayload
    }
    guard desiredVolume != currentVolume else {
      return AdapterPlan(group: group)
    }

    return AdapterPlan(
      group: group,
      operations: [
        PlannedOperation(
          group: group,
          key: "outputVolume",
          summary: "Change synthetic output volume",
          preview: OperationPreview(
            previousValue: percentage(currentVolume),
            desiredValue: percentage(desiredVolume)
          ),
          payload: try JSONEncoder().encode(
            SettingsLifecycleVolumePayload(volume: desiredVolume)
          ),
          rollbackPayload: try JSONEncoder().encode(
            SettingsLifecycleVolumePayload(volume: currentVolume)
          )
        )
      ]
    )
  }

  func apply(_ operation: PlannedOperation) async -> OperationResult {
    guard
      let payload = try? JSONDecoder().decode(
        SettingsLifecycleVolumePayload.self,
        from: operation.payload
      )
    else {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "Synthetic apply payload was invalid."
      )
    }
    currentVolume = payload.volume
    appliedVolumes.append(payload.volume)
    return OperationResult(
      operationID: operation.id,
      status: .succeeded,
      message: "Synthetic output volume applied."
    )
  }

  func rollback(_ operation: PlannedOperation) async -> OperationResult {
    guard let data = operation.rollbackPayload,
      let payload = try? JSONDecoder().decode(
        SettingsLifecycleVolumePayload.self,
        from: data
      )
    else {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "Synthetic rollback payload was invalid."
      )
    }
    currentVolume = payload.volume
    return OperationResult(
      operationID: operation.id,
      status: .rolledBack,
      message: "Synthetic output volume rolled back."
    )
  }

  func diagnostics() async -> [DiagnosticEntry] { [] }

  private func percentage(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }
}

private actor SettingsLifecycleConditionReader: ConditionDisplayReading,
  ConditionAudioReading, ConditionNetworkReading, ConditionHardwareReading
{
  func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity> { [] }
  func readAudioFacts() async throws -> ConditionAudioFacts { .init() }
  func readNetworkFacts() async throws -> ConditionNetworkFacts { .init() }
  func readHardwareIdentifiers() async throws -> Set<String> { [] }
}

@MainActor
private final class SettingsLifecycleLoginItemService: LoginItemServicing {
  var status: SMAppService.Status { .notRegistered }
  func register() throws {}
  func unregister() throws {}
}
