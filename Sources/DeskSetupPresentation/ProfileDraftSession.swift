import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// A destination requested while editing a profile.
///
/// `noProfile` is distinct from the absence of a pending request, allowing the
/// presentation layer to protect a dirty draft when the selection is cleared.
public enum ProfileSelectionTarget: Equatable, Sendable {
  case noProfile
  case profile(DeskProfile)

  public var profile: DeskProfile? {
    switch self {
    case .noProfile:
      nil
    case .profile(let profile):
      profile
    }
  }

  public var profileID: UUID? {
    profile?.id
  }
}

public enum ProfileSelectionRequestResult: Equatable, Sendable {
  case unchanged
  case selected(ProfileSelectionTarget)
  case requiresDecision(ProfileSelectionTarget)
}

public enum ProfileDraftSelectionDecision: Equatable, Sendable {
  case save
  case discard
  case cancel
}

public enum ProfileDraftSelectionResolution: Equatable, Sendable {
  case noPendingSelection
  case cancelled
  case selected(ProfileSelectionTarget)
  case saveRequired(candidate: DeskProfile, thenSelect: ProfileSelectionTarget)
}

public enum ProfileDraftSaveCompletion: Equatable, Sendable {
  case rejected(expectedProfileID: UUID?, actualProfileID: UUID)
  case saved
  case savedAndSelected(ProfileSelectionTarget)
}

/// Pure presentation state for editing one profile and safely changing selection.
///
/// The draft contains user-editable values. Identity, timestamps, and the last
/// application result are owned by persistence/runtime flows and are refreshed
/// from the latest saved profile before a save candidate is returned.
public struct ProfileDraftSession: Equatable, Sendable {
  public private(set) var savedProfile: DeskProfile?
  public private(set) var draft: DeskProfile?
  public private(set) var pendingSelection: ProfileSelectionTarget?

  public init(selectedProfile: DeskProfile? = nil) {
    self.savedProfile = selectedProfile
    self.draft = selectedProfile
    self.pendingSelection = nil
  }

  public var selectedProfileID: UUID? {
    savedProfile?.id
  }

  public var selection: ProfileSelectionTarget {
    savedProfile.map(ProfileSelectionTarget.profile) ?? .noProfile
  }

  /// Metadata-only changes never make the editor dirty.
  public var isDirty: Bool {
    switch (savedProfile, draft) {
    case (nil, nil):
      false
    case (.some(let saved), .some(let draft)):
      !Self.hasEqualUserEditableValues(saved, draft)
    case (.some, nil), (nil, .some):
      true
    }
  }

  /// Replaces the editable draft when it belongs to the selected profile.
  ///
  /// Non-user metadata supplied by the caller is ignored in favor of the latest
  /// saved metadata.
  @discardableResult
  public mutating func replaceDraft(_ replacement: DeskProfile) -> Bool {
    guard let savedProfile, replacement.id == savedProfile.id else {
      return false
    }

    draft = Self.mergingUserEditableValues(from: replacement, metadataFrom: savedProfile)
    return true
  }

  /// Mutates a local copy of the current draft and installs it if still valid.
  @discardableResult
  public mutating func updateDraft(_ update: (inout DeskProfile) -> Void) -> Bool {
    guard var draft else {
      return false
    }
    update(&draft)
    return replaceDraft(draft)
  }

  /// Replaces only the settings captured by a read-only snapshot.
  ///
  /// The expected identifier prevents a late asynchronous capture from updating
  /// a different profile after the user changes selection. All other unsaved
  /// fields and the latest runtime metadata are preserved.
  @discardableResult
  public mutating func replaceSettingsFromSnapshot(
    _ settings: ProfileSettings,
    expectedProfileID: UUID
  ) -> Bool {
    guard draft?.id == expectedProfileID else { return false }
    return updateDraft { $0.settings = settings }
  }

  /// Restores the latest saved values and cancels any pending selection request.
  public mutating func revertDraft() {
    draft = savedProfile
    pendingSelection = nil
  }

  /// Produces a profile suitable for persistence without clobbering runtime metadata.
  public func saveCandidate() -> DeskProfile? {
    guard let draft else {
      return nil
    }
    guard let savedProfile, savedProfile.id == draft.id else {
      return draft
    }
    return Self.mergingUserEditableValues(from: draft, metadataFrom: savedProfile)
  }

