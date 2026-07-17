import CoreLocation
import Testing

@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("App-lifetime tray presentation state")
  @MainActor
  struct TrayPresentationModelTests {
    @Test("dismiss and reopen preserve inline deletion state and focus intent")
    func deletionStateSurvivesViewLifetime() async {
      let fixture = UIAuditFixtures.fixture(.overview)
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      model.configureForUIAudit(fixture)
      let presentation = makePresentation(model: model)
      let first = fixture.profiles[0].id

      presentation.trayDidOpen(
        sessionGeneration: 1,
        viewport: CGSize(width: 368, height: 560)
      )
      presentation.trayContentDidAttach(sessionGeneration: 1)
      #expect(
        presentation.scrollResetRequest
          == TrayScrollResetRequest(sessionGeneration: 1, anchor: .top)
      )
      await presentation.executeStayOpen(.requestDelete(first))
      #expect(presentation.deletion.pendingProfileID == first)
      #expect(presentation.focusTarget == .cancelDelete(first))

      presentation.trayDidClose(sessionGeneration: 1)
      presentation.trayDidOpen(
        sessionGeneration: 2,
        viewport: CGSize(width: 368, height: 560)
      )
      presentation.trayContentDidAttach(sessionGeneration: 2)
      #expect(
        presentation.scrollResetRequest
          == TrayScrollResetRequest(sessionGeneration: 2, anchor: .top)
      )
      #expect(presentation.deletion.pendingProfileID == first)
      #expect(presentation.focusTarget == .cancelDelete(first))

      await presentation.executeStayOpen(.cancelDelete(first))
      #expect(presentation.deletion.pendingProfileID == nil)
      #expect(presentation.focusTarget == .delete(first))
    }

    @Test("view disappearance neither cancels nor duplicates capture work")
    func captureTaskSurvivesDismissAndDeduplicates() async {
      let fixture = UIAuditFixtures.fixture(.overview)
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      model.configureForUIAudit(fixture)
      let gate = CaptureGate()
      let presentation = makePresentation(model: model) {
        await gate.enterAndWait()
        return .rejected(message: "Synthetic capture failure")
      }

      presentation.trayDidOpen(
        sessionGeneration: 10,
        viewport: CGSize(width: 368, height: 560)
      )
      presentation.trayContentDidAttach(sessionGeneration: 10)
      await presentation.executeStayOpen(.capture)
      await gate.waitUntilEntered()
      #expect(presentation.capturePhase == .running)
      #expect(presentation.hasCaptureTask)

      presentation.trayDidClose(sessionGeneration: 10)
      presentation.trayDidOpen(
        sessionGeneration: 11,
        viewport: CGSize(width: 368, height: 560)
      )
      presentation.trayContentDidAttach(sessionGeneration: 11)
      await presentation.executeStayOpen(.capture)
      #expect(await gate.entryCount == 1)
      #expect(presentation.capturePhase == .running)

      await gate.release()
      for _ in 0..<20 where presentation.hasCaptureTask {
        await Task.yield()
      }
      #expect(presentation.capturePhase == .failure("Synthetic capture failure"))
      #expect(!presentation.hasCaptureTask)
    }

    @Test("twenty open generations each request a fresh top scroll")
    func everyReopenRequestsTopScroll() {
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      let presentation = makePresentation(model: model)
      let viewport = CGSize(width: 368, height: 560)

      for generation in UInt64(1)...20 {
        let previousRequest = presentation.scrollResetRequest
        presentation.trayDidOpen(sessionGeneration: generation, viewport: viewport)
        #expect(presentation.scrollResetRequest == previousRequest)
        presentation.trayContentDidAttach(sessionGeneration: generation &- 1)
        #expect(presentation.scrollResetRequest == previousRequest)
        presentation.trayContentDidAttach(sessionGeneration: generation)
        #expect(
          presentation.scrollResetRequest
            == TrayScrollResetRequest(sessionGeneration: generation, anchor: .top)
        )
        #expect(presentation.viewport == viewport)
        presentation.trayDidClose(sessionGeneration: generation)
      }
    }

    @Test("delete confirmation focuses cancel, then delete, then the next profile")
    func deletionFocusPolicy() async {
      let fixture = UIAuditFixtures.fixture(.overview)
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      model.configureForUIAudit(fixture)
      let presentation = makePresentation(model: model)
      let first = fixture.profiles[0].id
      let next = fixture.profiles[1].id

      await presentation.executeStayOpen(.requestDelete(first))
      #expect(presentation.focusTarget == .cancelDelete(first))
      await presentation.executeStayOpen(.cancelDelete(first))
      #expect(presentation.focusTarget == .delete(first))
      await presentation.executeStayOpen(.requestDelete(first))
      await presentation.executeStayOpen(.confirmDelete(first))
      #expect(presentation.focusTarget == .profile(next))
    }

    @Test("SwiftUI tray root owns no second full-surface material")
    func singleSurfaceMaterialPolicy() {
      #expect(TraySurfaceStylePolicy.swiftUIFullSurfaceBackgroundLayerCount == 0)
    }

    @Test("icon actions expose labels, help, and non-color status copy")
    func accessibilityCopyIsExplicit() {
      #expect(TrayAccessibilityCopy.captureLabel == "Capture Current Settings")
      #expect(TrayAccessibilityCopy.captureHelp.contains("without changing"))
      #expect(TrayAccessibilityCopy.settingsLabel == "Settings")
      #expect(TrayAccessibilityCopy.settingsHelp.contains("persistent"))
      #expect(TrayAccessibilityCopy.quitLabel == "Quit Desk Setup Switcher")
    }

    @Test("late cancelled capture cannot clear an immediate replacement task")
    func captureTaskOwnershipSurvivesImmediateRestart() async {
      let gate = SequencedCaptureGate()
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      let presentation = makePresentation(model: model) {
        await gate.capture()
      }

      presentation.startCapture()
      await gate.waitUntilEntryCount(1)
      #expect(presentation.hasCaptureTask)
      #expect(presentation.capturePhase == .running)

      presentation.cancelCapture()
      presentation.startCapture()
      await gate.waitUntilEntryCount(2)
      #expect(presentation.hasCaptureTask)
      #expect(presentation.capturePhase == .running)

      await gate.release(index: 1, message: "Stale first failure")
      for _ in 0..<20 {
        await Task.yield()
      }
      #expect(presentation.hasCaptureTask)
      #expect(presentation.capturePhase == .running)

      await gate.release(index: 2, message: "Current second failure")
      for _ in 0..<100 where presentation.hasCaptureTask {
        await Task.yield()
      }
      #expect(!presentation.hasCaptureTask)
      #expect(presentation.capturePhase == .failure("Current second failure"))
    }

    private func makePresentation(
      model: ApplicationModel,
      capture: TrayPresentationModel.CaptureOperation? = nil,
      delete: TrayPresentationModel.DeleteOperation? = { _ in .deleted }
    ) -> TrayPresentationModel {
      TrayPresentationModel(
        model: model,
        locationPermission: LocationPermissionController(
          allowsSystemRequests: false,
          syntheticAuthorizationStatus: .authorized
        ),
        profileEditor: ProfileEditorModel(),
        captureOperation: capture,
        deleteOperation: delete
      )
    }
  }

  private actor CaptureGate {
    private(set) var entryCount = 0
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
      entryCount += 1
      entered = true
      let waiters = entryWaiters
      entryWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      guard !released else { return }
      await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
      guard !entered else { return }
      await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
      released = true
      let waiters = releaseWaiters
      releaseWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
    }
  }

  private actor SequencedCaptureGate {
    private var entryCount = 0
    private var entryWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var resultWaiters: [Int: CheckedContinuation<ProfileCreationCaptureResult, Never>] =
      [:]

    func capture() async -> ProfileCreationCaptureResult {
      entryCount += 1
      let index = entryCount
      let ready = entryWaiters.filter { $0.count <= entryCount }
      entryWaiters.removeAll { $0.count <= entryCount }
      for waiter in ready {
        waiter.continuation.resume()
      }
      return await withCheckedContinuation { resultWaiters[index] = $0 }
    }

    func waitUntilEntryCount(_ expected: Int) async {
      guard entryCount < expected else { return }
      await withCheckedContinuation {
        entryWaiters.append((count: expected, continuation: $0))
      }
    }

    func release(index: Int, message: String) {
      guard let continuation = resultWaiters.removeValue(forKey: index) else { return }
      continuation.resume(returning: .rejected(message: message))
    }
  }
#endif
