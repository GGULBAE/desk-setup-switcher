import Foundation
import Testing

@testable import DeskSetupSystem

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

@Suite("Core Graphics display adapter")
struct DisplayAdapterTests {
  @Test("snapshot captures stable identity, bounds, primary, mirroring, and mode")
  func snapshotCapturesPublicDisplayState() async throws {
    var displays = makeDisplays()
    displays[1].bounds = DisplaySystemBounds(x: 0, y: 0, width: 2560, height: 1440)
    displays[1].mirrorSourceSessionID = displays[0].sessionID
    let api = MockDisplaySystemAPI(displays: displays)
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)

    let snapshot = try await adapter.snapshot()
    let settings = try displaySettings(from: snapshot)

    #expect(snapshot.group == .display)
    #expect(settings.displays.count == 2)
    #expect(settings.displays[0].identity.uuid == displays[0].identity.uuid)
    #expect(settings.displays[0].identity.vendorID == 1_555)
    #expect(settings.displays[0].identity.modelID == 2_001)
    #expect(settings.displays[0].identity.serialNumber == 90_001)
    #expect(settings.displays[0].identity.productName == "Built-in Test Panel")
    #expect(settings.displays[0].identity.isBuiltIn)
    #expect(settings.displays[0].isPrimary.value)
    #expect(settings.displays[0].origin.value == DisplayPoint(x: 0, y: 0))
    #expect(settings.displays[0].mode.value == displays[0].currentMode)
    #expect(settings.displays[1].mirroring.value == .mirrors(displays[0].identity))
    #expect(snapshot.items.allSatisfy { $0.state == .storable })
  }

  @Test("an unchanged snapshot plans no operation")
  func noOpPlanIsEmpty() async throws {
    let api = MockDisplaySystemAPI(displays: makeDisplays())
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let settings = try displaySettings(from: snapshot)

    let plan = try await adapter.plan(
      .display(settings),
      from: snapshot,
      mode: .normal
    )

    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.isEmpty)
    #expect(plan.issues.isEmpty)
  }

  @Test("supported changes produce one high-risk operation and a complete rollback")
  func plansAtomicChangeAndRollback() async throws {
    let displays = makeDisplays()
    let api = MockDisplaySystemAPI(displays: displays)
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    let externalIndex = try #require(
      settings.displays.firstIndex { !$0.identity.isBuiltIn }
    )
    settings.displays[externalIndex].origin.value = DisplayPoint(x: 1_800, y: 100)
    settings.displays[externalIndex].mode.value = DisplayMode(
      width: 1_920,
      height: 1_080,
      refreshRate: 60
    )

    let plan = try await adapter.plan(
      .display(settings),
      from: snapshot,
      mode: .normal
    )
    let operation = try #require(plan.operations.first)
    let rollbackData = try #require(operation.rollbackPayload)
    let requested = try JSONDecoder().decode(
      DisplayAtomicConfiguration.self,
      from: operation.payload
    )
    let rollback = try JSONDecoder().decode(
      DisplayAtomicConfiguration.self,
      from: rollbackData
    )
    let requestedExternal = try #require(
      requested.targets.first { !$0.identity.isBuiltIn }
    )
    let rollbackExternal = try #require(
      rollback.targets.first { !$0.identity.isBuiltIn }
    )

    #expect(plan.operations.count == 1)
    #expect(operation.risk == .high)
    #expect(operation.isFatalOnFailure)
    #expect(operation.preview?.previousValue.contains("x:1728 y:0") == true)
    #expect(operation.preview?.desiredValue.contains("x:1800 y:100") == true)
    #expect(requested.targets.count == displays.count)
    #expect(rollback.targets.count == displays.count)
    #expect(requestedExternal.origin == DisplayPoint(x: 1_800, y: 100))
    #expect(requestedExternal.mode.refreshRate == 59.94)
    #expect(rollbackExternal.origin == DisplayPoint(x: 1_728, y: 0))
    #expect(rollbackExternal.mode == displays[1].currentMode)

    let applyResult = await adapter.apply(operation)
    let confirmResult = await adapter.confirm(operation)
    let rollbackResult = await adapter.rollback(operation)
    let calls = await api.recordedApplyCalls()

    #expect(applyResult.status == .succeeded)
    #expect(confirmResult.status == .succeeded)
    #expect(rollbackResult.status == .rolledBack)
    #expect(calls.count == 3)
    #expect(calls[0].configuration == requested)
    #expect(calls[1].configuration == requested)
    #expect(calls[2].configuration == rollback)
    #expect(calls.map(\.commitScope) == [.appOnly, .sessionOnly, .sessionOnly])
  }

  @Test("an unnamed built-in display has a friendly preview label")
  func unnamedBuiltInPreviewIsFriendly() async throws {
    var displays = makeDisplays()
    displays[0].identity.productName = nil
    let api = MockDisplaySystemAPI(displays: displays)
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    settings.displays[1].origin.value = DisplayPoint(x: 1_900, y: 0)

    let plan = try await adapter.plan(
      .display(settings),
      from: snapshot,
      mode: .normal
    )
    let preview = try #require(plan.operations.first?.preview)

    #expect(preview.previousValue.contains("Built-in display"))
    #expect(preview.desiredValue.contains("Built-in display"))
    #expect(!preview.previousValue.contains("11111111"))
    #expect(!preview.desiredValue.contains("11111111"))
  }

  @Test("unsupported mode, rotation, and active state become omissions")
  func unsupportedPropertiesAreOmitted() async throws {
    let api = MockDisplaySystemAPI(displays: makeDisplays())
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    let externalIndex = try #require(
      settings.displays.firstIndex { !$0.identity.isBuiltIn }
    )
    settings.displays[externalIndex].origin.value = DisplayPoint(x: 1_900, y: 0)
    settings.displays[externalIndex].mode.value = DisplayMode(
      width: 800,
      height: 600,
      refreshRate: 75
    )
    settings.displays[externalIndex].rotationDegrees.value = 90
    settings.displays[externalIndex].isActive.value = false

    let validation = await adapter.validate(.display(settings), against: snapshot)
    let plan = try await adapter.plan(
      .display(settings),
      from: snapshot,
      mode: .force
    )

    #expect(validation.count == 3)
    #expect(validation.allSatisfy { !$0.isFatal })
    #expect(plan.operations.count == 1)
    #expect(plan.omissions.count == 3)
    #expect(plan.omissions.contains { $0.key.hasSuffix(".mode") })
    #expect(plan.omissions.contains { $0.key.hasSuffix(".rotation") })
    #expect(plan.omissions.contains { $0.key.hasSuffix(".active") })
    #expect(
      plan.omissions.first { $0.key.hasSuffix(".rotation") }?.reason
        == "Public Core Graphics does not expose display rotation mutation."
    )
  }

  @Test("selecting a new primary translates the complete topology")
  func primarySelectionTranslatesTopology() async throws {
    let api = MockDisplaySystemAPI(displays: makeDisplays())
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    let builtInIndex = try #require(
      settings.displays.firstIndex { $0.identity.isBuiltIn }
    )
    let externalIndex = try #require(
      settings.displays.firstIndex { !$0.identity.isBuiltIn }
    )
    settings.displays[builtInIndex].isPrimary.value = false
    settings.displays[externalIndex].isPrimary.value = true

    let plan = try await adapter.plan(
      .display(settings),
      from: snapshot,
      mode: .normal
    )
    let operation = try #require(plan.operations.first)
    let requested = try JSONDecoder().decode(
      DisplayAtomicConfiguration.self,
      from: operation.payload
    )
    let requestedBuiltIn = try #require(
      requested.targets.first { $0.identity.isBuiltIn }
    )
    let requestedExternal = try #require(
      requested.targets.first { !$0.identity.isBuiltIn }
    )

    #expect(plan.omissions.isEmpty)
    #expect(requestedBuiltIn.origin == DisplayPoint(x: -1_728, y: 0))
    #expect(requestedExternal.origin == DisplayPoint(x: 0, y: 0))
  }

  @Test("rotation values outside quarter turns are rejected")
  func invalidRotationIsRejected() async throws {
    let api = MockDisplaySystemAPI(displays: makeDisplays())
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    settings.displays[0].rotationDegrees.value = 45

    let plan = try await adapter.plan(
      .display(settings),
      from: snapshot,
      mode: .force
    )

    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.count == 1)
    #expect(
      plan.omissions[0].reason
        == "Display rotation must be one of 0, 90, 180, or 270 degrees."
    )
  }

  @Test("ambiguous fallback identity is never selected")
  func ambiguousIdentityIsOmitted() async throws {
    let mode = DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)
    let first = makeDisplay(
      sessionID: 1,
      uuid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      productName: "Panel A",
      originX: 0,
      mode: mode
    )
    let second = makeDisplay(
      sessionID: 2,
      uuid: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
      productName: "Panel B",
      originX: 1_920,
      mode: mode
    )
    let api = MockDisplaySystemAPI(displays: [first, second])
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let desiredIdentity = DisplayIdentity(vendorID: 1_555, modelID: 2_001)
    let desiredTarget = makeTarget(identity: desiredIdentity, mode: mode)
    let snapshot = AdapterSnapshot(
      group: .display,
      capturedAt: Date(timeIntervalSince1970: 0),
      payload: .display(.init()),
      items: []
    )

    let validation = await adapter.validate(
      .display(DisplayProfileSettings(displays: [desiredTarget])),
      against: snapshot
    )
    let plan = try await adapter.plan(
      .display(DisplayProfileSettings(displays: [desiredTarget])),
      from: snapshot,
      mode: .force
    )

    #expect(validation.count == 1)
    #expect(validation[0].message.contains("more than one"))
    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.count == 1)
  }
}

