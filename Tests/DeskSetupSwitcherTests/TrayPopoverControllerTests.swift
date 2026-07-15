import AppKit
import SwiftUI
import Testing

@testable import DeskSetupSwitcher

@Suite("Owned tray popover surface")
@MainActor
struct TrayPopoverControllerTests {
  @Test("controller owns one application-defined popover with matching viewport bounds")
  func ownsOneSurfaceAndMatchesBounds() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 3))
    let factory = SurfaceFactorySpy()
    let controller = TrayPopoverController(
      rootView: Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity),
      sessionState: state,
      factory: factory
    )

    controller.show()

    #expect(factory.statusItemCreations == 1)
    #expect(factory.popoverCreations == 1)
    #expect(factory.monitorCreations == 1)
    #expect(controller.popoverBehavior == .applicationDefined)
    #expect(controller.contentSize == CGSize(width: 368, height: 560))
    #expect(controller.hostingViewBounds.size == controller.contentSize)
    #expect(controller.contentViewBounds.size == controller.contentSize)
    #expect(state.openEvents == [.init(generation: 1, viewport: controller.contentSize)])
    #expect(factory.monitor.startCount == 1)
  }

  @Test("state updates never resize an open session")
  func openSessionDoesNotResize() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 1))
    let factory = SurfaceFactorySpy()
    let controller = TrayPopoverController(
      rootView: Color.clear,
      sessionState: state,
      factory: factory
    )
    controller.show()
    let opened = controller.contentSize

    state.context = TrayGeometryContext(
      profileCount: 10,
      deletionConfirmationVisible: true,
      capturePhase: .error,
      applyBannerVisible: true,
      usesLargeText: true
    )

    #expect(controller.contentSize == opened)
    #expect(factory.popover.contentSizeAssignments == [opened])
  }

  @Test("dismiss and reopen reuse ownership but create a new geometry generation")
  func reopenDoesNotDuplicateOwnership() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 1))
    let factory = SurfaceFactorySpy()
    let controller = TrayPopoverController(
      rootView: Color.clear,
      sessionState: state,
      factory: factory
    )
    controller.show()
    let firstGeneration = controller.activeSessionGeneration
    controller.requestClose(sessionGeneration: firstGeneration!)

    factory.metrics = TrayScreenMetrics(
      visibleFrame: CGRect(x: 1_440, y: 0, width: 1_024, height: 400),
      backingScaleFactor: 1
    )
    state.context = TrayGeometryContext(profileCount: 10)
    controller.show()

    #expect(factory.statusItemCreations == 1)
    #expect(factory.popoverCreations == 1)
    #expect(factory.monitorCreations == 1)
    #expect(controller.activeSessionGeneration == firstGeneration! + 1)
    #expect(controller.contentSize.height == 336)
    #expect(factory.monitor.startCount == 2)
    #expect(factory.monitor.stopCount == 1)
    #expect(state.closeGenerations == [firstGeneration!])
  }

  @Test("external mouse or app deactivation monitor closes and is removed")
  func scopedDismissalMonitorCloses() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 0))
    let factory = SurfaceFactorySpy()
    let controller = TrayPopoverController(
      rootView: Color.clear,
      sessionState: state,
      factory: factory
    )
    controller.show()
    let generation = controller.activeSessionGeneration

    factory.monitor.triggerDismiss()

    #expect(!controller.isTrayVisible)
    #expect(controller.activeSessionGeneration == nil)
    #expect(state.closeGenerations == [generation!])
    #expect(factory.monitor.stopCount == 1)
  }
}

@MainActor
private final class SessionStateSpy: TraySessionStateUpdating {
  struct OpenEvent: Equatable {
    let generation: UInt64
    let viewport: CGSize
  }

  var context: TrayGeometryContext
  private(set) var openEvents: [OpenEvent] = []
  private(set) var closeGenerations: [UInt64] = []

  init(context: TrayGeometryContext) {
    self.context = context
  }

  var geometryContext: TrayGeometryContext { context }

  func trayDidOpen(sessionGeneration: UInt64, viewport: CGSize) {
    openEvents.append(.init(generation: sessionGeneration, viewport: viewport))
  }

  func trayDidClose(sessionGeneration: UInt64) {
    closeGenerations.append(sessionGeneration)
  }
}

@MainActor
private final class SurfaceFactorySpy: TraySurfaceFactory {
  private(set) var statusItemCreations = 0
  private(set) var popoverCreations = 0
  private(set) var monitorCreations = 0
  let statusItem = StatusItemSurfaceSpy()
  let popover = PopoverSurfaceSpy()
  let monitor = DismissalMonitorSpy()
  var metrics = TrayScreenMetrics(
    visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
    backingScaleFactor: 2
  )

  func makeStatusItem() -> any TrayStatusItemSurface {
    statusItemCreations += 1
    return statusItem
  }

  func makePopover() -> any TrayPopoverSurface {
    popoverCreations += 1
    return popover
  }

  func makeDismissalMonitor() -> any TrayDismissalMonitoring {
    monitorCreations += 1
    return monitor
  }

  func screenMetrics(for anchorView: NSView) -> TrayScreenMetrics {
    metrics
  }
}

@MainActor
private final class StatusItemSurfaceSpy: TrayStatusItemSurface {
  let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
  private(set) var configurationCount = 0

  var anchorView: NSView? { anchor }

  func configure(target: AnyObject, action: Selector) {
    configurationCount += 1
  }
}

@MainActor
private final class PopoverSurfaceSpy: TrayPopoverSurface {
  var behavior: NSPopover.Behavior = .transient
  var contentSize: NSSize = .zero {
    didSet { contentSizeAssignments.append(contentSize) }
  }
  var contentViewController: NSViewController?
  private(set) var isShown = false
  var contentWindow: NSWindow? { nil }
  private var didClose: (@MainActor () -> Void)?
  private(set) var contentSizeAssignments: [CGSize] = []

  func setDidCloseHandler(_ handler: @escaping @MainActor () -> Void) {
    didClose = handler
  }

  func show(
    relativeTo positioningRect: NSRect,
    of positioningView: NSView,
    preferredEdge: NSRectEdge
  ) {
    isShown = true
  }

  func performClose(_ sender: Any?) {
    isShown = false
    didClose?()
  }
}

@MainActor
private final class DismissalMonitorSpy: TrayDismissalMonitoring {
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private var dismiss: (@MainActor () -> Void)?

  func start(
    anchorView: NSView,
    contentWindow: @escaping @MainActor () -> NSWindow?,
    dismiss: @escaping @MainActor () -> Void
  ) {
    startCount += 1
    self.dismiss = dismiss
  }

  func stop() {
    stopCount += 1
    dismiss = nil
  }

  func triggerDismiss() {
    dismiss?()
  }
}
