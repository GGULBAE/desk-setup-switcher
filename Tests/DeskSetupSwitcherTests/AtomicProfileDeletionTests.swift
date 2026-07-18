import CoreLocation
import Foundation
import ServiceManagement
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher
@testable import DeskSetupSystem

@Suite("Atomic profile deletion", .serialized)
@MainActor
struct AtomicProfileDeletionTests {
  @Test("successful persistence commits the dirty draft and selection afterward")
  func successfulPersistenceCommitsTrayState() async throws {
    let identifier = "DeskSetupSwitcherTests.AtomicDeleteSuccess.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      identifier,
      isDirectory: true
    )
    let defaults = try #require(UserDefaults(suiteName: identifier))
    defaults.removePersistentDomain(forName: identifier)
    defaults.set(true, forKey: "launchAtLoginPreferenceCreated")
    defaults.set(false, forKey: "launchAtLoginEnabled")
    defer {
      defaults.removePersistentDomain(forName: identifier)
      try? FileManager.default.removeItem(at: directory)
    }

    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let store = ProfileStore(directoryURL: directory, now: { timestamp })
    _ = try await store.load()
    let first = try await store.createProfile(
      DeskProfile(name: "First Profile"),
      selecting: true
    )
    let second = try await store.createProfile(DeskProfile(name: "Second Profile"))
    let primaryBefore = try Data(contentsOf: store.locations.primaryURL)
    let conditionReader = AtomicDeleteConditionReader()
    let loginItem = AtomicDeleteLoginItemService()
    let model = ApplicationModel(
      profileStore: store,
      snapshotCoordinator: SystemSnapshotCoordinator(adapters: []),
      conditionContextProvider: ConditionContextProvider(
        displayReader: conditionReader,
        audioReader: conditionReader,
        networkReader: conditionReader,
        hardwareReader: conditionReader
      ),
      applyEngine: ApplyEngine(registry: AdapterRegistry()),
      diagnosticLog: nil,
      defaults: defaults,
      loginItemService: loginItem
    )

