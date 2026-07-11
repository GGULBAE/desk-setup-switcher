import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public struct CoreAudioAdapter: SystemSettingsAdapter {
  public let group: SettingGroup = .audio

  private let api: any AudioSystemAPI
  private let now: @Sendable () -> Date

  public init(
    api: any AudioSystemAPI = CoreAudioSystemAPI(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.api = api
    self.now = now
  }

  public func capability() async -> AdapterCapability {
    do {
      let devices = try api.devices()
      return AdapterCapability(
        group: group,
        state: .supported,
        reason: "Core Audio reported \(devices.count) device(s)."
      )
    } catch {
      return AdapterCapability(
        group: group,
        state: .temporarilyUnavailable,
        reason: "Core Audio device discovery is currently unavailable."
      )
    }
  }

  public func snapshot() async throws -> AdapterSnapshot {
    let devices = try api.devices()
    var items = devices.map(deviceItem)

    let defaultInputUID = readDefaultDevice(
      role: .input,
      devices: devices,
      items: &items
    )
    let defaultOutputUID = readDefaultDevice(
      role: .output,
      devices: devices,
      items: &items
    )
    let systemOutputUID = readDefaultDevice(
      role: .systemOutput,
      devices: devices,
      items: &items
    )

    var outputVolume = SettingOption<Double?>(isIncluded: false, value: nil)
    var outputMuted = SettingOption<Bool?>(isIncluded: false, value: nil)
    if let defaultOutputUID {
      outputVolume = readVolume(deviceUID: defaultOutputUID, items: &items)
      outputMuted = readMute(deviceUID: defaultOutputUID, items: &items)
    } else {
      items.append(
        SnapshotItem(
          key: "outputVolume",
          label: "Output volume",
          state: .unreadable,
          detail: "No default output device is available."
        )
      )
      items.append(
        SnapshotItem(
          key: "outputMute",
          label: "Output mute",
          state: .unreadable,
          detail: "No default output device is available."
        )
      )
    }

    let settings = AudioProfileSettings(
      defaultInputUID: SettingOption(
        isIncluded: defaultInputUID != nil,
        value: defaultInputUID
      ),
      defaultOutputUID: SettingOption(
        isIncluded: defaultOutputUID != nil,
        value: defaultOutputUID
      ),
      systemOutputUID: SettingOption(
        isIncluded: systemOutputUID != nil,
        value: systemOutputUID
      ),
      outputVolume: outputVolume,
      outputMuted: outputMuted
    )
    return AdapterSnapshot(
      group: group,
      capturedAt: now(),
      payload: .audio(settings),
      items: items
    )
  }

  public func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue] {
    guard case .audio(let settings) = desired else {
      return [fatalIssue(key: "payload", message: "The audio adapter received another group.")]
    }
    guard snapshot.group == .audio,
      case .audio? = snapshot.payload
    else {
      return [fatalIssue(key: "snapshot", message: "The audio snapshot is invalid.")]
    }

    let devices: [AudioDeviceDescriptor]
    do {
      devices = try api.devices()
    } catch {
      return [fatalIssue(key: "devices", message: "Connected audio devices could not be read.")]
    }

    var issues: [ValidationIssue] = []
    validateDefaultOption(
      settings.defaultInputUID,
      role: .input,
      devices: devices,
      issues: &issues
    )
    validateDefaultOption(
      settings.defaultOutputUID,
      role: .output,
      devices: devices,
      issues: &issues
    )
    validateDefaultOption(
      settings.systemOutputUID,
      role: .systemOutput,
      devices: devices,
      issues: &issues
    )

    let needsOutputControl = settings.outputVolume.isIncluded || settings.outputMuted.isIncluded
    let outputUID: String?
    if settings.defaultOutputUID.isIncluded {
      outputUID = settings.defaultOutputUID.value
    } else {
      outputUID = try? api.defaultDeviceUID(for: .output)
    }

    if settings.outputVolume.isIncluded {
      if let value = settings.outputVolume.value {
        if !value.isFinite || !(0.0...1.0).contains(value) {
          issues.append(
            fatalIssue(
              key: "outputVolume",
              message: "Output volume must be a scalar between 0 and 1."
            )
          )
        }
      } else {
        issues.append(fatalIssue(key: "outputVolume", message: "No output volume was saved."))
      }
    }

    if settings.outputMuted.isIncluded, settings.outputMuted.value == nil {
      issues.append(fatalIssue(key: "outputMute", message: "No output mute value was saved."))
    }

    if needsOutputControl {
      guard let outputUID,
        let device = devices.first(where: { $0.uid == outputUID }),
        device.supportsOutput
      else {
        if settings.outputVolume.isIncluded {
          issues.append(
            fatalIssue(
              key: "outputVolume",
              message: "The output device for volume is unavailable."
            )
          )
        }
        if settings.outputMuted.isIncluded {
          issues.append(
            fatalIssue(
              key: "outputMute",
              message: "The output device for mute is unavailable."
            )
          )
        }
        return issues
      }

      if settings.outputVolume.isIncluded {
        appendControlIssue(
          try? api.outputVolume(forDeviceUID: outputUID),
          key: "outputVolume",
          label: "software volume",
          issues: &issues
        )
      }
      if settings.outputMuted.isIncluded {
        appendControlIssue(
          try? api.outputMute(forDeviceUID: outputUID),
          key: "outputMute",
          label: "software mute",
          issues: &issues
        )
      }
    }

    return issues
  }

  public func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan {
    guard case .audio(let settings) = desired else {
      return AdapterPlan(
        group: group,
        issues: [fatalIssue(key: "payload", message: "The audio adapter received another group.")]
      )
    }
    guard snapshot.group == .audio else {
      return AdapterPlan(
        group: group,
        issues: [fatalIssue(key: "snapshot", message: "The audio snapshot is invalid.")]
      )
    }

    let devices = try api.devices()
    var operations: [PlannedOperation] = []
    var omissions: [PlanOmission] = []

    try planDefaultDevice(
      settings.defaultInputUID,
      role: .input,
      devices: devices,
      operations: &operations,
      omissions: &omissions
    )
    try planDefaultDevice(
      settings.defaultOutputUID,
      role: .output,
      devices: devices,
      operations: &operations,
      omissions: &omissions
    )
    try planDefaultDevice(
      settings.systemOutputUID,
      role: .systemOutput,
      devices: devices,
      operations: &operations,
      omissions: &omissions
    )

    let outputUID: String?
    if settings.defaultOutputUID.isIncluded {
      outputUID = settings.defaultOutputUID.value
    } else {
      outputUID = try? api.defaultDeviceUID(for: .output)
    }
    planVolume(
      settings.outputVolume,
      deviceUID: outputUID,
      devices: devices,
      operations: &operations,
      omissions: &omissions
    )
    planMute(
      settings.outputMuted,
      deviceUID: outputUID,
      devices: devices,
      operations: &operations,
      omissions: &omissions
    )

    return AdapterPlan(
      group: group,
      operations: operations,
      omissions: omissions
    )
  }

  public func apply(_ operation: PlannedOperation) async -> OperationResult {
    guard operation.group == group else {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "The operation belongs to another settings group."
      )
    }
    do {
      try perform(decode(operation.payload))
      return OperationResult(
        operationID: operation.id,
        status: .succeeded,
        message: "The audio setting was applied."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "Core Audio rejected the requested setting."
      )
    }
  }

  public func rollback(_ operation: PlannedOperation) async -> OperationResult {
    guard operation.group == group, let rollbackPayload = operation.rollbackPayload else {
      return OperationResult(
        operationID: operation.id,
        status: .rollbackFailed,
        message: "No valid audio rollback value was captured."
      )
    }
    do {
      try perform(decode(rollbackPayload))
      return OperationResult(
        operationID: operation.id,
        status: .rolledBack,
        message: "The previous audio setting was restored."
      )
    } catch {
      return OperationResult(
        operationID: operation.id,
        status: .rollbackFailed,
        message: "Core Audio could not restore the previous setting."
      )
    }
  }

  public func diagnostics() async -> [DiagnosticEntry] {
    do {
      let devices = try api.devices()
      return [
        DiagnosticEntry(
          severity: .info,
          component: "adapter.audio",
          code: "audio.devices.available",
          message: "Core Audio reported \(devices.count) device(s); identifiers were omitted."
        )
      ]
    } catch {
      return [
        DiagnosticEntry(
          severity: .error,
          component: "adapter.audio",
          code: "audio.devices.unavailable",
          message: "Core Audio device discovery failed."
        )
      ]
    }
  }

  private func deviceItem(_ device: AudioDeviceDescriptor) -> SnapshotItem {
    var scopes: [String] = []
    if device.supportsInput { scopes.append("Input") }
    if device.supportsOutput { scopes.append("Output") }
    return SnapshotItem(
      key: "device:\(device.uid)",
      label: device.name,
      state: .detected,
      detail:
        "\(scopes.isEmpty ? "No I/O scopes" : scopes.joined(separator: ", ")) • UID \(device.uid)"
    )
  }

  private func readDefaultDevice(
    role: AudioDefaultDeviceRole,
    devices: [AudioDeviceDescriptor],
    items: inout [SnapshotItem]
  ) -> String? {
    do {
      guard let uid = try api.defaultDeviceUID(for: role) else {
        items.append(
          SnapshotItem(
            key: role.settingKey,
            label: role.displayName.capitalized,
            state: .unreadable,
            detail: "No device is currently selected."
          )
        )
        return nil
      }
      let device = devices.first(where: { $0.uid == uid })
      items.append(
        SnapshotItem(
          key: role.settingKey,
          label: role.displayName.capitalized,
          state: .storable,
          detail: device?.name ?? "Connected device"
        )
      )
      return uid
    } catch {
      items.append(
        SnapshotItem(
          key: role.settingKey,
          label: role.displayName.capitalized,
          state: .unreadable,
          detail: "Core Audio could not read this default device."
        )
      )
      return nil
    }
  }

  private func readVolume(
    deviceUID: String,
    items: inout [SnapshotItem]
  ) -> SettingOption<Double?> {
    do {
      switch try api.outputVolume(forDeviceUID: deviceUID) {
      case .available(let value, let isSettable):
        items.append(
          SnapshotItem(
            key: "outputVolume",
            label: "Output volume",
            state: .storable,
            detail: isSettable ? "Readable and writable" : "Readable, but not writable"
          )
        )
        return SettingOption(isIncluded: true, value: value)
      case .unsupported:
        items.append(unsupportedControlItem(key: "outputVolume", label: "Output volume"))
      case .unreadable(let reason):
        items.append(
          SnapshotItem(
            key: "outputVolume",
            label: "Output volume",
            state: .unreadable,
            detail: reason
          )
        )
      }
    } catch {
      items.append(
        SnapshotItem(
          key: "outputVolume",
          label: "Output volume",
          state: .unreadable,
          detail: "Core Audio could not inspect software volume."
        )
      )
    }
    return SettingOption(isIncluded: false, value: nil)
  }

  private func readMute(
    deviceUID: String,
    items: inout [SnapshotItem]
  ) -> SettingOption<Bool?> {
    do {
      switch try api.outputMute(forDeviceUID: deviceUID) {
      case .available(let value, let isSettable):
        items.append(
          SnapshotItem(
            key: "outputMute",
            label: "Output mute",
            state: .storable,
            detail: isSettable ? "Readable and writable" : "Readable, but not writable"
          )
        )
        return SettingOption(isIncluded: true, value: value)
      case .unsupported:
        items.append(unsupportedControlItem(key: "outputMute", label: "Output mute"))
      case .unreadable(let reason):
        items.append(
          SnapshotItem(
            key: "outputMute",
            label: "Output mute",
            state: .unreadable,
            detail: reason
          )
        )
      }
    } catch {
      items.append(
        SnapshotItem(
          key: "outputMute",
          label: "Output mute",
          state: .unreadable,
          detail: "Core Audio could not inspect software mute."
        )
      )
    }
    return SettingOption(isIncluded: false, value: nil)
  }

  private func unsupportedControlItem(key: String, label: String) -> SnapshotItem {
    SnapshotItem(
      key: key,
      label: label,
      state: .unsupported,
      detail: "The default output device has no software \(label.lowercased()) control."
    )
  }

  private func validateDefaultOption(
    _ option: SettingOption<String?>,
    role: AudioDefaultDeviceRole,
    devices: [AudioDeviceDescriptor],
    issues: inout [ValidationIssue]
  ) {
    guard option.isIncluded else { return }
    guard let uid = option.value, !uid.isEmpty else {
      issues.append(
        fatalIssue(key: role.settingKey, message: "No \(role.displayName) device UID was saved.")
      )
      return
    }
    guard let device = devices.first(where: { $0.uid == uid }) else {
      issues.append(
        fatalIssue(key: role.settingKey, message: "The saved \(role.displayName) device is absent.")
      )
      return
    }
    let supportsRole = role == .input ? device.supportsInput : device.supportsOutput
    if !supportsRole {
      issues.append(
        fatalIssue(
          key: role.settingKey,
          message: "The saved device does not support the \(role.displayName) scope."
        )
      )
    }
  }

  private func appendControlIssue<Value>(
    _ state: AudioControlState<Value>?,
    key: String,
    label: String,
    issues: inout [ValidationIssue]
  ) where Value: Hashable & Sendable {
    switch state {
    case .available(_, true):
      break
    case .available(_, false):
      issues.append(
        ValidationIssue(
          group: group,
          key: key,
          severity: .notice,
          isFatal: false,
          message: "The device's \(label) control is read-only."
        )
      )
    case .unsupported:
      issues.append(
        ValidationIssue(
          group: group,
          key: key,
          severity: .notice,
          isFatal: false,
          message: "The device does not support \(label)."
        )
      )
    case .unreadable(let reason):
      issues.append(
        ValidationIssue(
          group: group,
          key: key,
          severity: .warning,
          isFatal: false,
          message: reason
        )
      )
    case nil:
      issues.append(
        ValidationIssue(
          group: group,
          key: key,
          severity: .warning,
          isFatal: false,
          message: "The device's \(label) capability could not be inspected."
        )
      )
    }
  }

  private func planDefaultDevice(
    _ option: SettingOption<String?>,
    role: AudioDefaultDeviceRole,
    devices: [AudioDeviceDescriptor],
    operations: inout [PlannedOperation],
    omissions: inout [PlanOmission]
  ) throws {
    guard option.isIncluded else { return }
    guard let desiredUID = option.value,
      let descriptor = devices.first(where: { $0.uid == desiredUID }),
      role == .input ? descriptor.supportsInput : descriptor.supportsOutput
    else {
      omissions.append(
        unsupportedOmission(
          key: role.settingKey,
          reason: "The saved \(role.displayName) device is unavailable or has the wrong scope."
        )
      )
      return
    }
    let currentUID: String?
    do {
      currentUID = try api.defaultDeviceUID(for: role)
    } catch {
      omissions.append(
        skippedOmission(
          key: role.settingKey,
          reason: "The current \(role.displayName) device could not be read."
        )
      )
      return
    }
    guard let currentUID else {
      omissions.append(
        unsupportedOmission(
          key: role.settingKey,
          reason: "The current \(role.displayName) device could not be backed up."
        )
      )
      return
    }
    guard currentUID != desiredUID else {
      return
    }

    operations.append(
      try makeOperation(
        key: role.settingKey,
        summary: "Change the \(role.displayName) device",
        desired: .setDefaultDevice(role: role, uid: desiredUID),
        rollback: .setDefaultDevice(role: role, uid: currentUID),
        preview: OperationPreview(
          previousValue: previewDevice(currentUID, among: devices),
          desiredValue: previewDevice(desiredUID, among: devices)
        )
      )
    )
  }

  private func planVolume(
    _ option: SettingOption<Double?>,
    deviceUID: String?,
    devices: [AudioDeviceDescriptor],
    operations: inout [PlannedOperation],
    omissions: inout [PlanOmission]
  ) {
    guard option.isIncluded else { return }
    guard let desiredValue = option.value,
      desiredValue.isFinite,
      (0.0...1.0).contains(desiredValue),
      let deviceUID,
      devices.contains(where: { $0.uid == deviceUID && $0.supportsOutput })
    else {
      omissions.append(
        unsupportedOmission(
          key: "outputVolume",
          reason: "No valid output device and scalar volume are available."
        )
      )
      return
    }

    do {
      switch try api.outputVolume(forDeviceUID: deviceUID) {
      case .available(let currentValue, true):
        guard abs(currentValue - desiredValue) > 0.0001 else {
          return
        }
        operations.append(
          try makeOperation(
            key: "outputVolume",
            summary: "Change output volume",
            desired: .setOutputVolume(deviceUID: deviceUID, value: desiredValue),
            rollback: .setOutputVolume(deviceUID: deviceUID, value: currentValue),
            preview: OperationPreview(
              previousValue: previewVolume(currentValue),
              desiredValue: previewVolume(desiredValue)
            )
          )
        )
      case .available(_, false), .unsupported:
        omissions.append(
          unsupportedOmission(
            key: "outputVolume",
            reason: "The output device does not provide writable software volume."
          )
        )
      case .unreadable(let reason):
        omissions.append(skippedOmission(key: "outputVolume", reason: reason))
      }
    } catch {
      omissions.append(
        skippedOmission(key: "outputVolume", reason: "Software volume could not be inspected.")
      )
    }
  }

  private func planMute(
    _ option: SettingOption<Bool?>,
    deviceUID: String?,
    devices: [AudioDeviceDescriptor],
    operations: inout [PlannedOperation],
    omissions: inout [PlanOmission]
  ) {
    guard option.isIncluded else { return }
    guard let desiredValue = option.value,
      let deviceUID,
      devices.contains(where: { $0.uid == deviceUID && $0.supportsOutput })
    else {
      omissions.append(
        unsupportedOmission(
          key: "outputMute",
          reason: "No valid output device and mute value are available."
        )
      )
      return
    }

    do {
      switch try api.outputMute(forDeviceUID: deviceUID) {
      case .available(let currentValue, true):
        guard currentValue != desiredValue else {
          return
        }
        operations.append(
          try makeOperation(
            key: "outputMute",
            summary: "Change output mute",
            desired: .setOutputMute(deviceUID: deviceUID, value: desiredValue),
            rollback: .setOutputMute(deviceUID: deviceUID, value: currentValue),
            preview: OperationPreview(
              previousValue: currentValue ? "On" : "Off",
              desiredValue: desiredValue ? "On" : "Off"
            )
          )
        )
      case .available(_, false), .unsupported:
        omissions.append(
          unsupportedOmission(
            key: "outputMute",
            reason: "The output device does not provide writable software mute."
          )
        )
      case .unreadable(let reason):
        omissions.append(skippedOmission(key: "outputMute", reason: reason))
      }
    } catch {
      omissions.append(
        skippedOmission(key: "outputMute", reason: "Software mute could not be inspected.")
      )
    }
  }

  private func makeOperation(
    key: String,
    summary: String,
    desired: AudioOperationCommand,
    rollback: AudioOperationCommand,
    preview: OperationPreview
  ) throws -> PlannedOperation {
    PlannedOperation(
      group: group,
      key: key,
      summary: summary,
      risk: .low,
      isFatalOnFailure: false,
      preview: preview,
      payload: try encode(desired),
      rollbackPayload: try encode(rollback)
    )
  }

  private func previewDevice(
    _ uid: String,
    among devices: [AudioDeviceDescriptor]
  ) -> String {
    guard let device = devices.first(where: { $0.uid == uid }) else {
      return uid
    }
    return "\(device.name) [\(uid)]"
  }

  private func previewVolume(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }

  private func perform(_ command: AudioOperationCommand) throws {
    switch command {
    case .setDefaultDevice(let role, let uid):
      try api.setDefaultDeviceUID(uid, for: role)
    case .setOutputVolume(let deviceUID, let value):
      try api.setOutputVolume(value, forDeviceUID: deviceUID)
    case .setOutputMute(let deviceUID, let value):
      try api.setOutputMute(value, forDeviceUID: deviceUID)
    }
  }

  private func encode(_ command: AudioOperationCommand) throws -> Data {
    try JSONEncoder().encode(command)
  }

  private func decode(_ data: Data) throws -> AudioOperationCommand {
    try JSONDecoder().decode(AudioOperationCommand.self, from: data)
  }

  private func fatalIssue(key: String, message: String) -> ValidationIssue {
    ValidationIssue(
      group: group,
      key: key,
      severity: .error,
      isFatal: true,
      message: message
    )
  }

  private func unsupportedOmission(key: String, reason: String) -> PlanOmission {
    PlanOmission(group: group, key: key, status: .unsupported, reason: reason)
  }

  private func skippedOmission(key: String, reason: String) -> PlanOmission {
    PlanOmission(group: group, key: key, status: .skipped, reason: reason)
  }
}
