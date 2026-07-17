import AppKit
import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

enum TrayPermissionWorkflow: Hashable, Sendable {
  case captureExplanation
  case captureDenied
  case captureDirtyDraft
  case systemSettings
}

enum TrayDestination: Hashable, Sendable {
  case settings
  case profileEditor(UUID)
  case permission(TrayPermissionWorkflow)
  case applyPreview(UUID, ApplyMode)
  case resultDetails
}

enum TrayActionDisposition: Hashable, Sendable {
  case stayOpen
  case handoff(TrayDestination)
  case terminate
}

enum TrayAction: Hashable, Sendable {
  case requestDelete(UUID)
  case cancelDelete(UUID)
  case confirmDelete(UUID)
  case capture
  case refresh
  case dismissCaptureBanner
  case dismissApplyBanner
  case disabled
  case openSettings
  case editProfile(UUID)
  case openPermissionWorkflow(TrayPermissionWorkflow)
  case openApplyPreview(UUID, ApplyMode)
  case openResultDetails
  case quit

  var disposition: TrayActionDisposition {
    switch self {
    case .requestDelete, .cancelDelete, .confirmDelete, .capture, .refresh,
      .dismissCaptureBanner, .dismissApplyBanner, .disabled:
      .stayOpen
    case .openSettings:
      .handoff(.settings)
    case .editProfile(let profileID):
      .handoff(.profileEditor(profileID))
    case .openPermissionWorkflow(let workflow):
      .handoff(.permission(workflow))
    case .openApplyPreview(let profileID, let mode):
      .handoff(.applyPreview(profileID, mode))
    case .openResultDetails:
      .handoff(.resultDetails)
    case .quit:
      .terminate
    }
  }
}

enum TrayDestinationPresentation: Equatable, Sendable {
  case presented(isVisible: Bool, isKeyOrActive: Bool)
  case failed(String)
  case cancelled
}

enum TrayRoutingEvent: Equatable, Sendable {
  case destinationRequested(TrayDestination)
  case destinationVisible(TrayDestination)
  case destinationKeyOrActive(TrayDestination)
  case trayCloseRequested(TrayDestination)
}

@MainActor
protocol TrayActionExecuting: AnyObject {
  func executeStayOpen(_ action: TrayAction) async
  func reportHandoffFailure(_ message: String)
}

@MainActor
protocol TrayDestinationPresenting: AnyObject {
  func present(_ destination: TrayDestination) async -> TrayDestinationPresentation
}

@MainActor
protocol TraySurfaceRouting: AnyObject {
  var isTrayVisible: Bool { get }
  var activeSessionGeneration: UInt64? { get }
  func requestClose(sessionGeneration: UInt64)
}

/// The only type allowed to translate a tray action into a surface lifetime
/// change. Stay-open executors intentionally receive no surface reference.
@MainActor
final class TrayActionRouter {
  private weak var executor: (any TrayActionExecuting)?
  private weak var destinationPresenter: (any TrayDestinationPresenting)?
  weak var surface: (any TraySurfaceRouting)?

  private let terminateApplication: @MainActor () -> Void
  private let eventSink: @MainActor (TrayRoutingEvent) -> Void
  private var actionsInFlight: Set<TrayAction> = []
  private var isDestinationHandoffInFlight = false

  init(
    executor: any TrayActionExecuting,
    destinationPresenter: any TrayDestinationPresenting,
    surface: (any TraySurfaceRouting)? = nil,
    terminateApplication: @escaping @MainActor () -> Void = {
      NSApplication.shared.terminate(nil)
    },
    eventSink: @escaping @MainActor (TrayRoutingEvent) -> Void = { _ in }
  ) {
    self.executor = executor
    self.destinationPresenter = destinationPresenter
    self.surface = surface
    self.terminateApplication = terminateApplication
    self.eventSink = eventSink
  }

  func route(_ action: TrayAction, sessionGeneration: UInt64) async {
    guard actionsInFlight.insert(action).inserted else { return }
    defer { actionsInFlight.remove(action) }

    switch action.disposition {
    case .stayOpen:
      await executor?.executeStayOpen(action)

    case .handoff(let destination):
      // All destinations share one native window handoff slot. Per-action
      // deduplication is insufficient because two different profile actions
      // can otherwise join the same window presentation and both mutate the
      // workflow after it becomes key.
      guard !isDestinationHandoffInFlight else { return }
      isDestinationHandoffInFlight = true
      defer { isDestinationHandoffInFlight = false }
      guard let destinationPresenter else {
        executor?.reportHandoffFailure(appLocalized("The destination could not be opened."))
        return
      }
      eventSink(.destinationRequested(destination))
      let result = await destinationPresenter.present(destination)
      switch result {
      case .presented(let isVisible, let isKeyOrActive):
        if isVisible {
          eventSink(.destinationVisible(destination))
        }
        if isKeyOrActive {
          eventSink(.destinationKeyOrActive(destination))
        }
        guard isVisible, isKeyOrActive else {
          executor?.reportHandoffFailure(
            appLocalized("The destination window did not become visible and active."))
          return
        }
        guard let surface,
          surface.isTrayVisible,
          surface.activeSessionGeneration == sessionGeneration
        else {
          return
        }
        eventSink(.trayCloseRequested(destination))
        surface.requestClose(sessionGeneration: sessionGeneration)

      case .failed(let message):
        executor?.reportHandoffFailure(message)
      case .cancelled:
        executor?.reportHandoffFailure(appLocalized("Opening the destination was cancelled."))
      }

    case .terminate:
      terminateApplication()
    }
  }
}
