import Combine
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("Profile editor publication stability")
  @MainActor
  struct ProfileEditorModelStabilityTests {
    @Test("editing values registers them without inclusion controls and revert keeps saved values")
    func registeredValuesFollowDraftAndSave() throws {
      let profile = DeskProfile(name: "Synthetic")
      let editor = ProfileEditorModel()
      editor.initialize(profiles: [profile], preferredProfileID: profile.id)
      #expect(
        editor.updateDraft {
          $0.settings.audio.value.defaultOutputUID.value = "synthetic-output"
          $0.settings.audio.value.outputVolume.value = 0
        })
      let candidate = try #require(editor.session.saveCandidate())
      #expect(candidate.settings.audio.value.defaultOutputUID.isIncluded)
      #expect(candidate.settings.audio.value.outputVolume == .init(value: 0))
      #expect(!candidate.settings.audio.value.inputVolume.isIncluded)
      #expect(candidate.settings.audio.value.inputVolume.value == nil)
      #expect(editor.isDirty)
      editor.revertDraft()
      #expect(editor.draft == profile)
      #expect(!editor.isDirty)
      #expect(editor.replaceDraft(candidate))
      #expect(editor.completeSave(with: candidate) == .saved)
      #expect(!editor.isDirty)
    }

    @Test("reinstalling an identical draft does not republish the editor hierarchy")
    func identicalDraftDoesNotPublish() throws {
      let profile = try #require(UIAuditFixtures.fixture(.editorDisplay).profiles.first)
      let editor = ProfileEditorModel()
      editor.initialize(profiles: [profile], preferredProfileID: profile.id)
      var publicationCount = 0
      let observation = editor.objectWillChange.sink {
        publicationCount += 1
      }

      #expect(editor.replaceDraft(profile))
      #expect(publicationCount == 0)
      withExtendedLifetime(observation) {}
    }
  }
#endif
