import Foundation
import Testing

@testable import DeskSetupCore

@Suite("Visible setting registry")
struct VisibleSettingRegistryTests {
  @Test("every visible contract declares the complete vertical slice")
  func completeContracts() {
    let contracts = VisibleSettingRegistry.contracts

    #expect(contracts.count == VisibleSettingKind.allCases.count)
    #expect(Set(contracts.map(\.kind)) == Set(VisibleSettingKind.allCases))
    #expect(Set(contracts.map(\.kind)).count == contracts.count)
    #expect(contracts.allSatisfy { $0.stages == Set(VisibleSettingStage.allCases) })
    #expect(contracts.allSatisfy { !$0.snapshotKey.isEmpty })
    #expect(contracts.allSatisfy { !$0.runtimeCatalogSource.isEmpty })
    #expect(contracts.allSatisfy { !$0.validationKey.isEmpty })
    #expect(contracts.allSatisfy { !$0.operationKeyPrefix.isEmpty })
    #expect(contracts.allSatisfy { !$0.localizationKey.isEmpty })
    #expect(contracts.allSatisfy { !$0.accessibilityLabelKey.isEmpty })
  }

  @Test("supported public catalogs project every requested editor field")
  func supportedProjection() {
    let fields = VisibleSettingRegistry().fields(snapshots: supportedSnapshots)
    let counts = Dictionary(grouping: fields, by: { $0.contract.kind }).mapValues(\.count)

    #expect(counts[.displayOutputMode] == 1)
    #expect(counts[.displayPrimary] == 1)
    #expect(counts[.displayMode] == 2)
    #expect(counts[.displayColorProfile] == 1)
    #expect(counts[.audioDefaultInput] == 1)
    #expect(counts[.audioDefaultOutput] == 1)
    #expect(counts[.audioInputVolume] == 1)
    #expect(counts[.audioOutputVolume] == 1)
    #expect(counts[.networkServiceIPv4] == 2)
    #expect(fields.allSatisfy { $0.contract.stages.contains(.rollback) })
  }

  @Test("unsupported runtime controls are absent instead of disabled")
  func unsupportedProjectionIsHidden() {
    var snapshots = supportedSnapshots
    snapshots[0].displayColorProfileCatalog?[0].canApply = false
    snapshots[1].audioVolumeControlCatalog = snapshots[1].audioVolumeControlCatalog?.map {
      .init(
        role: $0.role,
        deviceUID: $0.deviceUID,
        currentValue: $0.currentValue,
        canApply: false
      )
    }
    snapshots[2].networkIPv4RollbackCatalog = []

    let kinds = VisibleSettingRegistry().fields(snapshots: snapshots).map(\.contract.kind)

    #expect(!kinds.contains(.displayColorProfile))
    #expect(!kinds.contains(.audioInputVolume))
    #expect(!kinds.contains(.audioOutputVolume))
    #expect(!kinds.contains(.networkServiceIPv4))
    #expect(kinds.contains(.audioDefaultInput))
    #expect(kinds.contains(.audioDefaultOutput))
  }

  @Test("ambiguous network service identities are absent")
  func ambiguousNetworkIdentityIsHidden() {
    var snapshots = supportedSnapshots
    let duplicate = snapshots[2].networkIPv4RollbackCatalog?[0]
    snapshots[2].networkIPv4RollbackCatalog?.append(try! #require(duplicate))

    let networkFields = VisibleSettingRegistry().fields(snapshots: snapshots).filter {
      $0.contract.kind == .networkServiceIPv4
    }

    #expect(networkFields.count == 1)
  }

  private var supportedSnapshots: [AdapterSnapshot] {
    let firstDisplay = DisplayIdentity(
      uuid: UUID(uuidString: "10000000-0000-0000-0000-000000000001"),
      productName: "Synthetic Built-in",
      isBuiltIn: true
    )
    let secondDisplay = DisplayIdentity(
      uuid: UUID(uuidString: "10000000-0000-0000-0000-000000000002"),
      productName: "Synthetic External"
    )
    let mode = DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)
    let color = ColorSyncProfileTarget(
      registeredProfileID: "synthetic-profile",
      fileSHA256: String(repeating: "a", count: 64),
      displayName: "Synthetic ICC"
    )
    let ethernet = NetworkServiceIdentity(
      kind: .ethernet,
      serviceName: "Synthetic Ethernet",
      interfaceType: "Ethernet"
    )
    let wifi = NetworkServiceIdentity(
      kind: .wifi,
      serviceName: "Synthetic Wi-Fi",
      interfaceType: "IEEE80211"
    )

    return [
      AdapterSnapshot(
        group: .display,
        capturedAt: .distantPast,
        payload: nil,
        items: [],
        displayModeCatalog: [
          .init(identity: firstDisplay, modes: [mode]),
          .init(identity: secondDisplay, modes: [mode]),
        ],
        displayColorProfileCatalog: [
          .init(identity: firstDisplay, profiles: [color], canApply: true),
          .init(identity: secondDisplay, profiles: [], canApply: false),
        ]
      ),
      AdapterSnapshot(
        group: .audio,
        capturedAt: .distantPast,
        payload: nil,
        items: [],
        audioDeviceCatalog: [
          .init(uid: "synthetic-input", name: "Input", supportsInput: true, supportsOutput: false),
          .init(
            uid: "synthetic-output", name: "Output", supportsInput: false, supportsOutput: true),
        ],
        audioVolumeControlCatalog: [
          .init(role: .input, deviceUID: "synthetic-input", currentValue: 0.4, canApply: true),
          .init(role: .output, deviceUID: "synthetic-output", currentValue: 0.5, canApply: true),
        ]
      ),
      AdapterSnapshot(
        group: .network,
        capturedAt: .distantPast,
        payload: nil,
        items: [],
        networkIPv4RollbackCatalog: [
          .init(identity: ethernet, configurationData: Data([1]), currentConfiguration: .dhcp),
          .init(identity: wifi, configurationData: Data([2]), currentConfiguration: .dhcp),
        ]
      ),
    ]
  }
}
