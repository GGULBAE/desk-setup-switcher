import DeskSetupCore
import Foundation
import XCTest

@testable import DeskSetupPresentation

final class ProfileDraftSessionTests: XCTestCase {
  func testInitializationTracksCleanSavedProfileAndDraft() {
    let profile = makeProfile(id: profileAID, name: "Home")

    let session = ProfileDraftSession(selectedProfile: profile)

    XCTAssertEqual(session.savedProfile, profile)
    XCTAssertEqual(session.draft, profile)
    XCTAssertEqual(session.selectedProfileID, profileAID)
    XCTAssertEqual(session.selection, .profile(profile))
    XCTAssertFalse(session.isDirty)
    XCTAssertNil(session.pendingSelection)
  }

  func testEmptyInitializationHasNoSelectionOrSaveCandidate() {
    let session = ProfileDraftSession()

    XCTAssertEqual(session.selection, .noProfile)
    XCTAssertNil(session.savedProfile)
    XCTAssertNil(session.draft)
    XCTAssertNil(session.saveCandidate())
    XCTAssertFalse(session.isDirty)
  }

  func testReplacingUserEditableValuesMarksDraftDirty() throws {
    let profile = makeProfile(id: profileAID, name: "Home")
    var replacement = profile
    replacement.name = "Focused Home"
    replacement.profileDescription = "Two external displays"
    replacement.isEnabled = false
    replacement.settings.audio.isIncluded = true
    replacement.conditions = ProfileConditionSet(
      mode: .any,
      conditions: [ProfileCondition(kind: .ethernetConnected)]
    )
    var session = ProfileDraftSession(selectedProfile: profile)

    XCTAssertTrue(session.replaceDraft(replacement))

    let draft = try XCTUnwrap(session.draft)
    XCTAssertEqual(draft.name, "Focused Home")
    XCTAssertEqual(draft.profileDescription, "Two external displays")
    XCTAssertFalse(draft.isEnabled)
    XCTAssertTrue(draft.settings.audio.isIncluded)
    XCTAssertEqual(draft.conditions.mode, .any)
    XCTAssertTrue(session.isDirty)
  }

  func testReplacementRejectsAnotherProfileWithoutChangingState() {
    let profile = makeProfile(id: profileAID, name: "Home")
    let replacement = makeProfile(id: profileBID, name: "Office")
    var session = ProfileDraftSession(selectedProfile: profile)

    XCTAssertFalse(session.replaceDraft(replacement))

    XCTAssertEqual(session.savedProfile, profile)
    XCTAssertEqual(session.draft, profile)
    XCTAssertFalse(session.isDirty)
  }

  func testMetadataOnlyReplacementIsNormalizedAndDoesNotMarkDraftDirty() throws {
    let profile = makeProfile(id: profileAID, name: "Home", metadataSeed: 10)
    var replacement = profile
    replacement.createdAt = Date(timeIntervalSince1970: 500)
    replacement.updatedAt = Date(timeIntervalSince1970: 600)
    replacement.lastApplication = makeApplication(seed: 600)
    var session = ProfileDraftSession(selectedProfile: profile)

    XCTAssertTrue(session.replaceDraft(replacement))

    let draft = try XCTUnwrap(session.draft)
    XCTAssertEqual(draft.createdAt, profile.createdAt)
    XCTAssertEqual(draft.updatedAt, profile.updatedAt)
    XCTAssertEqual(draft.lastApplication, profile.lastApplication)
    XCTAssertFalse(session.isDirty)
  }

  func testUpdateDraftUsesValidatedReplacementPath() throws {
    let profile = makeProfile(id: profileAID, name: "Home")
    var session = ProfileDraftSession(selectedProfile: profile)

    XCTAssertTrue(
      session.updateDraft {
        $0.name = "Updated"
        $0.updatedAt = Date(timeIntervalSince1970: 900)
        $0.lastApplication = makeApplication(seed: 900)
      }
    )

    let draft = try XCTUnwrap(session.draft)
    XCTAssertEqual(draft.id, profileAID)
    XCTAssertEqual(draft.name, "Updated")
    XCTAssertEqual(draft.updatedAt, profile.updatedAt)
    XCTAssertEqual(draft.lastApplication, profile.lastApplication)
    XCTAssertTrue(session.isDirty)
  }

