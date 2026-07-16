import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupPresentation

@Suite("Apply workflow presentation")
struct ApplyWorkflowPresentationTests {
  @Test("ready operations select the normal primary action")
  func readyNormalAction() {
    let state = PrimaryApplyActionState(
      profile: profileWithIncludedSetting(),
      readiness: .ready,
      normalOperationCount: 2,
      availableOperationCount: 2
    )

    #expect(state.kind == .normal)
    #expect(state.mode == .normal)
    #expect(state.isEnabled)
    #expect(state.defaultLabel == "Apply…")
  }

  @Test("partial operations select available-items in the same primary slot")
  func partialAvailableItemsAction() {
    let state = PrimaryApplyActionState(
      profile: profileWithIncludedSetting(),
      readiness: .partial,
      normalOperationCount: 0,
      availableOperationCount: 1
    )

    #expect(state.kind == .availableItems)
    #expect(state.mode == .force)
    #expect(state.isEnabled)
    #expect(state.defaultLabel == "Apply Available…")
  }

  @Test("zero operations distinguish an already matching Mac from no available work")
  func zeroOperationReasons() {
    let matching = PrimaryApplyActionState(
      profile: profileWithIncludedSetting(),
      readiness: .ready,
      normalOperationCount: 0,
      availableOperationCount: 0
    )
    let partial = PrimaryApplyActionState(
      profile: profileWithIncludedSetting(),
      readiness: .partial,
      normalOperationCount: 0,
      availableOperationCount: 0
    )

    #expect(!matching.isEnabled)
    #expect(matching.disabledReason == .alreadyMatches)
    #expect(!partial.isEnabled)
    #expect(partial.kind == .availableItems)
    #expect(partial.disabledReason == .noAvailableOperations)
  }

  @Test("refresh preserves a usable cached action but preparing blocks duplicate requests")
  func cachedRefreshAndPreparing() {
    let cached = PrimaryApplyActionState(
      profile: profileWithIncludedSetting(),
      readiness: .partial,
      normalOperationCount: 0,
      availableOperationCount: 1,
      isRefreshing: true,
      hasUsableCachedReadiness: true
    )
    let uncached = PrimaryApplyActionState(
      profile: profileWithIncludedSetting(),
      readiness: .partial,
      normalOperationCount: 0,
      availableOperationCount: 1,
      isRefreshing: true
    )
    let duplicate = PrimaryApplyActionState(
      profile: profileWithIncludedSetting(),
      readiness: .partial,
      normalOperationCount: 0,
      availableOperationCount: 1,
      isPreparing: true,
      isRefreshing: true,
      hasUsableCachedReadiness: true
    )

    #expect(cached.isEnabled)
    #expect(cached.usesCachedReadinessWhileRefreshing)
    #expect(uncached.disabledReason == .readinessRefreshing)
    #expect(duplicate.disabledReason == .preparing)
  }

  @Test("the preparation gate accepts only one in-flight request per profile")
  func preparationGateSuppressesDuplicateRequests() {
    var gate = ProfilePreparationGate()

    let firstRequest = gate.begin(profileID: profileID)
    let duplicateRequest = gate.begin(profileID: profileID)
    #expect(firstRequest)
    #expect(!duplicateRequest)
    #expect(gate.activeProfileIDs == Set([profileID]))
    gate.end(profileID: profileID)
    let requestAfterCompletion = gate.begin(profileID: profileID)
    #expect(requestAfterCompletion)
  }

  @Test("out-of-order cross-profile preparation retains the latest user intent")
  func latestPreparationRequestWins() {
    let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let latestID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    var tracker = LatestPreparationRequestTracker()

    tracker.begin(requestID: firstID)
    tracker.begin(requestID: latestID)

    #expect(!tracker.shouldPresent(requestID: firstID))
    #expect(tracker.shouldPresent(requestID: latestID))
  }

