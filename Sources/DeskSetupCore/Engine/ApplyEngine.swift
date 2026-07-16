import Foundation

public enum ApplyRejectionReason: String, Codable, Hashable, Sendable {
  case noIncludedSettings
  case conditionsUnsatisfied
  case unavailableItems
  case fatalValidationIssues
  case noOperations
  case transactionInProgress
  case safetyConfirmationCapacityReached
}

public struct ApplyPreparation: Codable, Hashable, Sendable {
  public var profileID: UUID
  public var mode: ApplyMode
  public var preparedAt: Date
  public var includedGroups: [SettingGroup]
  public var capabilities: [AdapterCapability]
  public var snapshots: [AdapterSnapshot]
  public var validationIssues: [ValidationIssue]
  public var operations: [PlannedOperation]
  public var omissions: [PlanOmission]
  public var readiness: ReadinessEvaluation
  public var rejectionReasons: [ApplyRejectionReason]

  public init(
    profileID: UUID,
    mode: ApplyMode,
    preparedAt: Date,
    includedGroups: [SettingGroup],
    capabilities: [AdapterCapability],
    snapshots: [AdapterSnapshot],
    validationIssues: [ValidationIssue],
    operations: [PlannedOperation],
    omissions: [PlanOmission],
    readiness: ReadinessEvaluation,
    rejectionReasons: [ApplyRejectionReason]
  ) {
    self.profileID = profileID
    self.mode = mode
    self.preparedAt = preparedAt
    self.includedGroups = includedGroups
    self.capabilities = capabilities
    self.snapshots = snapshots
    self.validationIssues = validationIssues
    self.operations = operations
    self.omissions = omissions
    self.readiness = readiness
    self.rejectionReasons = rejectionReasons
  }

  public var canExecute: Bool {
    rejectionReasons.isEmpty
  }

  /// Compares only execution-relevant planning data. Fresh preparations receive new
  /// timestamps and item identifiers, so those fields must not force a second preview.
  /// Rollback payloads are included: if the host changed after the preview, execution
  /// pauses and presents the refreshed plan instead of using stale backup state.
  public func isExecutionEquivalent(to other: ApplyPreparation) -> Bool {
    guard profileID == other.profileID,
      mode == other.mode,
      includedGroups == other.includedGroups,
      capabilities == other.capabilities,
      readiness == other.readiness,
      rejectionReasons == other.rejectionReasons,
      validationIssues.count == other.validationIssues.count,
      operations.count == other.operations.count,
      omissions.count == other.omissions.count
    else {
      return false
    }

    let validationMatches = zip(validationIssues, other.validationIssues).allSatisfy {
      lhs, rhs in
      lhs.group == rhs.group
        && lhs.key == rhs.key
        && lhs.severity == rhs.severity
        && lhs.isFatal == rhs.isFatal
        && lhs.message == rhs.message
    }
    guard validationMatches else { return false }

    let operationsMatch = zip(operations, other.operations).allSatisfy { lhs, rhs in
      lhs.group == rhs.group
        && lhs.key == rhs.key
        && lhs.summary == rhs.summary
        && lhs.risk == rhs.risk
        && lhs.isFatalOnFailure == rhs.isFatalOnFailure
        && lhs.preview == rhs.preview
        && lhs.payload == rhs.payload
        && lhs.rollbackPayload == rhs.rollbackPayload
    }
    guard operationsMatch else { return false }

    return zip(omissions, other.omissions).allSatisfy { lhs, rhs in
      lhs.group == rhs.group
        && lhs.key == rhs.key
        && lhs.status == rhs.status
        && lhs.reason == rhs.reason
    }
  }
}

public struct ApplyExecutionResult: Codable, Hashable, Sendable {
  public var preparation: ApplyPreparation
  public var didExecute: Bool
  public var completedAt: Date
  public var status: ProfileReadiness
  public var itemResults: [ApplicationItemSummary]
  public var rollbackResults: [ApplicationItemSummary]
  public var fatalOperationID: UUID?
  public var safetyConfirmationID: UUID?

