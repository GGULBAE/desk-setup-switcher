import Foundation
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSystem

@Suite("Visible setting end-to-end invariant")
struct VisibleSettingEndToEndInvariantTests {
  @Test("every projected field validates, plans, applies, verifies, and rolls back")
  func everyProjectedFieldHasAnExecutableVerticalSlice() async throws {
    let display = try await makeDisplaySlice()
    let audio = try await makeAudioSlice()
    let network = try await makeNetworkSlice()
    let slices = [display, audio, network]
    let snapshots = slices.map(\.snapshot)
    let fields = VisibleSettingRegistry().fields(snapshots: snapshots)

    #expect(Set(fields.map(\.contract.kind)) == Set(VisibleSettingKind.allCases))
    #expect(fields.allSatisfy { $0.contract.stages == Set(VisibleSettingStage.allCases) })

    for field in fields {
      let slice = try #require(slices.first { $0.snapshot.group == field.contract.group })
      #expect(slice.validationIssues.isEmpty)
      #expect(
        slice.operations.contains { operation in
          operation.key.hasPrefix(field.contract.operationKeyPrefix)
            && operation.rollbackPayload != nil
        },
        "No executable operation for projected field \(field.id)"
      )
    }

    for slice in slices {
      for operation in slice.operations {
        #expect(await slice.adapter.apply(operation).status == .succeeded)
      }
      for operation in slice.operations.reversed() {
        #expect(await slice.adapter.rollback(operation).status == .rolledBack)
      }
    }

    #expect(audioAPI.defaultUID(for: .input) == "input-A")
    #expect(audioAPI.defaultUID(for: .output) == "output-A")
    #expect(audioAPI.inputVolume(for: "input-B")?.value == 0.45)
    #expect(audioAPI.volume(for: "output-B")?.value == 0.4)
    #expect(await networkAPI.ipv4(for: ethernetIdentity) == .dhcp)
    #expect(
      await networkAPI.ipv4(for: wifiIdentity)
        == .manual(
          address: "198.51.100.20",
          subnetMask: "255.255.255.0",
          router: "198.51.100.1"
        )
    )
  }

  private struct Slice: Sendable {
    let adapter: any SystemSettingsAdapter
    let snapshot: AdapterSnapshot
    let validationIssues: [ValidationIssue]
    let operations: [PlannedOperation]
  }

  private func makeDisplaySlice() async throws -> Slice {
    let originalProfile = ColorSyncProfileTarget(
      registeredProfileID: "synthetic-original",
      fileSHA256: String(repeating: "a", count: 64),
      displayName: "Synthetic Original ICC"
    )
    let targetProfile = ColorSyncProfileTarget(
      registeredProfileID: "synthetic-target",
      fileSHA256: String(repeating: "b", count: 64),
      displayName: "Synthetic Target ICC"
    )
    let builtInIdentity = DisplayIdentity(
      uuid: UUID(uuidString: "30000000-0000-0000-0000-000000000001"),
      vendorID: 1_001,
      modelID: 2_001,
      serialNumber: 3_001,
      productName: "Synthetic Built-in Display",
      isBuiltIn: true
    )
    let externalIdentity = DisplayIdentity(
      uuid: UUID(uuidString: "30000000-0000-0000-0000-000000000002"),
      vendorID: 1_002,
      modelID: 2_002,
      serialNumber: 3_002,
      productName: "Synthetic External Display"
    )
    let builtInModes = [
      DisplayMode(width: 1_440, height: 900, refreshRate: 60),
      DisplayMode(width: 1_280, height: 800, refreshRate: 60),
    ]
    let externalModes = [
      DisplayMode(width: 2_560, height: 1_440, refreshRate: 60),
      DisplayMode(width: 1_920, height: 1_080, refreshRate: 60),
    ]
    let originalMapping = ColorSyncCustomProfileMapping(
      entries: [.init(key: "default", value: .scope("synthetic-original"))]
    )
    let api = MockDisplaySystemAPI(
      displays: [
        .init(
          sessionID: 10,
          identity: builtInIdentity,
          bounds: .init(x: 0, y: 0, width: 1_440, height: 900),
          isMain: true,
          rotationDegrees: 0,
          isActive: true,
          currentMode: builtInModes[0],
          supportedModes: builtInModes,
          availableColorProfiles: [originalProfile, targetProfile],
          currentColorProfile: originalProfile,
          currentColorProfileMapping: originalMapping,
          canSetColorProfile: true
        ),
        .init(
          sessionID: 20,
          identity: externalIdentity,
          bounds: .init(x: 1_440, y: 0, width: 2_560, height: 1_440),
          isMain: false,
          rotationDegrees: 0,
          isActive: true,
          currentMode: externalModes[0],
          supportedModes: externalModes,
          availableColorProfiles: [originalProfile, targetProfile],
          currentColorProfile: originalProfile,
          currentColorProfileMapping: originalMapping,
          canSetColorProfile: true
        ),
      ]
    )
    let adapter = CoreGraphicsDisplayAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    guard case .display(var desired)? = snapshot.payload else {
      throw InvariantError.missingPayload(.display)
    }
    desired.displays[0].isPrimary.value = false
    desired.displays[1].isPrimary.value = true
    desired.displays[0].mirroring.value = .mirrors(externalIdentity)
    desired.displays[1].mirroring.value = .extended
    desired.displays[0].mode.value = builtInModes[1]
    desired.displays[1].mode.value = externalModes[1]
    desired.displays[0].colorProfile = .init(value: targetProfile)
    desired.displays[1].colorProfile = .init(value: targetProfile)
    let payload = SettingsPayload.display(desired)
    let issues = await adapter.validate(payload, against: snapshot)
    let plan = try await adapter.plan(payload, from: snapshot, mode: .normal)
    return Slice(
      adapter: adapter,
      snapshot: snapshot,
      validationIssues: issues,
      operations: plan.operations
    )
  }

  private var audioAPI: MockAudioSystemAPI {
    AudioInvariantFixture.shared.api
  }

  private func makeAudioSlice() async throws -> Slice {
    let api = audioAPI
    let adapter = CoreAudioAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    let desired = AudioProfileSettings(
      defaultInputUID: .init(value: "input-B"),
      defaultOutputUID: .init(value: "output-B"),
      inputVolume: .init(value: 0.7),
      outputVolume: .init(value: 0.8)
    )
    let payload = SettingsPayload.audio(desired)
    let issues = await adapter.validate(payload, against: snapshot)
    let plan = try await adapter.plan(payload, from: snapshot, mode: .normal)
    return Slice(
      adapter: adapter,
      snapshot: snapshot,
      validationIssues: issues,
      operations: plan.operations
    )
  }

  private var ethernetIdentity: NetworkServiceIdentity {
    .init(
      kind: .ethernet,
      serviceName: "Synthetic Ethernet Service",
      interfaceType: "Ethernet"
    )
  }

  private var wifiIdentity: NetworkServiceIdentity {
    .init(
      kind: .wifi,
      serviceName: "Synthetic Wi-Fi Service",
      interfaceType: "IEEE80211"
    )
  }

  private var networkAPI: MockNetworkSystemAPI {
    NetworkInvariantFixture.shared.api
  }

  private func makeNetworkSlice() async throws -> Slice {
    let api = networkAPI
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    guard case .network(var desired)? = snapshot.payload else {
      throw InvariantError.missingPayload(.network)
    }
    desired.serviceIPv4 = [
      .init(
        identity: ethernetIdentity,
        configuration: .init(
          value: .manual(
            address: "192.0.2.40",
            subnetMask: "255.255.255.0",
            router: "192.0.2.1"
          )
        )
      ),
      .init(
        identity: wifiIdentity,
        configuration: .init(value: .dhcp)
      ),
    ]
    let payload = SettingsPayload.network(desired)
    let issues = await adapter.validate(payload, against: snapshot)
    let plan = try await adapter.plan(payload, from: snapshot, mode: .normal)
    return Slice(
      adapter: adapter,
      snapshot: snapshot,
      validationIssues: issues,
      operations: plan.operations
    )
  }
}

