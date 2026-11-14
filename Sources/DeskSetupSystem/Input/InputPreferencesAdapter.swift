import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

private struct InputPreferenceWrite: Codable, Sendable {
  let key: InputPreferenceKey
  let persistedValue: Double?
  let runtimeNanoseconds: Int64
}

public struct InputPreferencesAdapter: SystemSettingsAdapter {
  public let group = SettingGroup.input

  private let api: any InputPreferencesAPI
  private let now: @Sendable () -> Date
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    api: any InputPreferencesAPI = CFPreferencesInputPreferencesAPI(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.api = api
    self.now = now
  }

  public func capability() async -> AdapterCapability {
    AdapterCapability(
      group: group,
      state: .experimental,
      reason: "Key-repeat preferences use undocumented global keys."
    )
  }

  public func snapshot() async throws -> AdapterSnapshot {
    let repeatRuntime = api.runtimeNanoseconds(for: .keyRepeatInterval)
    let delayRuntime = api.runtimeNanoseconds(for: .initialKeyRepeatDelay)
    let repeatInterval = validSnapshotNumber(
      repeatRuntime.map(KeyboardRepeatTiming.ticks),
      range: 1...120
    )
    let initialDelay = validSnapshotNumber(
      delayRuntime.map(KeyboardRepeatTiming.ticks),
      range: 1...300
    )
    let repeatRollback = rollbackState(
      for: .keyRepeatInterval, runtime: repeatRuntime, range: 1...120)
    let delayRollback = rollbackState(
      for: .initialKeyRepeatDelay, runtime: delayRuntime, range: 1...300)
    let settings = InputProfileSettings(
      keyRepeatInterval: .init(isIncluded: repeatInterval != nil, value: repeatInterval),
      initialKeyRepeatDelay: .init(isIncluded: initialDelay != nil, value: initialDelay)
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
      ],
      keyboardControlCatalog: [
        .init(
          kind: .keyRepeatInterval,
          currentValue: repeatInterval,
          canApply: repeatRollback != nil,
          preferenceRollback: repeatRollback
        ),
        .init(
          kind: .initialKeyRepeatDelay,
          currentValue: initialDelay,
          canApply: delayRollback != nil,
          preferenceRollback: delayRollback
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
    return AdapterPlan(
      group: group,
      operations: operations,
      omissions: omissions,
      issues: await validate(desired, against: snapshot)
    )
  }

  public func apply(_ operation: PlannedOperation) async -> OperationResult {
    do {
      let write = try decoder.decode(InputPreferenceWrite.self, from: operation.payload)
      guard isValidPreferenceWrite(write, for: operation) else {
        throw CocoaError(.coderReadCorrupt)
      }
      guard let persistedValue = write.persistedValue,
        write.runtimeNanoseconds == KeyboardRepeatTiming.nanoseconds(for: persistedValue)
      else { throw CocoaError(.coderReadCorrupt) }
      try api.setValue(write.persistedValue.map(InputPreferenceValue.number), for: write.key)
      try api.setRuntimeNanoseconds(write.runtimeNanoseconds, for: write.key)
      guard confirms(write) else {
        return OperationResult(
          operationID: operation.id,
          status: .failed,
          message: "The saved and active keyboard repeat values could not both be confirmed."
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
    do {
      guard let rollbackPayload = operation.rollbackPayload else {
        throw CocoaError(.coderReadCorrupt)
      }
      let write = try decoder.decode(InputPreferenceWrite.self, from: rollbackPayload)
      guard isValidPreferenceWrite(write, for: operation) else {
        throw CocoaError(.coderReadCorrupt)
      }
      // Attempt both restores even when one layer fails. The engine reports
      // rollbackFailed if either layer cannot be positively confirmed.
      var restored = true
      do {
        try api.setValue(write.persistedValue.map(InputPreferenceValue.number), for: write.key)
      } catch { restored = false }
      do {
        try api.setRuntimeNanoseconds(write.runtimeNanoseconds, for: write.key)
      } catch { restored = false }
      guard restored && confirms(write) else {
        return OperationResult(
          operationID: operation.id,
          status: .rollbackFailed,
          message:
            "The previous saved and active keyboard repeat values could not both be restored."
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
    var entries = [
      DiagnosticEntry(
        severity: .info,
        component: "adapter.input",
        code: "input.experimental-preferences",
        message: "Key-repeat preferences are isolated behind an experimental capability."
      )
    ]
    for key in [InputPreferenceKey.keyRepeatInterval, .initialKeyRepeatDelay] {
      guard let saved = api.value(for: key)?.numberValue,
        saved.isFinite, (1...300).contains(saved),
        let active = api.runtimeNanoseconds(for: key),
        active != KeyboardRepeatTiming.nanoseconds(for: saved)
      else { continue }
      entries.append(
        DiagnosticEntry(
          severity: .warning,
          component: "adapter.input",
          code: "input.runtime-mismatch",
          message: "The saved keyboard repeat preference differs from the active setting."
        ))
    }
    return entries
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

  private func validSnapshotNumber(
    _ value: Double?,
    range: ClosedRange<Double>
  ) -> Double? {
    guard let value, value.isFinite, range.contains(value) else { return nil }
    return value
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
    guard let control = availableControl(kind, in: snapshot),
      let previous = control.preferenceRollback,
      let current
    else {
      omissions.append(unavailableOmission(key: key.rawValue, snapshot: snapshot))
      return
    }
    if previous.persistedValue == value,
      previous.runtimeNanoseconds == KeyboardRepeatTiming.nanoseconds(for: value)
    {
      return
    }
    operations.append(
      try preferenceOperation(
        key: key,
        label: label,
        desired: value,
        current: current,
        previous: previous
      )
    )
  }

  private func preferenceOperation(
    key: InputPreferenceKey,
    label: String,
    desired: Double,
    current: Double,
    previous: KeyboardPreferenceRollback
  ) throws -> PlannedOperation {
    PlannedOperation(
      group: group,
      key: key.rawValue,
      summary: "Change \(label)",
      risk: .moderate,
      isFatalOnFailure: false,
      preview: OperationPreview(
        previousValue: previewValue(.number(current)),
        desiredValue: previewValue(.number(desired))
      ),
      payload: try encoder.encode(
        InputPreferenceWrite(
          key: key, persistedValue: desired,
          runtimeNanoseconds: KeyboardRepeatTiming.nanoseconds(for: desired)
        )),
      rollbackPayload: try encoder.encode(
        InputPreferenceWrite(
          key: key, persistedValue: previous.persistedValue,
          runtimeNanoseconds: previous.runtimeNanoseconds
        ))
    )
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

  private func isValidPreferenceWrite(
    _ write: InputPreferenceWrite,
    for operation: PlannedOperation
  ) -> Bool {
    guard operation.group == group, operation.key == write.key.rawValue else { return false }
    let range: ClosedRange<Double>
    switch write.key {
    case .keyRepeatInterval: range = 1...120
    case .initialKeyRepeatDelay: range = 1...300
    case .pointerSpeed, .naturalScrolling, .standardFunctionKeys: return false
    }
    guard range.contains(KeyboardRepeatTiming.ticks(for: write.runtimeNanoseconds)) else {
      return false
    }
    guard let value = write.persistedValue else { return true }
    return value.isFinite && range.contains(value)
  }

  private func rollbackState(
    for key: InputPreferenceKey,
    runtime: Int64?,
    range: ClosedRange<Double>
  ) -> KeyboardPreferenceRollback? {
    guard let runtime,
      range.contains(KeyboardRepeatTiming.ticks(for: runtime))
    else { return nil }
    let persisted: Double?
    switch api.value(for: key) {
    case nil: persisted = nil
    case .number(let value) where value.isFinite && range.contains(value): persisted = value
    default: return nil
    }
    return KeyboardPreferenceRollback(persistedValue: persisted, runtimeNanoseconds: runtime)
  }

  private func confirms(_ write: InputPreferenceWrite) -> Bool {
    api.value(for: write.key) == write.persistedValue.map(InputPreferenceValue.number)
      && api.runtimeNanoseconds(for: write.key) == write.runtimeNanoseconds
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

  private func missingValueOmission(key: String) -> PlanOmission {
    PlanOmission(
      group: group,
      key: key,
      status: .skipped,
      reason: "The saved keyboard setting has no value."
    )
  }
}