  @Test("force preview keeps a display operation beside a DNS omission")
  func forcePreviewOperationAndOmission() {
    let display = operation(group: .display, key: "display.atomic-configuration")
    let dns = PlanOmission(
      group: .network,
      key: "network.dns",
      status: .unsupported,
      reason: "Snapshot only"
    )
    let preparation = ApplyPreparation(
      profileID: profileID,
      mode: .force,
      preparedAt: appliedAt,
      includedGroups: [.display, .network],
      capabilities: [],
      snapshots: [],
      validationIssues: [],
      operations: [display],
      omissions: [dns],
      readiness: ReadinessEvaluation(
        status: .partial,
        applicableGroups: [.display],
        unavailableGroups: [.network],
        reasons: ["Synthetic DNS omission"]
      ),
      rejectionReasons: []
    )

    #expect(preparation.canExecute)
    #expect(preparation.operations.map(\.key) == ["display.atomic-configuration"])
    #expect(preparation.omissions.map(\.key) == ["network.dns"])
  }

  @Test("protected confirmation keeps its specific reason while the transaction is locked")
  func displayConfirmationReasonPrecedesGenericLock() {
    let state = PrimaryApplyActionState(
      profile: profileWithIncludedSetting(),
      readiness: .ready,
      normalOperationCount: 1,
      availableOperationCount: 1,
      isTransactionLocked: true,
      isSafetyConfirmationPending: true
    )

    #expect(!state.isEnabled)
    #expect(state.disabledReason == .pendingSafetyConfirmation)
  }

  @Test("capture summary distinguishes complete partial and unusable captures")
  func captureSummaryStates() {
    let complete = ProfileCaptureSummary(items: [
      .init(group: .audio, key: "outputVolume", disposition: .savedApplicable),
      .init(group: .input, key: "pointerSpeed", disposition: .savedApplicable),
    ])
    let partial = ProfileCaptureSummary(items: [
      .init(group: .audio, key: "outputVolume", disposition: .savedApplicable),
      .init(group: .network, key: "dnsServers", disposition: .savedSnapshotOnly),
      .init(group: .network, key: "wifiSSID", disposition: .permissionRequired),
      .init(group: .display, key: "rotationDegrees", disposition: .unsupported),
      .init(group: .input, key: "keyRepeatInterval", disposition: .unreadable),
    ])
    let unusable = ProfileCaptureSummary(items: [
      .init(group: .network, key: "wifiSSID", disposition: .permissionRequired),
      .init(group: .network, key: "dnsServers", disposition: .savedSnapshotOnly),
    ])

    #expect(complete.status == .complete)
    #expect(complete.savedCount == 2)
    #expect(complete.canCreateProfile)
    #expect(partial.status == .partial)
    #expect(partial.savedCount == 2)
    #expect(partial.applicableCount == 1)
    #expect(partial.excludedCount == 1)
    #expect(partial.unreadableCount == 1)
    #expect(partial.permissionRequiredCount == 1)
    #expect(partial.unsupportedCount == 1)
    #expect(partial.wifiNetworkWasNotCaptured)
    #expect(unusable.status == .failure)
    #expect(!unusable.canCreateProfile)
  }