  /// Requests a new profile selection.
  ///
  /// Clean drafts transition immediately. Dirty drafts retain the current
  /// selection and expose a pending target until the caller resolves it.
  @discardableResult
  public mutating func requestSelection(
    _ requestedProfile: DeskProfile?
  ) -> ProfileSelectionRequestResult {
    let target = requestedProfile.map(ProfileSelectionTarget.profile) ?? .noProfile

    if target.profileID == selectedProfileID {
      if let requestedProfile {
        synchronizeProfile(requestedProfile)
      }
      pendingSelection = nil
      return .unchanged
    }

    guard isDirty else {
      activate(target)
      return .selected(target)
    }

    pendingSelection = target
    return .requiresDecision(target)
  }

  /// Resolves the current selection request.
  ///
  /// Saving is intentionally a two-step transition. The draft and pending
  /// selection remain intact until `completeSave(with:)` receives the profile
  /// returned by persistence, so a failed save cannot silently lose edits.
  @discardableResult
  public mutating func resolvePendingSelection(
    _ decision: ProfileDraftSelectionDecision
  ) -> ProfileDraftSelectionResolution {
    guard let pendingSelection else {
      return .noPendingSelection
    }

    switch decision {
    case .cancel:
      self.pendingSelection = nil
      return .cancelled

    case .discard:
      activate(pendingSelection)
      return .selected(pendingSelection)

    case .save:
      guard let candidate = saveCandidate() else {
        return .noPendingSelection
      }
      return .saveRequired(candidate: candidate, thenSelect: pendingSelection)
    }
  }

  /// Commits a successful persistence result and finishes a pending save transition.
  ///
  /// A mismatched result is rejected without changing the draft or pending target.
  @discardableResult
  public mutating func completeSave(
    with persistedProfile: DeskProfile
  ) -> ProfileDraftSaveCompletion {
    guard let savedProfile, persistedProfile.id == savedProfile.id else {
      return .rejected(
        expectedProfileID: savedProfile?.id,
        actualProfileID: persistedProfile.id
      )
    }

    if let pendingSelection {
      activate(pendingSelection)
      return .savedAndSelected(pendingSelection)
    }

    self.savedProfile = persistedProfile
    draft = persistedProfile
    return .saved
  }

  /// Incorporates a fresh profile value supplied by persistence/runtime state.
  ///
  /// Dirty user edits are retained for the selected profile while metadata is
  /// refreshed. A clean draft follows the fresh saved value. Pending targets are
  /// also refreshed so discard/save transitions do not activate stale snapshots.
  @discardableResult
  public mutating func synchronizeProfile(_ latestProfile: DeskProfile) -> Bool {
    var didSynchronize = false

    if savedProfile?.id == latestProfile.id {
      let hadLocalEdits = isDirty
      let currentDraft = draft
      savedProfile = latestProfile

      if hadLocalEdits, let currentDraft {
        draft = Self.mergingUserEditableValues(
          from: currentDraft,
          metadataFrom: latestProfile
        )
      } else {
        draft = latestProfile
      }
      didSynchronize = true
    }

    if case .profile(let pendingProfile)? = pendingSelection,
      pendingProfile.id == latestProfile.id
    {
      pendingSelection = .profile(latestProfile)
      didSynchronize = true
    }

    return didSynchronize
  }

  private mutating func activate(_ target: ProfileSelectionTarget) {
    savedProfile = target.profile
    draft = target.profile
    pendingSelection = nil
  }

  private static func hasEqualUserEditableValues(
    _ lhs: DeskProfile,
    _ rhs: DeskProfile
  ) -> Bool {
    lhs.id == rhs.id
      && lhs.name == rhs.name
      && lhs.profileDescription == rhs.profileDescription
      && lhs.symbolName == rhs.symbolName
      && lhs.isEnabled == rhs.isEnabled
      && lhs.settings == rhs.settings
      && lhs.conditions == rhs.conditions
  }

  private static func mergingUserEditableValues(
    from draft: DeskProfile,
    metadataFrom savedProfile: DeskProfile
  ) -> DeskProfile {
    var candidate = draft
    candidate.id = savedProfile.id
    candidate.createdAt = savedProfile.createdAt
    candidate.updatedAt = savedProfile.updatedAt
    candidate.lastApplication = savedProfile.lastApplication
    return candidate
  }
}