  func testUpdateDraftWithoutSelectionIsIgnored() {
    var session = ProfileDraftSession()

    XCTAssertFalse(session.updateDraft { $0.name = "Impossible" })
    XCTAssertNil(session.draft)
  }

  func testSnapshotSettingsPreserveOtherUnsavedFieldsAndMetadata() throws {
    let original = makeProfile(id: profileAID, name: "Home", metadataSeed: 10)
    var session = ProfileDraftSession(selectedProfile: original)
    session.updateDraft {
      $0.name = "Unsaved Name"
      $0.conditions = ProfileConditionSet(
        mode: .any,
        conditions: [ProfileCondition(kind: .ethernetConnected)]
      )
    }
    var settings = ProfileSettings()
    settings.audio.isIncluded = true
    settings.audio.value.outputVolume = .init(isIncluded: true, value: 0.42)

    XCTAssertTrue(
      session.replaceSettingsFromSnapshot(settings, expectedProfileID: profileAID)
    )

    let draft = try XCTUnwrap(session.draft)
    XCTAssertEqual(draft.name, "Unsaved Name")
    XCTAssertEqual(draft.conditions.mode, .any)
    XCTAssertEqual(draft.settings, settings)
    XCTAssertEqual(draft.createdAt, original.createdAt)
    XCTAssertEqual(draft.lastApplication, original.lastApplication)
    XCTAssertTrue(session.isDirty)
  }

  func testSnapshotSettingsRejectLateResultForAnotherProfile() {
    let original = makeProfile(id: profileAID, name: "Home")
    var session = ProfileDraftSession(selectedProfile: original)
    var settings = ProfileSettings()
    settings.network.isIncluded = true

    XCTAssertFalse(
      session.replaceSettingsFromSnapshot(settings, expectedProfileID: profileBID)
    )
    XCTAssertEqual(session.draft, original)
    XCTAssertFalse(session.isDirty)
  }

  func testMatchingSnapshotSettingsKeepCleanDraftClean() {
    let original = makeProfile(id: profileAID, name: "Home")
    var session = ProfileDraftSession(selectedProfile: original)

    XCTAssertTrue(
      session.replaceSettingsFromSnapshot(
        original.settings,
        expectedProfileID: profileAID
      )
    )
    XCTAssertEqual(session.draft, original)
    XCTAssertFalse(session.isDirty)
  }

  func testSaveCandidatePreservesLatestNonUserMetadata() throws {
    let saved = makeProfile(id: profileAID, name: "Home", metadataSeed: 10)
    var edited = saved
    edited.name = "Home Studio"
    edited.createdAt = Date(timeIntervalSince1970: 1)
    edited.updatedAt = Date(timeIntervalSince1970: 2)
    edited.lastApplication = makeApplication(seed: 2)
    var session = ProfileDraftSession(selectedProfile: saved)
    session.replaceDraft(edited)

    let candidate = try XCTUnwrap(session.saveCandidate())

    XCTAssertEqual(candidate.name, "Home Studio")
    XCTAssertEqual(candidate.id, saved.id)
    XCTAssertEqual(candidate.createdAt, saved.createdAt)
    XCTAssertEqual(candidate.updatedAt, saved.updatedAt)
    XCTAssertEqual(candidate.lastApplication, saved.lastApplication)
  }

