import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// A safe placeholder used until a concrete adapter has proven snapshot, validation,
/// planning, apply, and rollback behavior. It never changes the host Mac.
public struct UnsupportedSystemSettingsAdapter: SystemSettingsAdapter {
  public let group: SettingGroup
  public let reason: String

  public init(group: SettingGroup, reason: String) {
    self.group = group
    self.reason = reason
  }

  public func capability() async -> AdapterCapability {
    AdapterCapability(group: group, state: .unsupported, reason: reason)
  }

  public func snapshot() async throws -> AdapterSnapshot {
    AdapterSnapshot(
      group: group,
      capturedAt: Date(),
      payload: nil,
      items: [
        SnapshotItem(
          key: "adapter",
          label: group.rawValue.capitalized,
          state: .unsupported,
          detail: reason
        )
      ]
    )
  }

  public func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue] {
    [
      ValidationIssue(
        group: group,
        key: "adapter",
        severity: .error,
        isFatal: true,
        message: reason
      )
    ]
  }

  public func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan {
    AdapterPlan(
      group: group,
      omissions: [
        PlanOmission(
          group: group,
          key: "adapter",
          status: .unsupported,
          reason: reason
        )
      ]
    )
  }

  public func apply(_ operation: PlannedOperation) async -> OperationResult {
    OperationResult(operationID: operation.id, status: .unsupported, message: reason)
  }

  public func rollback(_ operation: PlannedOperation) async -> OperationResult {
    OperationResult(operationID: operation.id, status: .unsupported, message: reason)
  }

  public func diagnostics() async -> [DiagnosticEntry] {
    [
      DiagnosticEntry(
        severity: .info,
        component: "adapter.\(group.rawValue)",
        code: "adapter.unsupported-placeholder",
        message: reason
      )
    ]
  }
}

public enum SafeAdapterFactory {
  public static func makePlaceholders() -> [any SystemSettingsAdapter] {
    SettingGroup.allCases.map {
      UnsupportedSystemSettingsAdapter(
        group: $0,
        reason: "This explicit fallback adapter is unavailable and never mutates the host Mac."
      )
    }
  }
}
