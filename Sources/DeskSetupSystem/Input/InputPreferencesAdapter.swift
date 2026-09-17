import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

private struct InputPreferenceWrite: Codable, Sendable {
  let key: InputPreferenceKey
  let value: InputPreferenceValue
}

private struct KeyboardBrightnessWrite: Codable, Sendable {
  let value: Double
}

public struct InputPreferencesAdapter: SystemSettingsAdapter {
  public static let keyboardBrightnessKey = "KeyboardBrightness"

  public let group = SettingGroup.input

  private let api: any InputPreferencesAPI
  private let keyboardBacklightAPI: any KeyboardBacklightAPI
  private let now: @Sendable () -> Date
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    api: any InputPreferencesAPI = CFPreferencesInputPreferencesAPI(),
    keyboardBacklightAPI: any KeyboardBacklightAPI = CoreHIDKeyboardBacklightAPI(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.api = api
    self.keyboardBacklightAPI = keyboardBacklightAPI
    self.now = now
  }

  public func capability() async -> AdapterCapability {
    AdapterCapability(
      group: group,
      state: .experimental,
      reason:
        "Key-repeat preferences use undocumented global keys. Keyboard brightness uses public CoreHID only when permission and a compatible writable element are already available."
    )
  }

  public func snapshot() async throws -> AdapterSnapshot {
    let repeatInterval = validSnapshotNumber(
      api.value(for: .keyRepeatInterval)?.numberValue,
      range: 1...120
    )
    let initialDelay = validSnapshotNumber(
      api.value(for: .initialKeyRepeatDelay)?.numberValue,
      range: 1...300
    )
    let backlight = normalizedBacklightResult(await keyboardBacklightAPI.readBrightness())
    let brightnessMeasurement = backlight.availableMeasurement
    let brightness = brightnessMeasurement?.value

    let settings = InputProfileSettings(
      keyRepeatInterval: .init(isIncluded: repeatInterval != nil, value: repeatInterval),
      initialKeyRepeatDelay: .init(isIncluded: initialDelay != nil, value: initialDelay),
      keyboardBrightness: .init(isIncluded: brightness != nil, value: brightness)
    )

    return AdapterSnapshot(
      group: group,
      capturedAt: now(),
      payload: .input(settings),
      items: [
        snapshotItem(
          .keyRepeatInterval,
          valuePresent: repeatInterval != nil,
          label: "Key repeat speed"
        ),
        snapshotItem(
          .initialKeyRepeatDelay,
          valuePresent: initialDelay != nil,
          label: "Repeat delay"
        ),
        keyboardBrightnessSnapshotItem(backlight),
      ],
      keyboardControlCatalog: [
        .init(
          kind: .keyRepeatInterval,
          currentValue: repeatInterval,
          canApply: repeatInterval != nil
        ),
        .init(
          kind: .initialKeyRepeatDelay,
          currentValue: initialDelay,
          canApply: initialDelay != nil
        ),
        .init(
          kind: .keyboardBrightness,
          currentValue: brightness,
          canApply: brightness != nil,
          quantizationTolerance: brightnessMeasurement?.quantizationTolerance
        ),
      ]
    )
  }

