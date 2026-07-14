import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// The single primary action shown for a profile row.
///
/// The action kind selects the matching preview contract. Constructing this
/// value only consumes cached planning facts and never performs a snapshot or
/// system mutation.
public enum PrimaryApplyActionKind: String, Equatable, Sendable {
  case normal
  case availableItems

  public var mode: ApplyMode {
    switch self {
    case .normal: .normal
    case .availableItems: .force
    }
  }

  public var localizationKey: String {
    switch self {
    case .normal: "menu.action.apply"
    case .availableItems: "menu.action.applyAvailable"
    }
  }

  public var defaultLabel: String {
    switch self {
    case .normal: "Apply…"
    case .availableItems: "Apply Available…"
    }
  }
}

public enum PrimaryApplyDisabledReason: String, Equatable, Sendable {
  case profileDisabled
  case preparing
  case readinessRefreshing
  case applying
  case transactionInProgress
  case pendingDisplayConfirmation
  case noIncludedSettings
  case alreadyMatches
  case noAvailableOperations
  case temporarilyUnavailable

  public var localizationKey: String {
    "menu.apply.disabled.\(rawValue)"
  }

  public var defaultMessage: String {
    switch self {
    case .profileDisabled: "Enable this profile to apply it."
    case .preparing: "Preparing this profile…"
    case .readinessRefreshing: "Checking whether this profile can be applied…"
    case .applying: "This profile is being applied."
    case .transactionInProgress: "Another profile action is still in progress."
    case .pendingDisplayConfirmation:
      "Confirm or revert the previous display change first."
    case .noIncludedSettings: "Include at least one setting before applying this profile."
    case .alreadyMatches: "The Mac already matches this profile."
    case .noAvailableOperations: "No available setting can be applied."
    case .temporarilyUnavailable: "This action is temporarily unavailable."
    }
  }

  public var symbolName: String {
    switch self {
    case .profileDisabled: "pause.circle"
    case .preparing, .readinessRefreshing: "arrow.clockwise"
    case .applying, .transactionInProgress: "hourglass"
    case .pendingDisplayConfirmation: "display.trianglebadge.exclamationmark"
    case .noIncludedSettings: "square.dashed"
    case .alreadyMatches: "checkmark.circle"
    case .noAvailableOperations: "exclamationmark.circle"
    case .temporarilyUnavailable: "clock"
    }
  }
}

public struct PrimaryApplyActionState: Equatable, Sendable {
  public var kind: PrimaryApplyActionKind
  public var isEnabled: Bool
  public var disabledReason: PrimaryApplyDisabledReason?
  public var usesCachedReadinessWhileRefreshing: Bool

  public init(
    kind: PrimaryApplyActionKind,
    isEnabled: Bool,
    disabledReason: PrimaryApplyDisabledReason? = nil,
    usesCachedReadinessWhileRefreshing: Bool = false
  ) {
    self.kind = kind
    self.isEnabled = isEnabled
    self.disabledReason = isEnabled ? nil : (disabledReason ?? .temporarilyUnavailable)
    self.usesCachedReadinessWhileRefreshing = usesCachedReadinessWhileRefreshing
  }

  /// Selects one state-aware primary action from cached readiness and operation counts.
  ///
  /// A refresh does not invalidate a usable cached action. Per-profile preparation,
  /// transaction locks, and pending display confirmation always prevent execution.
  public init(
    profile: DeskProfile,
    readiness: ProfileReadiness,
    normalOperationCount: Int,
    availableOperationCount: Int,
    isPreparing: Bool = false,
    isRefreshing: Bool = false,
    hasUsableCachedReadiness: Bool = false,
    isTransactionLocked: Bool = false,
    isDisplayConfirmationPending: Bool = false
  ) {
    let kind: PrimaryApplyActionKind = readiness == .partial ? .availableItems : .normal
    let usesCache = isRefreshing && hasUsableCachedReadiness

    func disabled(_ reason: PrimaryApplyDisabledReason) -> Self {
      Self(
        kind: kind,
        isEnabled: false,
        disabledReason: reason,
        usesCachedReadinessWhileRefreshing: usesCache
      )
    }

    if readiness == .applying {
      self = disabled(.applying)
      return
    }
    if isDisplayConfirmationPending {
      self = disabled(.pendingDisplayConfirmation)
      return
    }
    if isTransactionLocked {
      self = disabled(.transactionInProgress)
      return
    }
    if isPreparing {
      self = disabled(.preparing)
      return
    }
    if isRefreshing, !hasUsableCachedReadiness {
      self = disabled(.readinessRefreshing)
      return
    }
    guard profile.isEnabled else {
      self = disabled(.profileDisabled)
      return
    }
    let hasIncludedSettings = SettingGroup.safeApplicationSequence.contains {
      profile.settings.payload(for: $0) != nil
    }
    guard hasIncludedSettings else {
      self = disabled(.noIncludedSettings)
      return
    }

    switch readiness {
    case .ready, .applied:
      if normalOperationCount > 0 {
        self = Self(
          kind: .normal,
          isEnabled: true,
          usesCachedReadinessWhileRefreshing: usesCache
        )
      } else {
        self = disabled(.alreadyMatches)
      }
    case .partial:
      if availableOperationCount > 0 {
        self = Self(
          kind: .availableItems,
          isEnabled: true,
          usesCachedReadinessWhileRefreshing: usesCache
        )
      } else {
        self = disabled(.noAvailableOperations)
      }
    case .unavailable:
      self = disabled(.noAvailableOperations)
    case .failed:
      self = disabled(.temporarilyUnavailable)
    case .applying:
      self = disabled(.applying)
    }
  }

