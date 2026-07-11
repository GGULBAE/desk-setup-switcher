import Foundation

public enum CapabilityState: String, Codable, Hashable, Sendable {
  case supported
  case experimental
  case permissionRequired
  case temporarilyUnavailable
  case unsupported
}

public struct AdapterCapability: Codable, Hashable, Sendable {
  public var group: SettingGroup
  public var state: CapabilityState
  public var reason: String

  public init(group: SettingGroup, state: CapabilityState, reason: String) {
    self.group = group
    self.state = state
    self.reason = reason
  }

  public var canApply: Bool {
    state == .supported || state == .experimental
  }
}

public enum SnapshotItemState: String, Codable, Hashable, Sendable {
  case detected
  case storable
  case unreadable
  case permissionRequired
  case unsupported
}

public struct SnapshotItem: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var key: String
  public var label: String
  public var state: SnapshotItemState
  public var detail: String

  public init(
    id: UUID = UUID(),
    key: String,
    label: String,
    state: SnapshotItemState,
    detail: String = ""
  ) {
    self.id = id
    self.key = key
    self.label = label
    self.state = state
    self.detail = detail
  }
}

public struct AdapterSnapshot: Codable, Hashable, Sendable {
  public var group: SettingGroup
  public var capturedAt: Date
  public var payload: SettingsPayload?
  public var items: [SnapshotItem]

  public init(
    group: SettingGroup,
    capturedAt: Date,
    payload: SettingsPayload?,
    items: [SnapshotItem]
  ) {
    self.group = group
    self.capturedAt = capturedAt
    self.payload = payload
    self.items = items
  }
}

public enum ValidationSeverity: String, Codable, Hashable, Sendable {
  case notice
  case warning
  case error
}

public struct ValidationIssue: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var group: SettingGroup
  public var key: String
  public var severity: ValidationSeverity
  public var isFatal: Bool
  public var message: String

  public init(
    id: UUID = UUID(),
    group: SettingGroup,
    key: String,
    severity: ValidationSeverity,
    isFatal: Bool,
    message: String
  ) {
    self.id = id
    self.group = group
    self.key = key
    self.severity = severity
    self.isFatal = isFatal
    self.message = message
  }
}

public enum ApplyMode: String, Codable, Hashable, Sendable {
  case normal
  case force
}

public enum OperationRisk: Int, Codable, Comparable, Hashable, Sendable {
  case low = 0
  case moderate = 1
  case high = 2

  public static func < (lhs: OperationRisk, rhs: OperationRisk) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Sanitized, local-UI-only values captured while an operation is planned.
/// Adapters must never place passwords, credentials, or opaque error details
/// here. Diagnostics intentionally do not serialize this value.
public struct OperationPreview: Codable, Hashable, Sendable {
  public var previousValue: String
  public var desiredValue: String

  public init(previousValue: String, desiredValue: String) {
    self.previousValue = previousValue
    self.desiredValue = desiredValue
  }
}

public struct PlannedOperation: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var group: SettingGroup
  public var key: String
  public var summary: String
  public var risk: OperationRisk
  public var isFatalOnFailure: Bool
  public var preview: OperationPreview?
  public var payload: Data
  public var rollbackPayload: Data?

  public init(
    id: UUID = UUID(),
    group: SettingGroup,
    key: String,
    summary: String,
    risk: OperationRisk = .low,
    isFatalOnFailure: Bool = false,
    preview: OperationPreview? = nil,
    payload: Data = Data(),
    rollbackPayload: Data? = nil
  ) {
    self.id = id
    self.group = group
    self.key = key
    self.summary = summary
    self.risk = risk
    self.isFatalOnFailure = isFatalOnFailure
    self.preview = preview
    self.payload = payload
    self.rollbackPayload = rollbackPayload
  }
}

public struct PlanOmission: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var group: SettingGroup
  public var key: String
  public var status: ApplicationItemStatus
  public var reason: String

  public init(
    id: UUID = UUID(),
    group: SettingGroup,
    key: String,
    status: ApplicationItemStatus,
    reason: String
  ) {
    self.id = id
    self.group = group
    self.key = key
    self.status = status
    self.reason = reason
  }
}

public struct AdapterPlan: Codable, Hashable, Sendable {
  public var group: SettingGroup
  public var operations: [PlannedOperation]
  public var omissions: [PlanOmission]
  public var issues: [ValidationIssue]

  public init(
    group: SettingGroup,
    operations: [PlannedOperation] = [],
    omissions: [PlanOmission] = [],
    issues: [ValidationIssue] = []
  ) {
    self.group = group
    self.operations = operations
    self.omissions = omissions
    self.issues = issues
  }
}

public struct OperationResult: Codable, Hashable, Sendable {
  public var operationID: UUID
  public var status: ApplicationItemStatus
  public var message: String

  public init(operationID: UUID, status: ApplicationItemStatus, message: String) {
    self.operationID = operationID
    self.status = status
    self.message = message
  }

  public var succeeded: Bool {
    status == .succeeded || status == .rolledBack
  }
}

public enum DiagnosticSeverity: String, Codable, Hashable, Sendable {
  case debug
  case info
  case warning
  case error
}

public struct DiagnosticEntry: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var timestamp: Date
  public var severity: DiagnosticSeverity
  public var component: String
  public var code: String
  public var message: String

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    severity: DiagnosticSeverity,
    component: String,
    code: String,
    message: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.severity = severity
    self.component = component
    self.code = code
    self.message = message
  }
}

public protocol SystemSettingsAdapter: Sendable {
  var group: SettingGroup { get }

  func capability() async -> AdapterCapability
  func snapshot() async throws -> AdapterSnapshot
  func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue]
  func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan
  func apply(_ operation: PlannedOperation) async -> OperationResult
  func confirm(_ operation: PlannedOperation) async -> OperationResult
  func rollback(_ operation: PlannedOperation) async -> OperationResult
  func diagnostics() async -> [DiagnosticEntry]
}

extension SystemSettingsAdapter {
  /// Most adapters commit during `apply`. High-risk adapters may override this
  /// hook to promote a temporary, fail-safe change only after user confirmation.
  public func confirm(_ operation: PlannedOperation) async -> OperationResult {
    OperationResult(
      operationID: operation.id,
      status: .succeeded,
      message: "No additional confirmation commit was required."
    )
  }
}
