import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupSystem

@Suite("Keyboard input preferences adapter")
struct InputPreferencesAdapterTests {
  @Test("snapshot exposes only the three requested keyboard controls")
  func snapshotCapturesRequestedValues() async throws {
    let api = MockInputPreferencesAPI(values: [
      .pointerSpeed: .number(1.5),
      .naturalScrolling: .boolean(true),
      .keyRepeatInterval: .number(2),
      .initialKeyRepeatDelay: .number(15),
      .standardFunctionKeys: .boolean(false),
    ])
    let backlight = MockKeyboardBacklightAPI(result: .available(0.4))
    let adapter = InputPreferencesAdapter(
      api: api,
      keyboardBacklightAPI: backlight,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let snapshot = try await adapter.snapshot()
    guard case .input(let settings)? = snapshot.payload else {
      Issue.record("Expected input payload")
      return
    }

    #expect(settings.keyRepeatInterval == .init(value: 2))
    #expect(settings.initialKeyRepeatDelay == .init(value: 15))
    #expect(settings.keyboardBrightness == .init(value: 0.4))
    #expect(settings.pointerSpeed == .init(isIncluded: false, value: nil))
    #expect(settings.naturalScrolling == .init(isIncluded: false, value: nil))
    #expect(settings.useStandardFunctionKeys == .init(isIncluded: false, value: nil))
    #expect(snapshot.items.map(\.key) == ["KeyRepeat", "InitialKeyRepeat", "KeyboardBrightness"])
    #expect(snapshot.items.allSatisfy { $0.state == .storable })
    #expect(
      snapshot.keyboardControlCatalog
        == [
          .init(kind: .keyRepeatInterval, currentValue: 2, canApply: true),
          .init(kind: .initialKeyRepeatDelay, currentValue: 15, canApply: true),
          .init(
            kind: .keyboardBrightness,
            currentValue: 0.4,
            canApply: true,
            quantizationTolerance: 0
          ),
        ]
    )
    #expect(await adapter.capability().state == .experimental)
  }

  @Test("all three controls plan with rollback and legacy controls stay dormant")
  func planApplyAndRollback() async throws {
    let api = MockInputPreferencesAPI(values: [
      .keyRepeatInterval: .number(2),
      .initialKeyRepeatDelay: .number(15),
    ])
    let backlight = MockKeyboardBacklightAPI(result: .available(0.4))
    let adapter = InputPreferencesAdapter(api: api, keyboardBacklightAPI: backlight)
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
    #expect(plan.operations.map(\.key) == ["KeyRepeat", "InitialKeyRepeat", "KeyboardBrightness"])
    #expect(plan.operations.allSatisfy { $0.rollbackPayload != nil })
    #expect(plan.operations[2].preview == .init(previousValue: "40%", desiredValue: "80%"))

    for operation in plan.operations {
      #expect(await adapter.apply(operation).status == .succeeded)
    }
    #expect(api.value(for: .keyRepeatInterval) == .number(3))
    #expect(api.value(for: .initialKeyRepeatDelay) == .number(20))
    #expect(await backlight.currentBrightness() == 0.8)

    for operation in plan.operations.reversed() {
      #expect(await adapter.rollback(operation).status == .rolledBack)
    }
    #expect(api.value(for: .keyRepeatInterval) == .number(2))
    #expect(api.value(for: .initialKeyRepeatDelay) == .number(15))
    #expect(await backlight.currentBrightness() == 0.4)
  }

  @Test("missing and out-of-range requested values fail validation without mutations")
  func invalidValues() async throws {
    let adapter = InputPreferencesAdapter(
      api: MockInputPreferencesAPI(values: [
        .keyRepeatInterval: .number(2),
        .initialKeyRepeatDelay: .number(15),
      ]),
      keyboardBacklightAPI: MockKeyboardBacklightAPI(result: .available(0.5))
    )
    let snapshot = try await adapter.snapshot()
    let desired = InputProfileSettings(
      keyRepeatInterval: .init(value: nil),
      initialKeyRepeatDelay: .init(value: .infinity),
      keyboardBrightness: .init(value: 1.1)
    )

    let issues = await adapter.validate(.input(desired), against: snapshot)
    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .force)

