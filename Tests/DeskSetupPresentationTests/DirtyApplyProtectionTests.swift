import DeskSetupCore
import DeskSetupPresentation
import Foundation
import Testing

@Suite("Dirty apply protection")
struct DirtyApplyProtectionTests {
  private let targetID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  private let otherID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

  @Test("clean editor proceeds immediately")
  func cleanEditorProceeds() {
    #expect(
      DirtyApplyProtectionDecision.evaluate(
        targetProfileID: targetID,
        openDraftProfileID: otherID,
        isDraftDirty: false,
        hasPendingSelection: false
      ) == .applyNow
    )
  }

  @Test("dirty target must be saved before apply")
  func dirtyTargetRequiresSave() {
    #expect(
      DirtyApplyProtectionDecision.evaluate(
        targetProfileID: targetID,
        openDraftProfileID: targetID,
        isDraftDirty: true,
        hasPendingSelection: false
      ) == .saveTargetBeforeApply
    )
  }

  @Test("different dirty draft requires an explicit decision")
  func otherDirtyDraftRequiresDecision() {
    #expect(
      DirtyApplyProtectionDecision.evaluate(
        targetProfileID: targetID,
        openDraftProfileID: otherID,
        isDraftDirty: true,
        hasPendingSelection: false
      ) == .resolveOtherDraft(openProfileID: otherID)
    )
  }

  @Test("pending selection blocks a second decision")
  func pendingSelectionBlocks() {
    #expect(
      DirtyApplyProtectionDecision.evaluate(
        targetProfileID: targetID,
        openDraftProfileID: otherID,
        isDraftDirty: true,
        hasPendingSelection: true
      ) == .blockedByPendingSelection
    )
  }

  @Test("a draft changed after preview creation blocks final execution")
  func dirtyDraftAfterPreviewIsRechecked() {
    let previewDecision = DirtyApplyProtectionDecision.evaluate(
      targetProfileID: targetID,
      openDraftProfileID: targetID,
      isDraftDirty: false,
      hasPendingSelection: false
    )
    let confirmationDecision = DirtyApplyProtectionDecision.evaluate(
      targetProfileID: targetID,
      openDraftProfileID: targetID,
      isDraftDirty: true,
      hasPendingSelection: false
    )

    #expect(previewDecision == .applyNow)
    #expect(confirmationDecision == .saveTargetBeforeApply)
  }

  @Test("same-target preparation waits for save and uses the persisted draft values")
  func saveSuccessUsesLatestDraft() {
    let saved = profile(id: targetID, volume: 0.2)
    var session = ProfileDraftSession(selectedProfile: saved)
    session.updateDraft { $0.settings.audio.value.outputVolume.value = 0.8 }
    var coordinator = DirtyApplySaveCoordinator(
      targetProfileID: targetID,
      mode: .normal,
      destination: .persistedTarget
    )

    #expect(
      DirtyApplyProtectionDecision.evaluate(
        targetProfileID: targetID,
        openDraftProfileID: session.selectedProfileID,
        isDraftDirty: session.isDirty,
        hasPendingSelection: session.pendingSelection != nil
      ) == .saveTargetBeforeApply
    )
    #expect(coordinator.isPending)

    let candidate = try! #require(session.saveCandidate())
    #expect(candidate.settings.audio.value.outputVolume.value == 0.8)
    let completion = session.completeSave(with: candidate)
    let effect = coordinator.handle(
      .saveSucceeded(profile: candidate, completion: completion)
    )

    #expect(effect == .prepare(profile: candidate, mode: .normal))
    #expect(!coordinator.isPending)
    if case .prepare(let prepared, _) = effect {
      #expect(prepared.settings.audio.value.outputVolume.value == 0.8)
    } else {
      Issue.record("Expected a prepare effect")
    }
  }

  @Test("save failure preserves the dirty draft and never prepares a stale profile")
  func saveFailurePreservesDraft() {
    var session = ProfileDraftSession(selectedProfile: profile(id: targetID, volume: 0.2))
    session.updateDraft { $0.settings.audio.value.outputVolume.value = 0.8 }
    var coordinator = DirtyApplySaveCoordinator(
      targetProfileID: targetID,
      mode: .normal,
      destination: .persistedTarget
    )
    let effect = coordinator.handle(.saveRejected)

    #expect(effect == .none)
    #expect(!coordinator.isPending)
    #expect(session.isDirty)
    #expect(session.draft?.settings.audio.value.outputVolume.value == 0.8)
  }

  @Test("cancel and duplicate completion never emit preparation work")
  func cancelAndDuplicateCompletionAreNoOps() {
    let persisted = profile(id: targetID, volume: 0.8)
    var cancelled = DirtyApplySaveCoordinator(
      targetProfileID: targetID,
      mode: .normal,
      destination: .persistedTarget
    )
    #expect(cancelled.handle(.cancelled) == .none)
    #expect(
      cancelled.handle(.saveSucceeded(profile: persisted, completion: .saved)) == .none
    )

    var completed = DirtyApplySaveCoordinator(
      targetProfileID: targetID,
      mode: .force,
      destination: .persistedTarget
    )
    #expect(
      completed.handle(.saveSucceeded(profile: persisted, completion: .saved))
        == .prepare(profile: persisted, mode: .force)
    )
    #expect(
      completed.handle(.saveSucceeded(profile: persisted, completion: .saved)) == .none
    )
  }

  @Test("different-target save emits selection only after the exact completion")
  func otherTargetSaveContinuation() {
    let savedOpenDraft = profile(id: otherID, volume: 0.3)
    let target = profile(id: targetID, volume: 0.6)
    var coordinator = DirtyApplySaveCoordinator(
      targetProfileID: targetID,
      mode: .force,
      destination: .selectedTarget(profileID: targetID)
    )

    #expect(
      coordinator.handle(
        .saveSucceeded(
          profile: savedOpenDraft,
          completion: .savedAndSelected(.profile(target))
        )
      ) == .selectAndPrepare(profileID: targetID, mode: .force)
    )

    var mismatch = DirtyApplySaveCoordinator(
      targetProfileID: targetID,
      mode: .force,
      destination: .selectedTarget(profileID: targetID)
    )
    #expect(
      mismatch.handle(
        .saveSucceeded(
          profile: savedOpenDraft,
          completion: .savedAndSelected(.profile(profile(id: otherID, volume: 0.1)))
        )
      ) == .none
    )
  }

  @Test("different-target save discard and cancel retain the exact target semantics")
  func otherDraftResolutionSemantics() {
    let open = profile(id: otherID, volume: 0.2)
    let target = profile(id: targetID, volume: 0.6)

    var saveSession = dirtySession(open)
    #expect(saveSession.requestSelection(target) == .requiresDecision(.profile(target)))
    guard
      case .saveRequired(let candidate, let destination) =
        saveSession.resolvePendingSelection(.save)
    else {
      Issue.record("Expected a save transition")
      return
    }
    #expect(candidate.id == otherID)
    #expect(destination.profileID == targetID)
    #expect(saveSession.selectedProfileID == otherID)

    var discardSession = dirtySession(open)
    _ = discardSession.requestSelection(target)
    #expect(discardSession.resolvePendingSelection(.discard) == .selected(.profile(target)))
    #expect(discardSession.selectedProfileID == targetID)

    var cancelSession = dirtySession(open)
    _ = cancelSession.requestSelection(target)
    #expect(cancelSession.resolvePendingSelection(.cancel) == .cancelled)
    #expect(cancelSession.selectedProfileID == otherID)
    #expect(cancelSession.isDirty)
  }

  @Test("disclosure changes never alter inclusion or saved values")
  func disclosureIsIndependentFromProfileValues() {
    let profile = profile(id: targetID, volume: 0.5)
    var disclosure = DisclosureState<String>()

    disclosure.toggle("audio.outputVolume")
    #expect(disclosure.isExpanded("audio.outputVolume"))
    disclosure.toggle("audio.outputVolume")

    #expect(!disclosure.isExpanded("audio.outputVolume"))
    #expect(profile.settings.audio.isIncluded)
    #expect(profile.settings.audio.value.outputVolume.isIncluded)
    #expect(profile.settings.audio.value.outputVolume.value == 0.5)
  }

  @Test("advanced numeric entry is collapsed by default and explicitly controllable")
  func advancedNumericDisclosureState() {
    let fieldID = DraftFieldIdentifier.input(.pointerSpeed)
    var disclosure = DisclosureState<DraftFieldIdentifier>()

    #expect(!disclosure.isExpanded(fieldID))
    disclosure.setExpanded(true, for: fieldID)
    #expect(disclosure.isExpanded(fieldID))
    disclosure.setExpanded(false, for: fieldID)
    #expect(!disclosure.isExpanded(fieldID))
  }

  @Test("choosing a primary display changes values without changing inclusion")
  func primarySelectionPreservesInclusion() {
    let first = DisplayTargetSettings(
      id: targetID,
      identity: .init(isBuiltIn: true),
      isPrimary: .init(isIncluded: false, value: true),
      origin: .init(isIncluded: false, value: .init(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: .init(width: 1_920, height: 1_080, refreshRate: 60)
      ),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
    let second = DisplayTargetSettings(
      id: otherID,
      identity: .init(isBuiltIn: false),
      isPrimary: .init(isIncluded: true, value: false),
      origin: .init(isIncluded: false, value: .init(x: 1_920, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: .init(width: 1_920, height: 1_080, refreshRate: 60)
      ),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )

    let updated = DisplayPrimarySelectionEditor.selecting(
      otherID,
      in: [first, second]
    )

    #expect(updated.map(\.isPrimary.isIncluded) == [false, true])
    #expect(updated.map(\.isPrimary.value) == [false, true])
  }

  private func dirtySession(_ profile: DeskProfile) -> ProfileDraftSession {
    var session = ProfileDraftSession(selectedProfile: profile)
    session.updateDraft { $0.profileDescription = "Synthetic draft change" }
    return session
  }

  private func profile(id: UUID, volume: Double) -> DeskProfile {
    DeskProfile(
      id: id,
      name: "Synthetic profile",
      settings: ProfileSettings(
        audio: .init(value: .init(outputVolume: .init(value: volume)))
      )
    )
  }
}
