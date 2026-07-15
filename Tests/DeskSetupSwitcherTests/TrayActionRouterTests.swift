import Foundation
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher

@Suite("Tray action lifetime policy")
@MainActor
struct TrayActionRouterTests {
  @Test("every tray action declares exactly one disposition")
  func everyActionHasOneDisposition() {
    let profileID = UUID()
    let actions: [(TrayAction, TrayActionDisposition)] = [
      (.requestDelete(profileID), .stayOpen),
      (.cancelDelete(profileID), .stayOpen),
      (.confirmDelete(profileID), .stayOpen),
      (.capture, .stayOpen),
      (.refresh, .stayOpen),
      (.dismissCaptureBanner, .stayOpen),
      (.dismissApplyBanner, .stayOpen),
      (.disabled, .stayOpen),
      (.openSettings, .handoff(.settings)),
      (.editProfile(profileID), .handoff(.profileEditor(profileID))),
      (
        .openPermissionWorkflow(.captureExplanation),
        .handoff(.permission(.captureExplanation))
      ),
      (
        .openApplyPreview(profileID, .normal),
        .handoff(.applyPreview(profileID, .normal))
      ),
      (.openResultDetails, .handoff(.resultDetails)),
      (.quit, .terminate),
    ]

    for (action, expected) in actions {
      #expect(action.disposition == expected)
    }
    #expect(actions.filter { $0.1 == .terminate }.map(\.0) == [.quit])
  }

  @Test("stay-open actions cannot close or order out the tray")
  func stayOpenDoesNotMutateSurface() async {
    let executor = ActionExecutorSpy()
    let presenter = DestinationPresenterSpy()
    let surface = TraySurfaceSpy(generation: 4, isVisible: true)
    let router = TrayActionRouter(
      executor: executor,
      destinationPresenter: presenter,
      surface: surface
    )

    let actions: [TrayAction] = [
      .requestDelete(UUID()), .cancelDelete(UUID()), .confirmDelete(UUID()),
      .capture, .refresh, .dismissCaptureBanner, .dismissApplyBanner, .disabled,
    ]
    for action in actions {
      await router.route(action, sessionGeneration: 4)
    }

    #expect(executor.actions == actions)
    #expect(surface.closeRequests.isEmpty)
    #expect(surface.orderOutRequests == 0)
    #expect(surface.isTrayVisible)
  }

  @Test("handoff closes only after destination is visible and key")
  func handoffOrdering() async {
    let events = EventLog()
    let executor = ActionExecutorSpy()
    let presenter = DestinationPresenterSpy(
      result: .presented(isVisible: true, isKeyOrActive: true)
    )
    let surface = TraySurfaceSpy(generation: 9, isVisible: true)
    let router = TrayActionRouter(
      executor: executor,
      destinationPresenter: presenter,
      surface: surface,
      eventSink: { events.values.append($0) }
    )

    await router.route(.openSettings, sessionGeneration: 9)

    #expect(
      events.values == [
        .destinationRequested(.settings),
        .destinationVisible(.settings),
        .destinationKeyOrActive(.settings),
        .trayCloseRequested(.settings),
      ])
    #expect(surface.closeRequests == [9])
    #expect(!surface.isTrayVisible)
  }

  @Test("failed or cancelled destination leaves the tray and error reachable")
  func failedDestinationDoesNotClose() async {
    let executor = ActionExecutorSpy()
    let presenter = DestinationPresenterSpy(result: .failed("Window could not be shown."))
    let surface = TraySurfaceSpy(generation: 3, isVisible: true)
    let router = TrayActionRouter(
      executor: executor,
      destinationPresenter: presenter,
      surface: surface
    )

    await router.route(.openSettings, sessionGeneration: 3)

    #expect(surface.closeRequests.isEmpty)
    #expect(surface.isTrayVisible)
    #expect(executor.errors == ["Window could not be shown."])
  }

  @Test("double-click while handoff is pending creates one destination")
  func handoffReentryIsIdempotent() async {
    let gate = PresentationGate()
    let executor = ActionExecutorSpy()
    let presenter = DestinationPresenterSpy(gate: gate)
    let surface = TraySurfaceSpy(generation: 12, isVisible: true)
    let router = TrayActionRouter(
      executor: executor,
      destinationPresenter: presenter,
      surface: surface
    )

    let first = Task { await router.route(.openSettings, sessionGeneration: 12) }
    await gate.waitUntilEntered()
    let second = Task { await router.route(.openSettings, sessionGeneration: 12) }
    await Task.yield()

    #expect(presenter.presentations == [.settings])
    await gate.release()
    await first.value
    await second.value
    #expect(presenter.presentations == [.settings])
    #expect(surface.closeRequests == [12])
  }

  @Test("completion from an older open session cannot close a reopened tray")
  func staleCompletionIsIgnored() async {
    let gate = PresentationGate()
    let executor = ActionExecutorSpy()
    let presenter = DestinationPresenterSpy(gate: gate)
    let surface = TraySurfaceSpy(generation: 21, isVisible: true)
    let router = TrayActionRouter(
      executor: executor,
      destinationPresenter: presenter,
      surface: surface
    )

    let task = Task { await router.route(.openSettings, sessionGeneration: 21) }
    await gate.waitUntilEntered()
    surface.reopen(generation: 22)
    await gate.release()
    await task.value

    #expect(surface.closeRequests.isEmpty)
    #expect(surface.isTrayVisible)
    #expect(surface.activeSessionGeneration == 22)
  }
}

@MainActor
private final class ActionExecutorSpy: TrayActionExecuting {
  private(set) var actions: [TrayAction] = []
  private(set) var errors: [String] = []

  func executeStayOpen(_ action: TrayAction) async {
    actions.append(action)
  }

  func reportHandoffFailure(_ message: String) {
    errors.append(message)
  }
}

@MainActor
private final class DestinationPresenterSpy: TrayDestinationPresenting {
  private let result: TrayDestinationPresentation
  private let gate: PresentationGate?
  private(set) var presentations: [TrayDestination] = []

  init(
    result: TrayDestinationPresentation = .presented(isVisible: true, isKeyOrActive: true),
    gate: PresentationGate? = nil
  ) {
    self.result = result
    self.gate = gate
  }

  func present(_ destination: TrayDestination) async -> TrayDestinationPresentation {
    presentations.append(destination)
    if let gate {
      await gate.enterAndWait()
    }
    return result
  }
}

@MainActor
private final class TraySurfaceSpy: TraySurfaceRouting {
  private(set) var closeRequests: [UInt64] = []
  private(set) var orderOutRequests = 0
  private(set) var isTrayVisible: Bool
  private(set) var activeSessionGeneration: UInt64?

  init(generation: UInt64, isVisible: Bool) {
    activeSessionGeneration = generation
    isTrayVisible = isVisible
  }

  func requestClose(sessionGeneration: UInt64) {
    closeRequests.append(sessionGeneration)
    isTrayVisible = false
    activeSessionGeneration = nil
  }

  func reopen(generation: UInt64) {
    activeSessionGeneration = generation
    isTrayVisible = true
  }
}

@MainActor
private final class EventLog {
  var values: [TrayRoutingEvent] = []
}

private actor PresentationGate {
  private var entered = false
  private var released = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func enterAndWait() async {
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