private actor MockDisplaySystemAPI: DisplaySystemAPI {
  struct ApplyCall: Hashable, Sendable {
    var configuration: DisplayAtomicConfiguration
    var commitScope: DisplayConfigurationCommitScope
  }

  private var displays: [DisplaySystemDisplay]
  private var applyCalls: [ApplyCall] = []

  init(displays: [DisplaySystemDisplay]) {
    self.displays = displays
  }

  func activeDisplays() async throws -> [DisplaySystemDisplay] {
    displays
  }

  func apply(
    _ configuration: DisplayAtomicConfiguration,
    commitScope: DisplayConfigurationCommitScope
  ) async throws {
    applyCalls.append(
      ApplyCall(configuration: configuration, commitScope: commitScope)
    )
  }

  func recordedApplyCalls() -> [ApplyCall] {
    applyCalls
  }
}

private enum DisplayTestError: Error {
  case missingDisplayPayload
}

private func displaySettings(from snapshot: AdapterSnapshot) throws -> DisplayProfileSettings {
  guard case .display(let settings)? = snapshot.payload else {
    throw DisplayTestError.missingDisplayPayload
  }
  return settings
}

private func makeDisplays() -> [DisplaySystemDisplay] {
  let builtInMode = DisplayMode(
    width: 1_728,
    height: 1_117,
    pixelWidth: 3_456,
    pixelHeight: 2_234,
    refreshRate: 120
  )
  let externalMode = DisplayMode(
    width: 2_560,
    height: 1_440,
    refreshRate: 60
  )
  return [
    DisplaySystemDisplay(
      sessionID: 101,
      identity: DisplayIdentity(
        uuid: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
        vendorID: 1_555,
        modelID: 2_001,
        serialNumber: 90_001,
        productName: "Built-in Test Panel",
        isBuiltIn: true
      ),
      bounds: DisplaySystemBounds(x: 0, y: 0, width: 1_728, height: 1_117),
      isMain: true,
      rotationDegrees: 0,
      isActive: true,
      currentMode: builtInMode,
      supportedModes: [builtInMode]
    ),
    DisplaySystemDisplay(
      sessionID: 202,
      identity: DisplayIdentity(
        uuid: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
        vendorID: 4_321,
        modelID: 8_765,
        serialNumber: 12_345,
        productName: "External Test Panel"
      ),
      bounds: DisplaySystemBounds(x: 1_728, y: 0, width: 2_560, height: 1_440),
      isMain: false,
      rotationDegrees: 0,
      isActive: true,
      currentMode: externalMode,
      supportedModes: [
        externalMode,
        DisplayMode(width: 1_920, height: 1_080, refreshRate: 59.94),
      ]
    ),
  ]
}

