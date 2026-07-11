import Foundation

public enum MockAdapterFailure: Error, Hashable, Sendable {
  case snapshot(String)
  case planning(String)
}

extension MockAdapterFailure: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .snapshot(let message), .planning(let message):
      message
    }
  }
}

public enum MockAdapterInvocation: Hashable, Sendable {
  case capability
  case snapshot
  case validate
  case plan(ApplyMode)
  case apply(UUID)
  case confirm(UUID)
  case rollback(UUID)
  case diagnostics
}

/// A deterministic test double. It records calls and returns configured values without
/// importing a system framework or changing any host setting.
public actor MockSystemSettingsAdapter: SystemSettingsAdapter {
  public nonisolated let group: SettingGroup

  private var capabilityValue: AdapterCapability
  private var snapshotValue: AdapterSnapshot
  private var snapshotFailure: MockAdapterFailure?
  private var validationIssues: [ValidationIssue]
  private var planValue: AdapterPlan
  private var planningFailure: MockAdapterFailure?
  private var applyResults: [UUID: OperationResult]
  private var confirmResults: [UUID: OperationResult]
  private var rollbackResults: [UUID: OperationResult]
  private var diagnosticEntries: [DiagnosticEntry]
  private var invocationValues: [MockAdapterInvocation] = []

  public init(
    group: SettingGroup,
    capability: AdapterCapability? = nil,
    snapshot: AdapterSnapshot? = nil,
    snapshotFailure: MockAdapterFailure? = nil,
    validationIssues: [ValidationIssue] = [],
    plan: AdapterPlan? = nil,
    planningFailure: MockAdapterFailure? = nil,
    applyResults: [UUID: OperationResult] = [:],
    confirmResults: [UUID: OperationResult] = [:],
    rollbackResults: [UUID: OperationResult] = [:],
    diagnostics: [DiagnosticEntry] = []
  ) {
    self.group = group
    capabilityValue =
      capability
      ?? AdapterCapability(
        group: group,
        state: .supported,
        reason: "The mock adapter is available."
      )
    snapshotValue =
      snapshot
      ?? AdapterSnapshot(
        group: group,
        capturedAt: Date(timeIntervalSince1970: 0),
        payload: nil,
        items: []
      )
    self.snapshotFailure = snapshotFailure
    self.validationIssues = validationIssues
    planValue = plan ?? AdapterPlan(group: group)
    self.planningFailure = planningFailure
    self.applyResults = applyResults
    self.confirmResults = confirmResults
    self.rollbackResults = rollbackResults
    diagnosticEntries = diagnostics
  }

  public func capability() async -> AdapterCapability {
    invocationValues.append(.capability)
    return capabilityValue
  }

  public func snapshot() async throws -> AdapterSnapshot {
    invocationValues.append(.snapshot)
    if let snapshotFailure {
      throw snapshotFailure
    }
    return snapshotValue
  }

  public func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue] {
    invocationValues.append(.validate)
    return validationIssues
  }

  public func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan {
    invocationValues.append(.plan(mode))
    if let planningFailure {
      throw planningFailure
    }
    return planValue
  }

  public func apply(_ operation: PlannedOperation) async -> OperationResult {
    invocationValues.append(.apply(operation.id))
    return applyResults[operation.id]
      ?? OperationResult(
        operationID: operation.id,
        status: .succeeded,
        message: "Mock operation succeeded."
      )
  }

  public func rollback(_ operation: PlannedOperation) async -> OperationResult {
    invocationValues.append(.rollback(operation.id))
    return rollbackResults[operation.id]
      ?? OperationResult(
        operationID: operation.id,
        status: .rolledBack,
        message: "Mock operation rolled back."
      )
  }

  public func confirm(_ operation: PlannedOperation) async -> OperationResult {
    invocationValues.append(.confirm(operation.id))
    return confirmResults[operation.id]
      ?? OperationResult(
        operationID: operation.id,
        status: .succeeded,
        message: "Mock operation was confirmed."
      )
  }

  public func diagnostics() async -> [DiagnosticEntry] {
    invocationValues.append(.diagnostics)
    return diagnosticEntries
  }

  public func setApplyResult(_ result: OperationResult) {
    applyResults[result.operationID] = result
  }

  public func setRollbackResult(_ result: OperationResult) {
    rollbackResults[result.operationID] = result
  }

  public func setConfirmResult(_ result: OperationResult) {
    confirmResults[result.operationID] = result
  }

  public func recordedInvocations() -> [MockAdapterInvocation] {
    invocationValues
  }

  public func resetInvocations() {
    invocationValues.removeAll(keepingCapacity: true)
  }
}
