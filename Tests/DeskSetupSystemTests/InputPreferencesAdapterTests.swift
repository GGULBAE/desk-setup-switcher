import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupSystem

@Suite("Keyboard input preferences adapter")
struct InputPreferencesAdapterTests {
  @Test("snapshot exposes only key repeat speed and delay")
  func snapshotCapturesRequestedValues() async throws {
    let api = MockInputPreferencesAPI(values: [
      .pointerSpeed: .number(1.5),
      .naturalScrolling: .boolean(true),
      .keyRepeatInterval: .number(2),
      .initialKeyRepeatDelay: .number(15),
      .standardFunctionKeys: .boolean(false),
    ])
    let adapter = InputPreferencesAdapter(
      api: api,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let snapshot = try await adapter.snapshot()
    guard case .input(let settings)? = snapshot.payload else {
      Issue.record("Expected input payload")
      return
    }

    #expect(settings.keyRepeatInterval == .init(value: 2))
    #expect(settings.initialKeyRepeatDelay == .init(value: 15))
    #expect(settings.keyboardBrightness == .init(isIncluded: false, value: nil))
    #expect(settings.pointerSpeed == .init(isIncluded: false, value: nil))
    #expect(settings.naturalScrolling == .init(isIncluded: false, value: nil))
    #expect(settings.useStandardFunctionKeys == .init(isIncluded: false, value: nil))
    #expect(snapshot.items.map(\.key) == ["KeyRepeat", "InitialKeyRepeat"])
    #expect(snapshot.items.allSatisfy { $0.state == .storable })
    #expect(
      snapshot.keyboardControlCatalog
        == [
          .init(
            kind: .keyRepeatInterval, currentValue: 2, canApply: true,
            preferenceRollback: .init(persistedValue: 2, runtimeNanoseconds: 33_333_333)
          ),
          .init(
            kind: .initialKeyRepeatDelay, currentValue: 15, canApply: true,
            preferenceRollback: .init(persistedValue: 15, runtimeNanoseconds: 250_000_000)
          ),
        ]
    )
    #expect(await adapter.capability().state == .experimental)
  }

  @Test("repeat controls plan with rollback while legacy brightness stays dormant")
  func planApplyAndRollback() async throws {
    let api = MockInputPreferencesAPI(values: [
      .keyRepeatInterval: .number(2),
      .initialKeyRepeatDelay: .number(15),
    ])
    let adapter = InputPreferencesAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    let desired = InputProfileSettings(
      pointerSpeed: .init(value: 8),
      naturalScrolling: .init(value: true),
      keyRepeatInterval: .init(value: 3),
      initialKeyRepeatDelay: .init(value: 20),
      keyboardBrightness: .init(value: 0.8),
      useStandardFunctionKeys: .init(value: true)
    )

    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)

    #expect(plan.issues.isEmpty)
    #expect(plan.omissions.isEmpty)
    #expect(plan.operations.map(\.key) == ["KeyRepeat", "InitialKeyRepeat"])
    #expect(plan.operations.allSatisfy { $0.rollbackPayload != nil })

    for operation in plan.operations {
      #expect(await adapter.apply(operation).status == .succeeded)
    }
    #expect(api.value(for: .keyRepeatInterval) == .number(3))
    #expect(api.value(for: .initialKeyRepeatDelay) == .number(20))

