import Foundation
import Testing

@testable import DeskSetupCore

@Suite("Apply engine planning")
struct ApplyEngineTests {
  @Test("planning defensively excludes unsupported leaves without mutating the profile value")
  func planningNormalizesUnsupportedLeaves() async throws {
    let displayOperation = PlannedOperation(
      group: .display,
      key: "display.atomic-configuration",
      summary: "Display"
    )
    let displayAdapter = MockSystemSettingsAdapter(
      group: .display,
      plan: AdapterPlan(group: .display, operations: [displayOperation])
    )
    let networkAdapter = MockSystemSettingsAdapter(group: .network)
    let engine = ApplyEngine(
      registry: try AdapterRegistry([displayAdapter, networkAdapter])
    )
    var profile = makeProfile(including: [.display])
    profile.settings.display.value.displays[0].rotationDegrees = .init(value: 90)
    profile.settings.network = .init(
      isIncluded: true,
      value: .init(dnsServers: .init(value: ["192.0.2.53"]))
    )

    let preparation = await engine.prepare(profile: profile, mode: .force)

    #expect(preparation.includedGroups == [.display])
    #expect(preparation.operations.map(\.key) == [displayOperation.key])
    #expect(preparation.omissions.isEmpty)
    #expect(await networkAdapter.recordedInvocations().isEmpty)
    #expect(profile.settings.display.value.displays[0].rotationDegrees.isIncluded)
    #expect(profile.settings.display.value.displays[0].rotationDegrees.value == 90)
    #expect(profile.settings.network.value.dnsServers.isIncluded)
    #expect(profile.settings.network.value.dnsServers.value == ["192.0.2.53"])
  }

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

  @Test("planning cannot execute a mixed primary-display inclusion state")
  func mixedPrimaryDisplayInclusionCannotExecute() async throws {
    let adapter = MockSystemSettingsAdapter(group: .display)
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))
    var profile = makeProfile(including: [.display])
    var secondDisplay = testDisplayTarget()
    profile.settings.display.value.displays[0].isPrimary = .init(
      isIncluded: true,
      value: false
    )
    secondDisplay.isPrimary = .init(isIncluded: false, value: true)
    profile.settings.display.value.displays.append(secondDisplay)

    let preparation = await engine.prepare(profile: profile, mode: .force)

    #expect(preparation.includedGroups.isEmpty)
    #expect(preparation.rejectionReasons == [.noIncludedSettings, .noOperations])
    #expect(await adapter.recordedInvocations().isEmpty)
  }

  @Test("legacy conditions do not block the default manual apply policy")
  func legacyConditionsAreDormantForManualApply() async throws {
    let operation = PlannedOperation(
      group: .audio,
      key: "defaultOutput",
      summary: "Synthetic output change"
    )
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      plan: AdapterPlan(group: .audio, operations: [operation])
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))
    var profile = makeProfile(including: [.audio])
    profile.conditions = ProfileConditionSet(
      conditions: [ProfileCondition(kind: .wifiSSID("Synthetic Legacy Network"))]
    )

    let manualPreparation = await engine.prepare(profile: profile, mode: .normal)
    let explicitlyConditionedPreparation = await engine.prepare(
      profile: profile,
      mode: .normal,
      conditionsSatisfied: false
    )

    #expect(manualPreparation.canExecute)
    #expect(manualPreparation.operations.map(\.key) == [operation.key])
    #expect(
      explicitlyConditionedPreparation.rejectionReasons.contains(.conditionsUnsatisfied)
    )
  }

  @Test("a legacy false activation value remains visible and fully applicable")
  func legacyDisabledProfileStillApplies() async throws {
    let operation = PlannedOperation(
      group: .audio,
      key: "defaultOutput",
      summary: "Synthetic output change"
    )
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      plan: AdapterPlan(group: .audio, operations: [operation])
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))
    var profile = makeProfile(including: [.audio])
    profile.isEnabled = false

    let preparation = await engine.prepare(profile: profile, mode: .normal)
    let result = await engine.execute(preparation)

    #expect(preparation.canExecute)
    #expect(preparation.operations.map(\.key) == [operation.key])
    #expect(result.didExecute)
    #expect(result.itemResults.map(\.status) == [.succeeded])
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
    let audioModerate = PlannedOperation(
      group: .audio,
      key: "audio.moderate",
      summary: "Audio moderate",
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
    let inputAdapter = MockSystemSettingsAdapter(
      group: .input,
      plan: AdapterPlan(group: .input, operations: [inputLow])
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
        plan: AdapterPlan(group: .audio, operations: [audioModerate, audioLow])
      ),
      inputAdapter,
    ]
    let engine = ApplyEngine(registry: try AdapterRegistry(adapters))

    let preparation = await engine.prepare(
      profile: makeProfile(including: Set(SettingGroup.allCases)),
      mode: .normal
    )

    #expect(preparation.canExecute)
    #expect(
      preparation.operations.map(\.key) == [
        "audio.low",
        "display.low",
        "audio.moderate",
        "display.high",
        "network.low",
      ])
    #expect(await inputAdapter.recordedInvocations().isEmpty)
  }

  @Test("execution results decode when legacy data omits the safety token")
  func executionResultCodableCompatibility() async throws {
    let operation = PlannedOperation(group: .audio, key: "low", summary: "Low risk")
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      plan: AdapterPlan(group: .audio, operations: [operation])
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))
    let result = await engine.apply(
      profile: makeProfile(including: [.audio]),
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
      group: .audio,
      key: "outputVolume",
      summary: "Change output volume",
      risk: .moderate,
      payload: Data([1]),
      rollbackPayload: Data([0])
    )
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      validationIssues: [
        ValidationIssue(
          group: .audio,
          key: "notice",
          severity: .notice,
          isFatal: false,
          message: "Synthetic capability notice."
        )
      ],
      plan: AdapterPlan(
        group: .audio,
        operations: [operation],
        omissions: [
          PlanOmission(
            group: .audio,
            key: "optional",
            status: .skipped,
            reason: "Optional item is unavailable."
          )
        ]
      )
    )
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))
    let preview = await engine.prepare(
      profile: makeProfile(including: [.audio]),
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
      group: .audio,
      key: "first",
      summary: "First",
      rollbackPayload: Data([0])
    )
    let partialFailure = PlannedOperation(
      group: .audio,
      key: "partial",
      summary: "Partial",
      isFatalOnFailure: false,
      rollbackPayload: Data([1])
    )
    let last = PlannedOperation(
      group: .audio,
      key: "last",
      summary: "Last",
      rollbackPayload: Data([2])
    )
    let adapter = MockSystemSettingsAdapter(
      group: .audio,
      plan: AdapterPlan(group: .audio, operations: [first, partialFailure, last]),
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
      profile: makeProfile(including: [.audio]),
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
  settings.network.value.serviceIPv4 =
    groups.contains(.network)
    ? [
      NetworkServiceIPv4Settings(
        identity: .init(
          kind: .ethernet,
          serviceName: "Synthetic Ethernet",
          interfaceType: "Ethernet"
        ),
        configuration: .init(value: .dhcp)
      )
    ] : []
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