  public var mode: ApplyMode {
    kind.mode
  }

  public var localizationKey: String {
    kind.localizationKey
  }

  public var defaultLabel: String {
    kind.defaultLabel
  }
}

/// Prevents two asynchronous preparations for the same profile while allowing
/// independent rows to retain their own cached state.
public struct ProfilePreparationGate: Equatable, Sendable {
  public private(set) var activeProfileIDs: Set<UUID>

  public init(activeProfileIDs: Set<UUID> = []) {
    self.activeProfileIDs = activeProfileIDs
  }

  @discardableResult
  public mutating func begin(profileID: UUID) -> Bool {
    activeProfileIDs.insert(profileID).inserted
  }

  public mutating func end(profileID: UUID) {
    activeProfileIDs.remove(profileID)
  }
}

/// Resolves out-of-order asynchronous preparations into the most recent user
/// intent. Multiple profiles may prepare independently, but only the latest
/// accepted request may replace the single preview slot.
public struct LatestPreparationRequestTracker: Equatable, Sendable {
  public private(set) var latestRequestID: UUID?

  public init(latestRequestID: UUID? = nil) {
    self.latestRequestID = latestRequestID
  }

  public mutating func begin(requestID: UUID) {
    latestRequestID = requestID
  }

  public func shouldPresent(requestID: UUID) -> Bool {
    latestRequestID == requestID
  }
}

public enum CaptureItemDisposition: String, Equatable, Sendable {
  /// Saved and eligible to become an apply operation.
  case savedApplicable
  /// Saved for reference but deliberately excluded from application.
  case savedSnapshotOnly
  case unreadable
  case permissionRequired
  case unsupported
}

/// Sanitized capture evidence. It carries no captured value or error detail.
public struct CaptureSummaryItem: Equatable, Sendable {
  public var group: SettingGroup
  public var key: String
  public var disposition: CaptureItemDisposition

  public init(
    group: SettingGroup,
    key: String,
    disposition: CaptureItemDisposition
  ) {
    self.group = group
    self.key = key
    self.disposition = disposition
  }
}

public enum ProfileCaptureStatus: String, Equatable, Sendable {
  case complete
  case partial
  case failure

  public var localizationKey: String {
    "capture.result.\(rawValue)"
  }
}

/// Compact, value-free capture result used by the menu and settings editor.
public struct ProfileCaptureSummary: Equatable, Sendable {
  public var status: ProfileCaptureStatus
  public var savedCount: Int
  public var applicableCount: Int
  public var excludedCount: Int
  public var unreadableCount: Int
  public var permissionRequiredCount: Int
  public var unsupportedCount: Int
  public var wifiNetworkWasNotCaptured: Bool

  public init(items: [CaptureSummaryItem]) {
    applicableCount = items.count { $0.disposition == .savedApplicable }
    excludedCount = items.count { $0.disposition == .savedSnapshotOnly }
    unreadableCount = items.count { $0.disposition == .unreadable }
    permissionRequiredCount = items.count { $0.disposition == .permissionRequired }
    unsupportedCount = items.count { $0.disposition == .unsupported }
    savedCount = applicableCount + excludedCount

    let incompleteCount =
      excludedCount + unreadableCount + permissionRequiredCount + unsupportedCount
    if applicableCount == 0 {
      status = .failure
    } else if incompleteCount > 0 {
      status = .partial
    } else {
      status = .complete
    }

    wifiNetworkWasNotCaptured = items.contains { item in
      item.group == .network
        && (item.key == "wifiSSID" || item.key == "wifi.ssid")
        && item.disposition != .savedApplicable
        && item.disposition != .savedSnapshotOnly
    }
  }

