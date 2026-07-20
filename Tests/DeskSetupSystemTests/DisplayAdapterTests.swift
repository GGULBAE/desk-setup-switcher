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
    displays[1].rotationDegrees = 90
    displays[1].isActive = false
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
    #expect(settings.displays[1].rotationDegrees.value == 90)
    #expect(!settings.displays[1].rotationDegrees.isIncluded)
    #expect(settings.displays[1].isActive.value == false)
    #expect(!settings.displays[1].isActive.isIncluded)
    #expect(snapshot.items.allSatisfy { $0.state == .storable })
    #expect(snapshot.displayModeCatalog?.count == 2)
    #expect(snapshot.displayModeCatalog?[1].identity == displays[1].identity)
    #expect(snapshot.displayModeCatalog?[1].modes == displays[1].supportedModes)
    #expect(snapshot.displayColorEvidence?.map(\.colorSpaceName) == ["Synthetic sRGB", "P3"])
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
    settings.displays[externalIndex].rotationDegrees.isIncluded = true
    settings.displays[externalIndex].rotationDegrees.value = 90
    settings.displays[externalIndex].isActive.isIncluded = true
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

  @Test("a rotation-only request produces one unsupported omission")
  func rotationOnlyRequestIsOmitted() async throws {
    let adapter = CoreGraphicsDisplayAdapter(
      systemAPI: MockDisplaySystemAPI(displays: makeDisplays())
    )
    let snapshot = try await adapter.snapshot()
    let settings = try displaySettings(from: snapshot)
    var target = try #require(settings.displays.first)
    target.isPrimary.isIncluded = false
    target.origin.isIncluded = false
    target.mirroring.isIncluded = false
    target.mode.isIncluded = false
    target.colorProfile.isIncluded = false
    target.rotationDegrees = .init(value: 90)
    target.isActive.isIncluded = false
    let key = "display.\(target.id.uuidString).rotation"

    let plan = try await adapter.plan(
      .display(.init(displays: [target])),
      from: snapshot,
      mode: .normal
    )

    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.map(\.key) == [key])
    #expect(plan.omissions.first?.status == .unsupported)
  }

  @Test("a rotation-only request does not require unrelated topology rollback")
  func rotationOnlyRequestSkipsTopologyRollback() async throws {
    var displays = makeDisplays()
    displays[1].currentMode = nil
    let adapter = CoreGraphicsDisplayAdapter(
      systemAPI: MockDisplaySystemAPI(displays: displays)
    )
    let snapshot = try await adapter.snapshot()
    let settings = try displaySettings(from: snapshot)
    var target = try #require(settings.displays.first)
    target.isPrimary.isIncluded = false
    target.origin.isIncluded = false
    target.mirroring.isIncluded = false
    target.mode.isIncluded = false
    target.colorProfile.isIncluded = false
    target.rotationDegrees = .init(value: 90)
    target.isActive.isIncluded = false
    let key = "display.\(target.id.uuidString).rotation"

    let plan = try await adapter.plan(
      .display(.init(displays: [target])),
      from: snapshot,
      mode: .normal
    )

    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.map(\.key) == [key])
    #expect(plan.omissions.first?.status == .unsupported)
    #expect(!plan.omissions.contains { $0.key == "display.rollback" })
  }

  @Test("an active-only request produces one unsupported omission")
  func activeOnlyRequestIsOmitted() async throws {
    let adapter = CoreGraphicsDisplayAdapter(
      systemAPI: MockDisplaySystemAPI(displays: makeDisplays())
    )
    let snapshot = try await adapter.snapshot()
    let settings = try displaySettings(from: snapshot)
    var target = try #require(settings.displays.first)
    target.isPrimary.isIncluded = false
    target.origin.isIncluded = false
    target.mirroring.isIncluded = false
    target.mode.isIncluded = false
    target.colorProfile.isIncluded = false
    target.rotationDegrees.isIncluded = false
    target.isActive = .init(value: false)
    let key = "display.\(target.id.uuidString).active"

    let plan = try await adapter.plan(
      .display(.init(displays: [target])),
      from: snapshot,
      mode: .normal
    )

    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.map(\.key) == [key])
    #expect(plan.omissions.first?.status == .unsupported)
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
    settings.displays[0].rotationDegrees.isIncluded = true
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

  @Test("mixed topology and unsupported leaves report a missing identity once")
  func mixedMissingIdentityIsOmittedOnce() async throws {
    let displays = makeDisplays()
    let adapter = CoreGraphicsDisplayAdapter(
      systemAPI: MockDisplaySystemAPI(displays: displays)
    )
    let snapshot = try await adapter.snapshot()
    let missingIdentity = DisplayIdentity(
      uuid: UUID(),
      vendorID: 9_999,
      modelID: 8_888,
      serialNumber: 7_777,
      productName: "Missing Test Panel"
    )
    var target = makeTarget(
      identity: missingIdentity,
      mode: try #require(displays[0].currentMode)
    )
    target.rotationDegrees = .init(value: 90)
    let identityKey = "display.\(target.id.uuidString).identity"

    let plan = try await adapter.plan(
      .display(.init(displays: [target])),
      from: snapshot,
      mode: .normal
    )

    #expect(plan.operations.isEmpty)
    #expect(plan.issues.map(\.key) == [identityKey])
    #expect(plan.omissions.map(\.key) == [identityKey])
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

  @Test("ColorSync profile target is portable and apply verifies exact rollback")
  func colorProfileRoundTrip() async throws {
    let original = colorProfile("original", hash: "a", name: "Synthetic Original ICC")
    let target = colorProfile("target", hash: "b", name: "Synthetic Target ICC")
    let mapping = ColorSyncCustomProfileMapping(
      entries: [.init(key: "default", value: .scope("synthetic-original"))]
    )
    var displays = makeDisplays()
    displays[0].availableColorProfiles = [original, target]
    displays[0].currentColorProfile = original
    displays[0].currentColorProfileMapping = mapping
    displays[0].canSetColorProfile = true
    let api = MockDisplaySystemAPI(displays: displays)
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    settings.displays[0].colorProfile = .init(value: target)

    #expect(snapshot.items.count == displays.count + 1)
    #expect(
      snapshot.items.count(where: { $0.key.hasPrefix("display.colorProfile.") }) == 1
    )

    let validation = await adapter.validate(.display(settings), against: snapshot)
    let plan = try await adapter.plan(.display(settings), from: snapshot, mode: .normal)
    let operation = try #require(
      plan.operations.first(where: { $0.key.hasPrefix("display.colorProfile.") })
    )

    #expect(validation.isEmpty)
    #expect(plan.omissions.isEmpty)
    #expect(operation.risk == .high)
    #expect(operation.isFatalOnFailure)
    #expect(
      operation.preview
        == .init(
          previousValue: original.displayName,
          desiredValue: target.displayName
        ))
    let encodedSettings = String(
      decoding: try JSONEncoder().encode(settings),
      as: UTF8.self
    )
    #expect(encodedSettings.contains(target.registeredProfileID))
    #expect(encodedSettings.contains(target.fileSHA256))
    #expect(!encodedSettings.contains("file://"))
    #expect(await adapter.apply(operation).status == .succeeded)
    #expect(await adapter.confirm(operation).status == .succeeded)
    #expect(await api.currentColorProfile(for: displays[0].identity) == target)
    #expect(await adapter.rollback(operation).status == .rolledBack)
    #expect(await api.currentColorProfile(for: displays[0].identity) == original)
    #expect(await api.recordedMutationNames() == ["color.set", "color.restore"])
  }

  @Test("ColorSync enumeration records hash ICC bytes without persisting runtime URLs")
  func colorProfileEnumerationCreatesPortableTarget() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "DeskSetupSwitcher-ColorSync-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Synthetic.icc")
    try Data("abc".utf8).write(to: url)

    let target = try #require(
      CoreGraphicsDisplaySystemAPI.portableColorProfileTarget(
        registeredProfileID: "synthetic-profile",
        url: url,
        displayName: "Synthetic ICC"
      )
    )
    let encoded = String(decoding: try JSONEncoder().encode(target), as: UTF8.self)

    #expect(target.registeredProfileID == "synthetic-profile")
    #expect(
      target.fileSHA256
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
    #expect(target.displayName == "Synthetic ICC")
    #expect(!encoded.contains(url.path))
    #expect(!encoded.contains("file://"))
  }

  @Test("ColorSync read-back mismatch and hot-plug fail closed")
  func colorProfileFailures() async throws {
    let original = colorProfile("original", hash: "c", name: "Original ICC")
    let target = colorProfile("target", hash: "d", name: "Target ICC")
    var displays = makeDisplays()
    displays[0].availableColorProfiles = [original, target]
    displays[0].currentColorProfile = original
    displays[0].currentColorProfileMapping = .init(
      entries: [.init(key: "default", value: .scope("original"))]
    )
    displays[0].canSetColorProfile = true
    let api = MockDisplaySystemAPI(displays: displays)
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    settings.displays[0].colorProfile = .init(value: target)
    let plan = try await adapter.plan(.display(settings), from: snapshot, mode: .normal)
    let operation = try #require(
      plan.operations.first(where: { $0.key.hasPrefix("display.colorProfile.") })
    )

    await api.setIgnoreColorWrites(true)
    #expect(await adapter.apply(operation).status == .failed)

    await api.setIgnoreColorWrites(false)
    await api.replaceDisplays(Array(displays.dropFirst()))
    #expect(await adapter.apply(operation).status == .failed)
  }

  @Test("an included ColorSync target without rollback support is explicitly omitted")
  func unavailableColorProfileControlIsOmitted() async throws {
    let original = colorProfile("original", hash: "1", name: "Original ICC")
    let target = colorProfile("target", hash: "2", name: "Target ICC")
    var displays = makeDisplays()
    displays[0].availableColorProfiles = [original, target]
    displays[0].currentColorProfile = original
    displays[0].currentColorProfileMapping = nil
    displays[0].canSetColorProfile = false
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: MockDisplaySystemAPI(displays: displays))
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    settings.displays[0].colorProfile = .init(value: target)

    let validation = await adapter.validate(.display(settings), against: snapshot)
    let plan = try await adapter.plan(.display(settings), from: snapshot, mode: .normal)
    let key = "display.colorProfile.\(settings.displays[0].id.uuidString)"

    #expect(validation.contains { $0.key == key })
    #expect(!plan.operations.contains { $0.key == key })
    #expect(plan.omissions.contains { $0.key == key && $0.status == .unsupported })
  }

  @Test("an already-satisfied ColorSync target needs no writable control or rollback")
  func alreadySatisfiedColorProfileNeedsNoControl() async throws {
    let current = colorProfile("current", hash: "1", name: "Current ICC")
    var displays = makeDisplays()
    displays[0].availableColorProfiles = [current]
    displays[0].currentColorProfile = current
    displays[0].currentColorProfileMapping = nil
    displays[0].canSetColorProfile = false
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: MockDisplaySystemAPI(displays: displays))
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    settings.displays[0].colorProfile = .init(value: current)

    let validation = await adapter.validate(.display(settings), against: snapshot)
    let plan = try await adapter.plan(.display(settings), from: snapshot, mode: .normal)
    let key = "display.colorProfile.\(settings.displays[0].id.uuidString)"

    #expect(!validation.contains { $0.key == key })
    #expect(!plan.operations.contains { $0.key == key })
    #expect(!plan.omissions.contains { $0.key == key })
  }

  @Test("a missing color-only target produces one ColorSync omission")
  func missingColorOnlyTargetProducesOneOmission() async throws {
    let targetID = UUID()
    let targetProfile = colorProfile("target", hash: "2", name: "Target ICC")
    let target = DisplayTargetSettings(
      id: targetID,
      identity: DisplayIdentity(
        uuid: UUID(),
        vendorID: 9_999,
        modelID: 8_888,
        serialNumber: 7_777,
        productName: "Missing Test Panel"
      ),
      isPrimary: .init(isIncluded: false, value: false),
      origin: .init(isIncluded: false, value: DisplayPoint(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)
      ),
      colorProfile: .init(value: targetProfile),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
    let adapter = CoreGraphicsDisplayAdapter(
      systemAPI: MockDisplaySystemAPI(displays: makeDisplays())
    )
    let snapshot = try await adapter.snapshot()
    let settings = DisplayProfileSettings(displays: [target])
    let colorKey = "display.colorProfile.\(targetID.uuidString)"
    let identityKey = "display.\(targetID.uuidString).identity"

    let validation = await adapter.validate(.display(settings), against: snapshot)
    let plan = try await adapter.plan(.display(settings), from: snapshot, mode: .normal)

    #expect(validation.map(\.key) == [colorKey])
    #expect(plan.issues.map(\.key) == [colorKey])
    #expect(plan.omissions.map(\.key) == [colorKey])
    #expect(plan.omissions.first?.status == .skipped)
    #expect(!plan.omissions.contains { $0.key == identityKey })
  }

  @Test("color-only planning does not require unrelated topology rollback")
  func colorOnlyPlanningSkipsTopologyRollback() async throws {
    let original = colorProfile("original", hash: "1", name: "Original ICC")
    let target = colorProfile("target", hash: "2", name: "Target ICC")
    var displays = makeDisplays()
    displays[0].availableColorProfiles = [original, target]
    displays[0].currentColorProfile = original
    displays[0].currentColorProfileMapping = .init(
      entries: [.init(key: "default", value: .scope("original"))]
    )
    displays[0].canSetColorProfile = true
    displays[1].currentMode = nil
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: MockDisplaySystemAPI(displays: displays))
    let snapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: snapshot)
    for index in settings.displays.indices {
      settings.displays[index].isPrimary.isIncluded = false
      settings.displays[index].origin.isIncluded = false
      settings.displays[index].mirroring.isIncluded = false
      settings.displays[index].mode.isIncluded = false
      settings.displays[index].colorProfile.isIncluded = false
    }
    settings.displays[0].colorProfile = .init(value: target)

    let validation = await adapter.validate(.display(settings), against: snapshot)
    let plan = try await adapter.plan(.display(settings), from: snapshot, mode: .normal)

    #expect(!validation.contains { $0.key == "display.rollback" })
    #expect(!plan.omissions.contains { $0.key == "display.rollback" })
    #expect(plan.operations.count == 1)
    #expect(plan.operations[0].key.hasPrefix("display.colorProfile."))
  }

  @Test("display topology applies before color and rollback reverses that order")
  func topologyAndColorTransactionOrdering() async throws {
    let original = colorProfile("original", hash: "e", name: "Original ICC")
    let target = colorProfile("target", hash: "f", name: "Target ICC")
    var displays = makeDisplays()
    displays[0].availableColorProfiles = [original, target]
    displays[0].currentColorProfile = original
    displays[0].currentColorProfileMapping = .init(
      entries: [.init(key: "default", value: .scope("original"))]
    )
    displays[0].canSetColorProfile = true
    let api = MockDisplaySystemAPI(displays: displays)
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let initialSnapshot = try await adapter.snapshot()
    var settings = try displaySettings(from: initialSnapshot)
    settings.displays[0].colorProfile = .init(value: target)
    settings.displays[1].mode.value = try #require(
      displays[1].supportedModes.first(where: { $0 != displays[1].currentMode })
    )
    let profile = DeskProfile(
      name: "Synthetic",
      settings: .init(
        display: .init(value: settings)
      ))
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))

    let result = await engine.apply(profile: profile, mode: .normal)
    let confirmationID = try #require(result.safetyConfirmationID)
    let rollback = await engine.revertSafetyRollback(confirmationID)

    #expect(result.status == .applied)
    #expect(rollback.status == .reverted)
    #expect(
      await api.recordedMutationNames() == [
        "topology.appOnly",
        "color.set",
        "color.restore",
        "topology.sessionOnly",
      ]
    )
  }
}