private func makeDisplay(
  sessionID: UInt32,
  uuid: String,
  productName: String,
  originX: Int,
  mode: DisplayMode
) -> DisplaySystemDisplay {
  DisplaySystemDisplay(
    sessionID: sessionID,
    identity: DisplayIdentity(
      uuid: UUID(uuidString: uuid),
      vendorID: 1_555,
      modelID: 2_001,
      productName: productName
    ),
    bounds: DisplaySystemBounds(
      x: originX,
      y: 0,
      width: mode.width,
      height: mode.height
    ),
    isMain: originX == 0,
    rotationDegrees: 0,
    isActive: true,
    currentMode: mode,
    supportedModes: [mode]
  )
}

private func makeTarget(
  identity: DisplayIdentity,
  mode: DisplayMode
) -> DisplayTargetSettings {
  DisplayTargetSettings(
    identity: identity,
    isPrimary: SettingOption(isIncluded: false, value: false),
    origin: SettingOption(isIncluded: false, value: DisplayPoint(x: 0, y: 0)),
    mirroring: SettingOption(isIncluded: false, value: .extended),
    mode: SettingOption(value: mode),
    rotationDegrees: SettingOption(isIncluded: false, value: 0),
    isActive: SettingOption(isIncluded: false, value: true)
  )
}
