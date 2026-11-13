import Foundation
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSystem

@Suite("Visible setting end-to-end invariant")
struct VisibleSettingEndToEndInvariantTests {
  @Test("every projected field validates, plans, applies, verifies, and rolls back")
  func everyProjectedFieldHasAnExecutableVerticalSlice() async throws {
    let audio = try await makeAudioSlice()
    let input = try await makeInputSlice()
    let slices = [audio, input]
    let snapshots = slices.map(\.snapshot)
    let fields = VisibleSettingRegistry().fields(snapshots: snapshots)

    #expect(Set(fields.map(\.contract.kind)) == Set(VisibleSettingKind.allCases))
    #expect(Set(fields.map(\.contract.group)) == [.audio, .input])
    #expect(!fields.contains { $0.contract.group == .display })
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
    #expect(audioAPI.mute(for: "output-B")?.value == false)
    #expect(inputPreferencesAPI.value(for: .keyRepeatInterval) == .number(2))
    #expect(inputPreferencesAPI.value(for: .initialKeyRepeatDelay) == .number(15))
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
      outputVolume: .init(value: 0.8),
      outputMuted: .init(value: true)
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

  private var inputPreferencesAPI: MockInvariantInputPreferencesAPI {
    InputInvariantFixture.shared.preferences
  }

  private func makeInputSlice() async throws -> Slice {
    let adapter = InputPreferencesAdapter(api: inputPreferencesAPI)
    let snapshot = try await adapter.snapshot()
    let desired = InputProfileSettings(
      keyRepeatInterval: .init(value: 3),
      initialKeyRepeatDelay: .init(value: 20),
      keyboardBrightness: .init(value: 0.8)
    )
    let payload = SettingsPayload.input(desired)
    let issues = await adapter.validate(payload, against: snapshot)
    let plan = try await adapter.plan(payload, from: snapshot, mode: .normal)
    #expect(plan.operations.map(\.key) == ["KeyRepeat", "InitialKeyRepeat"])
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

private final class InputInvariantFixture: @unchecked Sendable {
  static let shared = InputInvariantFixture()
  let preferences = MockInvariantInputPreferencesAPI(values: [
    .keyRepeatInterval: .number(2),
    .initialKeyRepeatDelay: .number(15),
  ])

  private init() {}
}

private final class MockInvariantInputPreferencesAPI: InputPreferencesAPI, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [InputPreferenceKey: InputPreferenceValue]

  init(values: [InputPreferenceKey: InputPreferenceValue]) {
    self.values = values
  }

  func value(for key: InputPreferenceKey) -> InputPreferenceValue? {
    lock.withLock { values[key] }
  }

  func setValue(_ value: InputPreferenceValue?, for key: InputPreferenceKey) throws {
    lock.withLock {
      values[key] = value
    }
  }
}