  @Test("remaining executed operations are not verified while force omissions stay separate")
  func postApplyClassification() {
    let display = operation(group: .display, key: "mode")
    let audio = operation(group: .audio, key: "outputVolume")
    let newlyNeeded = operation(group: .input, key: "pointerSpeed")
    let dns = PlanOmission(
      group: .network,
      key: "dnsServers",
      status: .unsupported,
      reason: "Snapshot only"
    )

    let result = PostApplyVerificationResult.classify(
      executedOperations: [display, audio],
      remainingOperations: [display, newlyNeeded],
      intentionalOmissions: [dns]
    )

    #expect(
      result.executedOperations == [
        .init(
          operation: .init(display),
          status: .notVerified,
          failureReason: .stillRequired
        ),
        .init(operation: .init(audio), status: .verified),
      ]
    )
    #expect(result.intentionalOmissions == [.init(dns)])
    #expect(result.unexpectedRemainingOperations == [.init(newlyNeeded)])
    #expect(result.notVerifiedCount == 1)
  }

  @Test("an unavailable fresh read-back never verifies an absent operation")
  func unavailableReadBackIsNotVerified() {
    let display = operation(group: .display, key: "mode")
    let readBack = ApplyPreparation(
      profileID: profileID,
      mode: .normal,
      preparedAt: appliedAt,
      includedGroups: [.display],
      capabilities: [
        AdapterCapability(group: .display, state: .supported, reason: "Synthetic")
      ],
      snapshots: [],
      validationIssues: [
        ValidationIssue(
          group: .display,
          key: "snapshot",
          severity: .error,
          isFatal: true,
          message: "Synthetic read failure"
        )
      ],
      operations: [],
      omissions: [],
      readiness: ReadinessEvaluation(
        status: .unavailable,
        applicableGroups: [],
        unavailableGroups: [.display],
        reasons: ["Synthetic read failure"]
      ),
      rejectionReasons: [.fatalValidationIssues]
    )

    let result = PostApplyVerificationResult.classify(
      executedOperations: [display],
      readBackPreparation: readBack
    )

    #expect(result.notVerifiedCount == 1)
    #expect(result.executedOperations.first?.failureReason == .readBackUnavailable)
  }

  @Test("a fresh omission for the executed item is not treated as verification")
  func readBackOmissionIsNotVerified() {
    let display = operation(group: .display, key: "mode")
    let readBack = ApplyPreparation(
      profileID: profileID,
      mode: .force,
      preparedAt: appliedAt,
      includedGroups: [.display],
      capabilities: [
        AdapterCapability(group: .display, state: .supported, reason: "Synthetic")
      ],
      snapshots: [
        AdapterSnapshot(group: .display, capturedAt: appliedAt, payload: nil, items: [])
      ],
      validationIssues: [],
      operations: [],
      omissions: [
        PlanOmission(
          group: .display,
          key: "mode",
          status: .skipped,
          reason: "Synthetic read-back omission"
        )
      ],
      readiness: ReadinessEvaluation(
        status: .partial,
        applicableGroups: [],
        unavailableGroups: [.display],
        reasons: ["Synthetic omission"]
      ),
      rejectionReasons: [.noOperations]
    )

    let result = PostApplyVerificationResult.classify(
      executedOperations: [display],
      readBackPreparation: readBack
    )

    #expect(result.notVerifiedCount == 1)
    #expect(result.executedOperations.first?.failureReason == .readBackUnavailable)
  }

  @Test("a succeeded operation rolled back after a fatal failure is not read back as applied")
  func fatalRollbackIsExcludedFromReadBackTargets() {
    let appliedID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    let failedID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    let applied = PlannedOperation(
      id: appliedID,
      group: .audio,
      key: "outputVolume",
      summary: "Apply output volume"
    )
    let failed = PlannedOperation(
      id: failedID,
      group: .input,
      key: "pointerSpeed",
      summary: "Apply pointer speed",
      isFatalOnFailure: true
    )
    let preparation = ApplyPreparation(
      profileID: profileID,
      mode: .normal,
      preparedAt: appliedAt,
      includedGroups: [.audio, .input],
      capabilities: [],
      snapshots: [],
      validationIssues: [],
      operations: [applied, failed],
      omissions: [],
      readiness: ReadinessEvaluation(
        status: .ready,
        applicableGroups: [.audio, .input],
        unavailableGroups: [],
        reasons: []
      ),
      rejectionReasons: []
    )
    let result = ApplyExecutionResult(
      preparation: preparation,
      didExecute: true,
      completedAt: appliedAt,
      status: .failed,
      itemResults: [
        ApplicationItemSummary(
          id: appliedID,
          group: .audio,
          key: "outputVolume",
          status: .succeeded,
          message: "Applied before fatal failure"
        ),
        ApplicationItemSummary(
          id: failedID,
          group: .input,
          key: "pointerSpeed",
          status: .failed,
          message: "Fatal failure"
        ),
      ],
      rollbackResults: [
        ApplicationItemSummary(
          id: appliedID,
          group: .audio,
          key: "outputVolume",
          status: .rolledBack,
          message: "Restored after fatal failure"
        )
      ],
      fatalOperationID: failedID
    )

    let readBackTargets = PostApplyVerificationResult.readBackTargets(in: result)
    let verification = PostApplyVerificationResult.classify(
      executedOperations: readBackTargets,
      remainingOperations: [applied]
    )
    let summary = ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: appliedAt,
      itemResults: result.itemResults,
      rollbackResults: result.rollbackResults,
      verification: verification
    )

    #expect(readBackTargets.isEmpty)
    #expect(verification.notVerifiedCount == 0)
    #expect(summary.notVerifiedCount == 0)
    #expect(summary.rolledBackCount == 1)
    #expect(summary.failedCount == 1)
    #expect(summary.status == .failure)
  }

  @Test("confirmed display messaging preserves specific failure and read-back outcomes")
  func confirmedSafetyMessageClassification() {
    #expect(
      ConfirmedSafetyMessageKind(status: .applied, notVerifiedCount: 0) == .kept
    )
    #expect(
      ConfirmedSafetyMessageKind(status: .partial, notVerifiedCount: 0) == .partial
    )
    #expect(
      ConfirmedSafetyMessageKind(status: .partial, notVerifiedCount: 1) == .notVerified
    )
    #expect(
      ConfirmedSafetyMessageKind(status: .failed, notVerifiedCount: 1) == .failed
    )
  }

  @Test("compact result reconciles not-verified operations without changing force omissions")
  func reconciledCompactResult() {
    let display = operation(group: .display, key: "mode")
    let verification = PostApplyVerificationResult.classify(
      executedOperations: [display],
      remainingOperations: [display],
      intentionalOmissions: []
    )
    let items = [
      ApplicationItemSummary(
        group: .display,
        key: "mode",
        status: .succeeded,
        message: "Accepted"
      ),
      ApplicationItemSummary(
        group: .network,
        key: "dnsServers",
        status: .unsupported,
        message: "Snapshot only"
      ),
    ]

    let summary = ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: appliedAt,
      itemResults: items,
      verification: verification
    )

    #expect(summary.status == .partial)
    #expect(summary.succeededCount == 0)
    #expect(summary.notVerifiedCount == 1)
    #expect(summary.unsupportedCount == 1)
    #expect(summary.totalCount == 2)
  }

  @Test("compact result distinguishes success partial failure rollback and not verified")
  func compactResultStatuses() {
    #expect(summary(.succeeded).status == .success)
    #expect(summary(.failed).status == .failure)
    #expect(summary(.rolledBack).status == .rolledBack)
    #expect(summary(.rollbackFailed).status == .rollbackFailed)
    #expect(summary(.notVerified).status == .notVerified)

    let partial = ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: appliedAt,
      items: [item(.succeeded), item(.failed)]
    )
    #expect(partial.status == .partial)

    let availableItems = ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: appliedAt,
      items: [item(.succeeded), item(.unsupported)]
    )
    #expect(availableItems.status == .partial)
    #expect(availableItems.status.profileReadiness == .partial)
  }

  @Test("a removed preview profile produces a non-executed failure card")
  func removedProfileProducesFailureResult() {
    let planned = operation(group: .audio, key: "audio.output-volume")
    let preparation = ApplyPreparation(
      profileID: profileID,
      mode: .normal,
      preparedAt: appliedAt,
      includedGroups: [.audio],
      capabilities: [],
      snapshots: [],
      validationIssues: [],
      operations: [planned],
      omissions: [],
      readiness: ReadinessEvaluation(
        status: .ready,
        applicableGroups: [.audio],
        unavailableGroups: [],
        reasons: []
      ),
      rejectionReasons: []
    )
    let result = ApplyRequestFailureResultBuilder().result(
      preparation: preparation,
      completedAt: appliedAt,
      message: "Synthetic request ended"
    )
    let summary = ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: result.completedAt,
      itemResults: result.itemResults
    )

    #expect(!result.didExecute)
    #expect(result.status == .failed)
    #expect(result.itemResults.map(\.status) == [.skipped])
    #expect(summary.status == .failure)
    #expect(summary.skippedCount == 1)
  }

  @Test("a succeeded operation replaced by rollback is counted once as rolled back")
  func rollbackReconcilesSucceededOperation() {
    let operationID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let applied = ApplicationItemSummary(
      id: operationID,
      group: .display,
      key: "display.atomic-configuration",
      status: .succeeded,
      message: "Applied"
    )
    let rollback = ApplicationItemSummary(
      id: operationID,
      group: .display,
      key: "display.atomic-configuration",
      status: .rolledBack,
      message: "Restored"
    )

    let summary = ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: appliedAt,
      itemResults: [applied],
      rollbackResults: [rollback]
    )

    #expect(summary.status == .rolledBack)
    #expect(summary.succeededCount == 0)
    #expect(summary.rolledBackCount == 1)
    #expect(summary.totalCount == 1)
  }

  @Test("rollback reconciliation uses operation IDs instead of shared group keys")
  func rollbackReconciliationUsesIDs() {
    let firstID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let secondID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let items = [firstID, secondID].map {
      ApplicationItemSummary(
        id: $0,
        group: .display,
        key: "display.atomic-configuration",
        status: .succeeded,
        message: "Applied"
      )
    }
    let rollback = ApplicationItemSummary(
      id: firstID,
      group: .display,
      key: "display.atomic-configuration",
      status: .rolledBack,
      message: "Restored"
    )

    let summary = ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: appliedAt,
      itemResults: items,
      rollbackResults: [rollback]
    )

    #expect(summary.status == .partial)
    #expect(summary.status.profileReadiness == .partial)
    #expect(summary.succeededCount == 1)
    #expect(summary.rolledBackCount == 1)
    #expect(summary.totalCount == 2)
  }

  @Test("failed work followed by successful rollback remains an apply failure")
  func failedAndRolledBackIsFailure() {
    let summary = ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: appliedAt,
      items: [item(.failed), item(.rolledBack)]
    )

    #expect(summary.status == .failure)
    #expect(summary.status.profileReadiness == .failed)
  }

  @Test("workflow values satisfy Sendable contracts")
  func sendableContracts() {
    requireSendable(
      PrimaryApplyActionState(
        profile: profileWithIncludedSetting(),
        readiness: .ready,
        normalOperationCount: 1,
        availableOperationCount: 1
      )
    )
    requireSendable(ProfileCaptureSummary(items: []))
    requireSendable(
      PostApplyVerificationResult(
        executedOperations: [],
        intentionalOmissions: []
      )
    )
    requireSendable(summary(.succeeded))
  }

  private func profileWithIncludedSetting() -> DeskProfile {
    DeskProfile(
      id: profileID,
      name: "Synthetic profile",
      settings: ProfileSettings(
        audio: .init(
          value: .init(outputVolume: .init(value: 0.5))
        )
      )
    )
  }

  private func operation(group: SettingGroup, key: String) -> PlannedOperation {
    PlannedOperation(group: group, key: key, summary: "Synthetic operation")
  }

  private func item(_ status: ApplyResultItemStatus) -> ApplyResultPresentationItem {
    ApplyResultPresentationItem(
      operation: .init(group: .audio, key: "outputVolume"),
      status: status
    )
  }

  private func summary(_ status: ApplyResultItemStatus) -> ApplyResultSummary {
    ApplyResultSummary(
      profileID: profileID,
      profileName: "Synthetic profile",
      appliedAt: appliedAt,
      items: [item(status)]
    )
  }

  private func requireSendable<T: Sendable>(_ value: T) {
    _ = value
  }

  private var profileID: UUID {
    UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  }

  private var appliedAt: Date {
    Date(timeIntervalSince1970: 1_234)
  }
}
