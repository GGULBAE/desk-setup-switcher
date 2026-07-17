import Foundation
import ServiceManagement
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher
@testable import DeskSetupSystem

@Suite("Application apply handoff", .serialized)
@MainActor
struct ApplicationModelApplyTests {
  @Test("confirmed stable preview reaches the adapter exactly once")
  func stablePreviewExecutes() async throws {
    let fixture = try await makeFixture(planBehavior: .stable)
    defer { fixture.cleanup() }
    let model = fixture.model

    #expect(model.executePendingApply() == .rejected(.noPendingRequest))
    model.start()
    #expect(
      await waitUntil {
        model.profiles.count == 1 && !model.isProfileMutationLocked
          && !model.isReadinessRefreshInProgress
      }
    )
    let profile = try #require(model.profiles.first)

    model.prepareApply(profile: profile, mode: .normal)
    #expect(await waitUntil { model.pendingApply != nil })
    #expect(model.pendingApply?.reviewReason == .initial)
    #expect(model.executePendingApply() == .started)
    #expect(
      await waitUntil {
        model.lastApplyResult != nil && !model.isApplyTransactionInProgress
      }
    )

    #expect(await fixture.adapter.applyCount == 1)
    #expect(model.lastApplyResult?.didExecute == true)
  }

  @Test("changed preflight returns a visible refreshed review without applying")
  func changedPreflightRequiresAnotherReview() async throws {
    let fixture = try await makeFixture(planBehavior: .changesOnExecutionPreflight)
    defer { fixture.cleanup() }
    let model = fixture.model

    model.start()
    #expect(
      await waitUntil {
        model.profiles.count == 1 && !model.isProfileMutationLocked
          && !model.isReadinessRefreshInProgress
      }
    )
    let profile = try #require(model.profiles.first)
    model.prepareApply(profile: profile, mode: .normal)
    #expect(await waitUntil { model.pendingApply != nil })
    #expect(model.executePendingApply() == .started)
    #expect(
      await waitUntil {
        model.pendingApply?.reviewReason == .refreshedSystemState
          && !model.isApplyTransactionInProgress
      }
    )

    #expect(await fixture.adapter.applyCount == 0)
    #expect(model.lastApplyResult == nil)
  }

  @Test("closing a window invalidates a late read-only preview preparation")
  func windowCloseInvalidatesLatePreparation() async throws {
    let fixture = try await makeFixture(planBehavior: .stable)
    defer { fixture.cleanup() }
    let model = fixture.model

    model.start()
    #expect(
      await waitUntil {
        model.profiles.count == 1 && !model.isProfileMutationLocked
          && !model.isReadinessRefreshInProgress
      }
    )
    let profile = try #require(model.profiles.first)
    let editor = ProfileEditorModel()
    editor.initialize(profiles: model.profiles, preferredProfileID: profile.id)
    let presentation = TrayPresentationModel(
      model: model,
      locationPermission: LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .authorized
      ),
      profileEditor: editor
    )

    await fixture.adapter.blockNextPlan()
    presentation.setWorkflowDestination(.applyPreview(profile.id, .normal))
    presentation.beginApplyWorkflow(profileID: profile.id, mode: .normal)
    await fixture.adapter.waitUntilPlanIsBlocked()
    #expect(model.isPreparingApply(for: profile))
    #expect(model.pendingApply == nil)

    presentation.handleWorkflowWindowClose()
    #expect(presentation.workflowDestination == nil)
    #expect(model.pendingApply == nil)

    await fixture.adapter.releaseBlockedPlan()
    #expect(await waitUntil { !model.isPreparingApply(for: profile) })
    #expect(model.pendingApply == nil)
  }

  @Test("closing and immediately reopening the same profile starts a fresh preview")
  func immediateSameProfileReopenStartsFreshPreparation() async throws {
    let fixture = try await makeFixture(planBehavior: .stable)
    defer { fixture.cleanup() }
    let model = fixture.model

    model.start()
    #expect(
      await waitUntil {
        model.profiles.count == 1 && !model.isProfileMutationLocked
          && !model.isReadinessRefreshInProgress
      }
    )
    let profile = try #require(model.profiles.first)
    let editor = ProfileEditorModel()
    editor.initialize(profiles: model.profiles, preferredProfileID: profile.id)
    let presentation = TrayPresentationModel(
      model: model,
      locationPermission: LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .authorized
      ),
      profileEditor: editor
    )

    await fixture.adapter.blockNextPlan()
    presentation.setWorkflowDestination(.applyPreview(profile.id, .normal))
    presentation.beginApplyWorkflow(profileID: profile.id, mode: .normal)
    await fixture.adapter.waitUntilPlanIsBlocked()
    #expect(model.isPreparingApply(for: profile))

    presentation.handleWorkflowWindowClose()
    #expect(!model.isPreparingApply(for: profile))
    presentation.setWorkflowDestination(.applyPreview(profile.id, .normal))
    presentation.beginApplyWorkflow(profileID: profile.id, mode: .normal)

    #expect(await waitUntil { model.pendingApply?.profile.id == profile.id })
    #expect(presentation.workflowDestination == .applyPreview(profile.id, .normal))

    await fixture.adapter.releaseBlockedPlan()
    for _ in 0..<20 {
      await Task.yield()
    }
    #expect(model.pendingApply?.profile.id == profile.id)
  }

  private func makeFixture(planBehavior: SequencedApplyAdapter.PlanBehavior) async throws
    -> ApplyModelFixture
  {
    let identifier = "DeskSetupSwitcherTests.Apply.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      identifier,
      isDirectory: true
    )
    let defaults = try #require(UserDefaults(suiteName: identifier))
    defaults.removePersistentDomain(forName: identifier)
    defaults.set(true, forKey: "launchAtLoginPreferenceCreated")
    defaults.set(false, forKey: "launchAtLoginEnabled")

    let profile = DeskProfile(
      name: "Synthetic apply",
      settings: ProfileSettings(
        audio: SettingGroupConfiguration(
          isIncluded: true,
          value: AudioProfileSettings(
            outputVolume: SettingOption(isIncluded: true, value: 0.2)
          )
        )
      )
    )
    let store = ProfileStore(directoryURL: directory)
    _ = try await store.load()
    _ = try await store.createProfile(profile, selecting: true)

    let adapter = SequencedApplyAdapter(planBehavior: planBehavior)
    let conditionReader = EmptyConditionReader()
    let model = ApplicationModel(
      profileStore: store,
      snapshotCoordinator: SystemSnapshotCoordinator(adapters: [adapter]),
      conditionContextProvider: ConditionContextProvider(
        displayReader: conditionReader,
        audioReader: conditionReader,
        networkReader: conditionReader,
        hardwareReader: conditionReader,
        locationReader: conditionReader
      ),
      applyEngine: ApplyEngine(registry: try AdapterRegistry([adapter])),
      diagnosticLog: nil,
      defaults: defaults,
      loginItemService: NoopLoginItemService()
    )
    return ApplyModelFixture(
      model: model,
      adapter: adapter,
      cleanup: {
        defaults.removePersistentDomain(forName: identifier)
        try? FileManager.default.removeItem(at: directory)
      }
    )
  }

  private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<2_000 {
      if condition() { return true }
      await Task.yield()
    }
    return condition()
  }
}