  public init(
    preparation: ApplyPreparation,
    didExecute: Bool,
    completedAt: Date,
    status: ProfileReadiness,
    itemResults: [ApplicationItemSummary],
    rollbackResults: [ApplicationItemSummary] = [],
    fatalOperationID: UUID? = nil,
    safetyConfirmationID: UUID? = nil
  ) {
    self.preparation = preparation
    self.didExecute = didExecute
    self.completedAt = completedAt
    self.status = status
    self.itemResults = itemResults
    self.rollbackResults = rollbackResults
    self.fatalOperationID = fatalOperationID
    self.safetyConfirmationID = safetyConfirmationID
  }

  public var applicationSummary: ApplicationSummary {
    ApplicationSummary(
      appliedAt: completedAt,
      status: status,
      items: itemResults + rollbackResults
    )
  }
}

public enum SafetyRollbackResolutionStatus: String, Codable, Hashable, Sendable {
  case confirmed
  case confirmationFailed
  case reverted
  case rollbackFailed
  case unknownOrExpired
  case transactionInProgress
}

public struct SafetyRollbackResolution: Codable, Hashable, Sendable {
  public var status: SafetyRollbackResolutionStatus
  public var rollbackResults: [ApplicationItemSummary]

  public init(
    status: SafetyRollbackResolutionStatus,
    rollbackResults: [ApplicationItemSummary] = []
  ) {
    self.status = status
    self.rollbackResults = rollbackResults
  }
}

private struct PendingSafetyRollback: Sendable {
  var operations: [PlannedOperation]
}