  func testSynchronizingDirtyProfileRetainsEditsAndRefreshesMetadata() throws {
    let original = makeProfile(id: profileAID, name: "Home", metadataSeed: 10)
    var edited = original
    edited.name = "My Home"
    var latest = original
    latest.updatedAt = Date(timeIntervalSince1970: 90)
    latest.lastApplication = makeApplication(seed: 90)
    var session = ProfileDraftSession(selectedProfile: original)
    session.replaceDraft(edited)

    XCTAssertTrue(session.synchronizeProfile(latest))

    XCTAssertEqual(session.savedProfile, latest)
    let draft = try XCTUnwrap(session.draft)
    XCTAssertEqual(draft.name, "My Home")
    XCTAssertEqual(draft.updatedAt, latest.updatedAt)
    XCTAssertEqual(draft.lastApplication, latest.lastApplication)
    XCTAssertTrue(session.isDirty)
    XCTAssertEqual(session.saveCandidate()?.lastApplication, latest.lastApplication)
  }

  func testSynchronizingCleanProfileFollowsLatestEditableAndMetadataValues() {
    let original = makeProfile(id: profileAID, name: "Home", metadataSeed: 10)
    var latest = makeProfile(id: profileAID, name: "Renamed Elsewhere", metadataSeed: 90)
    latest.profileDescription = "Latest persisted description"
    var session = ProfileDraftSession(selectedProfile: original)

    XCTAssertTrue(session.synchronizeProfile(latest))

    XCTAssertEqual(session.savedProfile, latest)
    XCTAssertEqual(session.draft, latest)
    XCTAssertFalse(session.isDirty)
  }

  func testSynchronizingUnrelatedProfileIsIgnored() {
    let original = makeProfile(id: profileAID, name: "Home")
    let unrelated = makeProfile(id: profileBID, name: "Office")
    var session = ProfileDraftSession(selectedProfile: original)

    XCTAssertFalse(session.synchronizeProfile(unrelated))
    XCTAssertEqual(session.savedProfile, original)
    XCTAssertEqual(session.draft, original)
  }

  func testCleanSelectionRequestTransitionsImmediately() {
    let home = makeProfile(id: profileAID, name: "Home")
    let office = makeProfile(id: profileBID, name: "Office")
    var session = ProfileDraftSession(selectedProfile: home)

    let result = session.requestSelection(office)

    XCTAssertEqual(result, .selected(.profile(office)))
    XCTAssertEqual(session.savedProfile, office)
    XCTAssertEqual(session.draft, office)
    XCTAssertFalse(session.isDirty)
    XCTAssertNil(session.pendingSelection)
  }

  func testCleanSelectionCanBeClearedImmediately() {
    let home = makeProfile(id: profileAID, name: "Home")
    var session = ProfileDraftSession(selectedProfile: home)

    let result = session.requestSelection(nil)

    XCTAssertEqual(result, .selected(.noProfile))
    XCTAssertEqual(session.selection, .noProfile)
    XCTAssertNil(session.savedProfile)
    XCTAssertNil(session.draft)
  }

  func testRequestingCurrentProfileRefreshesItWithoutDiscardingDirtyDraft() throws {
    let home = makeProfile(id: profileAID, name: "Home", metadataSeed: 10)
    var edited = home
    edited.name = "Local Name"
    var latest = home
    latest.updatedAt = Date(timeIntervalSince1970: 80)
    latest.lastApplication = makeApplication(seed: 80)
    var session = ProfileDraftSession(selectedProfile: home)
    session.replaceDraft(edited)

    let result = session.requestSelection(latest)

    XCTAssertEqual(result, .unchanged)
    XCTAssertEqual(session.savedProfile, latest)
    XCTAssertEqual(try XCTUnwrap(session.draft).name, "Local Name")
    XCTAssertTrue(session.isDirty)
    XCTAssertNil(session.pendingSelection)
  }

  func testDirtySelectionRequestRetainsDraftAndRequiresDecision() {
    let home = makeProfile(id: profileAID, name: "Home")
    let office = makeProfile(id: profileBID, name: "Office")
    var session = dirtySession(from: home)

    let result = session.requestSelection(office)

    XCTAssertEqual(result, .requiresDecision(.profile(office)))
    XCTAssertEqual(session.savedProfile, home)
    XCTAssertEqual(session.draft?.name, "Edited Home")
    XCTAssertEqual(session.pendingSelection, .profile(office))
    XCTAssertTrue(session.isDirty)
  }