@MainActor
private struct ApplyModelFixture {
  let model: ApplicationModel
  let adapter: SequencedApplyAdapter
  let cleanup: () -> Void
}

private actor SequencedApplyAdapter: SystemSettingsAdapter {
  enum PlanBehavior: Equatable, Sendable {
    case stable
    case changesOnExecutionPreflight
  }

  nonisolated let group: SettingGroup = .audio
  private let planBehavior: PlanBehavior
  private var planCount = 0
  private(set) var applyCount = 0
  private var shouldBlockNextPlan = false
  private var isPlanBlocked = false
  private var blockedPlanWaiters: [CheckedContinuation<Void, Never>] = []
  private var planReleaseWaiters: [CheckedContinuation<Void, Never>] = []

  init(planBehavior: PlanBehavior) {
    self.planBehavior = planBehavior
  }

  func blockNextPlan() {
    shouldBlockNextPlan = true
  }

  func waitUntilPlanIsBlocked() async {
    guard !isPlanBlocked else { return }
    await withCheckedContinuation { blockedPlanWaiters.append($0) }
  }

  func releaseBlockedPlan() {
    let waiters = planReleaseWaiters
    planReleaseWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }

  func capability() async -> AdapterCapability {
    AdapterCapability(group: group, state: .supported, reason: "Synthetic audio is available.")
  }

  func snapshot() async throws -> AdapterSnapshot {
    AdapterSnapshot(
      group: group,
      capturedAt: Date(timeIntervalSince1970: 0),
      payload: .audio(
        AudioProfileSettings(
          outputVolume: SettingOption(isIncluded: true, value: 0.5)
        )
      ),
      items: []
    )
  }

  func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue] {
    []
  }

  func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan {
    if shouldBlockNextPlan {
      shouldBlockNextPlan = false
      isPlanBlocked = true
      let waiters = blockedPlanWaiters
      blockedPlanWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      await withCheckedContinuation { planReleaseWaiters.append($0) }
      isPlanBlocked = false
    }
    planCount += 1
    let usesChangedRollback =
      planBehavior == .changesOnExecutionPreflight && planCount >= 3
    return AdapterPlan(
      group: group,
      operations: [
        PlannedOperation(
          group: group,
          key: "outputVolume",
          summary: "Change output volume",
          preview: OperationPreview(
            previousValue: usesChangedRollback ? "51%" : "50%",
            desiredValue: "20%"
          ),
          payload: Data([0x20]),
          rollbackPayload: Data([usesChangedRollback ? 0x51 : 0x50])
        )
      ]
    )
  }

  func apply(_ operation: PlannedOperation) async -> OperationResult {
    applyCount += 1
    return OperationResult(
      operationID: operation.id,
      status: .succeeded,
      message: "Synthetic apply succeeded."
    )
  }

  func rollback(_ operation: PlannedOperation) async -> OperationResult {
    OperationResult(
      operationID: operation.id,
      status: .rolledBack,
      message: "Synthetic rollback succeeded."
    )
  }

  func diagnostics() async -> [DiagnosticEntry] { [] }
}

private actor EmptyConditionReader: ConditionDisplayReading, ConditionAudioReading,
  ConditionNetworkReading, ConditionHardwareReading, ConditionLocationReading
{
  func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity> { [] }
  func readAudioFacts() async throws -> ConditionAudioFacts { .init() }
  func readNetworkFacts() async throws -> ConditionNetworkFacts { .init() }
  func readHardwareIdentifiers() async throws -> Set<String> { [] }
  func readAuthorizedLocation() async throws -> LocationRegion? { nil }
}

@MainActor
private final class NoopLoginItemService: LoginItemServicing {
  var status: SMAppService.Status { .notRegistered }
  func register() throws {}
  func unregister() throws {}
}
