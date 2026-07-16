import Combine
import Testing

@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("Profile editor publication stability")
  @MainActor
  struct ProfileEditorModelStabilityTests {
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