    #expect(Set(issues.map(\.key)) == ["KeyRepeat", "InitialKeyRepeat", "KeyboardBrightness"])
    #expect(plan.omissions.contains { $0.key == "KeyRepeat" })
  }

  @Test("permission-required brightness stays nonfatal and cannot plan")
  func permissionRequiredBrightnessIsOmitted() async throws {
    let adapter = InputPreferencesAdapter(
      api: MockInputPreferencesAPI(values: [
        .keyRepeatInterval: .number(2),
        .initialKeyRepeatDelay: .number(15),
      ]),
      keyboardBacklightAPI: MockKeyboardBacklightAPI(result: .permissionRequired)
    )
    let snapshot = try await adapter.snapshot()
    let desired = InputProfileSettings(keyboardBrightness: .init(value: 0.75))

    let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)

    #expect(snapshot.items.last?.state == .permissionRequired)
    #expect(snapshot.keyboardControlCatalog?.last?.canApply == false)
    #expect(snapshot.keyboardControlCatalog?.last?.currentValue == nil)
    #expect(plan.operations.isEmpty)
    #expect(plan.issues.isEmpty)
    #expect(plan.omissions.count == 1)
    #expect(plan.omissions[0].key == "KeyboardBrightness")
    #expect(plan.omissions[0].reason.contains("permission"))
  }

  @Test("invalid captured numbers stay unreadable, excluded, and non-applicable")
  func invalidCapturedNumbersFailClosed() async throws {
    for brightness in [Double.nan, -0.01, 1.01] {
      let adapter = InputPreferencesAdapter(
        api: MockInputPreferencesAPI(values: [
          .keyRepeatInterval: .number(.infinity),
          .initialKeyRepeatDelay: .number(301),
        ]),
        keyboardBacklightAPI: MockKeyboardBacklightAPI(result: .available(brightness))
      )

      let snapshot = try await adapter.snapshot()
      let settings = try #require(snapshot.payload?.inputValue)

      #expect(snapshot.items.allSatisfy { $0.state == .unreadable })
      #expect(snapshot.keyboardControlCatalog?.allSatisfy { !$0.canApply } == true)
      #expect(snapshot.keyboardControlCatalog?.allSatisfy { $0.currentValue == nil } == true)
      #expect(!settings.keyRepeatInterval.isIncluded)
      #expect(!settings.initialKeyRepeatDelay.isIncluded)
      #expect(!settings.keyboardBrightness.isIncluded)
    }
  }

  @Test("denied and unknown HID access return permission-required without discovery")
  func accessPreflightFailsClosed() async {
    for status in [KeyboardBacklightAccessStatus.denied, .unknown] {
      let api = CoreHIDKeyboardBacklightAPI(accessStatus: { status })

      let expectedRead: KeyboardBacklightReadResult =
        if #available(macOS 15, *) { .permissionRequired } else { .unsupported }
      let expectedError: KeyboardBacklightAPIError =
        if #available(macOS 15, *) { .permissionRequired } else { .unsupported }
      #expect(await api.readBrightness() == expectedRead)
      do {
        _ = try await api.setBrightness(0.5)
        Issue.record("Expected a typed unsupported or permission-required write failure")
      } catch let error as KeyboardBacklightAPIError {
        #expect(error == expectedError)
      } catch {
        Issue.record("Expected typed keyboard-backlight error")
      }
    }
  }

  @Test("keyboard backlight discovery accepts exactly one compatible candidate")
  func soleCandidatePolicyFailsClosedOnZeroOrAmbiguity() {
    #expect(KeyboardBacklightCandidatePolicy.soleCandidate([Int]()) == nil)
    #expect(KeyboardBacklightCandidatePolicy.soleCandidate([42]) == 42)
    #expect(KeyboardBacklightCandidatePolicy.soleCandidate([1, 2]) == nil)
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
    let adapter = InputPreferencesAdapter(
      api: api,
      keyboardBacklightAPI: MockKeyboardBacklightAPI(result: .unsupported)
    )
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

  @Test("crafted out-of-range brightness never reaches the backlight API")
  func craftedBrightnessIsRejected() async throws {
    let backlight = MockKeyboardBacklightAPI(result: .available(0.4))
    let adapter = InputPreferencesAdapter(
      api: MockInputPreferencesAPI(),
      keyboardBacklightAPI: backlight
    )
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
    #expect(await backlight.recordedSetCallCount() == 0)
    #expect(await backlight.currentBrightness() == 0.4)
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
      let adapter = InputPreferencesAdapter(
        api: api,
        keyboardBacklightAPI: MockKeyboardBacklightAPI(result: .unsupported)
      )
      let snapshot = try await adapter.snapshot()
      let desired = InputProfileSettings(keyRepeatInterval: .init(value: 3))
      let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)
      let operation = try #require(plan.operations.first)

      #expect((await adapter.apply(operation)).status == .failed)
      #expect(api.value(for: .keyRepeatInterval) == .number(2))
    }
  }

  @Test("brightness write errors and mismatched read-back fail closed")
  func brightnessFailureAndMismatch() async throws {
    for behavior in [MockKeyboardBacklightAPI.WriteBehavior.fail, .ignore, .invalidReadBack] {
      let backlight = MockKeyboardBacklightAPI(result: .available(0.4), behavior: behavior)
      let adapter = InputPreferencesAdapter(
        api: MockInputPreferencesAPI(),
        keyboardBacklightAPI: backlight
      )
      let snapshot = try await adapter.snapshot()
      let desired = InputProfileSettings(keyboardBrightness: .init(value: 0.8))
      let plan = try await adapter.plan(.input(desired), from: snapshot, mode: .normal)
      let operation = try #require(plan.operations.first)

      #expect((await adapter.apply(operation)).status == .failed)
      #expect(await backlight.currentBrightness() == 0.4)
    }
  }

  @Test("device quantization tolerance governs apply, rollback, and fresh-plan no-ops")
  func quantizedBrightnessRoundTrips() async throws {
    for (logicalRange, previousLevel) in [(16, 6), (100, 37)] {
      let previous = Double(previousLevel) / Double(logicalRange)
      let tolerance = min(0.5, 0.5 / Double(logicalRange) + Double.ulpOfOne * 8)
      let backlight = MockKeyboardBacklightAPI(
        result: .available(
          .init(value: previous, quantizationTolerance: tolerance)
        ),
        behavior: .quantize(logicalRange: logicalRange)
      )
      let adapter = InputPreferencesAdapter(
        api: MockInputPreferencesAPI(),
        keyboardBacklightAPI: backlight
      )
      let desired = InputProfileSettings(keyboardBrightness: .init(value: 0.834))
      let snapshot = try await adapter.snapshot()
      let operation = try #require(
        try await adapter.plan(.input(desired), from: snapshot, mode: .normal)
          .operations.first
      )

      #expect(
        snapshot.keyboardControlCatalog?.last?.quantizationTolerance == tolerance
      )
      #expect(await adapter.apply(operation).status == .succeeded)

      let quantizedDesired = (0.834 * Double(logicalRange)).rounded() / Double(logicalRange)
      #expect(await backlight.currentBrightness() == quantizedDesired)

      let freshSnapshot = try await adapter.snapshot()
      let freshPlan = try await adapter.plan(
        .input(desired),
        from: freshSnapshot,
        mode: .normal
      )
      #expect(freshPlan.operations.isEmpty)

      #expect(await adapter.rollback(operation).status == .rolledBack)
      #expect(await backlight.currentBrightness() == previous)
    }
  }

  @Test("older keyboard catalog entries decode without quantization metadata")
  func keyboardCatalogBackwardCompatibility() throws {
    let data = Data(
      #"{"kind":"keyboardBrightness","currentValue":0.5,"canApply":true}"#.utf8
    )

    let decoded = try JSONDecoder().decode(KeyboardControlCatalogEntry.self, from: data)

    #expect(decoded.quantizationTolerance == nil)
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

private actor MockKeyboardBacklightAPI: KeyboardBacklightAPI {
  enum WriteBehavior: Sendable {
    case update
    case ignore
    case invalidReadBack
    case fail
    case quantize(logicalRange: Int)
  }

  private var result: KeyboardBacklightReadResult
  private let behavior: WriteBehavior
  private var setCallCount = 0

  init(
    result: KeyboardBacklightReadResult,
    behavior: WriteBehavior = .update
  ) {
    self.result = result
    self.behavior = behavior
  }

  func readBrightness() -> KeyboardBacklightReadResult {
    result
  }

  func setBrightness(_ brightness: Double) throws -> KeyboardBacklightMeasurement {
    setCallCount += 1
    switch behavior {
    case .update:
      let tolerance = currentMeasurement()?.quantizationTolerance ?? 0
      let measurement = KeyboardBacklightMeasurement(
        value: brightness,
        quantizationTolerance: tolerance
      )
      result = .available(measurement)
      return measurement
    case .ignore:
      guard let current = currentMeasurement() else {
        throw KeyboardBacklightAPIError.unsupported
      }
      guard abs(current.value - brightness) <= current.quantizationTolerance else {
        throw KeyboardBacklightAPIError.verificationFailed(
          expected: brightness,
          actual: current.value
        )
      }
      return current
    case .invalidReadBack:
      return .init(value: .nan, quantizationTolerance: 0)
    case .fail:
      throw KeyboardBacklightAPIError.temporarilyUnavailable
    case .quantize(let logicalRange):
      guard logicalRange > 0 else { throw KeyboardBacklightAPIError.unsupported }
      let tolerance = min(0.5, 0.5 / Double(logicalRange) + Double.ulpOfOne * 8)
      let actual = (brightness * Double(logicalRange)).rounded() / Double(logicalRange)
      let measurement = KeyboardBacklightMeasurement(
        value: actual,
        quantizationTolerance: tolerance
      )
      result = .available(measurement)
      return measurement
    }
  }

  func currentBrightness() -> Double? {
    currentMeasurement()?.value
  }

  func recordedSetCallCount() -> Int {
    setCallCount
  }

  private func currentMeasurement() -> KeyboardBacklightMeasurement? {
    guard case .available(let measurement) = result else { return nil }
    return measurement
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
