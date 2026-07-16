import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// Deterministic decision used before a menu apply request is allowed to build
/// a plan from persisted profile data.
public enum DirtyApplyProtectionDecision: Equatable, Sendable {
  /// No unsaved draft can be lost or bypassed.
  case applyNow

  /// The target profile itself has unsaved values. It must be saved before a
  /// plan is prepared so the persisted and previewed values are identical.
  case saveTargetBeforeApply

  /// A different profile has unsaved values. The caller must offer an explicit
  /// save, discard, or cancel decision before changing selection and applying.
  case resolveOtherDraft(openProfileID: UUID)

  /// A previous draft-selection decision is still unresolved.
  case blockedByPendingSelection

  public static func evaluate(
    targetProfileID: UUID,
    openDraftProfileID: UUID?,
    isDraftDirty: Bool,
    hasPendingSelection: Bool
  ) -> Self {
    guard !hasPendingSelection else {
      return .blockedByPendingSelection
    }
    guard isDraftDirty, let openDraftProfileID else {
      return .applyNow
    }
    if openDraftProfileID == targetProfileID {
      return .saveTargetBeforeApply
    }
    return .resolveOtherDraft(openProfileID: openDraftProfileID)
  }
}

/// One-shot continuation for an Apply request that is waiting for a draft to
/// be persisted. The only transition that can emit preparation work is a
/// matching successful save completion.
public struct DirtyApplySaveCoordinator: Equatable, Sendable {
  public enum Destination: Equatable, Sendable {
    case persistedTarget
    case selectedTarget(profileID: UUID)
  }

  public enum Event: Equatable, Sendable {
    case saveSucceeded(profile: DeskProfile, completion: ProfileDraftSaveCompletion)
    case saveRejected
    case cancelled
  }

  public enum Effect: Equatable, Sendable {
    case none
    case prepare(profile: DeskProfile, mode: ApplyMode)
    case selectAndPrepare(profileID: UUID, mode: ApplyMode)
  }

  public let targetProfileID: UUID
  public let mode: ApplyMode
  public let destination: Destination
  public private(set) var isPending = true

  public init(
    targetProfileID: UUID,
    mode: ApplyMode,
    destination: Destination
  ) {
    self.targetProfileID = targetProfileID
    self.mode = mode
    self.destination = destination
  }

  public mutating func handle(_ event: Event) -> Effect {
    guard isPending else { return .none }
    isPending = false

    switch (destination, event) {
    case (
      .persistedTarget,
      .saveSucceeded(let profile, .saved)
    ) where profile.id == targetProfileID:
      return .prepare(profile: profile, mode: mode)

    case (
      .selectedTarget(let expectedProfileID),
      .saveSucceeded(_, .savedAndSelected(let target))
    ) where expectedProfileID == targetProfileID && target.profileID == targetProfileID:
      return .selectAndPrepare(profileID: targetProfileID, mode: mode)

    case (_, .saveSucceeded), (_, .saveRejected), (_, .cancelled):
      return .none
    }
  }
}

/// Updates the target value for the global primary-display option without
/// coupling that value edit to the separate inclusion switches.
public enum DisplayPrimarySelectionEditor {
  public static func selecting(
    _ selectedID: UUID,
    in displays: [DisplayTargetSettings]
  ) -> [DisplayTargetSettings] {
    var updated = displays
    for index in updated.indices {
      updated[index].isPrimary.value = updated[index].id == selectedID
    }
    return updated
  }
}
