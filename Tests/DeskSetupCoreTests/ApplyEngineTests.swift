import Foundation
import Testing

@testable import DeskSetupCore

@Suite("Apply engine planning")
struct ApplyEngineTests {
  @Test("a group toggle without included leaf settings is not applicable")
  func emptyIncludedGroupIsRejected() async {
    var settings = ProfileSettings()
    settings.audio.isIncluded = true
    let profile = DeskProfile(name: "Empty audio", settings: settings)
    let engine = ApplyEngine(registry: AdapterRegistry())

    let preparation = await engine.prepare(profile: profile, mode: .normal)

    #expect(preparation.includedGroups.isEmpty)
    #expect(preparation.rejectionReasons == [.noIncludedSettings])
    #expect(preparation.readiness.status == .unavailable)
  }

  @Test("normal mode rejects an unavailable included group")
  func normalRejectsUnavailableGroup() async throws {
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      capability: AdapterCapability(
        group: .audio,
        state: .temporarilyUnavailable,
        reason: "The selected audio device is disconnected."
      )
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let preparation = await engine.prepare(
      profile: makeProfile(including: [.audio]),
      mode: .normal
    )

    #expect(!preparation.canExecute)
    #expect(preparation.rejectionReasons.contains(.unavailableItems))
    #expect(preparation.readiness.status == .unavailable)
    #expect(preparation.operations.isEmpty)
    #expect(await adapter.recordedInvocations() == [.capability])
  }