actor MockDisplaySystemAPI: DisplaySystemAPI {
  struct ApplyCall: Hashable, Sendable {
    var configuration: DisplayAtomicConfiguration
    var commitScope: DisplayConfigurationCommitScope
  }

  private var displays: [DisplaySystemDisplay]
  private var applyCalls: [ApplyCall] = []
  private var mutationNames: [String] = []
  private var targetByMapping: [ColorSyncCustomProfileMapping: ColorSyncProfileTarget?] = [:]
  private var ignoresColorWrites = false

  init(displays: [DisplaySystemDisplay]) {
    self.displays = displays
    for display in displays {
      if let mapping = display.currentColorProfileMapping {
        targetByMapping[mapping] = display.currentColorProfile
      }
    }
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
    mutationNames.append("topology.\(commitScope.rawValue)")
    let sessionIDByIdentity = Dictionary(
      uniqueKeysWithValues: displays.map { ($0.identity, $0.sessionID) }
    )
    for target in configuration.targets {
      guard let index = displays.firstIndex(where: { $0.identity == target.identity }) else {
        continue
      }
      displays[index].bounds = DisplaySystemBounds(
        x: target.origin.x,
        y: target.origin.y,
        width: target.mode.width,
        height: target.mode.height
      )
      displays[index].isMain = target.origin == DisplayPoint(x: 0, y: 0)
      displays[index].currentMode = target.mode
      displays[index].mirrorSourceSessionID = target.mirrorSource.flatMap {
        sessionIDByIdentity[$0]
      }
    }
  }

  func setColorProfile(
    _ target: ColorSyncProfileTarget,
    for display: DisplayIdentity
  ) async throws {
    mutationNames.append("color.set")
    guard let index = displays.firstIndex(where: { $0.identity == display }),
      displays[index].canSetColorProfile,
      displays[index].availableColorProfiles.count(where: { $0 == target }) == 1
    else {
      throw DisplayAdapterError.colorProfileUnavailable
    }
    guard !ignoresColorWrites else { return }
    let mapping = ColorSyncCustomProfileMapping(
      entries: [.init(key: "default", value: .scope("target:\(target.fileSHA256)"))]
    )
    displays[index].currentColorProfile = target
    displays[index].currentColorProfileMapping = mapping
    targetByMapping[mapping] = target
  }

  func restoreColorProfileMapping(
    _ mapping: ColorSyncCustomProfileMapping,
    for display: DisplayIdentity
  ) async throws {
    mutationNames.append("color.restore")
    guard let index = displays.firstIndex(where: { $0.identity == display }) else {
      throw DisplayAdapterError.topologyChanged
    }
    guard !ignoresColorWrites else { return }
    displays[index].currentColorProfileMapping = mapping
    displays[index].currentColorProfile = targetByMapping[mapping] ?? nil
  }

  func recordedApplyCalls() -> [ApplyCall] {
    applyCalls
  }

  func recordedMutationNames() -> [String] {
    mutationNames
  }

  func currentColorProfile(for identity: DisplayIdentity) -> ColorSyncProfileTarget? {
    displays.first(where: { $0.identity == identity })?.currentColorProfile
  }

  func setIgnoreColorWrites(_ ignored: Bool) {
    ignoresColorWrites = ignored
  }

  func replaceDisplays(_ updated: [DisplaySystemDisplay]) {
    displays = updated
  }
}

private enum DisplayTestError: Error {
  case missingDisplayPayload
}

private func colorProfile(_ id: String, hash: Character, name: String) -> ColorSyncProfileTarget {
  ColorSyncProfileTarget(
    registeredProfileID: "synthetic-\(id)",
    fileSHA256: String(repeating: hash, count: 64),
    displayName: name
  )
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
      supportedModes: [builtInMode],
      currentColorSpaceName: "Synthetic sRGB"
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
      ],
      currentColorSpaceName: "P3"
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