private enum InvariantError: Error {
  case missingPayload(SettingGroup)
}

private final class AudioInvariantFixture: @unchecked Sendable {
  static let shared = AudioInvariantFixture()
  let api: MockAudioSystemAPI

  private init() {
    api = MockAudioSystemAPI(
      devices: [
        .init(
          uid: "input-A", name: "Synthetic Input A", supportsInput: true, supportsOutput: false),
        .init(
          uid: "input-B", name: "Synthetic Input B", supportsInput: true, supportsOutput: false),
        .init(
          uid: "output-A", name: "Synthetic Output A", supportsInput: false, supportsOutput: true),
        .init(
          uid: "output-B", name: "Synthetic Output B", supportsInput: false, supportsOutput: true),
      ],
      defaults: [.input: "input-A", .output: "output-A", .systemOutput: "output-A"],
      inputVolumes: [
        "input-A": .available(value: 0.3, isSettable: true),
        "input-B": .available(value: 0.45, isSettable: true),
      ],
      volumes: [
        "output-A": .available(value: 0.25, isSettable: true),
        "output-B": .available(value: 0.4, isSettable: true),
      ],
      mutes: [
        "output-A": .available(value: false, isSettable: true),
        "output-B": .available(value: false, isSettable: true),
      ]
    )
  }
}

private final class NetworkInvariantFixture: @unchecked Sendable {
  static let shared = NetworkInvariantFixture()
  let api: MockNetworkSystemAPI

  private init() {
    api = MockNetworkSystemAPI(
      snapshot: .init(
        services: [
          .init(
            serviceID: "synthetic-runtime-ethernet",
            serviceName: "Synthetic Ethernet Service",
            interfaceType: "Ethernet",
            kind: .ethernet,
            enabled: true,
            ipv4: .dhcp,
            ipv4ConfigurationData: Data("synthetic-ethernet-rollback".utf8)
          ),
          .init(
            serviceID: "synthetic-runtime-wifi",
            serviceName: "Synthetic Wi-Fi Service",
            interfaceType: "IEEE80211",
            kind: .wifi,
            enabled: true,
            ipv4: .manual(
              address: "198.51.100.20",
              subnetMask: "255.255.255.0",
              router: "198.51.100.1"
            ),
            ipv4ConfigurationData: Data("synthetic-wifi-rollback".utf8)
          ),
        ]
      )
    )
  }
}