    for operation in plan.operations.reversed() {
      #expect(await adapter.rollback(operation).status == .rolledBack)
    }
    #expect(api.value(for: .keyRepeatInterval) == .number(2))
    #expect(api.value(for: .initialKeyRepeatDelay) == .number(15))
  }

  @Test("missing and out-of-range requested values fail validation without mutations")
  func invalidValues() async throws {
    let adapter = InputPreferencesAdapter(
      api: MockInputPreferencesAPI(values: [
        .keyRepeatInterval: .number(2),
        .initialKeyRepeatDelay: .number(15),
      ])
    )
    let snapshot = try await adapter.snapshot()
    let desired = InputProfileSettings(
      keyRepeatInterval: .init(value: nil),
      initialKeyRepeatDelay: .init(value: .infinity),
      keyboardBrightness: .init(value: 1.1)
    )

    let issues = await adapter.validate(.input(desired), against: snapshot)
    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .force)

    #expect(Set(issues.map(\.key)) == ["KeyRepeat", "InitialKeyRepeat"])
    #expect(plan.omissions.contains { $0.key == "KeyRepeat" })
    #expect(!plan.omissions.contains { $0.key == "KeyboardBrightness" })
  }

  @Test("invalid captured numbers stay unreadable, excluded, and non-applicable")
  func invalidCapturedNumbersFailClosed() async throws {
    let adapter = InputPreferencesAdapter(
      api: MockInputPreferencesAPI(values: [
        .keyRepeatInterval: .number(.infinity),
        .initialKeyRepeatDelay: .number(301),
      ])
    )

    let snapshot = try await adapter.snapshot()
    let settings = try #require(snapshot.payload?.inputValue)

    #expect(snapshot.items.allSatisfy { $0.state == .unreadable })
    #expect(snapshot.keyboardControlCatalog?.allSatisfy { !$0.canApply } == true)
    #expect(snapshot.keyboardControlCatalog?.allSatisfy { $0.currentValue == nil } == true)
    #expect(!settings.keyRepeatInterval.isIncluded)
    #expect(!settings.initialKeyRepeatDelay.isIncluded)
    #expect(settings.keyboardBrightness == .init(isIncluded: false, value: nil))
  }

  @Test("crafted preference operations cannot reach dormant, mismatched, or invalid writes")
  func craftedPreferenceOperationsAreRejected() async throws {
    let api = MockInputPreferencesAPI(values: [
      .pointerSpeed: .number(1),
      .naturalScrolling: .boolean(false),
      .keyRepeatInterval: .number(2),
      .initialKeyRepeatDelay: .number(15),
      .standardFunctionKeys: .boolean(false),
    ])
    let adapter = InputPreferencesAdapter(api: api)
    let writes: [(InputPreferenceKey, InputPreferenceValue)] = [
      (.pointerSpeed, .number(2)),
      (.naturalScrolling, .boolean(true)),
      (.standardFunctionKeys, .boolean(true)),
      (.keyRepeatInterval, .boolean(true)),
      (.keyRepeatInterval, .number(0)),
      (.initialKeyRepeatDelay, .number(301)),
    ]

    for (key, value) in writes {
      let payload = try JSONEncoder().encode(CraftedInputPreferenceWrite(key: key, value: value))
      let operation = PlannedOperation(
        group: .input,
        key: key.rawValue,
        summary: "Synthetic crafted write",
        payload: payload,
        rollbackPayload: payload
      )

      #expect((await adapter.apply(operation)).status == .failed)
      #expect((await adapter.rollback(operation)).status == .rollbackFailed)
    }
    #expect(api.recordedWriteCount() == 0)
  }

  @Test("crafted legacy brightness operations cannot reach any preference write")
  func craftedBrightnessIsRejected() async throws {
    let api = MockInputPreferencesAPI()
    let adapter = InputPreferencesAdapter(api: api)
    let payload = try JSONEncoder().encode(CraftedKeyboardBrightnessWrite(value: 1.1))
    let operation = PlannedOperation(
      group: .input,
      key: "KeyboardBrightness",
      summary: "Synthetic crafted brightness",
      payload: payload,
      rollbackPayload: payload
    )

    #expect((await adapter.apply(operation)).status == .failed)
    #expect((await adapter.rollback(operation)).status == .rollbackFailed)
    #expect(api.recordedWriteCount() == 0)
  }

  @Test("experimental preference failures and read-back mismatches fail closed")
  func preferenceFailureAndMismatch() async throws {
    for api in [
      MockInputPreferencesAPI(
        values: [.keyRepeatInterval: .number(2)],
        failingKeys: [.keyRepeatInterval]
      ),
      MockInputPreferencesAPI(
        values: [.keyRepeatInterval: .number(2)],
        ignoredWriteKeys: [.keyRepeatInterval]
      ),
    ] {
      let adapter = InputPreferencesAdapter(api: api)
      let snapshot = try await adapter.snapshot()
      let desired = InputProfileSettings(keyRepeatInterval: .init(value: 3))
      let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)
      let operation = try #require(plan.operations.first)

      #expect((await adapter.apply(operation)).status == .failed)
      #expect(api.value(for: .keyRepeatInterval) == .number(2))
    }
  }

  @Test("saved fast values cannot hide a slow active keyboard or suppress Apply")
  func persistedAndRuntimeDrift() async throws {
    let api = MockInputPreferencesAPI(
      values: [.keyRepeatInterval: .number(2), .initialKeyRepeatDelay: .number(15)],
      runtimeValues: [.keyRepeatInterval: 2_000_000_000, .initialKeyRepeatDelay: 2_000_000_000]
    )
    let adapter = InputPreferencesAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    #expect(snapshot.payload?.inputValue?.keyRepeatInterval.value == 120)
    #expect(snapshot.payload?.inputValue?.initialKeyRepeatDelay.value == 120)
    #expect(await adapter.diagnostics().filter { $0.code == "input.runtime-mismatch" }.count == 2)
    let desired = InputProfileSettings(
      keyRepeatInterval: .init(value: 2), initialKeyRepeatDelay: .init(value: 15))
    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)
    #expect(plan.operations.count == 2)
    for operation in plan.operations {
      #expect(await adapter.apply(operation).status == .succeeded)
    }
    #expect(api.runtimeNanoseconds(for: .keyRepeatInterval) == 33_333_333)
    #expect(api.runtimeNanoseconds(for: .initialKeyRepeatDelay) == 250_000_000)
    for operation in plan.operations.reversed() {
      #expect(await adapter.rollback(operation).status == .rolledBack)
    }
    #expect(api.value(for: .keyRepeatInterval) == .number(2))
    #expect(api.value(for: .initialKeyRepeatDelay) == .number(15))
    #expect(api.runtimeNanoseconds(for: .keyRepeatInterval) == 2_000_000_000)
    #expect(api.runtimeNanoseconds(for: .initialKeyRepeatDelay) == 2_000_000_000)
  }

  @Test("an accepted preference write with ignored runtime write fails and rolls back")
  func runtimeMismatchDoesNotSucceed() async throws {
    let api = MockInputPreferencesAPI(
      values: [.keyRepeatInterval: .number(120)],
      ignoredRuntimeWriteKeys: [.keyRepeatInterval])
    let adapter = InputPreferencesAdapter(api: api)
    let plan = try await adapter.plan(
      .input(.init(keyRepeatInterval: .init(value: 2))),
      from: adapter.snapshot(), mode: .normal)
    let operation = try #require(plan.operations.first)
    #expect(await adapter.apply(operation).status == .failed)
    #expect(api.value(for: .keyRepeatInterval) == .number(2))
    #expect(api.runtimeNanoseconds(for: .keyRepeatInterval) == 2_000_000_000)
    #expect(await adapter.rollback(operation).status == .rolledBack)
    #expect(api.value(for: .keyRepeatInterval) == .number(120))
  }

  @Test("the transaction restores a partial keyboard write before continuing")
  func engineRecoversPartialWrite() async throws {
    let api = MockInputPreferencesAPI(
      values: [.keyRepeatInterval: .number(120), .initialKeyRepeatDelay: .number(120)],
      ignoredRuntimeWriteKeys: [.keyRepeatInterval])
    let adapter = InputPreferencesAdapter(api: api)
    let engine = ApplyEngine(registry: try AdapterRegistry([adapter]))
    var settings = ProfileSettings()
    settings.input.isIncluded = true
    settings.input.value.keyRepeatInterval = .init(value: 2)
    settings.input.value.initialKeyRepeatDelay = .init(value: 15)
    let preparation = await engine.prepare(
      profile: DeskProfile(name: "Synthetic keyboard drift", settings: settings), mode: .normal)
    #expect(preparation.canExecute)
    let result = await engine.execute(preparation)
    #expect(result.status == .failed)
    #expect(result.itemResults.map(\.status) == [.failed, .succeeded])
    #expect(result.rollbackResults.map(\.status) == [.rolledBack])
    #expect(api.value(for: .keyRepeatInterval) == .number(120))
    #expect(api.runtimeNanoseconds(for: .keyRepeatInterval) == 2_000_000_000)
    #expect(api.value(for: .initialKeyRepeatDelay) == .number(15))
    #expect(api.runtimeNanoseconds(for: .initialKeyRepeatDelay) == 250_000_000)
  }

  @Test("runtime access failure is nonfatal and never counts as successful Apply")
  func runtimeWriteFailure() async throws {
    let api = MockInputPreferencesAPI(
      values: [.keyRepeatInterval: .number(120)],
      failingRuntimeKeys: [.keyRepeatInterval])
    let adapter = InputPreferencesAdapter(api: api)
    let plan = try await adapter.plan(
      .input(.init(keyRepeatInterval: .init(value: 2))),
      from: adapter.snapshot(), mode: .normal)
    let operation = try #require(plan.operations.first)
    #expect(!operation.isFatalOnFailure)
    #expect(await adapter.apply(operation).status == .failed)
    #expect(await adapter.rollback(operation).status == .rollbackFailed)
    #expect(api.value(for: .keyRepeatInterval) == .number(120))
  }

  @Test("absent global keys round-trip while the exact active value is restored")
  func absentPersistedPreference() async throws {
    let api = MockInputPreferencesAPI(runtimeValues: [.keyRepeatInterval: 83_333_333])
    let adapter = InputPreferencesAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    let roundTrip = try JSONDecoder().decode(
      AdapterSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(roundTrip == snapshot)
    let plan = try await adapter.plan(
      .input(.init(keyRepeatInterval: .init(value: 2))), from: roundTrip, mode: .normal)
    let operation = try #require(plan.operations.first)
    #expect(await adapter.apply(operation).status == .succeeded)
    #expect(await adapter.rollback(operation).status == .rolledBack)
    #expect(api.value(for: .keyRepeatInterval) == nil)
    #expect(api.runtimeNanoseconds(for: .keyRepeatInterval) == 83_333_333)
  }

  @Test("rollback still restores runtime when the saved preference restore fails")
  func rollbackAttemptsBothLayers() async throws {
    let api = MockInputPreferencesAPI(values: [.keyRepeatInterval: .number(120)])
    let adapter = InputPreferencesAdapter(api: api)
    let plan = try await adapter.plan(
      .input(.init(keyRepeatInterval: .init(value: 2))),
      from: adapter.snapshot(), mode: .normal)
    let operation = try #require(plan.operations.first)
    #expect(await adapter.apply(operation).status == .succeeded)
    api.failPreferenceWrites(for: .keyRepeatInterval)
    #expect(await adapter.rollback(operation).status == .rollbackFailed)
    #expect(api.runtimeNanoseconds(for: .keyRepeatInterval) == 2_000_000_000)
    #expect(api.value(for: .keyRepeatInterval) == .number(2))
  }

  @Test("unreadable runtime and old snapshots omit only the unavailable control")
  func unavailableRuntimeAndLegacySnapshot() async throws {
    let api = MockInputPreferencesAPI(
      values: [.keyRepeatInterval: .number(2), .initialKeyRepeatDelay: .number(15)],
      runtimeValues: [.initialKeyRepeatDelay: 250_000_000])
    let adapter = InputPreferencesAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    let desired = SettingsPayload.input(
      .init(
        keyRepeatInterval: .init(value: 3), initialKeyRepeatDelay: .init(value: 25)))
    for mode in [ApplyMode.normal, .force] {
      let plan = try await adapter.plan(desired, from: snapshot, mode: mode)
      #expect(plan.operations.map(\.key) == ["InitialKeyRepeat"])
      #expect(plan.omissions.map(\.key) == ["KeyRepeat"])
    }
    var legacy = snapshot
    legacy.keyboardControlCatalog = [
      try JSONDecoder().decode(
        KeyboardControlCatalogEntry.self,
        from: Data(#"{"kind":"keyRepeatInterval","currentValue":2,"canApply":true}"#.utf8))
    ]
    #expect(legacy.keyboardControlCatalog?.first?.preferenceRollback == nil)
    let plan = try await adapter.plan(desired, from: legacy, mode: .normal)
    #expect(plan.operations.isEmpty)
    #expect(api.recordedWriteCount() == 0)
  }

  @Test("no-op requires both layers to agree, including fractional imported values")
  func noOpRequiresBothLayers() async throws {
    let api = MockInputPreferencesAPI(values: [.keyRepeatInterval: .number(2.5)])
    let adapter = InputPreferencesAdapter(api: api)
    let desired = SettingsPayload.input(.init(keyRepeatInterval: .init(value: 2.5)))
    let plan = try await adapter.plan(desired, from: adapter.snapshot(), mode: .normal)
    #expect(plan.operations.isEmpty)
    try api.setValue(.number(5), for: .keyRepeatInterval)
    let changed = try await adapter.plan(desired, from: adapter.snapshot(), mode: .normal)
    #expect(changed.operations.count == 1)
    let operation = try #require(changed.operations.first)
    #expect(await adapter.apply(operation).status == .succeeded)
    #expect(await adapter.rollback(operation).status == .rolledBack)
    #expect(api.value(for: .keyRepeatInterval) == .number(5))
    #expect(api.runtimeNanoseconds(for: .keyRepeatInterval) == 41_666_667)
  }

  @Test("native Off and malformed paired writes cannot enter the mutation path")
  func unsupportedOffAndCraftedPair() async throws {
    let api = MockInputPreferencesAPI(
      values: [.keyRepeatInterval: .number(2)],
      runtimeValues: [.keyRepeatInterval: 0])
    let adapter = InputPreferencesAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    #expect(snapshot.items.allSatisfy { $0.state == .unreadable })
    for (key, saved, runtime) in [
      ("KeyRepeat", 2.0, 250_000_000),
      ("InitialKeyRepeat", 15.0, 0),
      ("KeyRepeat", 121.0, 2_016_666_667),
    ] {
      let payload = try JSONSerialization.data(withJSONObject: [
        "key": key, "persistedValue": saved, "runtimeNanoseconds": runtime,
      ])
      let operation = PlannedOperation(
        group: .input, key: key, summary: "Synthetic invalid pair", payload: payload)
      #expect(await adapter.apply(operation).status == .failed)
    }
    #expect(api.recordedWriteCount() == 0)
  }

}

private final class MockInputPreferencesAPI: InputPreferencesAPI, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [InputPreferenceKey: InputPreferenceValue]
  private var failingKeys: Set<InputPreferenceKey>
  private let ignoredWriteKeys: Set<InputPreferenceKey>
  private var writeCount = 0
  private var runtimeValues: [InputPreferenceKey: Int64]
  private let failingRuntimeKeys: Set<InputPreferenceKey>
  private let ignoredRuntimeWriteKeys: Set<InputPreferenceKey>

  init(
    values: [InputPreferenceKey: InputPreferenceValue] = [:],
    failingKeys: Set<InputPreferenceKey> = [],
    ignoredWriteKeys: Set<InputPreferenceKey> = [],
    runtimeValues: [InputPreferenceKey: Int64]? = nil,
    failingRuntimeKeys: Set<InputPreferenceKey> = [],
    ignoredRuntimeWriteKeys: Set<InputPreferenceKey> = []
  ) {
    self.values = values
    self.failingKeys = failingKeys
    self.ignoredWriteKeys = ignoredWriteKeys
    self.runtimeValues =
      runtimeValues
      ?? values.compactMapValues {
        guard case .number(let number) = $0, number.isFinite, (1...300).contains(number) else {
          return nil
        }
        return KeyboardRepeatTiming.nanoseconds(for: number)
      }
    self.failingRuntimeKeys = failingRuntimeKeys
    self.ignoredRuntimeWriteKeys = ignoredRuntimeWriteKeys
  }

  func value(for key: InputPreferenceKey) -> InputPreferenceValue? {
    lock.withLock { values[key] }
  }

  func setValue(_ value: InputPreferenceValue?, for key: InputPreferenceKey) throws {
    try lock.withLock {
      writeCount += 1
      if failingKeys.contains(key) {
        throw InputPreferencesAPIError.synchronizationFailed
      }
      if ignoredWriteKeys.contains(key) {
        return
      }
      values[key] = value
    }
  }

  func runtimeNanoseconds(for key: InputPreferenceKey) -> Int64? {
    lock.withLock { runtimeValues[key] }
  }

  func setRuntimeNanoseconds(_ value: Int64, for key: InputPreferenceKey) throws {
    try lock.withLock {
      writeCount += 1
      if failingRuntimeKeys.contains(key) { throw InputPreferencesAPIError.runtimeUnavailable }
      if !ignoredRuntimeWriteKeys.contains(key) { runtimeValues[key] = value }
    }
  }

  func recordedWriteCount() -> Int {
    lock.withLock { writeCount }
  }

  func failPreferenceWrites(for key: InputPreferenceKey) {
    _ = lock.withLock { failingKeys.insert(key) }
  }
}

private struct CraftedInputPreferenceWrite: Codable {
  let key: InputPreferenceKey
  let value: InputPreferenceValue
}

private struct CraftedKeyboardBrightnessWrite: Codable {
  let value: Double
}

extension SettingsPayload {
  fileprivate var inputValue: InputProfileSettings? {
    guard case .input(let value) = self else { return nil }
    return value
  }
}