  @Test("normal mode rejects and filters a fatal item")
  func normalRejectsFatalItem() async throws {
    let operation = PlannedOperation(group: .audio, key: "defaultOutput", summary: "Output")
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      validationIssues: [
        ValidationIssue(
          group: .audio,
          key: operation.key,
          severity: .error,
          isFatal: true,
          message: "The output device is ambiguous."
        )
      ],
      plan: AdapterPlan(group: .audio, operations: [operation])
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let preparation = await engine.prepare(
      profile: makeProfile(including: [.audio]),
      mode: .normal
    )

    #expect(!preparation.canExecute)
    #expect(preparation.rejectionReasons.contains(.fatalValidationIssues))
    #expect(preparation.rejectionReasons.contains(.unavailableItems))
    #expect(preparation.operations.isEmpty)
    #expect(preparation.omissions.map(\.key) == [operation.key])
    #expect(
      await adapter.recordedInvocations() == [
        .capability,
        .snapshot,
        .validate,
        .plan(.normal),
      ])
  }

  @Test("force mode rejects a zero-operation plan")
  func forceRejectsZeroOperations() async throws {
    let adapter = MockSystemSettingsAdapter(
      group: .network,
      plan: AdapterPlan(
        group: .network,
        omissions: [
          PlanOmission(
            group: .network,
            key: "wifiSSID",
            status: .skipped,
            reason: "The saved network is unavailable."
          )
        ]
      )
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let preparation = await engine.prepare(
      profile: makeProfile(including: [.network]),
      mode: .force
    )

    #expect(!preparation.canExecute)
    #expect(preparation.rejectionReasons == [.noOperations])
    #expect(preparation.readiness.status == .unavailable)
    #expect(preparation.omissions.count == 1)
  }

  @Test("operations sort by risk and then safe group order")
  func deterministicOperationOrdering() async throws {
    let inputLow = PlannedOperation(group: .input, key: "input.low", summary: "Input low")
    let inputModerate = PlannedOperation(
      group: .input,
      key: "input.moderate",
      summary: "Input moderate",
      risk: .moderate
    )
    let audioLow = PlannedOperation(group: .audio, key: "audio.low", summary: "Audio low")
    let networkLow = PlannedOperation(group: .network, key: "network.low", summary: "Network low")
    let displayLow = PlannedOperation(group: .display, key: "display.low", summary: "Display low")
    let displayHigh = PlannedOperation(
      group: .display,
      key: "display.high",
      summary: "Display high",
      risk: .high
    )

    let adapters: [any SystemSettingsAdapter] = [
      MockSystemSettingsAdapter(
        group: .display,
        plan: AdapterPlan(group: .display, operations: [displayHigh, displayLow])
      ),
      MockSystemSettingsAdapter(
        group: .network,
        plan: AdapterPlan(group: .network, operations: [networkLow])
      ),
      MockSystemSettingsAdapter(
        group: .audio,
        plan: AdapterPlan(group: .audio, operations: [audioLow])
      ),
      MockSystemSettingsAdapter(
        group: .input,
        plan: AdapterPlan(group: .input, operations: [inputModerate, inputLow])
      ),
    ]
    let engine = ApplyEngine(registry: try AdapterRegistry(adapters))

    let preparation = await engine.prepare(
      profile: makeProfile(including: Set(SettingGroup.allCases)),
      mode: .normal
    )

    #expect(preparation.canExecute)
    #expect(
      preparation.operations.map(\.key) == [
        "input.low",
        "audio.low",
        "network.low",
        "display.low",
        "input.moderate",
        "display.high",
      ])
  }

  @Test("execution results decode when legacy data omits the safety token")
  func executionResultCodableCompatibility() async throws {
    let operation = PlannedOperation(group: .input, key: "low", summary: "Low risk")
    let adapter = MockSystemSettingsAdapter(
      group: .input,
      plan: AdapterPlan(group: .input, operations: [operation])
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))
    let result = await engine.apply(
      profile: makeProfile(including: [.input]),
      mode: .normal
    )
    let encoded = try JSONEncoder().encode(result)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "safetyConfirmationID")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(
      ApplyExecutionResult.self,
      from: legacyData
    )

    #expect(decoded.safetyConfirmationID == nil)
    #expect(decoded.status == result.status)
    #expect(decoded.itemResults == result.itemResults)
  }

  @Test("fresh execution plans ignore generated metadata but detect stale rollback state")
  func executionEquivalenceProtectsRollbackState() async throws {
    let operation = PlannedOperation(
      group: .input,
      key: "pointer",
      summary: "Change pointer speed",
      risk: .moderate,
      payload: Data([1]),
      rollbackPayload: Data([0])
    )
    let adapter = MockSystemSettingsAdapter(
      group: .input,
      validationIssues: [
        ValidationIssue(
          group: .input,
          key: "notice",
          severity: .notice,
          isFatal: false,
          message: "Experimental preference."
        )
      ],
      plan: AdapterPlan(
        group: .input,
        operations: [operation],
        omissions: [
          PlanOmission(
            group: .input,
            key: "optional",
            status: .skipped,
            reason: "Optional item is unavailable."
          )
        ]
      )
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))
    let preview = await engine.prepare(
      profile: makeProfile(including: [.input]),
      mode: .force
    )
    var refreshed = preview
    refreshed.preparedAt = preview.preparedAt.addingTimeInterval(30)
    refreshed.operations[0].id = UUID()
    refreshed.omissions[0].id = UUID()
    refreshed.validationIssues[0].id = UUID()
    refreshed.snapshots[0].capturedAt = preview.preparedAt.addingTimeInterval(30)

    #expect(preview.isExecutionEquivalent(to: refreshed))

    refreshed.operations[0].rollbackPayload = Data([9])
    #expect(!preview.isExecutionEquivalent(to: refreshed))
  }

  @Test("a failed nonfatal partial write is restored before later operations continue")
  func failedNonfatalOperationSelfRollsBack() async throws {
    let first = PlannedOperation(
      group: .input,
      key: "first",
      summary: "First",
      rollbackPayload: Data([0])
    )
    let partialFailure = PlannedOperation(
      group: .input,
      key: "partial",
      summary: "Partial",
      isFatalOnFailure: false,
      rollbackPayload: Data([1])
    )
    let last = PlannedOperation(
      group: .input,
      key: "last",
      summary: "Last",
      rollbackPayload: Data([2])
    )
    let adapter = MockSystemSettingsAdapter(
      group: .input,
      plan: AdapterPlan(group: .input, operations: [first, partialFailure, last]),
      applyResults: [
        partialFailure.id: OperationResult(
          operationID: partialFailure.id,
          status: .failed,
          message: "The write changed state before reporting failure."
        )
      ]
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let result = await engine.apply(
      profile: makeProfile(including: [.input]),
      mode: .normal
    )

    #expect(result.status == .failed)
    #expect(result.fatalOperationID == nil)
    #expect(result.rollbackResults.map(\.key) == ["partial"])
    #expect(result.rollbackResults.map(\.status) == [.rolledBack])
    #expect(
      await adapter.recordedInvocations() == [
        .capability,
        .snapshot,
        .validate,
        .plan(.normal),
        .apply(first.id),
        .apply(partialFailure.id),
        .rollback(partialFailure.id),
        .apply(last.id),
      ]
    )
  }
}

private func makeProfile(including groups: Set<SettingGroup>) -> DeskProfile {
  var settings = ProfileSettings()
  settings.display.isIncluded = groups.contains(.display)
  if groups.contains(.display) {
    settings.display.value.displays = [testDisplayTarget()]
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
  return DeskProfile(name: "Test profile", settings: settings)
}

private func testDisplayTarget() -> DisplayTargetSettings {
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
