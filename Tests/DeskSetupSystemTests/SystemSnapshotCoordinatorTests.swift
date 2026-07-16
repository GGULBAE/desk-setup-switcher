import Foundation
import XCTest

@testable import DeskSetupSystem

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

final class SystemSnapshotCoordinatorTests: XCTestCase {
  func testSuccessfulSnapshotsBuildVisibleSettingsAndPreserveDormantValues() async throws {
    let displayValue = DisplayProfileSettings()
    let audioValue = AudioProfileSettings(
      defaultInputUID: .init(isIncluded: true, value: "input-uid"),
      outputVolume: .init(isIncluded: false, value: 0.8)
    )
    let networkValue = NetworkProfileSettings(
      wifiPower: .init(isIncluded: true, value: true),
      wifiSSID: .init(isIncluded: false, value: "Office"),
      serviceIPv4: [
        .init(
          identity: .init(
            kind: .ethernet,
            serviceName: "Synthetic Ethernet",
            interfaceType: "Ethernet"
          ),
          configuration: .init(value: .dhcp)
        )
      ]
    )
    let inputValue = InputProfileSettings(
      pointerSpeed: .init(isIncluded: true, value: 1.25),
      naturalScrolling: .init(isIncluded: false, value: true)
    )
    let display = makeAdapter(
      group: .display,
      payload: .display(displayValue),
      items: allItemStates()
    )
    let audio = makeAdapter(
      group: .audio,
      payload: .audio(audioValue),
      items: [item("audio", state: .storable)]
    )
    let network = makeAdapter(
      group: .network,
      payload: .network(networkValue),
      items: [item("network", state: .storable)]
    )
    let input = makeAdapter(
      group: .input,
      payload: .input(inputValue),
      items: [item("input", state: .storable)]
    )
    let adapters: [MockSystemSettingsAdapter] = [input, network, audio, display]
    let coordinator = SystemSnapshotCoordinator(
      adapters: adapters,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let result = await coordinator.capture()

    XCTAssertEqual(result.capturedAt, Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertEqual(result.groups.map(\.group), [.display, .audio, .network, .input])
    XCTAssertFalse(result.settings.display.isIncluded)
    XCTAssertTrue(result.settings.audio.isIncluded)
    XCTAssertTrue(result.settings.network.isIncluded)
    XCTAssertFalse(result.settings.input.isIncluded)
    XCTAssertEqual(result.settings.display.value, displayValue)
    XCTAssertEqual(result.settings.audio.value, audioValue)
    XCTAssertEqual(result.settings.network.value.serviceIPv4, networkValue.serviceIPv4)
    XCTAssertEqual(result.settings.network.value.wifiPower.value, true)
    XCTAssertFalse(result.settings.network.value.wifiPower.isIncluded)
    XCTAssertEqual(result.settings.input.value.pointerSpeed.value, 1.25)
    XCTAssertFalse(result.settings.input.value.pointerSpeed.isIncluded)
    XCTAssertFalse(result.settings.audio.value.outputVolume.isIncluded)
    XCTAssertEqual(result.settings.audio.value.outputVolume.value, 0.8)
    XCTAssertFalse(result.settings.network.value.wifiSSID.isIncluded)
    XCTAssertEqual(result.settings.network.value.wifiSSID.value, "Office")
    XCTAssertFalse(result.settings.input.value.naturalScrolling.isIncluded)
    XCTAssertEqual(result.settings.input.value.naturalScrolling.value, true)

    let displayResult = try XCTUnwrap(result.result(for: .display))
    XCTAssertEqual(displayResult.detectedItems.map(\.key), ["detected"])
    XCTAssertEqual(displayResult.storableItems.map(\.key), ["storable"])
    XCTAssertEqual(displayResult.unreadableItems.map(\.key), ["unreadable"])
    XCTAssertEqual(displayResult.permissionRequiredItems.map(\.key), ["permission"])
    XCTAssertEqual(displayResult.unsupportedItems.map(\.key), ["unsupported"])

    for adapter in adapters {
      let invocations = await adapter.recordedInvocations()
      XCTAssertEqual(invocations, [.capability, .snapshot])
    }
  }

  func testSnapshotFailureIsIsolatedAndOtherGroupStillBuildsSettings() async throws {
    let display = MockSystemSettingsAdapter(
      group: .display,
      snapshotFailure: .snapshot("Synthetic read failure")
    )
    let audioValue = AudioProfileSettings(
      defaultOutputUID: .init(isIncluded: true, value: "output-uid")
    )
    let audio = makeAdapter(
      group: .audio,
      payload: .audio(audioValue),
      items: [item("defaultOutput", state: .storable)]
    )
    let coordinator = SystemSnapshotCoordinator(adapters: [display, audio])

    let result = await coordinator.capture()

    let displayResult = try XCTUnwrap(result.result(for: .display))
    XCTAssertEqual(displayResult.failures.map(\.stage), [.snapshot])
    XCTAssertNil(displayResult.snapshot)
    XCTAssertEqual(displayResult.unreadableItems.map(\.key), ["snapshot"])
    XCTAssertFalse(result.settings.display.isIncluded)
    XCTAssertTrue(result.settings.audio.isIncluded)
    XCTAssertEqual(result.settings.audio.value, audioValue)
    let displayInvocations = await display.recordedInvocations()
    let audioInvocations = await audio.recordedInvocations()
    XCTAssertEqual(displayInvocations, [.capability, .snapshot])
    XCTAssertEqual(audioInvocations, [.capability, .snapshot])
  }

  func testPermissionRequiredWithoutStorableValueRemainsVisibleButExcluded() async throws {
    let networkValue = NetworkProfileSettings(
      wifiSSID: .init(isIncluded: false, value: nil)
    )
    let network = makeAdapter(
      group: .network,
      payload: .network(networkValue),
      items: [item("wifiSSID", state: .permissionRequired)]
    )

    let result = await SystemSnapshotCoordinator(adapters: [network]).capture()

    let networkResult = try XCTUnwrap(result.result(for: .network))
    XCTAssertEqual(networkResult.permissionRequiredItems.map(\.key), ["wifiSSID"])
    XCTAssertTrue(networkResult.storableItems.isEmpty)
    XCTAssertFalse(result.settings.network.isIncluded)
  }

  func testMatchingPayloadIsRequiredEvenWithStorableItem() async throws {
    let audio = makeAdapter(
      group: .audio,
      payload: .network(.init(wifiPower: .init(isIncluded: true, value: true))),
      items: [item("wrongPayload", state: .storable)]
    )

    let result = await SystemSnapshotCoordinator(adapters: [audio]).capture()

    let audioResult = try XCTUnwrap(result.result(for: .audio))
    XCTAssertEqual(audioResult.failures.map(\.stage), [.payloadContract])
    XCTAssertFalse(result.settings.audio.isIncluded)
    XCTAssertFalse(result.settings.network.isIncluded)
  }

  func testNoAdaptersReturnsEmptyGroupsAndExcludedSettings() async {
    let result = await SystemSnapshotCoordinator(
      adapters: [],
      now: { Date(timeIntervalSince1970: 123) }
    ).capture()

    XCTAssertEqual(result.capturedAt, Date(timeIntervalSince1970: 123))
    XCTAssertTrue(result.groups.isEmpty)
    XCTAssertFalse(result.settings.display.isIncluded)
    XCTAssertFalse(result.settings.audio.isIncluded)
    XCTAssertFalse(result.settings.network.isIncluded)
    XCTAssertFalse(result.settings.input.isIncluded)
  }

  func testReadOnlyEditorCatalogsRemainSessionScoped() async throws {
    let identity = DisplayIdentity(uuid: UUID())
    let display = MockSystemSettingsAdapter(
      group: .display,
      snapshot: AdapterSnapshot(
        group: .display,
        capturedAt: Date(timeIntervalSince1970: 100),
        payload: .display(.init()),
        items: [],
        displayColorEvidence: [
          DisplayColorEvidenceEntry(identity: identity, colorSpaceName: "Synthetic sRGB")
        ]
      )
    )
    let network = MockSystemSettingsAdapter(
      group: .network,
      snapshot: AdapterSnapshot(
        group: .network,
        capturedAt: Date(timeIntervalSince1970: 100),
        payload: .network(.init()),
        items: [],
        savedWiFiNetworkNames: ["Synthetic Saved Wi-Fi"]
      )
    )

    let result = await SystemSnapshotCoordinator(adapters: [network, display]).capture()

    XCTAssertEqual(result.displayColorEvidence.first?.identity, identity)
    XCTAssertEqual(result.displayColorEvidence.first?.colorSpaceName, "Synthetic sRGB")
    XCTAssertEqual(result.savedWiFiNetworkNames, ["Synthetic Saved Wi-Fi"])
    XCTAssertTrue(result.profileSettings.network.value.wifiSSID.value == nil)
  }

  func testCoordinatorNeverCallsMutationOrPlanningMethods() async {
    let adapter = makeAdapter(
      group: .input,
      payload: .input(.init(pointerSpeed: .init(isIncluded: true, value: 2.0))),
      items: [item("pointerSpeed", state: .storable)]
    )

    _ = await SystemSnapshotCoordinator(adapters: [adapter]).capture()

    let invocations = await adapter.recordedInvocations()
    XCTAssertEqual(invocations, [.capability, .snapshot])
    XCTAssertFalse(invocations.contains(.validate))
    XCTAssertFalse(invocations.contains(.plan(.normal)))
    XCTAssertFalse(invocations.contains(.plan(.force)))
    XCTAssertFalse(
      invocations.contains { invocation in
        if case .apply = invocation { return true }
        return false
      })
    XCTAssertFalse(
      invocations.contains { invocation in
        if case .rollback = invocation { return true }
        return false
      })
  }

  func testLiveFactoryReturnsEveryConcreteAdapterWithoutPerformingIO() {
    let adapters = LiveAdapterFactory.makeAdapters()

    XCTAssertEqual(adapters.map(\.group), [.display, .audio, .network, .input])
    XCTAssertTrue(adapters[0] is CoreGraphicsDisplayAdapter)
    XCTAssertTrue(adapters[1] is CoreAudioAdapter)
    XCTAssertTrue(adapters[2] is NetworkAdapter)
    XCTAssertTrue(adapters[3] is InputPreferencesAdapter)
  }

  private func makeAdapter(
    group: SettingGroup,
    payload: SettingsPayload?,
    items: [SnapshotItem]
  ) -> MockSystemSettingsAdapter {
    MockSystemSettingsAdapter(
      group: group,
      snapshot: AdapterSnapshot(
        group: group,
        capturedAt: Date(timeIntervalSince1970: 100),
        payload: payload,
        items: items
      )
    )
  }

  private func item(_ key: String, state: SnapshotItemState) -> SnapshotItem {
    SnapshotItem(key: key, label: key, state: state)
  }

  private func allItemStates() -> [SnapshotItem] {
    [
      item("detected", state: .detected),
      item("storable", state: .storable),
      item("unreadable", state: .unreadable),
      item("permission", state: .permissionRequired),
      item("unsupported", state: .unsupported),
    ]
  }
}
