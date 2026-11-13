import Combine
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("Profile editor publication stability")
  @MainActor
  struct ProfileEditorModelStabilityTests {
    @Test("editing values preserves explicit exclusion and revert keeps saved values")
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
      #expect(!candidate.settings.audio.value.defaultOutputUID.isIncluded)
      #expect(candidate.settings.audio.value.outputVolume == .init(isIncluded: false, value: 0))
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

    @Test("section selection remains off through recapture, save and reload")
    func sectionSelectionSurvivesEditorLifecycle() throws {
      var profile = try #require(UIAuditFixtures.fixture(.editorAudio).profiles.first)
      let captured = profile.settings
      let editor = ProfileEditorModel()
      editor.initialize(profiles: [profile], preferredProfileID: profile.id)
      #expect(editor.updateDraft { $0.settings.setIncluded(false, for: .soundInput) })
      #expect(editor.isDirty)
      #expect(editor.replaceSettingsFromSnapshot(captured, expectedProfileID: profile.id))
      #expect(editor.draft?.settings.isIncluded(.soundInput) == false)
      profile = try #require(editor.session.saveCandidate())
      #expect(editor.completeSave(with: profile) == .saved)
      #expect(!editor.isDirty)
      let codec = ProfileJSONCodec()
      let reloaded = try codec.decode(codec.encode(.init(profiles: [profile]))).document.profiles
      let reopened = ProfileEditorModel()
      reopened.initialize(profiles: reloaded, preferredProfileID: profile.id)
      #expect(reopened.draft?.settings.isIncluded(.soundInput) == false)
      #expect(reopened.draft?.settings.isIncluded(.soundOutput) == true)
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