  public var canCreateProfile: Bool {
    applicableCount > 0
  }

  public var omittedCount: Int {
    unreadableCount + permissionRequiredCount + unsupportedCount
  }
}

public struct ApplyOperationReference: Hashable, Sendable {
  public var group: SettingGroup
  public var key: String

  public init(group: SettingGroup, key: String) {
    self.group = group
    self.key = key
  }

  public init(_ operation: PlannedOperation) {
    self.init(group: operation.group, key: operation.key)
  }

  public init(_ omission: PlanOmission) {
    self.init(group: omission.group, key: omission.key)
  }

  public init(_ item: ApplicationItemSummary) {
    self.init(group: item.group, key: item.key)
  }
}

public enum PostApplyVerificationStatus: String, Equatable, Sendable {
  case verified
  case notVerified
}

public enum PostApplyVerificationFailureReason: String, Equatable, Sendable {
  case stillRequired
  case readBackUnavailable
}

public enum ConfirmedSafetyMessageKind: String, Equatable, Sendable {
  case kept
  case partial
  case failed
  case notVerified

  public init(status: ProfileReadiness, notVerifiedCount: Int) {
    if status == .failed {
      self = .failed
    } else if notVerifiedCount > 0 {
      self = .notVerified
    } else if status == .partial {
      self = .partial
    } else {
      self = .kept
    }
  }
}

public struct PostApplyVerificationItem: Equatable, Sendable {
  public var operation: ApplyOperationReference
  public var status: PostApplyVerificationStatus
  public var failureReason: PostApplyVerificationFailureReason?

  public init(
    operation: ApplyOperationReference,
    status: PostApplyVerificationStatus,
    failureReason: PostApplyVerificationFailureReason? = nil
  ) {
    self.operation = operation
    self.status = status
    self.failureReason = status == .verified ? nil : failureReason
  }
}

/// Pure classification of a post-apply plan. A successfully executed operation
/// that is still planned is not verified; force omissions remain separate.
public struct PostApplyVerificationResult: Equatable, Sendable {
  public var executedOperations: [PostApplyVerificationItem]
  public var intentionalOmissions: [ApplyOperationReference]
  public var unexpectedRemainingOperations: [ApplyOperationReference]

  public init(
    executedOperations: [PostApplyVerificationItem],
    intentionalOmissions: [ApplyOperationReference] = [],
    unexpectedRemainingOperations: [ApplyOperationReference] = []
  ) {
    self.executedOperations = executedOperations
    self.intentionalOmissions = intentionalOmissions
    self.unexpectedRemainingOperations = unexpectedRemainingOperations
  }

  /// Selects only operations whose applied target is still expected to be in
  /// effect. A result recorded as succeeded may have been rolled back later in
  /// the same fatal transaction, so any operation ID present in rollback
  /// results must be excluded from desired-state read-back verification.
  public static func readBackTargets(
    in result: ApplyExecutionResult
  ) -> [PlannedOperation] {
    let rollbackOperationIDs = Set(result.rollbackResults.map(\.id))
    let succeededOperationIDs = Set(
      result.itemResults.lazy
        .filter {
          $0.status == .succeeded && !rollbackOperationIDs.contains($0.id)
        }
        .map(\.id)
    )
    return result.preparation.operations.filter {
      succeededOperationIDs.contains($0.id)
    }
  }

  public static func classify(
    executedOperations: [PlannedOperation],
    remainingOperations: [PlannedOperation],
    readBackUnavailableGroups: Set<SettingGroup> = [],
    readBackUnavailableOperations: Set<ApplyOperationReference> = [],
    intentionalOmissions: [PlanOmission] = []
  ) -> Self {
    let executedReferences = executedOperations.map(ApplyOperationReference.init)
    let executedSet = Set(executedReferences)
    let remainingReferences = remainingOperations.map(ApplyOperationReference.init)
    let remainingSet = Set(remainingReferences)

    return Self(
      executedOperations: executedReferences.map { reference in
        let failureReason: PostApplyVerificationFailureReason? =
          if remainingSet.contains(reference) {
            .stillRequired
          } else if readBackUnavailableGroups.contains(reference.group)
            || readBackUnavailableOperations.contains(reference)
          {
            .readBackUnavailable
          } else {
            nil
          }
        return PostApplyVerificationItem(
          operation: reference,
          status: failureReason == nil ? .verified : .notVerified,
          failureReason: failureReason
        )
      },
      intentionalOmissions: intentionalOmissions.map(ApplyOperationReference.init),
      unexpectedRemainingOperations: remainingReferences.filter {
        !executedSet.contains($0)
      }
    )
  }