  public func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue] {
    guard case .input(let settings) = desired else {
      return [
        ValidationIssue(
          group: group,
          key: "payload",
          severity: .error,
          isFatal: true,
          message: "The input adapter received a different settings payload."
        )
      ]
    }

    var issues: [ValidationIssue] = []
    validateNumber(
      settings.keyRepeatInterval,
      key: InputPreferenceKey.keyRepeatInterval.rawValue,
      range: 1...120,
      issues: &issues
    )
    validateNumber(
      settings.initialKeyRepeatDelay,
      key: InputPreferenceKey.initialKeyRepeatDelay.rawValue,
      range: 1...300,
      issues: &issues
    )
    validateNumber(
      settings.keyboardBrightness,
      key: Self.keyboardBrightnessKey,
      range: 0...1,
      issues: &issues
    )
    return issues
  }

  public func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan {
    guard case .input(let desiredSettings) = desired else {
      return AdapterPlan(
        group: group,
        issues: await validate(desired, against: snapshot)
      )
    }
    guard case .input(let currentSettings)? = snapshot.payload else {
      return AdapterPlan(
        group: group,
        issues: [
          ValidationIssue(
            group: group,
            key: "snapshot",
            severity: .error,
            isFatal: true,
            message: "Current input preferences could not be read."
          )
        ]
      )
    }

    var operations: [PlannedOperation] = []
    var omissions: [PlanOmission] = []

    try appendPreferenceOperation(
      desired: desiredSettings.keyRepeatInterval,
      current: currentSettings.keyRepeatInterval.value,
      kind: .keyRepeatInterval,
      key: .keyRepeatInterval,
      label: "key repeat speed",
      range: 1...120,
      snapshot: snapshot,
      operations: &operations,
      omissions: &omissions
    )
    try appendPreferenceOperation(
      desired: desiredSettings.initialKeyRepeatDelay,
      current: currentSettings.initialKeyRepeatDelay.value,
      kind: .initialKeyRepeatDelay,
      key: .initialKeyRepeatDelay,
      label: "repeat delay",
      range: 1...300,
      snapshot: snapshot,
      operations: &operations,
      omissions: &omissions
    )
    try appendBrightnessOperation(
      desired: desiredSettings.keyboardBrightness,
      current: currentSettings.keyboardBrightness.value,
      snapshot: snapshot,
      operations: &operations,
      omissions: &omissions
    )

    return AdapterPlan(
      group: group,
      operations: operations,
      omissions: omissions,
      issues: await validate(desired, against: snapshot)
    )
  }

  public func apply(_ operation: PlannedOperation) async -> OperationResult {
    if operation.key == Self.keyboardBrightnessKey {
      return await applyKeyboardBrightness(operation)
    }

    do {
      let write = try decoder.decode(InputPreferenceWrite.self, from: operation.payload)
      guard isValidPreferenceWrite(write, for: operation) else {
        throw CocoaError(.coderReadCorrupt)
      }
      try api.setValue(write.value, for: write.key)
      guard api.value(for: write.key) == write.value else {
        return OperationResult(
          operationID: operation.id,
          status: .failed,
          message:
            "macOS accepted the experimental input preference write, but read-back did not confirm the requested value."
        )
      }
      return OperationResult(
        operationID: operation.id,
        status: .succeeded,
        message: "Updated the experimental \(write.key.rawValue) preference."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "The input preference could not be updated."
      )
    }
  }

  public func rollback(_ operation: PlannedOperation) async -> OperationResult {
    if operation.key == Self.keyboardBrightnessKey {
      return await rollbackKeyboardBrightness(operation)
    }

    do {
      guard let rollbackPayload = operation.rollbackPayload else {
        throw CocoaError(.coderReadCorrupt)
      }
      let write = try decoder.decode(InputPreferenceWrite.self, from: rollbackPayload)
      guard isValidPreferenceWrite(write, for: operation) else {
        throw CocoaError(.coderReadCorrupt)
      }
      try api.setValue(write.value, for: write.key)
      guard api.value(for: write.key) == write.value else {
        return OperationResult(
          operationID: operation.id,
          status: .rollbackFailed,
          message: "The previous input preference could not be confirmed after rollback."
        )
      }
      return OperationResult(
        operationID: operation.id,
        status: .rolledBack,
        message: "Restored the previous experimental input preference."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .rollbackFailed,
        message: "The previous input preference could not be restored."
      )
    }
  }

  public func diagnostics() async -> [DiagnosticEntry] {
    [
      DiagnosticEntry(
        severity: .info,
        component: "adapter.input",
        code: "input.experimental-preferences",
        message: "Key-repeat preferences are isolated behind an experimental capability."
      ),
      DiagnosticEntry(
        severity: .info,
        component: "adapter.input.keyboard-backlight",
        code: "keyboard-backlight.public-corehid",
        message:
          "Keyboard brightness requires macOS 15 or later, prior Input Monitoring approval, and a compatible public CoreHID element."
      ),
    ]
  }

  private func snapshotItem(
    _ key: InputPreferenceKey,
    valuePresent: Bool,
    label: String
  ) -> SnapshotItem {
    SnapshotItem(
      key: key.rawValue,
      label: label,
      state: valuePresent ? .storable : .unreadable,
      detail: valuePresent ? "Experimental global preference" : "No compatible value was found"
    )
  }

  private func keyboardBrightnessSnapshotItem(
    _ result: KeyboardBacklightReadResult
  ) -> SnapshotItem {
    let state: SnapshotItemState
    let detail: String
    switch result {
    case .available:
      state = .storable
      detail = "Public CoreHID keyboard-backlight control"
    case .permissionRequired:
      state = .permissionRequired
      detail = "Input Monitoring access must be granted in System Settings"
    case .temporarilyUnavailable:
      state = .unreadable
      detail = "The compatible keyboard-backlight control could not be read"
    case .unsupported:
      state = .unsupported
      detail = "No compatible public CoreHID keyboard-backlight control was found"
    }
    return SnapshotItem(
      key: Self.keyboardBrightnessKey,
      label: "Keyboard brightness",
      state: state,
      detail: detail
    )
  }

  private func validSnapshotNumber(
    _ value: Double?,
    range: ClosedRange<Double>
  ) -> Double? {
    guard let value, value.isFinite, range.contains(value) else { return nil }
    return value
  }

  private func normalizedBacklightResult(
    _ result: KeyboardBacklightReadResult
  ) -> KeyboardBacklightReadResult {
    guard case .available(let measurement) = result else { return result }
    guard validBacklightMeasurement(measurement) else { return .temporarilyUnavailable }
    return result
  }

  private func validateNumber(
    _ option: SettingOption<Double?>,
    key: String,
    range: ClosedRange<Double>,
    issues: inout [ValidationIssue]
  ) {
    guard option.isIncluded else { return }
    guard let value = option.value, value.isFinite, range.contains(value) else {
      issues.append(
        ValidationIssue(
          group: group,
          key: key,
          severity: .error,
          isFatal: true,
          message: "The saved \(key) value is outside the safe range."
        )
      )
      return
    }
  }

  private func appendPreferenceOperation(
    desired: SettingOption<Double?>,
    current: Double?,
    kind: KeyboardControlKind,
    key: InputPreferenceKey,
    label: String,
    range: ClosedRange<Double>,
    snapshot: AdapterSnapshot,
    operations: inout [PlannedOperation],
    omissions: inout [PlanOmission]
  ) throws {
    guard desired.isIncluded else { return }
    guard let value = desired.value else {
      omissions.append(missingValueOmission(key: key.rawValue))
      return
    }
    guard value.isFinite, range.contains(value) else { return }
    guard controlIsAvailable(kind, in: snapshot), let current else {
      omissions.append(unavailableOmission(key: key.rawValue, snapshot: snapshot))
      return
    }
    if abs(current - value) < 0.000_001 { return }
    operations.append(
      try preferenceOperation(
        key: key,
        label: label,
        desired: .number(value),
        previous: .number(current)
      )
    )
  }

  private func appendBrightnessOperation(
    desired: SettingOption<Double?>,
    current: Double?,
    snapshot: AdapterSnapshot,
    operations: inout [PlannedOperation],
    omissions: inout [PlanOmission]
  ) throws {
    guard desired.isIncluded else { return }
    guard let value = desired.value else {
      omissions.append(missingValueOmission(key: Self.keyboardBrightnessKey))
      return
    }
    guard value.isFinite, (0...1).contains(value) else { return }
    guard
      let control = availableControl(.keyboardBrightness, in: snapshot),
      let current
    else {
      omissions.append(
        unavailableOmission(key: Self.keyboardBrightnessKey, snapshot: snapshot)
      )
      return
    }
    if abs(current - value) <= (control.quantizationTolerance ?? 0) { return }
    operations.append(
      PlannedOperation(
        group: group,
        key: Self.keyboardBrightnessKey,
        summary: "Change keyboard brightness",
        risk: .moderate,
        isFatalOnFailure: false,
        preview: OperationPreview(
          previousValue: percentagePreview(current),
          desiredValue: percentagePreview(value)
        ),
        payload: try encoder.encode(KeyboardBrightnessWrite(value: value)),
        rollbackPayload: try encoder.encode(KeyboardBrightnessWrite(value: current))
      )
    )
  }

  private func preferenceOperation(
    key: InputPreferenceKey,
    label: String,
    desired: InputPreferenceValue,
    previous: InputPreferenceValue
  ) throws -> PlannedOperation {
    PlannedOperation(
      group: group,
      key: key.rawValue,
      summary: "Change \(label)",
      risk: .moderate,
      isFatalOnFailure: false,
      preview: OperationPreview(
        previousValue: previewValue(previous),
        desiredValue: previewValue(desired)
      ),
      payload: try encoder.encode(InputPreferenceWrite(key: key, value: desired)),
      rollbackPayload: try encoder.encode(InputPreferenceWrite(key: key, value: previous))
    )
  }

  private func applyKeyboardBrightness(_ operation: PlannedOperation) async -> OperationResult {
    do {
      let write = try decoder.decode(KeyboardBrightnessWrite.self, from: operation.payload)
      guard operation.group == group,
        write.value.isFinite,
        (0...1).contains(write.value)
      else {
        throw CocoaError(.coderReadCorrupt)
      }
      let measurement = try await keyboardBacklightAPI.setBrightness(write.value)
      guard validBacklightMeasurement(measurement),
        abs(measurement.value - write.value) <= measurement.quantizationTolerance
      else {
        return OperationResult(
          operationID: operation.id,
          status: .failed,
          message: "Keyboard brightness read-back did not confirm the requested value."
        )
      }
      return OperationResult(
        operationID: operation.id,
        status: .succeeded,
        message: "Updated keyboard brightness and confirmed it with public CoreHID."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "Keyboard brightness could not be updated."
      )
    }
  }

  private func rollbackKeyboardBrightness(_ operation: PlannedOperation) async -> OperationResult {
    do {
      guard let payload = operation.rollbackPayload else {
        throw CocoaError(.coderReadCorrupt)
      }
      let write = try decoder.decode(KeyboardBrightnessWrite.self, from: payload)
      guard operation.group == group,
        write.value.isFinite,
        (0...1).contains(write.value)
      else {
        throw CocoaError(.coderReadCorrupt)
      }
      let measurement = try await keyboardBacklightAPI.setBrightness(write.value)
      guard validBacklightMeasurement(measurement),
        abs(measurement.value - write.value) <= measurement.quantizationTolerance
      else {
        return OperationResult(
          operationID: operation.id,
          status: .rollbackFailed,
          message: "The previous keyboard brightness could not be confirmed after rollback."
        )
      }
      return OperationResult(
        operationID: operation.id,
        status: .rolledBack,
        message: "Restored the previous keyboard brightness."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .rollbackFailed,
        message: "The previous keyboard brightness could not be restored."
      )
    }
  }

  private func controlIsAvailable(
    _ kind: KeyboardControlKind,
    in snapshot: AdapterSnapshot
  ) -> Bool {
    availableControl(kind, in: snapshot) != nil
  }

  private func availableControl(
    _ kind: KeyboardControlKind,
    in snapshot: AdapterSnapshot
  ) -> KeyboardControlCatalogEntry? {
    (snapshot.keyboardControlCatalog ?? []).first {
      guard $0.kind == kind, $0.canApply, let value = $0.currentValue, value.isFinite else {
        return false
      }
      guard let tolerance = $0.quantizationTolerance else { return true }
      return tolerance.isFinite && (0...0.5).contains(tolerance)
    }
  }

  private func validBacklightMeasurement(_ measurement: KeyboardBacklightMeasurement) -> Bool {
    measurement.value.isFinite
      && (0...1).contains(measurement.value)
      && measurement.quantizationTolerance.isFinite
      && (0...0.5).contains(measurement.quantizationTolerance)
  }

  private func isValidPreferenceWrite(
    _ write: InputPreferenceWrite,
    for operation: PlannedOperation
  ) -> Bool {
    guard operation.group == group, operation.key == write.key.rawValue else { return false }
    guard case .number(let value) = write.value, value.isFinite else { return false }
    switch write.key {
    case .keyRepeatInterval:
      return (1...120).contains(value)
    case .initialKeyRepeatDelay:
      return (1...300).contains(value)
    case .pointerSpeed, .naturalScrolling, .standardFunctionKeys:
      return false
    }
  }

  private func unavailableOmission(
    key: String,
    snapshot: AdapterSnapshot
  ) -> PlanOmission {
    let state = snapshot.items.first(where: { $0.key == key })?.state
    let reason: String
    switch state {
    case .permissionRequired:
      reason = "The keyboard control requires permission before it can be changed."
    case .unsupported:
      reason = "This Mac does not expose a compatible keyboard control."
    default:
      reason = "The keyboard control has no readable rollback value."
    }
    return PlanOmission(group: group, key: key, status: .skipped, reason: reason)
  }

  private func previewValue(_ value: InputPreferenceValue) -> String {
    switch value {
    case .boolean(let enabled):
      return enabled ? "On" : "Off"
    case .number(let number):
      return String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), number)
    }
  }

  private func percentagePreview(_ value: Double) -> String {
    String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), value * 100)
  }

  private func missingValueOmission(key: String) -> PlanOmission {
    PlanOmission(
      group: group,
      key: key,
      status: .skipped,
      reason: "The saved keyboard setting has no value."
    )
  }
}

extension KeyboardBacklightReadResult {
  fileprivate var availableMeasurement: KeyboardBacklightMeasurement? {
    guard case .available(let measurement) = self else { return nil }
    return measurement
  }
}
