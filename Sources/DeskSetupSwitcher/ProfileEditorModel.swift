import Combine
import Foundation
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

enum ProfileEditorActivity: Equatable {
  case saved
  case changed
  case saving
  case capturing
  case message(String)
  case error(String)

  var isBusy: Bool {
    switch self {
    case .saving, .capturing:
      true
    case .saved, .changed, .message, .error:
      false
    }
  }
}

/// Process-lifetime editor state shared by every Settings window presentation.
/// Keeping the draft above the window scene prevents closing and reopening
/// Settings from silently discarding unsaved profile edits.
@MainActor
final class ProfileEditorModel: ObservableObject {
  @Published private(set) var session = ProfileDraftSession()
  @Published private(set) var activity: ProfileEditorActivity = .saved

  var draft: DeskProfile? {
    session.draft
  }

  var selectedProfileID: UUID? {
    session.selectedProfileID
  }

  var isDirty: Bool {
    session.isDirty
  }

  func initialize(profiles: [DeskProfile], preferredProfileID: UUID?) {
    guard session.savedProfile == nil, session.draft == nil else {
      synchronize(profiles: profiles, preferredProfileID: preferredProfileID)
      return
    }
    session = ProfileDraftSession(
      selectedProfile: preferredProfile(in: profiles, id: preferredProfileID)
    )
    setActivity(.saved)
  }

  func synchronize(profiles: [DeskProfile], preferredProfileID: UUID?) {
    if let selectedID = session.selectedProfileID,
      let latest = profiles.first(where: { $0.id == selectedID })
    {
      mutateSession { $0.synchronizeProfile(latest) }
    }

    if case .profile(let pending)? = session.pendingSelection,
      let latest = profiles.first(where: { $0.id == pending.id })
    {
      mutateSession { $0.synchronizeProfile(latest) }
    }

    let preferred = preferredProfile(in: profiles, id: preferredProfileID)
    let selectedStillExists =
      session.selectedProfileID.map { selectedID in
        profiles.contains { $0.id == selectedID }
      } ?? (session.draft == nil)

    if !activity.isBusy,
      !session.isDirty,
      !selectedStillExists || session.selectedProfileID != preferred?.id
    {
      mutateSession { $0.requestSelection(preferred) }
    }

    refreshIdleActivity()
  }

  @discardableResult
  func replaceDraft(_ draft: DeskProfile) -> Bool {
    let replaced = mutateSession { $0.replaceDraft(draft) }
    if replaced {
      refreshIdleActivity(force: true)
    }
    return replaced
  }

  @discardableResult
  func updateDraft(_ update: (inout DeskProfile) -> Void) -> Bool {
    let updated = mutateSession { $0.updateDraft(update) }
    if updated {
      refreshIdleActivity(force: true)
    }
    return updated
  }

  @discardableResult
  func replaceSettingsFromSnapshot(
    _ settings: ProfileSettings,
    expectedProfileID: UUID
  ) -> Bool {
    let updated = mutateSession {
      $0.replaceSettingsFromSnapshot(settings, expectedProfileID: expectedProfileID)
    }
    if updated {
      refreshIdleActivity(force: true)
    }
    return updated
  }

  @discardableResult
  func requestSelection(_ profile: DeskProfile?) -> ProfileSelectionRequestResult {
    let result = mutateSession { $0.requestSelection(profile) }
    refreshIdleActivity()
    return result
  }

  @discardableResult
  func resolvePendingSelection(
    _ decision: ProfileDraftSelectionDecision
  ) -> ProfileDraftSelectionResolution {
    let result = mutateSession { $0.resolvePendingSelection(decision) }
    refreshIdleActivity(force: true)
    return result
  }

  @discardableResult
  func completeSave(with profile: DeskProfile) -> ProfileDraftSaveCompletion {
    let result = mutateSession { $0.completeSave(with: profile) }
    switch result {
    case .saved, .savedAndSelected:
      setActivity(.saved)
      AccessibilityNotification.Announcement(appLocalized("Profile saved.")).post()
    case .rejected:
      let message = appLocalized("The saved profile did not match the active draft.")
      setActivity(.error(message))
      AccessibilityNotification.Announcement(message).post()
    }
    return result
  }

  func revertDraft() {
    mutateSession { $0.revertDraft() }
    setActivity(.saved)
  }

  func beginSaving() {
    setActivity(.saving)
  }

  func beginCapture() {
    setActivity(.capturing)
  }

  func finishWithMessage(_ message: String) {
    setActivity(.message(message))
    AccessibilityNotification.Announcement(message).post()
  }

  func finishWithError(_ message: String) {
    setActivity(.error(message))
    AccessibilityNotification.Announcement(message).post()
  }

  private func preferredProfile(in profiles: [DeskProfile], id: UUID?) -> DeskProfile? {
    if let id, let profile = profiles.first(where: { $0.id == id }) {
      return profile
    }
    return profiles.first
  }

  @discardableResult
  private func mutateSession<Result>(
    _ mutation: (inout ProfileDraftSession) -> Result
  ) -> Result {
    var updated = session
    let result = mutation(&updated)
    if updated != session {
      session = updated
    }
    return result
  }

  private func refreshIdleActivity(force: Bool = false) {
    guard force || !activity.isBusy else { return }
    switch activity {
    case .error where !force:
      return
    case .message where !force:
      return
    case .saved, .changed, .saving, .capturing, .message, .error:
      setActivity(session.isDirty ? .changed : .saved)
    }
  }

  private func setActivity(_ newValue: ProfileEditorActivity) {
    guard activity != newValue else { return }
    activity = newValue
  }
}
