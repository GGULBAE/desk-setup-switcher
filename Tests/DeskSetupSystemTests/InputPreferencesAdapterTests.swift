import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupSystem

@Suite("Experimental input preferences adapter")
struct InputPreferencesAdapterTests {
  @Test("snapshot captures available common values")
  func snapshotCapturesValues() async throws {
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

    #expect(settings.pointerSpeed.value == 1.5)
    #expect(settings.naturalScrolling.value == true)
    #expect(settings.useStandardFunctionKeys.value == false)
    #expect(snapshot.items.allSatisfy { $0.state == .storable })
    #expect(await adapter.capability().state == .experimental)
  }

  @Test("plan skips no-ops and carries rollback values")
  func planAndRollback() async throws {
    let api = MockInputPreferencesAPI(values: [
      .pointerSpeed: .number(1),
      .naturalScrolling: .boolean(true),
    ])
    let adapter = InputPreferencesAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    var desired = InputProfileSettings()
    desired.pointerSpeed = .init(value: 2)
    desired.naturalScrolling = .init(value: true)

    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)
    #expect(plan.operations.count == 1)
    guard let operation = plan.operations.first else { return }
    #expect(operation.preview == OperationPreview(previousValue: "1", desiredValue: "2"))

    #expect((await adapter.apply(operation)).status == .succeeded)
    #expect(api.value(for: .pointerSpeed) == .number(2))
    #expect((await adapter.rollback(operation)).status == .rolledBack)
    #expect(api.value(for: .pointerSpeed) == .number(1))
  }

  @Test("missing values are omitted and unsafe numbers are rejected")
  func invalidValues() async throws {
    let adapter = InputPreferencesAdapter(api: MockInputPreferencesAPI())
    let snapshot = try await adapter.snapshot()
    var desired = InputProfileSettings()
    desired.pointerSpeed = .init(value: 99)
    desired.naturalScrolling = .init(value: nil)

    let issues = await adapter.validate(.input(desired), against: snapshot)
    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .force)

    #expect(issues.contains(where: { $0.key == InputPreferenceKey.pointerSpeed.rawValue }))
    #expect(
      plan.omissions.contains(where: { $0.key == InputPreferenceKey.naturalScrolling.rawValue }))
  }

  @Test("write failures return typed failure without changing the host")
  func writeFailure() async throws {
    let api = MockInputPreferencesAPI(
      values: [.pointerSpeed: .number(1)],
      failingKeys: [.pointerSpeed]
    )
    let adapter = InputPreferencesAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    var desired = InputProfileSettings()
    desired.pointerSpeed = .init(value: 2)
    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)
    guard let operation = plan.operations.first else {
      Issue.record("Expected an operation")
      return
    }

    #expect((await adapter.apply(operation)).status == .failed)
    #expect(api.value(for: .pointerSpeed) == .number(1))
  }

  @Test("write is not successful when immediate read-back disagrees")
  func readBackMismatchFails() async throws {
    let api = MockInputPreferencesAPI(
      values: [.pointerSpeed: .number(1)],
      ignoredWriteKeys: [.pointerSpeed]
    )
    let adapter = InputPreferencesAdapter(api: api)
    let snapshot = try await adapter.snapshot()
    var desired = InputProfileSettings()
    desired.pointerSpeed = .init(value: 2)
    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)
    guard let operation = plan.operations.first else {
      Issue.record("Expected an operation")
      return
    }

    let result = await adapter.apply(operation)

    #expect(result.status == .failed)
    #expect(result.message.contains("read-back"))
    #expect(api.value(for: .pointerSpeed) == .number(1))
  }
}

private final class MockInputPreferencesAPI: InputPreferencesAPI, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [InputPreferenceKey: InputPreferenceValue]
  private let failingKeys: Set<InputPreferenceKey>
  private let ignoredWriteKeys: Set<InputPreferenceKey>

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
      if failingKeys.contains(key) {
        throw InputPreferencesAPIError.synchronizationFailed
      }
      if ignoredWriteKeys.contains(key) {
        return
      }
      values[key] = value
    }
  }
}