/// Coordinates safe, previewable application transactions. The engine contains no live
/// system API calls; all effects are delegated through the injected adapter registry.
public actor ApplyEngine {
  private static let safetyRollbackHardLimit = 8

  private let registry: AdapterRegistry
  private let readinessEvaluator: ReadinessEvaluator
  private let profileNormalizer: ProfileApplicabilityNormalizer
  private let now: @Sendable () -> Date
  private let maximumPendingSafetyRollbacks: Int
  private var isExecuting = false
  private var pendingSafetyRollbacks: [UUID: PendingSafetyRollback] = [:]

  public init(
    registry: AdapterRegistry,
    readinessEvaluator: ReadinessEvaluator = .init(),
    profileNormalizer: ProfileApplicabilityNormalizer = .init(),
    maximumPendingSafetyRollbacks: Int = 1,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.registry = registry
    self.readinessEvaluator = readinessEvaluator
    self.profileNormalizer = profileNormalizer
    self.maximumPendingSafetyRollbacks = min(
      max(1, maximumPendingSafetyRollbacks),
      Self.safetyRollbackHardLimit
    )
    self.now = now
  }

  public func prepare(
    profile: DeskProfile,
    mode: ApplyMode,
    conditionsSatisfied: Bool = true
  ) async -> ApplyPreparation {
    let profile = profileNormalizer.normalize(profile)
    let includedGroups = SettingGroup.safeApplicationSequence.filter {
      profile.settings.payload(for: $0) != nil
    }
    var capabilities: [AdapterCapability] = []
    var snapshots: [AdapterSnapshot] = []
    var issues: [ValidationIssue] = []
    var operations: [PlannedOperation] = []
    var omissions: [PlanOmission] = []
    var viableGroups = Set<SettingGroup>()

    for group in includedGroups {
      guard let desired = profile.settings.payload(for: group) else { continue }
      guard let adapter = registry.adapter(for: group) else {
        let message = "No adapter is registered for the \(group.rawValue) settings group."
        capabilities.append(
          AdapterCapability(group: group, state: .unsupported, reason: message)
        )
        appendInfrastructureFailure(
          group: group,
          key: "adapter",
          message: message,
          issues: &issues,
          omissions: &omissions
        )
        continue
      }

      let reportedCapability = await adapter.capability()
      guard reportedCapability.group == group else {
        let message = "The registered adapter returned capability data for a different group."
        capabilities.append(
          AdapterCapability(group: group, state: .unsupported, reason: message)
        )
        appendInfrastructureFailure(
          group: group,
          key: "adapter.capability",
          message: message,
          issues: &issues,
          omissions: &omissions
        )
        continue
      }
      capabilities.append(reportedCapability)

      guard reportedCapability.canApply else {
        omissions.append(
          PlanOmission(
            group: group,
            key: "capability",
            status: reportedCapability.state == .unsupported ? .unsupported : .skipped,
            reason: reportedCapability.reason
          )
        )
        continue
      }

      let snapshot: AdapterSnapshot
      do {
        snapshot = try await adapter.snapshot()
      } catch {
        appendInfrastructureFailure(
          group: group,
          key: "snapshot",
          message: "The \(group.rawValue) settings could not be read safely.",
          issues: &issues,
          omissions: &omissions
        )
        continue
      }

      guard snapshot.group == group,
        snapshot.payload == nil || snapshot.payload?.group == group
      else {
        appendInfrastructureFailure(
          group: group,
          key: "snapshot",
          message: "The adapter returned a snapshot for a different settings group.",
          issues: &issues,
          omissions: &omissions
        )
        continue
      }
      snapshots.append(snapshot)

      let validationIssues = await adapter.validate(desired, against: snapshot)
      guard validationIssues.allSatisfy({ $0.group == group }) else {
        appendInfrastructureFailure(
          group: group,
          key: "validation",
          message: "The adapter returned validation data for a different settings group.",
          issues: &issues,
          omissions: &omissions
        )
        continue
      }
      issues.append(contentsOf: validationIssues)

      let adapterPlan: AdapterPlan
      do {
        adapterPlan = try await adapter.plan(desired, from: snapshot, mode: mode)
      } catch {
        appendInfrastructureFailure(
          group: group,
          key: "plan",
          message: "The \(group.rawValue) settings could not be planned safely.",
          issues: &issues,
          omissions: &omissions
        )
        continue
      }

      if let contractViolation = planContractViolation(adapterPlan, expectedGroup: group) {
        appendInfrastructureFailure(
          group: group,
          key: "plan",
          message: contractViolation,
          issues: &issues,
          omissions: &omissions
        )
        continue
      }

      issues.append(contentsOf: adapterPlan.issues)
      omissions.append(contentsOf: adapterPlan.omissions)
      viableGroups.insert(group)

      let fatalIssues = (validationIssues + adapterPlan.issues).filter(\.isFatal)
      let operationKeys = Set(adapterPlan.operations.map(\.key))
      let hasGroupLevelFatalIssue = fatalIssues.contains { !operationKeys.contains($0.key) }
      let fatalKeys = Set(fatalIssues.map(\.key))

      for issue in fatalIssues
      where !omissions.contains(where: {
        $0.group == issue.group && $0.key == issue.key
      }) {
        omissions.append(
          PlanOmission(
            group: issue.group,
            key: issue.key,
            status: .skipped,
            reason: issue.message
          )
        )
      }

      if !hasGroupLevelFatalIssue {
        operations.append(
          contentsOf: adapterPlan.operations.filter {
            !fatalKeys.contains($0.key)
          })
      }
    }

    removeOperationsWithDuplicateIDs(
      operations: &operations,
      issues: &issues,
      omissions: &omissions
    )
    operations = deterministicallyOrdered(operations)

    let readiness = readinessEvaluator.evaluate(
      includedGroups: includedGroups,
      capabilities: capabilities,
      viableGroups: viableGroups,
      operations: operations,
      omissions: omissions,
      issues: issues,
      conditionsSatisfied: conditionsSatisfied
    )

    var rejectionReasons: [ApplyRejectionReason] = []
    if includedGroups.isEmpty {
      appendUnique(.noIncludedSettings, to: &rejectionReasons)
    }

    switch mode {
    case .normal:
      if !conditionsSatisfied {
        appendUnique(.conditionsUnsatisfied, to: &rejectionReasons)
      }
      if !omissions.isEmpty || capabilities.contains(where: { !$0.canApply }) {
        appendUnique(.unavailableItems, to: &rejectionReasons)
      }
      if issues.contains(where: \.isFatal) {
        appendUnique(.fatalValidationIssues, to: &rejectionReasons)
      }
    case .force:
      if operations.isEmpty {
        appendUnique(.noOperations, to: &rejectionReasons)
      }
    }

    return ApplyPreparation(
      profileID: profile.id,
      mode: mode,
      preparedAt: now(),
      includedGroups: includedGroups,
      capabilities: capabilities,
      snapshots: snapshots,
      validationIssues: issues,
      operations: operations,
      omissions: omissions,
      readiness: readiness,
      rejectionReasons: rejectionReasons
    )
  }

  public func apply(
    profile: DeskProfile,
    mode: ApplyMode,
    conditionsSatisfied: Bool = true
  ) async -> ApplyExecutionResult {
    let preparation = await prepare(
      profile: profile,
      mode: mode,
      conditionsSatisfied: conditionsSatisfied
    )
    return await execute(preparation)
  }

  public func execute(_ preparation: ApplyPreparation) async -> ApplyExecutionResult {
    guard !isExecuting else {
      var blockedPreparation = preparation
      appendUnique(.transactionInProgress, to: &blockedPreparation.rejectionReasons)
      return rejectedResult(for: blockedPreparation)
    }
    guard preparation.canExecute else {
      return rejectedResult(for: preparation)
    }
    if preparation.operations.contains(where: { $0.risk == .high }),
      pendingSafetyRollbacks.count >= maximumPendingSafetyRollbacks
    {
      var blockedPreparation = preparation
      appendUnique(
        .safetyConfirmationCapacityReached,
        to: &blockedPreparation.rejectionReasons
      )
      return rejectedResult(for: blockedPreparation)
    }

    isExecuting = true
    defer { isExecuting = false }

    var itemResults = omissionSummaries(for: preparation.omissions)
    var rollbackResults: [ApplicationItemSummary] = []
    var completedOperations: [PlannedOperation] = []
    var encounteredFailure = false
    var fatalOperationID: UUID?

    for (index, operation) in preparation.operations.enumerated() {
      let operationResult: OperationResult
      if let adapter = registry.adapter(for: operation.group) {
        operationResult = normalizedApplyResult(
          await adapter.apply(operation),
          for: operation
        )
      } else {
        operationResult = OperationResult(
          operationID: operation.id,
          status: .failed,
          message: "The adapter was unavailable when the operation was applied."
        )
      }

      itemResults.append(
        ApplicationItemSummary(
          id: operation.id,
          group: operation.group,
          key: operation.key,
          status: operationResult.status,
          message: operationResult.message
        )
      )

      if operationResult.status == .succeeded {
        completedOperations.append(operation)
        continue
      }

      encounteredFailure = true
      var failingOperationWasRestored = false
      if operation.rollbackPayload != nil {
        let failingRollback = await rollback(operation)
        rollbackResults.append(failingRollback)
        failingOperationWasRestored = failingRollback.status == .rolledBack
      }

      // A nonfatal operation may continue only after its own possibly partial
      // mutation has been positively restored. A missing or failed rollback
      // escalates the failure to a transaction stop because the host state is
      // then unknown.
      if !operation.isFatalOnFailure, failingOperationWasRestored {
        continue
      }

      fatalOperationID = operation.id
      if index + 1 < preparation.operations.count {
        for skippedOperation in preparation.operations[(index + 1)...] {
          itemResults.append(
            ApplicationItemSummary(
              id: skippedOperation.id,
              group: skippedOperation.group,
              key: skippedOperation.key,
              status: .skipped,
              message: "Skipped after a fatal operation failure."
            )
          )
        }
      }

      for completedOperation in completedOperations.reversed() {
        rollbackResults.append(await rollback(completedOperation))
      }
      break
    }

    if rollbackResults.contains(where: { $0.status == .rollbackFailed }) {
      encounteredFailure = true
    }

    let completedHighRiskOperations = completedOperations.filter { $0.risk == .high }
    let safetyConfirmationID: UUID?
    if fatalOperationID == nil, !completedHighRiskOperations.isEmpty {
      let confirmationID = makeSafetyConfirmationID()
      pendingSafetyRollbacks[confirmationID] = PendingSafetyRollback(
        operations: completedHighRiskOperations
      )
      safetyConfirmationID = confirmationID
    } else {
      safetyConfirmationID = nil
    }

    return ApplyExecutionResult(
      preparation: preparation,
      didExecute: true,
      completedAt: now(),
      status: encounteredFailure ? .failed : .applied,
      itemResults: itemResults,
      rollbackResults: rollbackResults,
      fatalOperationID: fatalOperationID,
      safetyConfirmationID: safetyConfirmationID
    )
  }

  public func confirmSafetyRollback(_ confirmationID: UUID) async -> SafetyRollbackResolution {
    guard let pending = pendingSafetyRollbacks[confirmationID] else {
      return SafetyRollbackResolution(status: .unknownOrExpired)
    }
    guard !isExecuting else {
      return SafetyRollbackResolution(status: .transactionInProgress)
    }

    pendingSafetyRollbacks.removeValue(forKey: confirmationID)
    isExecuting = true
    defer { isExecuting = false }

    var confirmationFailed = false
    for operation in pending.operations {
      guard let adapter = registry.adapter(for: operation.group) else {
        confirmationFailed = true
        break
      }
      let result = await adapter.confirm(operation)
      guard result.operationID == operation.id, result.status == .succeeded else {
        confirmationFailed = true
        break
      }
    }

    guard confirmationFailed else {
      return SafetyRollbackResolution(status: .confirmed)
    }

    var rollbackResults: [ApplicationItemSummary] = []
    for operation in pending.operations.reversed() {
      rollbackResults.append(await rollback(operation))
    }
    let rollbackFailed = rollbackResults.contains { $0.status == .rollbackFailed }
    return SafetyRollbackResolution(
      status: rollbackFailed ? .rollbackFailed : .confirmationFailed,
      rollbackResults: rollbackResults
    )
  }

  public func revertSafetyRollback(_ confirmationID: UUID) async -> SafetyRollbackResolution {
    guard pendingSafetyRollbacks[confirmationID] != nil else {
      return SafetyRollbackResolution(status: .unknownOrExpired)
    }
    guard !isExecuting else {
      return SafetyRollbackResolution(status: .transactionInProgress)
    }
    guard let pending = pendingSafetyRollbacks.removeValue(forKey: confirmationID) else {
      return SafetyRollbackResolution(status: .unknownOrExpired)
    }

    isExecuting = true
    defer { isExecuting = false }

    var rollbackResults: [ApplicationItemSummary] = []
    for operation in pending.operations.reversed() {
      rollbackResults.append(await rollback(operation))
    }
    let status: SafetyRollbackResolutionStatus =
      rollbackResults.contains {
        $0.status == .rollbackFailed
      } ? .rollbackFailed : .reverted
    return SafetyRollbackResolution(
      status: status,
      rollbackResults: rollbackResults
    )
  }

  private func rollback(_ operation: PlannedOperation) async -> ApplicationItemSummary {
    guard let adapter = registry.adapter(for: operation.group) else {
      return ApplicationItemSummary(
        id: operation.id,
        group: operation.group,
        key: operation.key,
        status: .rollbackFailed,
        message: "The adapter was unavailable during rollback."
      )
    }

    let result = await adapter.rollback(operation)
    let status: ApplicationItemStatus
    let message: String
    if result.operationID != operation.id {
      status = .rollbackFailed
      message = "The adapter returned a mismatched rollback result."
    } else if result.succeeded {
      status = .rolledBack
      message = result.message
    } else {
      status = .rollbackFailed
      message = result.message
    }

    return ApplicationItemSummary(
      id: operation.id,
      group: operation.group,
      key: operation.key,
      status: status,
      message: message
    )
  }

  private func normalizedApplyResult(
    _ result: OperationResult,
    for operation: PlannedOperation
  ) -> OperationResult {
    guard result.operationID == operation.id else {
      return OperationResult(
        operationID: operation.id,
        status: .failed,
        message: "The adapter returned a mismatched operation result."
      )
    }
    return result
  }

  private func rejectedResult(for preparation: ApplyPreparation) -> ApplyExecutionResult {
    ApplyExecutionResult(
      preparation: preparation,
      didExecute: false,
      completedAt: now(),
      status: .failed,
      itemResults: omissionSummaries(for: preparation.omissions)
    )
  }

  private func makeSafetyConfirmationID() -> UUID {
    var confirmationID = UUID()
    while pendingSafetyRollbacks[confirmationID] != nil {
      confirmationID = UUID()
    }
    return confirmationID
  }

  private func omissionSummaries(
    for omissions: [PlanOmission]
  ) -> [ApplicationItemSummary] {
    omissions.map {
      ApplicationItemSummary(
        id: $0.id,
        group: $0.group,
        key: $0.key,
        status: $0.status,
        message: $0.reason
      )
    }
  }

  private func appendInfrastructureFailure(
    group: SettingGroup,
    key: String,
    message: String,
    issues: inout [ValidationIssue],
    omissions: inout [PlanOmission]
  ) {
    issues.append(
      ValidationIssue(
        group: group,
        key: key,
        severity: .error,
        isFatal: true,
        message: message
      )
    )
    omissions.append(
      PlanOmission(
        group: group,
        key: key,
        status: .skipped,
        reason: message
      )
    )
  }

  private func planContractViolation(
    _ plan: AdapterPlan,
    expectedGroup: SettingGroup
  ) -> String? {
    guard plan.group == expectedGroup else {
      return "The adapter returned a plan for a different settings group."
    }
    guard plan.operations.allSatisfy({ $0.group == expectedGroup }),
      plan.omissions.allSatisfy({ $0.group == expectedGroup }),
      plan.issues.allSatisfy({ $0.group == expectedGroup })
    else {
      return "The adapter plan contains items from a different settings group."
    }
    guard Set(plan.operations.map(\.id)).count == plan.operations.count else {
      return "The adapter plan contains duplicate operation identifiers."
    }
    return nil
  }

  private func removeOperationsWithDuplicateIDs(
    operations: inout [PlannedOperation],
    issues: inout [ValidationIssue],
    omissions: inout [PlanOmission]
  ) {
    let occurrences = Dictionary(grouping: operations, by: \.id)
    let duplicateIDs = Set(
      occurrences.compactMap { id, values in
        values.count > 1 ? id : nil
      })
    guard !duplicateIDs.isEmpty else { return }

    for operation in operations where duplicateIDs.contains(operation.id) {
      appendInfrastructureFailure(
        group: operation.group,
        key: operation.key,
        message: "The combined plan contains a duplicate operation identifier.",
        issues: &issues,
        omissions: &omissions
      )
    }
    operations.removeAll { duplicateIDs.contains($0.id) }
  }

  private func deterministicallyOrdered(
    _ operations: [PlannedOperation]
  ) -> [PlannedOperation] {
    operations.enumerated().sorted { lhs, rhs in
      let lhsIsNetwork = lhs.element.group == .network
      let rhsIsNetwork = rhs.element.group == .network
      if lhsIsNetwork != rhsIsNetwork {
        return !lhsIsNetwork
      }
      if lhs.element.risk != rhs.element.risk {
        return lhs.element.risk < rhs.element.risk
      }
      if lhs.element.group.safeApplicationOrder != rhs.element.group.safeApplicationOrder {
        return lhs.element.group.safeApplicationOrder < rhs.element.group.safeApplicationOrder
      }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }

  private func appendUnique<T: Equatable>(_ value: T, to values: inout [T]) {
    guard !values.contains(value) else { return }
    values.append(value)
  }
}
