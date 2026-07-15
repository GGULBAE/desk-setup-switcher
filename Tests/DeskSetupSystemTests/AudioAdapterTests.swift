import Foundation
import XCTest

@testable import DeskSetupSystem

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

final class AudioAdapterTests: XCTestCase {
  func testSnapshotUsesUIDsAndReportsScopesAndControls() async throws {
    let api = makeAPI()
    let adapter = makeAdapter(api: api)

    let snapshot = try await adapter.snapshot()

    XCTAssertEqual(snapshot.group, .audio)
    XCTAssertEqual(snapshot.capturedAt, Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertEqual(
      Set(snapshot.items.filter { $0.key.hasPrefix("device:") }.map(\.key)),
      ["device:input-A", "device:input-B", "device:output-A", "device:output-B"]
    )
    XCTAssertEqual(
      snapshot.items.filter { $0.label == "USB Audio" }.count,
      2,
      "Identical presentation names must remain separate UID-backed devices."
    )

    guard case .audio(let settings)? = snapshot.payload else {
      return XCTFail("Expected an audio payload")
    }
    XCTAssertEqual(settings.defaultInputUID.value, "input-A")
    XCTAssertEqual(settings.defaultOutputUID.value, "output-A")
    XCTAssertEqual(settings.systemOutputUID.value, "output-A")
    XCTAssertEqual(settings.inputVolume.value, 0.35)
    XCTAssertEqual(settings.outputVolume.value, 0.25)
    XCTAssertEqual(settings.outputMuted.value, false)
    XCTAssertTrue(settings.inputVolume.isIncluded)
    XCTAssertTrue(settings.outputVolume.isIncluded)
    XCTAssertTrue(settings.outputMuted.isIncluded)

    let capability = await adapter.capability()
    XCTAssertEqual(capability.state, .supported)
  }

  func testPlansTypedUIDOperationsAndApplyRollbackRoundTrip() async throws {
    let api = makeAPI()
    let adapter = makeAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    let desired = AudioProfileSettings(
      defaultInputUID: .init(isIncluded: true, value: "input-B"),
      defaultOutputUID: .init(isIncluded: true, value: "output-B"),
      systemOutputUID: .init(isIncluded: true, value: "output-B"),
      inputVolume: .init(isIncluded: true, value: 0.65),
      outputVolume: .init(isIncluded: true, value: 0.75),
      outputMuted: .init(isIncluded: true, value: true)
    )

    let issues = await adapter.validate(.audio(desired), against: snapshot)
    XCTAssertFalse(issues.contains(where: \.isFatal))
    let plan = try await adapter.plan(.audio(desired), from: snapshot, mode: .force)

    XCTAssertEqual(
      plan.operations.map(\.key),
      [
        "defaultInput", "defaultOutput", "systemOutput", "inputVolume", "outputVolume",
        "outputMute",
      ]
    )
    XCTAssertTrue(plan.omissions.isEmpty)
    let volumeOperation = try XCTUnwrap(
      plan.operations.first(where: { $0.key == "outputVolume" })
    )
    XCTAssertEqual(volumeOperation.preview?.previousValue, "40%")
    XCTAssertEqual(volumeOperation.preview?.desiredValue, "75%")
    let inputOperation = try XCTUnwrap(
      plan.operations.first(where: { $0.key == "defaultInput" })
    )
    XCTAssertTrue(inputOperation.preview?.previousValue.contains("Built-in Audio") == true)
    XCTAssertTrue(inputOperation.preview?.desiredValue.contains("USB Microphone") == true)
    XCTAssertEqual(
      try JSONDecoder().decode(
        AudioOperationCommand.self,
        from: try XCTUnwrap(volumeOperation.rollbackPayload)
      ),
      .setOutputVolume(deviceUID: "output-B", value: 0.4)
    )

    for operation in plan.operations {
      let result = await adapter.apply(operation)
      XCTAssertEqual(result.status, .succeeded)
    }
    XCTAssertEqual(api.defaultUID(for: .input), "input-B")
    XCTAssertEqual(api.defaultUID(for: .output), "output-B")
    XCTAssertEqual(api.defaultUID(for: .systemOutput), "output-B")
    XCTAssertEqual(api.inputVolume(for: "input-B")?.value, 0.65)
    XCTAssertEqual(api.volume(for: "output-B")?.value, 0.75)
    XCTAssertEqual(api.mute(for: "output-B")?.value, true)

    for operation in plan.operations.reversed() {
      let result = await adapter.rollback(operation)
      XCTAssertEqual(result.status, .rolledBack)
    }
    XCTAssertEqual(api.defaultUID(for: .input), "input-A")
    XCTAssertEqual(api.defaultUID(for: .output), "output-A")
    XCTAssertEqual(api.defaultUID(for: .systemOutput), "output-A")
    XCTAssertEqual(api.inputVolume(for: "input-B")?.value, 0.55)
    XCTAssertEqual(api.volume(for: "output-B")?.value, 0.4)
    XCTAssertEqual(api.mute(for: "output-B")?.value, false)
  }

  func testUnsupportedVolumeAndMuteAreItemOmissionsNotFatalGroupIssues() async throws {
    let api = makeAPI()
    api.setInputVolumeState(.unsupported, for: "input-A")
    api.setVolumeState(.unsupported, for: "output-A")
    api.setMuteState(.unsupported, for: "output-A")
    let adapter = makeAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    let desired = AudioProfileSettings(
      inputVolume: .init(isIncluded: true, value: 0.5),
      outputVolume: .init(isIncluded: true, value: 0.5),
      outputMuted: .init(isIncluded: true, value: true)
    )

    let issues = await adapter.validate(.audio(desired), against: snapshot)
    let plan = try await adapter.plan(.audio(desired), from: snapshot, mode: .force)

    XCTAssertFalse(issues.contains(where: \.isFatal))
    XCTAssertTrue(plan.operations.isEmpty)
    XCTAssertEqual(
      Set(plan.omissions.map(\.key)),
      ["inputVolume", "outputVolume", "outputMute"]
    )
    XCTAssertTrue(plan.omissions.allSatisfy { $0.status == .unsupported })
  }

  func testNoOpsAreNotPlannedOrReportedUnavailable() async throws {
    let api = makeAPI()
    let adapter = makeAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    let desired = AudioProfileSettings(
      defaultInputUID: .init(isIncluded: true, value: "input-A"),
      defaultOutputUID: .init(isIncluded: true, value: "output-A"),
      systemOutputUID: .init(isIncluded: true, value: "output-A"),
      inputVolume: .init(isIncluded: true, value: 0.35),
      outputVolume: .init(isIncluded: true, value: 0.25),
      outputMuted: .init(isIncluded: true, value: false)
    )

    let plan = try await adapter.plan(.audio(desired), from: snapshot, mode: .normal)

    XCTAssertTrue(plan.operations.isEmpty)
    XCTAssertTrue(plan.omissions.isEmpty)
    XCTAssertTrue(api.mutations().isEmpty)
  }

  func testValidationUsesUIDAndRequiredScopeRatherThanName() async throws {
    let api = makeAPI()
    let adapter = makeAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    let desired = AudioProfileSettings(
      defaultInputUID: .init(isIncluded: true, value: "output-B"),
      defaultOutputUID: .init(isIncluded: true, value: "missing")
    )

    let issues = await adapter.validate(.audio(desired), against: snapshot)

    XCTAssertTrue(issues.contains { $0.key == "defaultInput" && $0.isFatal })
    XCTAssertTrue(issues.contains { $0.key == "defaultOutput" && $0.isFatal })
  }

  func testApplyFailsWithoutCallingReadOnlyControlSetter() async throws {
    let api = makeAPI()
    api.setVolumeState(.available(value: 0.25, isSettable: false), for: "output-A")
    let adapter = makeAdapter(api: api)
    let payload = try JSONEncoder().encode(
      AudioOperationCommand.setOutputVolume(deviceUID: "output-A", value: 0.8)
    )
    let operation = PlannedOperation(
      group: .audio,
      key: "outputVolume",
      summary: "Synthetic read-only test",
      payload: payload
    )

    let result = await adapter.apply(operation)

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(api.volume(for: "output-A")?.value, 0.25)
    XCTAssertTrue(api.mutations().isEmpty)
  }

  private func makeAdapter(api: MockAudioSystemAPI) -> CoreAudioAdapter {
    CoreAudioAdapter(
      api: api,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
  }

  private func makeAPI() -> MockAudioSystemAPI {
    MockAudioSystemAPI(
      devices: [
        AudioDeviceDescriptor(
          uid: "input-A",
          name: "Built-in Audio",
          supportsInput: true,
          supportsOutput: false
        ),
        AudioDeviceDescriptor(
          uid: "output-A",
          name: "USB Audio",
          supportsInput: false,
          supportsOutput: true
        ),
        AudioDeviceDescriptor(
          uid: "input-B",
          name: "USB Microphone",
          supportsInput: true,
          supportsOutput: false
        ),
        AudioDeviceDescriptor(
          uid: "output-B",
          name: "USB Audio",
          supportsInput: false,
          supportsOutput: true
        ),
      ],
      defaults: [
        .input: "input-A",
        .output: "output-A",
        .systemOutput: "output-A",
      ],
      inputVolumes: [
        "input-A": .available(value: 0.35, isSettable: true),
        "input-B": .available(value: 0.55, isSettable: true),
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

private final class MockAudioSystemAPI: AudioSystemAPI, @unchecked Sendable {
  private let lock = NSLock()
  private var deviceValues: [AudioDeviceDescriptor]
  private var defaultValues: [AudioDefaultDeviceRole: String]
  private var inputVolumeValues: [String: AudioControlState<Double>]
  private var volumeValues: [String: AudioControlState<Double>]
  private var muteValues: [String: AudioControlState<Bool>]
  private var mutationValues: [AudioOperationCommand] = []

  init(
    devices: [AudioDeviceDescriptor],
    defaults: [AudioDefaultDeviceRole: String],
    inputVolumes: [String: AudioControlState<Double>],
    volumes: [String: AudioControlState<Double>],
    mutes: [String: AudioControlState<Bool>]
  ) {
    deviceValues = devices
    defaultValues = defaults
    inputVolumeValues = inputVolumes
    volumeValues = volumes
    muteValues = mutes
  }

  func devices() throws -> [AudioDeviceDescriptor] {
    withLock { deviceValues }
  }

  func defaultDeviceUID(for role: AudioDefaultDeviceRole) throws -> String? {
    withLock { defaultValues[role] }
  }

  func outputVolume(forDeviceUID uid: String) throws -> AudioControlState<Double> {
    try withLock {
      guard deviceValues.contains(where: { $0.uid == uid && $0.supportsOutput }) else {
        throw AudioSystemError.deviceNotFound(uid: uid)
      }
      return volumeValues[uid] ?? .unsupported
    }
  }

  func inputVolume(forDeviceUID uid: String) throws -> AudioControlState<Double> {
    try withLock {
      guard deviceValues.contains(where: { $0.uid == uid && $0.supportsInput }) else {
        throw AudioSystemError.deviceNotFound(uid: uid)
      }
      return inputVolumeValues[uid] ?? .unsupported
    }
  }

  func outputMute(forDeviceUID uid: String) throws -> AudioControlState<Bool> {
    try withLock {
      guard deviceValues.contains(where: { $0.uid == uid && $0.supportsOutput }) else {
        throw AudioSystemError.deviceNotFound(uid: uid)
      }
      return muteValues[uid] ?? .unsupported
    }
  }

  func setDefaultDeviceUID(_ uid: String, for role: AudioDefaultDeviceRole) throws {
    try withLock {
      guard let device = deviceValues.first(where: { $0.uid == uid }) else {
        throw AudioSystemError.deviceNotFound(uid: uid)
      }
      let supported = role == .input ? device.supportsInput : device.supportsOutput
      guard supported else {
        throw AudioSystemError.deviceHasWrongScope(uid: uid, role: role)
      }
      defaultValues[role] = uid
      mutationValues.append(.setDefaultDevice(role: role, uid: uid))
    }
  }

  func setOutputVolume(_ value: Double, forDeviceUID uid: String) throws {
    try withLock {
      guard value.isFinite, (0.0...1.0).contains(value) else {
        throw AudioSystemError.invalidVolume(value)
      }
      switch volumeValues[uid] ?? .unsupported {
      case .available(_, true):
        volumeValues[uid] = .available(value: value, isSettable: true)
        mutationValues.append(.setOutputVolume(deviceUID: uid, value: value))
      case .available(_, false):
        throw AudioSystemError.controlNotSettable(uid: uid, key: "volume")
      case .unsupported:
        throw AudioSystemError.unsupportedControl(uid: uid, key: "volume")
      case .unreadable:
        throw AudioSystemError.malformedProperty("volume")
      }
    }
  }

  func setInputVolume(_ value: Double, forDeviceUID uid: String) throws {
    try withLock {
      guard value.isFinite, (0.0...1.0).contains(value) else {
        throw AudioSystemError.invalidVolume(value)
      }
      switch inputVolumeValues[uid] ?? .unsupported {
      case .available(_, true):
        inputVolumeValues[uid] = .available(value: value, isSettable: true)
        mutationValues.append(.setInputVolume(deviceUID: uid, value: value))
      case .available(_, false):
        throw AudioSystemError.controlNotSettable(uid: uid, key: "input volume")
      case .unsupported:
        throw AudioSystemError.unsupportedControl(uid: uid, key: "input volume")
      case .unreadable:
        throw AudioSystemError.malformedProperty("input volume")
      }
    }
  }

  func setOutputMute(_ value: Bool, forDeviceUID uid: String) throws {
    try withLock {
      switch muteValues[uid] ?? .unsupported {
      case .available(_, true):
        muteValues[uid] = .available(value: value, isSettable: true)
        mutationValues.append(.setOutputMute(deviceUID: uid, value: value))
      case .available(_, false):
        throw AudioSystemError.controlNotSettable(uid: uid, key: "mute")
      case .unsupported:
        throw AudioSystemError.unsupportedControl(uid: uid, key: "mute")
      case .unreadable:
        throw AudioSystemError.malformedProperty("mute")
      }
    }
  }

  func defaultUID(for role: AudioDefaultDeviceRole) -> String? {
    withLock { defaultValues[role] }
  }

  func volume(for uid: String) -> AudioControlState<Double>? {
    withLock { volumeValues[uid] }
  }

  func inputVolume(for uid: String) -> AudioControlState<Double>? {
    withLock { inputVolumeValues[uid] }
  }

  func mute(for uid: String) -> AudioControlState<Bool>? {
    withLock { muteValues[uid] }
  }

  func mutations() -> [AudioOperationCommand] {
    withLock { mutationValues }
  }

  func setVolumeState(_ state: AudioControlState<Double>, for uid: String) {
    withLock { volumeValues[uid] = state }
  }

  func setInputVolumeState(_ state: AudioControlState<Double>, for uid: String) {
    withLock { inputVolumeValues[uid] = state }
  }

  func setMuteState(_ state: AudioControlState<Bool>, for uid: String) {
    withLock { muteValues[uid] = state }
  }

  private func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
