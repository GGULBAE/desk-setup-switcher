import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

private struct InputPreferenceWrite: Codable, Sendable {
  let key: InputPreferenceKey
  let value: InputPreferenceValue?
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
      reason:
        "CFPreferences is public, but Apple does not document the stability of these global input preference keys."
    )
  }

  public func snapshot() async throws -> AdapterSnapshot {
    let pointer = api.value(for: .pointerSpeed)?.numberValue
    let natural = api.value(for: .naturalScrolling)?.boolValue
    let repeatInterval = api.value(for: .keyRepeatInterval)?.numberValue
    let initialDelay = api.value(for: .initialKeyRepeatDelay)?.numberValue
    let functionKeys = api.value(for: .standardFunctionKeys)?.boolValue

    let settings = InputProfileSettings(
      pointerSpeed: .init(isIncluded: pointer != nil, value: pointer),
      naturalScrolling: .init(isIncluded: natural != nil, value: natural),
      keyRepeatInterval: .init(isIncluded: repeatInterval != nil, value: repeatInterval),
      initialKeyRepeatDelay: .init(isIncluded: initialDelay != nil, value: initialDelay),
      useStandardFunctionKeys: .init(isIncluded: functionKeys != nil, value: functionKeys)
    )

    return AdapterSnapshot(
      group: group,
      capturedAt: now(),
      payload: .input(settings),
      items: [
        snapshotItem(.pointerSpeed, valuePresent: pointer != nil, label: "Pointer speed"),
        snapshotItem(.naturalScrolling, valuePresent: natural != nil, label: "Natural scrolling"),
        snapshotItem(.keyRepeatInterval, valuePresent: repeatInterval != nil, label: "Key repeat"),
        snapshotItem(
          .initialKeyRepeatDelay,
          valuePresent: initialDelay != nil,
          label: "Initial key repeat delay"
        ),
        snapshotItem(
          .standardFunctionKeys,
          valuePresent: functionKeys != nil,
          label: "Standard function keys"
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
      settings.pointerSpeed,
      key: .pointerSpeed,
      range: -1...10,
      issues: &issues
    )
    validateNumber(
      settings.keyRepeatInterval,
      key: .keyRepeatInterval,
      range: 1...120,
      issues: &issues
    )
    validateNumber(
      settings.initialKeyRepeatDelay,
      key: .initialKeyRepeatDelay,
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

    try appendNumberOperation(
      desired: desiredSettings.pointerSpeed,
      current: currentSettings.pointerSpeed.value,
      key: .pointerSpeed,
      label: "pointer speed",
      operations: &operations,
      omissions: &omissions
    )
    try appendBooleanOperation(
      desired: desiredSettings.naturalScrolling,
      current: currentSettings.naturalScrolling.value,
      key: .naturalScrolling,
      label: "natural scrolling",
      operations: &operations,
      omissions: &omissions
    )
    try appendNumberOperation(
      desired: desiredSettings.keyRepeatInterval,
      current: currentSettings.keyRepeatInterval.value,
      key: .keyRepeatInterval,
      label: "key repeat",
      operations: &operations,
      omissions: &omissions
    )
    try appendNumberOperation(
      desired: desiredSettings.initialKeyRepeatDelay,
      current: currentSettings.initialKeyRepeatDelay.value,
      key: .initialKeyRepeatDelay,
      label: "initial key repeat delay",
      operations: &operations,
      omissions: &omissions
    )
    try appendBooleanOperation(
      desired: desiredSettings.useStandardFunctionKeys,
      current: currentSettings.useStandardFunctionKeys.value,
      key: .standardFunctionKeys,
      label: "function-key behavior",
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
    do {
      guard let rollbackPayload = operation.rollbackPayload else {
        throw CocoaError(.coderReadCorrupt)
      }
      let write = try decoder.decode(InputPreferenceWrite.self, from: rollbackPayload)
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
        message: "Global input preferences are isolated behind an experimental capability."
      )
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

  private func validateNumber(
    _ option: SettingOption<Double?>,
    key: InputPreferenceKey,
    range: ClosedRange<Double>,
    issues: inout [ValidationIssue]
  ) {
    guard option.isIncluded else { return }
    guard let value = option.value, value.isFinite, range.contains(value) else {
      issues.append(
        ValidationIssue(
          group: group,
          key: key.rawValue,
          severity: .error,
          isFatal: true,
          message: "The saved \(key.rawValue) value is outside the safe range."
        )
      )
      return
    }
  }

  private func appendNumberOperation(
    desired: SettingOption<Double?>,
    current: Double?,
    key: InputPreferenceKey,
    label: String,
    operations: inout [PlannedOperation],
    omissions: inout [PlanOmission]
  ) throws {
    guard desired.isIncluded else { return }
    guard let value = desired.value else {
      omissions.append(missingValueOmission(key: key))
      return
    }
    if let current, abs(current - value) < 0.000_001 { return }
    operations.append(
      try operation(
        key: key,
        label: label,
        desired: .number(value),
        previous: current.map(InputPreferenceValue.number)
      )
    )
  }

  private func appendBooleanOperation(
    desired: SettingOption<Bool?>,
    current: Bool?,
    key: InputPreferenceKey,
    label: String,
    operations: inout [PlannedOperation],
    omissions: inout [PlanOmission]
  ) throws {
    guard desired.isIncluded else { return }
    guard let value = desired.value else {
      omissions.append(missingValueOmission(key: key))
      return
    }
    if current == value { return }
    operations.append(
      try operation(
        key: key,
        label: label,
        desired: .boolean(value),
        previous: current.map(InputPreferenceValue.boolean)
      )
    )
  }

  private func operation(
    key: InputPreferenceKey,
    label: String,
    desired: InputPreferenceValue,
    previous: InputPreferenceValue?
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

  private func previewValue(_ value: InputPreferenceValue?) -> String {
    switch value {
    case .boolean(let enabled):
      return enabled ? "On" : "Off"
    case .number(let number):
      return String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), number)
    case nil:
      return "Unset"
    }
  }

  private func missingValueOmission(key: InputPreferenceKey) -> PlanOmission {
    PlanOmission(
      group: group,
      key: key.rawValue,
      status: .skipped,
      reason: "The saved input preference has no value."
    )
  }
}
