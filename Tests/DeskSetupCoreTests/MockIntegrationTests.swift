import Foundation
import Testing

@testable import DeskSetupCore

@Suite("Mock apply integration")
struct MockIntegrationTests {
  @Test("force mode applies available operations and records omissions")
  func forceModeAppliesPartialPlan() async throws {
    let audioOperation = PlannedOperation(
      group: .audio,
      key: "defaultOutput",
      summary: "Set default output"
    )
    let audioAdapter = MockSystemSettingsAdapter(
      group: .audio,
      plan: AdapterPlan(group: .audio, operations: [audioOperation])
    )
    let displayAdapter = MockSystemSettingsAdapter(
      group: .display,
      capability: AdapterCapability(
        group: .display,
        state: .unsupported,
        reason: "No safe display adapter is available."
      )
    )
    let engine = ApplyEngine(
      registry: try AdapterRegistry([audioAdapter, displayAdapter])
    )

    let result = await engine.apply(
      profile: makeIntegrationProfile(including: [.audio, .display]),
      mode: .force
    )

    #expect(result.didExecute)
    #expect(result.status == .applied)
    #expect(result.preparation.readiness.status == .partial)
    #expect(result.itemResults.map(\.status) == [.unsupported, .succeeded])
    #expect(await displayAdapter.recordedInvocations() == [.capability])
    #expect(
      await audioAdapter.recordedInvocations() == [
        .capability,
        .snapshot,
        .validate,
        .plan(.force),
        .apply(audioOperation.id),
      ])
  }

  @Test("fatal failure rolls back in reverse order and keeps rollback failures separate")
  func fatalFailureRollsBackInReverse() async throws {
    let first = PlannedOperation(group: .audio, key: "first", summary: "First")
    let second = PlannedOperation(group: .audio, key: "second", summary: "Second")
    let fatal = PlannedOperation(
      group: .audio,
      key: "fatal",
      summary: "Fatal",
      isFatalOnFailure: true
    )
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      plan: AdapterPlan(group: .audio, operations: [first, second, fatal]),
      applyResults: [
        fatal.id: OperationResult(
          operationID: fatal.id,
          status: .failed,
          message: "Synthetic fatal failure."
        )
      ],
      rollbackResults: [
        second.id: OperationResult(
          operationID: second.id,
          status: .rolledBack,
          message: "Second rolled back."
        ),
        first.id: OperationResult(
          operationID: first.id,
          status: .failed,
          message: "Synthetic rollback failure."
        ),
      ]
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let result = await engine.apply(
      profile: makeIntegrationProfile(including: [.audio]),
      mode: .normal
    )

    #expect(result.didExecute)
    #expect(result.status == .failed)
    #expect(result.fatalOperationID == fatal.id)
    #expect(result.itemResults.map(\.status) == [.succeeded, .succeeded, .failed])
    #expect(result.rollbackResults.map(\.key) == ["second", "first"])
    #expect(result.rollbackResults.map(\.status) == [.rolledBack, .rollbackFailed])
    #expect(result.applicationSummary.items.count == 5)
    #expect(
      await adapter.recordedInvocations() == [
        .capability,
        .snapshot,
        .validate,
        .plan(.normal),
        .apply(first.id),
        .apply(second.id),
        .apply(fatal.id),
        .rollback(second.id),
        .rollback(first.id),
      ])
  }

  @Test("force mode omits a fatal item but applies safe items from the same group")
  func forceModeFiltersFatalItem() async throws {
    let unsafe = PlannedOperation(group: .network, key: "staticIP", summary: "Static IP")
    let safe = PlannedOperation(group: .network, key: "wifiPower", summary: "Wi-Fi power")
    let adapter = MockSystemSettingsAdapter(
      group: .network,
      validationIssues: [
        ValidationIssue(
          group: .network,
          key: unsafe.key,
          severity: .error,
          isFatal: true,
          message: "Administrative authorization is unavailable."
        )
      ],
      plan: AdapterPlan(group: .network, operations: [unsafe, safe])
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let result = await engine.apply(
      profile: makeIntegrationProfile(including: [.network]),
      mode: .force
    )

    #expect(result.didExecute)
    #expect(result.status == .applied)
    #expect(result.preparation.operations.map(\.id) == [safe.id])
    #expect(result.preparation.omissions.map(\.key) == [unsafe.key])
    #expect(result.itemResults.map(\.status) == [.skipped, .succeeded])
    #expect(await adapter.recordedInvocations().suffix(1) == [.apply(safe.id)])
  }

  @Test("a fatal operation with backup state is rolled back even when apply reports failure")
  func fatalAttemptIsConservativelyRolledBack() async throws {
    let fatal = PlannedOperation(
      group: .network,
      key: "association",
      summary: "Join network",
      isFatalOnFailure: true,
      rollbackPayload: Data([0x01])
    )
    let adapter = MockSystemSettingsAdapter(
      group: .network,
      plan: AdapterPlan(group: .network, operations: [fatal]),
      applyResults: [
        fatal.id: OperationResult(
          operationID: fatal.id,
          status: .failed,
          message: "The operation changed state before reporting failure."
        )
      ]
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let result = await engine.apply(
      profile: makeIntegrationProfile(including: [.network]),
      mode: .normal
    )

    #expect(result.status == .failed)
    #expect(result.rollbackResults.map(\.key) == ["association"])
    #expect(result.rollbackResults.map(\.status) == [.rolledBack])
    #expect(
      await adapter.recordedInvocations().suffix(2) == [
        .apply(fatal.id),
        .rollback(fatal.id),
      ])
  }

  @Test("a restored nonfatal operation failure does not stop later operations")
  func nonfatalFailureContinues() async throws {
    let failed = PlannedOperation(
      group: .audio,
      key: "volume",
      summary: "Volume",
      rollbackPayload: Data([0x01])
    )
    let later = PlannedOperation(group: .audio, key: "mute", summary: "Mute")
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      plan: AdapterPlan(group: .audio, operations: [failed, later]),
      applyResults: [
        failed.id: OperationResult(
          operationID: failed.id,
          status: .failed,
          message: "Volume is unavailable."
        )
      ]
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let result = await engine.apply(
      profile: makeIntegrationProfile(including: [.audio]),
      mode: .normal
    )

    #expect(result.status == .failed)
    #expect(result.itemResults.map(\.status) == [.failed, .succeeded])
    #expect(result.rollbackResults.map(\.status) == [.rolledBack])
    #expect(
      await adapter.recordedInvocations().suffix(3) == [
        .apply(failed.id),
        .rollback(failed.id),
        .apply(later.id),
      ])
  }
}