  /// Classifies a fresh plan conservatively. An absent operation proves the
  /// target only when that setting group completed capability, snapshot, and
  /// validation/plan analysis. A read failure must never be treated as success.
  public static func classify(
    executedOperations: [PlannedOperation],
    readBackPreparation: ApplyPreparation,
    intentionalOmissions: [PlanOmission] = []
  ) -> Self {
    let executedGroups = Set(executedOperations.map(\.group))
    let unavailableGroups = Set(
      executedGroups.filter { group in
        let canReadAndApply = readBackPreparation.capabilities.contains {
          $0.group == group && $0.canApply
        }
        let hasSnapshot = readBackPreparation.snapshots.contains { $0.group == group }
        let hasFatalIssue = readBackPreparation.validationIssues.contains {
          $0.group == group && $0.isFatal
        }
        let hasInfrastructureOmission = readBackPreparation.omissions.contains {
          $0.group == group
            && ["adapter", "adapter.capability", "capability", "snapshot", "validation", "plan"]
              .contains($0.key)
        }
        return !canReadAndApply || !hasSnapshot || hasFatalIssue || hasInfrastructureOmission
      })
    let executedReferences = Set(executedOperations.map(ApplyOperationReference.init))
    let unavailableOperations = Set(
      readBackPreparation.omissions.lazy
        .map(ApplyOperationReference.init)
        .filter(executedReferences.contains)
    )

    return classify(
      executedOperations: executedOperations,
      remainingOperations: readBackPreparation.operations,
      readBackUnavailableGroups: unavailableGroups,
      readBackUnavailableOperations: unavailableOperations,
      intentionalOmissions: intentionalOmissions
    )
  }

  public var notVerifiedOperations: Set<ApplyOperationReference> {
    Set(
      executedOperations.lazy
        .filter { $0.status == .notVerified }
        .map(\.operation)
    )
  }

  public var notVerifiedCount: Int {
    executedOperations.count { $0.status == .notVerified }
  }

  public func failureReason(
    for operation: ApplyOperationReference
  ) -> PostApplyVerificationFailureReason? {
    executedOperations.first { $0.operation == operation }?.failureReason
  }
}

public enum ApplyResultItemStatus: String, Equatable, Sendable {
  case succeeded
  case failed
  case skipped
  case unsupported
  case rolledBack
  case rollbackFailed
  case notVerified

  public init(_ status: ApplicationItemStatus) {
    switch status {
    case .succeeded: self = .succeeded
    case .failed: self = .failed
    case .skipped: self = .skipped
    case .unsupported: self = .unsupported
    case .rolledBack: self = .rolledBack
    case .rollbackFailed: self = .rollbackFailed
    }
  }
}

/// Value-free item state for compact and detailed result presentation.
public struct ApplyResultPresentationItem: Equatable, Sendable {
  public var operation: ApplyOperationReference
  public var status: ApplyResultItemStatus

  public init(
    operation: ApplyOperationReference,
    status: ApplyResultItemStatus
  ) {
    self.operation = operation
    self.status = status
  }

  public init(_ item: ApplicationItemSummary) {
    self.init(
      operation: ApplyOperationReference(item),
      status: ApplyResultItemStatus(item.status)
    )
  }
}

public enum ApplyResultOverallStatus: String, Equatable, Sendable {
  case success
  case partial
  case failure
  case rolledBack
  case rollbackFailed
  case notVerified

  public var profileReadiness: ProfileReadiness {
    switch self {
    case .success: .applied
    case .partial, .rolledBack, .notVerified: .partial
    case .failure, .rollbackFailed: .failed
    }
  }

  public var localizationKey: String {
    "apply.result.\(rawValue)"
  }
}

/// Produces a value-free failed result when an accepted preview cannot reach
/// execution (for example, because its profile was deleted). Every planned
/// operation is recorded as skipped so the compact card and details remain
/// truthful without implying a system mutation occurred.
public struct ApplyRequestFailureResultBuilder: Equatable, Sendable {
  public init() {}