    model.start()
    #expect(
      await eventually {
        model.profiles.count == 2 && !model.isProfileMutationLocked
      }
    )

    let editor = ProfileEditorModel()
    editor.initialize(profiles: model.profiles, preferredProfileID: first.id)
    #expect(editor.updateDraft { $0.name = "Unsaved First Profile" })
    #expect(editor.isDirty)
    let deleteGate = AtomicDeleteGate()
    var observedDeleteResult: ProfileDeleteResult?
    let presentation = TrayPresentationModel(
      model: model,
      locationPermission: LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .authorized
      ),
      profileEditor: editor,
      deleteOperation: { profileID in
        await deleteGate.enterAndWait()
        let result = await model.deleteProfile(id: profileID)
        observedDeleteResult = result
        return result
      }
    )
    var dismissRequests: [UInt64] = []
    presentation.setSurfaceDismissRequest { generation in
      dismissRequests.append(generation)
      presentation.trayDidClose(sessionGeneration: generation)
    }
    presentation.trayDidOpen(
      sessionGeneration: 41,
      viewport: CGSize(width: 368, height: 560)
    )

    await presentation.executeStayOpen(.requestDelete(first.id))
    #expect(editor.isDirty)
    #expect(model.profiles.contains(where: { $0.id == first.id }))
    let confirmation = Task { @MainActor in
      await presentation.executeStayOpen(.confirmDelete(first.id))
    }
    await deleteGate.waitUntilEntered()

    #expect(presentation.isDeletionInFlight(profileID: first.id))
    #expect(presentation.deletion.pendingProfileID == first.id)
    #expect(presentation.focusTarget == .cancelDelete(first.id))
    #expect(editor.isDirty)
    #expect(editor.draft?.name == "Unsaved First Profile")

    // Once persistence starts, Cancel and a duplicate confirmation cannot
    // claim cancellation. Escape still dismisses the active surface so the
    // disabled destructive row never traps keyboard users.
    await presentation.executeStayOpen(.cancelDelete(first.id))
    presentation.requestEscape()
    #expect(dismissRequests == [41])
    #expect(!presentation.isTrayVisible)
    presentation.trayDidOpen(
      sessionGeneration: 42,
      viewport: CGSize(width: 368, height: 560)
    )
    await presentation.executeStayOpen(.confirmDelete(first.id))
    #expect(await deleteGate.entryCount == 1)
    #expect(presentation.deletion.pendingProfileID == first.id)
    #expect(presentation.focusTarget == .cancelDelete(first.id))
    #expect(editor.isDirty)
    #expect(presentation.isTrayVisible)

    await deleteGate.release()
    await confirmation.value

    #expect(observedDeleteResult == .deleted)
    #expect(!presentation.isDeletionInFlight(profileID: first.id))
    #expect(presentation.deletion.pendingProfileID == nil)
    #expect(presentation.focusTarget == .profile(second.id))
    #expect(presentation.handoffError == nil)
    #expect(!editor.isDirty)
    #expect(editor.selectedProfileID == second.id)
    #expect(editor.draft?.id == second.id)
    #expect(model.profiles.map(\.id) == [second.id])
    #expect(model.selectedProfileID == second.id)
    #expect(!model.isProfileMutationLocked)
    let persisted = await store.currentDocument()
    #expect(persisted.profiles.map(\.id) == [second.id])
    #expect(persisted.selectedProfileID == second.id)
    #expect(try Data(contentsOf: store.locations.primaryURL) != primaryBefore)
    #expect(!loginItem.mutatedRegistration)
  }

  @Test("failed persistence preserves the dirty tray draft and deletion decision")
  func failedPersistencePreservesTrayState() async throws {
    let identifier = "DeskSetupSwitcherTests.AtomicDelete.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      identifier,
      isDirectory: true
    )
    let defaults = try #require(UserDefaults(suiteName: identifier))
    defaults.removePersistentDomain(forName: identifier)
    defaults.set(true, forKey: "launchAtLoginPreferenceCreated")
    defaults.set(false, forKey: "launchAtLoginEnabled")
    defer {
      defaults.removePersistentDomain(forName: identifier)
      try? FileManager.default.removeItem(at: directory)
    }

    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let seedStore = ProfileStore(directoryURL: directory, now: { timestamp })
    _ = try await seedStore.load()
    let profile = try await seedStore.createProfile(
      DeskProfile(name: "Persisted Profile"),
      selecting: true
    )
    let locations = seedStore.locations
    let primaryBefore = try Data(contentsOf: locations.primaryURL)
    let liveWriter = PrivateAtomicFileWriter()
    let failingStore = ProfileStore(
      directoryURL: directory,
      now: { timestamp },
      fileOperations: ProfileStoreFileOperations(
        privateFileWriter: { data, destination in
          if destination == locations.backupURL {
            throw CocoaError(.fileWriteNoPermission)
          }
          try liveWriter.write(data, to: destination)
        }
      )
    )
    let conditionReader = AtomicDeleteConditionReader()
    let loginItem = AtomicDeleteLoginItemService()
    let model = ApplicationModel(
      profileStore: failingStore,
      snapshotCoordinator: SystemSnapshotCoordinator(adapters: []),
      conditionContextProvider: ConditionContextProvider(
        displayReader: conditionReader,
        audioReader: conditionReader,
        networkReader: conditionReader,
        hardwareReader: conditionReader
      ),
      applyEngine: ApplyEngine(registry: AdapterRegistry()),
      diagnosticLog: nil,
      defaults: defaults,
      loginItemService: loginItem
    )

    model.start()
    #expect(
      await eventually {
        model.profiles.count == 1 && !model.isProfileMutationLocked
      }
    )
    let profilesBefore = model.profiles
    let selectedBefore = model.selectedProfileID
    let documentBefore = await failingStore.currentDocument()

    let editor = ProfileEditorModel()
    editor.initialize(profiles: model.profiles, preferredProfileID: model.selectedProfileID)
    #expect(editor.updateDraft { $0.name = "Unsaved Profile Name" })
    let draftBefore = try #require(editor.draft)
    #expect(editor.isDirty)

    let deleteGate = AtomicDeleteGate()
    let presentation = TrayPresentationModel(
      model: model,
      locationPermission: LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .authorized
      ),
      profileEditor: editor,
      deleteOperation: { profileID in
        await deleteGate.enterAndWait()
        return await model.deleteProfile(id: profileID)
      }
    )
    var dismissRequests: [UInt64] = []
    presentation.setSurfaceDismissRequest { generation in
      dismissRequests.append(generation)
      presentation.trayDidClose(sessionGeneration: generation)
    }
    presentation.trayDidOpen(
      sessionGeneration: 51,
      viewport: CGSize(width: 368, height: 560)
    )
    await presentation.executeStayOpen(.requestDelete(profile.id))
    #expect(presentation.deletion.pendingProfileID == profile.id)
    #expect(presentation.focusTarget == .cancelDelete(profile.id))

    let confirmation = Task { @MainActor in
      await presentation.executeStayOpen(.confirmDelete(profile.id))
    }
    await deleteGate.waitUntilEntered()
    presentation.requestEscape()
    #expect(dismissRequests == [51])
    #expect(!presentation.isTrayVisible)
    #expect(presentation.deletion.pendingProfileID == profile.id)
    presentation.trayDidOpen(
      sessionGeneration: 52,
      viewport: CGSize(width: 368, height: 560)
    )
    #expect(presentation.isDeletionInFlight(profileID: profile.id))
    #expect(presentation.deletion.pendingProfileID == profile.id)

    await deleteGate.release()
    await confirmation.value

    let expectedError = appLocalized("A local profile storage operation failed.")
    #expect(presentation.deletion.pendingProfileID == profile.id)
    #expect(presentation.focusTarget == .cancelDelete(profile.id))
    #expect(presentation.handoffError == expectedError)
    #expect(presentation.isTrayVisible)
    #expect(editor.draft == draftBefore)
    #expect(editor.isDirty)
    #expect(editor.selectedProfileID == profile.id)
    #expect(model.profiles == profilesBefore)
    #expect(model.selectedProfileID == selectedBefore)
    #expect(model.storageStatus == expectedError)
    #expect(!model.isProfileMutationLocked)
    #expect(await failingStore.currentDocument() == documentBefore)
    #expect(try Data(contentsOf: locations.primaryURL) == primaryBefore)
    #expect(!loginItem.mutatedRegistration)
  }

  @Test("dirty deletion confirmation explicitly names unsaved-change loss in both languages")
  func dirtyDeletionConfirmationCopy() {
    let standard = ProfileDeletionConfirmationCopy.format(discardsUnsavedChanges: false)
    let dirty = ProfileDeletionConfirmationCopy.format(discardsUnsavedChanges: true)

    #expect(standard == ProfileDeletionConfirmationCopy.standardFormat)
    #expect(dirty == ProfileDeletionConfirmationCopy.unsavedChangesFormat)
    #expect(dirty != standard)
    #expect(appLocalizedRuntime(dirty, languageCode: "en").contains("unsaved changes"))
    #expect(appLocalizedRuntime(dirty, languageCode: "ko").contains("저장하지 않은 변경사항"))
    #expect(
      appLocalizedRuntime(TrayDeletionProgressCopy.title, languageCode: "en")
        == "Deleting Profile…"
    )
    #expect(
      appLocalizedRuntime(TrayDeletionProgressCopy.title, languageCode: "ko")
        == "프로필 삭제 중…"
    )
    #expect(
      appLocalizedRuntime(TrayDeletionProgressCopy.detail, languageCode: "en")
        .contains("cannot be cancelled")
    )
    #expect(
      appLocalizedRuntime(TrayDeletionProgressCopy.detail, languageCode: "ko")
        .contains("취소할 수 없습니다")
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

private actor AtomicDeleteGate {
  private(set) var entryCount = 0
  private var hasEntered = false
  private var isReleased = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func enterAndWait() async {
    entryCount += 1
    hasEntered = true
    let waiters = entryWaiters
    entryWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    guard !isReleased else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func waitUntilEntered() async {
    guard !hasEntered else { return }
    await withCheckedContinuation { entryWaiters.append($0) }
  }

  func release() {
    isReleased = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }
}

private actor AtomicDeleteConditionReader: ConditionDisplayReading, ConditionAudioReading,
  ConditionNetworkReading, ConditionHardwareReading
{
  func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity> { [] }
  func readAudioFacts() async throws -> ConditionAudioFacts { ConditionAudioFacts() }
  func readNetworkFacts() async throws -> ConditionNetworkFacts { ConditionNetworkFacts() }
  func readHardwareIdentifiers() async throws -> Set<String> { [] }
}

@MainActor
private final class AtomicDeleteLoginItemService: LoginItemServicing {
  private(set) var mutatedRegistration = false

  var status: SMAppService.Status { .notRegistered }

  func register() throws {
    mutatedRegistration = true
  }

  func unregister() throws {
    mutatedRegistration = true
  }
}