private func makeIntegrationProfile(including groups: Set<SettingGroup>) -> DeskProfile {
  var settings = ProfileSettings()
  settings.display.isIncluded = groups.contains(.display)
  if groups.contains(.display) {
    settings.display.value.displays = [integrationDisplayTarget()]
  }
  settings.audio.isIncluded = groups.contains(.audio)
  settings.audio.value.defaultOutputUID = .init(
    isIncluded: groups.contains(.audio), value: "test-output")
  settings.network.isIncluded = groups.contains(.network)
  settings.network.value.wifiPower = .init(
    isIncluded: groups.contains(.network), value: true)
  settings.input.isIncluded = groups.contains(.input)
  settings.input.value.pointerSpeed = .init(
    isIncluded: groups.contains(.input), value: 1)
  return DeskProfile(name: "Integration profile", settings: settings)
}

private func integrationDisplayTarget() -> DisplayTargetSettings {
  DisplayTargetSettings(
    identity: DisplayIdentity(uuid: UUID()),
    isPrimary: .init(value: true),
    origin: .init(isIncluded: false, value: DisplayPoint(x: 0, y: 0)),
    mirroring: .init(isIncluded: false, value: .extended),
    mode: .init(
      isIncluded: false,
      value: DisplayMode(width: 1, height: 1, refreshRate: 0)
    ),
    rotationDegrees: .init(isIncluded: false, value: 0),
    isActive: .init(isIncluded: false, value: true)
  )
}