  func testNewDirtySelectionRequestDeterministicallyReplacesPendingTarget() {
    let home = makeProfile(id: profileAID, name: "Home")
    let office = makeProfile(id: profileBID, name: "Office")
    let studio = makeProfile(id: profileCID, name: "Studio")
    var session = dirtySession(from: home)
    session.requestSelection(office)

    let result = session.requestSelection(studio)

    XCTAssertEqual(result, .requiresDecision(.profile(studio)))
    XCTAssertEqual(session.pendingSelection, .profile(studio))
    XCTAssertEqual(session.savedProfile, home)
    XCTAssertTrue(session.isDirty)
  }

  func testCancelResolutionKeepsDirtyDraftAndCurrentSelection() {
    let home = makeProfile(id: profileAID, name: "Home")
    let office = makeProfile(id: profileBID, name: "Office")
    var session = dirtySession(from: home)
    session.requestSelection(office)

    let resolution = session.resolvePendingSelection(.cancel)

    XCTAssertEqual(resolution, .cancelled)
    XCTAssertNil(session.pendingSelection)
    XCTAssertEqual(session.savedProfile, home)
    XCTAssertEqual(session.draft?.name, "Edited Home")
    XCTAssertTrue(session.isDirty)
  }

  func testDiscardResolutionActivatesPendingProfileAndClearsDirtyState() {
    let home = makeProfile(id: profileAID, name: "Home")
    let office = makeProfile(id: profileBID, name: "Office")
    var session = dirtySession(from: home)
    session.requestSelection(office)

    let resolution = session.resolvePendingSelection(.discard)

    XCTAssertEqual(resolution, .selected(.profile(office)))
    XCTAssertEqual(session.savedProfile, office)
    XCTAssertEqual(session.draft, office)
    XCTAssertNil(session.pendingSelection)
    XCTAssertFalse(session.isDirty)
  }

  func testDiscardResolutionCanClearSelection() {
    let home = makeProfile(id: profileAID, name: "Home")
    var session = dirtySession(from: home)
    session.requestSelection(nil)

    let resolution = session.resolvePendingSelection(.discard)

    XCTAssertEqual(resolution, .selected(.noProfile))
    XCTAssertEqual(session.selection, .noProfile)
    XCTAssertNil(session.draft)
    XCTAssertFalse(session.isDirty)
  }

  func testSaveResolutionRetainsDraftUntilMatchingPersistenceCompletion() throws {
    let home = makeProfile(id: profileAID, name: "Home", metadataSeed: 10)
    let office = makeProfile(id: profileBID, name: "Office")
    var session = dirtySession(from: home)
    session.requestSelection(office)

    let resolution = session.resolvePendingSelection(.save)

    guard case .saveRequired(let candidate, let thenSelect) = resolution else {
      return XCTFail("Expected a save requirement")
    }
    XCTAssertEqual(candidate.name, "Edited Home")
    XCTAssertEqual(candidate.lastApplication, home.lastApplication)
    XCTAssertEqual(thenSelect, .profile(office))
    XCTAssertEqual(session.savedProfile, home)
    XCTAssertEqual(session.draft?.name, "Edited Home")
    XCTAssertEqual(session.pendingSelection, .profile(office))

    var persisted = candidate
    persisted.updatedAt = Date(timeIntervalSince1970: 120)
    let completion = session.completeSave(with: persisted)

    XCTAssertEqual(completion, .savedAndSelected(.profile(office)))
    XCTAssertEqual(session.savedProfile, office)
    XCTAssertEqual(session.draft, office)
    XCTAssertNil(session.pendingSelection)
    XCTAssertFalse(session.isDirty)
  }

