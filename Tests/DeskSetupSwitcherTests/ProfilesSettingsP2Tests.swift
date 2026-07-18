import Foundation
import ServiceManagement
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher
@testable import DeskSetupSystem

@Suite("P2 profile settings", .serialized)
@MainActor
struct ProfilesSettingsP2Tests {
  @Test("profile creation remains direct while management and file actions are secondary")
  func profileActionHierarchy() {
    #expect(ProfileManagementActionPolicy.primaryActions == [.create])
    #expect(
      ProfileManagementActionPolicy.secondaryActionGroups == [
        [.duplicate, .delete],
        [.moveUp, .moveDown],
        [.importProfiles, .exportSavedProfiles],
      ]
    )
  }

  @Test("dirty export copy explicitly excludes the unsaved draft")
  func savedProfileExportCopy() {
    #expect(ProfileExportScopePolicy.actionTitle == "Export Saved Profiles…")
    #expect(ProfileExportScopePolicy.unsavedDraftNotice.contains("saved profiles only"))
    #expect(ProfileExportScopePolicy.unsavedDraftNotice.contains("not included"))
    #expect(ProfileExportScopePolicy.accessibilityHint.contains("saved profiles"))
    #expect(ProfileExportScopePolicy.accessibilityHint.contains("unsaved draft"))
  }

  @Test("include controls expose meaning and a non-color state")
  func includedSettingPresentation() {
    let included = ProfileSettingInclusionPresentation.make(
      settingTitle: "Output volume",
      isIncluded: true
    )
    let excluded = ProfileSettingInclusionPresentation.make(
      settingTitle: "Output volume",
      isIncluded: false
    )

    #expect(included.visibleTitle == "Apply with profile")
    #expect(included.visibleState == "Included")
    #expect(included.systemImage == "checkmark.circle.fill")
    #expect(included.accessibilityLabel.contains("Output volume"))
    #expect(included.accessibilityLabel.contains("Apply with profile"))
    #expect(included.accessibilityValue == "Included in profile application")
    #expect(included.accessibilityHint.contains("changes when the profile is applied"))

    #expect(excluded.visibleTitle == included.visibleTitle)
    #expect(excluded.visibleState == "Not included")
    #expect(excluded.systemImage == "minus.circle")
    #expect(excluded.accessibilityValue == "Not included in profile application")
    #expect(excluded.accessibilityHint == included.accessibilityHint)

    #expect(!ProfileSettingInclusionLayoutPolicy.usesStackedHeader(for: .large))
    #expect(ProfileSettingInclusionLayoutPolicy.usesStackedHeader(for: .accessibility3))
    #expect(ProfileSettingInclusionLayoutPolicy.minimumAvailableHeaderWidth == 314)
    #expect(
      ProfileSettingInclusionLayoutPolicy.maximumExpectedControlWidth
        < ProfileSettingInclusionLayoutPolicy.minimumAvailableHeaderWidth
    )
  }

  @Test("export reads the persisted document and never the dirty editor draft")
  func exportUsesPersistedDocument() async throws {
    let fixture = try makeFixture("ExportScope")
    defer { fixture.cleanUp() }
    let store = ProfileStore(directoryURL: fixture.directory)
    _ = try await store.load()
    let persisted = try await store.createProfile(
      DeskProfile(name: "Saved Name"),
      selecting: true
    )
    let model = makeModel(store: store, defaults: fixture.defaults)
    let editor = ProfileEditorModel()
    editor.initialize(profiles: [persisted], preferredProfileID: persisted.id)
    #expect(editor.updateDraft { $0.name = "Unsaved Draft Name" })
    #expect(editor.isDirty)

    let destination = fixture.directory.appendingPathComponent("saved-export.json")
    #expect(await model.exportProfiles(to: destination))
    let exported = try ProfileImportExport().importDocument(from: destination).document

    #expect(exported.profiles.map(\.name) == ["Saved Name"])
    #expect(!exported.profiles.contains(where: { $0.name == "Unsaved Draft Name" }))
    #expect(editor.draft?.name == "Unsaved Draft Name")
    #expect(editor.isDirty)
  }

  @Test("generic operation failure has one real dismiss action")
  func genericStorageFailureCanBeDismissed() async throws {
    let fixture = try makeFixture("StorageDismiss")
    defer { fixture.cleanUp() }
    let store = ProfileStore(directoryURL: fixture.directory)
    _ = try await store.load()
    _ = try await store.createProfile(DeskProfile(name: "Saved"), selecting: true)
    let model = makeModel(store: store, defaults: fixture.defaults)
    let missingDirectory = fixture.directory.appendingPathComponent("missing", isDirectory: true)
    let destination = missingDirectory.appendingPathComponent("export.json")

    #expect(!(await model.exportProfiles(to: destination)))
    #expect(
      model.profileStorageFailure
        == ProfileStorageFailurePresentation(
          message: appLocalized("A local profile storage operation failed."),
          recovery: .dismiss
        )
    )
    #expect(model.profileStorageFailure?.availableActions == [.dismiss])

    model.dismissProfileStorageFailure()

    #expect(model.profileStorageFailure == nil)
    #expect(model.storageStatus == appLocalized("Ready for profile actions."))
  }

  @Test("a later global failure replaces the editor error without resurrecting it")
  func editorErrorOwnsItsSingleVisibleStatus() async throws {
    #expect(
      ProfileStorageFooterPolicy.showsStorageStatus(
        hasGlobalStorageFailure: false,
        editorOwnsCurrentError: false
      )
    )
    #expect(
      !ProfileStorageFooterPolicy.showsStorageStatus(
        hasGlobalStorageFailure: false,
        editorOwnsCurrentError: true
      )
    )
    #expect(
      !ProfileStorageFooterPolicy.showsStorageStatus(
        hasGlobalStorageFailure: true,
        editorOwnsCurrentError: false
      )
    )
    #expect(
      !ProfileStorageFooterPolicy.showsFooter(
        hasUnsavedDraft: false,
        showsStorageStatus: false
      )
    )
    #expect(
      ProfileStorageFooterPolicy.showsFooter(
        hasUnsavedDraft: true,
        showsStorageStatus: false
      )
    )
    #expect(
      ProfileEditorErrorVisibilityPolicy.showsEditorError(
        hasGlobalStorageFailure: false
      )
    )
    #expect(
      !ProfileEditorErrorVisibilityPolicy.showsEditorError(
        hasGlobalStorageFailure: true
      )
    )
    #expect(
      !ProfileWorkspaceInteractionPolicy.isDisabled(
        isMutationLocked: false,
        hasGlobalStorageFailure: false
      )
    )
    #expect(
      ProfileWorkspaceInteractionPolicy.isDisabled(
        isMutationLocked: false,
        hasGlobalStorageFailure: true
      )
    )
    #expect(
      ProfileWorkspaceInteractionPolicy.isDisabled(
        isMutationLocked: true,
        hasGlobalStorageFailure: false
      )
    )
    #expect(ProfileStorageFailureAccessibilityPolicy.movesFocusToHeadingOnPresentation)

    let fixture = try makeFixture("EditorErrorOwnership")
    defer { fixture.cleanUp() }
    let seedStore = ProfileStore(directoryURL: fixture.directory)
    _ = try await seedStore.load()
    let profile = try await seedStore.createProfile(
      DeskProfile(name: "Saved"),
      selecting: true
    )
    let locations = seedStore.locations
    let liveWriter = PrivateAtomicFileWriter()
    let failingStore = ProfileStore(
      directoryURL: fixture.directory,
      fileOperations: ProfileStoreFileOperations(
        privateFileWriter: { data, destination in
          if destination == locations.backupURL {
            throw CocoaError(.fileWriteNoPermission)
          }
          try liveWriter.write(data, to: destination)
        }
      )
    )
    _ = try await failingStore.load()
    let model = makeModel(store: failingStore, defaults: fixture.defaults)
    let editor = ProfileEditorModel()
    editor.initialize(profiles: [profile], preferredProfileID: profile.id)
    #expect(editor.updateDraft { $0.name = "Unsaved" })
    let candidate = try #require(editor.session.saveCandidate())

    let result = await model.updateProfile(candidate)
    guard case .rejected(let message) = result else {
      Issue.record("Expected the synthetic editor persistence to fail")
      return
    }
    editor.finishWithError(message)

    #expect(model.profileStorageFailure == nil)
    #expect(model.storageStatus == message)
    #expect(editor.activity == .error(message))
    #expect(
      !ProfileStorageFooterPolicy.showsStorageStatus(
        hasGlobalStorageFailure: model.profileStorageFailure != nil,
        editorOwnsCurrentError: true
      )
    )

    let missingDirectory = fixture.directory.appendingPathComponent("missing", isDirectory: true)
    #expect(
      !(await model.exportProfiles(
        to: missingDirectory.appendingPathComponent("saved-profiles.json")
      ))
    )
    #expect(model.profileStorageFailure?.recovery == .dismiss)
    #expect(editor.activity == .error(message))
    editor.clearTransientFeedback()
    #expect(editor.activity == .changed)
    #expect(
      !ProfileEditorErrorVisibilityPolicy.showsEditorError(
        hasGlobalStorageFailure: model.profileStorageFailure != nil
      )
    )

    model.dismissProfileStorageFailure()
    #expect(model.profileStorageFailure == nil)
    #expect(editor.activity == .changed)
    #expect(
      ProfileEditorErrorVisibilityPolicy.showsEditorError(
        hasGlobalStorageFailure: model.profileStorageFailure != nil
      )
    )
  }

  @Test("an existing global failure clears later editor feedback and locks the workspace")
  func globalFailureOwnsLaterEditorFeedback() {
    let profile = DeskProfile(name: "Saved")
    let editor = ProfileEditorModel()
    editor.initialize(profiles: [profile], preferredProfileID: profile.id)
    let hasGlobalStorageFailure = true

    #expect(
      ProfileWorkspaceInteractionPolicy.isDisabled(
        isMutationLocked: false,
        hasGlobalStorageFailure: hasGlobalStorageFailure
      )
    )

    // A previously started asynchronous editor operation may still finish
    // after the global card appears. The activity observer clears that late
    // transient feedback while preserving the saved/dirty editor state.
    editor.finishWithError("Late editor failure")
    editor.clearTransientFeedback()
    #expect(editor.activity == .saved)

    #expect(editor.updateDraft { $0.name = "Unsaved" })
    editor.finishWithMessage("Late editor message")
    editor.clearTransientFeedback()
    #expect(editor.activity == .changed)
    #expect(editor.draft?.name == "Unsaved")
  }

  @Test("initial load failure offers only a real retry and retry preserves the error if it fails")
  func loadFailureCanRetry() async throws {
    let fixture = try makeFixture("StorageRetry")
    defer { fixture.cleanUp() }
    let store = ProfileStore(
      directoryURL: fixture.directory,
      fileOperations: ProfileStoreFileOperations(
        privateFileWriter: { _, _ in
          throw CocoaError(.fileWriteNoPermission)
        }
      )
    )
    let model = makeModel(store: store, defaults: fixture.defaults)

    model.start()
    #expect(
      await eventually {
        model.profileStorageFailure?.recovery == .retryLoading
          && !model.isProfileMutationLocked
      }
    )
    #expect(model.profileStorageFailure?.availableActions == [.retryLoading])

    #expect(model.retryProfileStorageLoad())
    #expect(
      await eventually {
        model.profileStorageFailure?.recovery == .retryLoading
          && !model.isProfileMutationLocked
      }
    )
  }

  private func makeFixture(_ suffix: String) throws -> P2SettingsFixture {
    let identifier = "DeskSetupSwitcherTests.P2Settings.\(suffix).\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: identifier))
    defaults.removePersistentDomain(forName: identifier)
    defaults.set(true, forKey: "launchAtLoginPreferenceCreated")
    defaults.set(false, forKey: "launchAtLoginEnabled")
    return P2SettingsFixture(
      identifier: identifier,
      directory: FileManager.default.temporaryDirectory.appendingPathComponent(
        identifier,
        isDirectory: true
      ),
      defaults: defaults
    )
  }

  private func makeModel(store: ProfileStore, defaults: UserDefaults) -> ApplicationModel {
    ApplicationModel(
      profileStore: store,
      snapshotCoordinator: SystemSnapshotCoordinator(adapters: []),
      applyEngine: ApplyEngine(registry: AdapterRegistry()),
      diagnosticLog: nil,
      defaults: defaults,
      loginItemService: P2SettingsLoginItemService()
    )
  }

  private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<4_000 {
      if condition() { return true }
      await Task.yield()
    }
    return condition()
  }
}

private struct P2SettingsFixture {
  let identifier: String
  let directory: URL
  let defaults: UserDefaults

  func cleanUp() {
    defaults.removePersistentDomain(forName: identifier)
    try? FileManager.default.removeItem(at: directory)
  }
}

@MainActor
private final class P2SettingsLoginItemService: LoginItemServicing {
  var status: SMAppService.Status { .notRegistered }
  func register() throws {}
  func unregister() throws {}
}
