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
          .init(kind: .keyRepeatInterval, currentValue: 2, canApply: true),
          .init(kind: .initialKeyRepeatDelay, currentValue: 15, canApply: true),
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

}

private final class MockInputPreferencesAPI: InputPreferencesAPI, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [InputPreferenceKey: InputPreferenceValue]
  private let failingKeys: Set<InputPreferenceKey>
  private let ignoredWriteKeys: Set<InputPreferenceKey>
  private var writeCount = 0

  init(
    values: [InputPreferenceKey: InputPreferenceValue] = [:],
    failingKeys: Set<InputPreferenceKey> = [],
    ignoredWriteKeys: Set<InputPreferenceKey> = []
  ) {
    self.values = values
    self.failingKeys = failingKeys
    self.ignoredWriteKeys = ignoredWriteKeys
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

  func recordedWriteCount() -> Int {
    lock.withLock { writeCount }
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