  func testMismatchedSaveCompletionIsRejectedWithoutStateLoss() {
    let home = makeProfile(id: profileAID, name: "Home")
    let office = makeProfile(id: profileBID, name: "Office")
    var session = dirtySession(from: home)
    session.requestSelection(office)

    let completion = session.completeSave(with: office)

    XCTAssertEqual(
      completion,
      .rejected(expectedProfileID: profileAID, actualProfileID: profileBID)
    )
    XCTAssertEqual(session.savedProfile, home)
    XCTAssertEqual(session.draft?.name, "Edited Home")
    XCTAssertEqual(session.pendingSelection, .profile(office))
    XCTAssertTrue(session.isDirty)
  }

  func testDirectSaveCompletionMarksDraftClean() throws {
    let home = makeProfile(id: profileAID, name: "Home")
    var session = dirtySession(from: home)
    var persisted = try XCTUnwrap(session.saveCandidate())
    persisted.updatedAt = Date(timeIntervalSince1970: 120)

    let completion = session.completeSave(with: persisted)

    XCTAssertEqual(completion, .saved)
    XCTAssertEqual(session.savedProfile, persisted)
    XCTAssertEqual(session.draft, persisted)
    XCTAssertFalse(session.isDirty)
  }

  func testSynchronizingPendingTargetRefreshesDiscardDestination() {
    let home = makeProfile(id: profileAID, name: "Home")
    let office = makeProfile(id: profileBID, name: "Office", metadataSeed: 20)
    var latestOffice = office
    latestOffice.name = "Updated Office"
    latestOffice.updatedAt = Date(timeIntervalSince1970: 90)
    var session = dirtySession(from: home)
    session.requestSelection(office)

    XCTAssertTrue(session.synchronizeProfile(latestOffice))
    XCTAssertEqual(session.pendingSelection, .profile(latestOffice))

    XCTAssertEqual(
      session.resolvePendingSelection(.discard),
      .selected(.profile(latestOffice))
    )
    XCTAssertEqual(session.savedProfile, latestOffice)
  }

  func testRevertDraftClearsPendingSelectionAndRestoresSavedValues() {
    let home = makeProfile(id: profileAID, name: "Home")
    let office = makeProfile(id: profileBID, name: "Office")
    var session = dirtySession(from: home)
    session.requestSelection(office)

    session.revertDraft()

    XCTAssertEqual(session.draft, home)
    XCTAssertFalse(session.isDirty)
    XCTAssertNil(session.pendingSelection)
  }

  func testResolvingWithoutPendingSelectionIsANoOp() {
    let home = makeProfile(id: profileAID, name: "Home")
    var session = ProfileDraftSession(selectedProfile: home)

    XCTAssertEqual(session.resolvePendingSelection(.cancel), .noPendingSelection)
    XCTAssertEqual(session.resolvePendingSelection(.discard), .noPendingSelection)
    XCTAssertEqual(session.resolvePendingSelection(.save), .noPendingSelection)
    XCTAssertEqual(session.savedProfile, home)
  }

  private func dirtySession(from profile: DeskProfile) -> ProfileDraftSession {
    var session = ProfileDraftSession(selectedProfile: profile)
    session.updateDraft { $0.name = "Edited Home" }
    return session
  }

  private func makeProfile(
    id: UUID,
    name: String,
    metadataSeed: TimeInterval = 10
  ) -> DeskProfile {
    DeskProfile(
      id: id,
      name: name,
      profileDescription: "Synthetic test profile",
      createdAt: Date(timeIntervalSince1970: metadataSeed),
      updatedAt: Date(timeIntervalSince1970: metadataSeed + 1),
      lastApplication: makeApplication(seed: metadataSeed + 1)
    )
  }

  private func makeApplication(seed: TimeInterval) -> ApplicationSummary {
    ApplicationSummary(
      appliedAt: Date(timeIntervalSince1970: seed),
      status: .applied,
      items: [
        ApplicationItemSummary(
          id: applicationItemID,
          group: .audio,
          key: "synthetic-output",
          status: .succeeded,
          message: "Synthetic result"
        )
      ]
    )
  }

  private var profileAID: UUID {
    UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  }

  private var profileBID: UUID {
    UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  }

  private var profileCID: UUID {
    UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
  }

  private var applicationItemID: UUID {
    UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
  }
}