  public func result(
    preparation: ApplyPreparation,
    completedAt: Date,
    message: String
  ) -> ApplyExecutionResult {
    ApplyExecutionResult(
      preparation: preparation,
      didExecute: false,
      completedAt: completedAt,
      status: .failed,
      itemResults: preparation.operations.map { operation in
        ApplicationItemSummary(
          id: operation.id,
          group: operation.group,
          key: operation.key,
          status: .skipped,
          message: message
        )
      }
    )
  }
}

/// Counts and overall state for the result card shown immediately after apply.
public struct ApplyResultSummary: Equatable, Sendable {
  public var profileID: UUID
  public var profileName: String
  public var appliedAt: Date
  public var status: ApplyResultOverallStatus
  public var succeededCount: Int
  public var failedCount: Int
  public var skippedCount: Int
  public var unsupportedCount: Int
  public var rolledBackCount: Int
  public var rollbackFailedCount: Int
  public var notVerifiedCount: Int

  public init(
    profileID: UUID,
    profileName: String,
    appliedAt: Date,
    items: [ApplyResultPresentationItem]
  ) {
    self.profileID = profileID
    self.profileName = profileName
    self.appliedAt = appliedAt
    succeededCount = items.count { $0.status == .succeeded }
    failedCount = items.count { $0.status == .failed }
    skippedCount = items.count { $0.status == .skipped }
    unsupportedCount = items.count { $0.status == .unsupported }
    rolledBackCount = items.count { $0.status == .rolledBack }
    rollbackFailedCount = items.count { $0.status == .rollbackFailed }
    notVerifiedCount = items.count { $0.status == .notVerified }
    status = Self.overallStatus(
      succeeded: succeededCount,
      failed: failedCount,
      skipped: skippedCount,
      unsupported: unsupportedCount,
      rolledBack: rolledBackCount,
      rollbackFailed: rollbackFailedCount,
      notVerified: notVerifiedCount
    )
  }

  public init(
    profileID: UUID,
    profileName: String,
    appliedAt: Date,
    itemResults: [ApplicationItemSummary],
    rollbackResults: [ApplicationItemSummary] = [],
    verification: PostApplyVerificationResult? = nil
  ) {
    let notVerified = verification?.notVerifiedOperations ?? []
    let rollbackByID = Dictionary(
      rollbackResults.map { ($0.id, $0) },
      uniquingKeysWith: { _, latest in latest }
    )
    var replacedIDs = Set<UUID>()
    var items = itemResults.map { item in
      var presentation = ApplyResultPresentationItem(item)
      if presentation.status == .succeeded,
        let rollback = rollbackByID[item.id]
      {
        presentation = ApplyResultPresentationItem(rollback)
        replacedIDs.insert(item.id)
      } else if presentation.status == .succeeded,
        notVerified.contains(presentation.operation)
      {
        presentation.status = .notVerified
      }
      return presentation
    }
    items.append(
      contentsOf: rollbackResults.lazy
        .filter { !replacedIDs.contains($0.id) }
        .map(ApplyResultPresentationItem.init)
    )
    self.init(
      profileID: profileID,
      profileName: profileName,
      appliedAt: appliedAt,
      items: items
    )
  }

  public var totalCount: Int {
    succeededCount + failedCount + skippedCount + unsupportedCount
      + rolledBackCount + rollbackFailedCount + notVerifiedCount
  }

  private static func overallStatus(
    succeeded: Int,
    failed: Int,
    skipped: Int,
    unsupported: Int,
    rolledBack: Int,
    rollbackFailed: Int,
    notVerified: Int
  ) -> ApplyResultOverallStatus {
    if rollbackFailed > 0 { return .rollbackFailed }

    if failed > 0 {
      let otherOutcomes = succeeded + notVerified
      return otherOutcomes > 0 ? .partial : .failure
    }

    if notVerified > 0 {
      let verifiedOrOmitted = succeeded + skipped + unsupported + rolledBack
      return verifiedOrOmitted > 0 ? .partial : .notVerified
    }

    if rolledBack > 0 {
      let nonRollbackOutcomes = succeeded
      return nonRollbackOutcomes > 0 ? .partial : .rolledBack
    }

    if skipped + unsupported > 0 {
      return succeeded > 0 ? .partial : .failure
    }

    return succeeded > 0 ? .success : .failure
  }
}
