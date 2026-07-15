import AppKit
import SwiftUI

@MainActor
protocol TrayStatusItemSurface: AnyObject {
  var anchorView: NSView? { get }
  func configure(target: AnyObject, action: Selector)
}

@MainActor
protocol TrayPopoverSurface: AnyObject {
  var behavior: NSPopover.Behavior { get set }
  var contentSize: NSSize { get set }
  var contentViewController: NSViewController? { get set }
  var isShown: Bool { get }
  var contentWindow: NSWindow? { get }
  func setDidCloseHandler(_ handler: @escaping @MainActor () -> Void)
  func show(
    relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge)
  func performClose(_ sender: Any?)
}

@MainActor
protocol TrayDismissalMonitoring: AnyObject {
  func start(
    anchorView: NSView,
    contentWindow: @escaping @MainActor () -> NSWindow?,
    dismiss: @escaping @MainActor () -> Void
  )
  func stop()
}

@MainActor
protocol TraySurfaceFactory: AnyObject {
  func makeStatusItem() -> any TrayStatusItemSurface
  func makePopover() -> any TrayPopoverSurface
  func makeDismissalMonitor() -> any TrayDismissalMonitoring
  func screenMetrics(for anchorView: NSView) -> TrayScreenMetrics
}

@MainActor
final class AppKitTraySurfaceFactory: TraySurfaceFactory {
  func makeStatusItem() -> any TrayStatusItemSurface {
    AppKitTrayStatusItemSurface()
  }

  func makePopover() -> any TrayPopoverSurface {
    AppKitTrayPopoverSurface()
  }

  func makeDismissalMonitor() -> any TrayDismissalMonitoring {
    AppKitTrayDismissalMonitor()
  }

  func screenMetrics(for anchorView: NSView) -> TrayScreenMetrics {
    let screen = anchorView.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
    return TrayScreenMetrics(
      visibleFrame: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900),
      backingScaleFactor: screen?.backingScaleFactor ?? 1
    )
  }
}

@MainActor
private final class AppKitTrayStatusItemSurface: TrayStatusItemSurface {
  let statusItem: NSStatusItem

  init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem.button {
      let image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil)
      image?.isTemplate = true
      button.image = image
      button.imagePosition = .imageOnly
      button.toolTip = appLocalized("Desk Setup Switcher")
      button.setAccessibilityLabel(appLocalized("Desk Setup Switcher"))
      button.setAccessibilityHelp(
        appLocalized("Opens or closes the Desk Setup Switcher tray."))
    }
  }

  var anchorView: NSView? {
    statusItem.button
  }

  func configure(target: AnyObject, action: Selector) {
    statusItem.button?.target = target
    statusItem.button?.action = action
    statusItem.button?.sendAction(on: [.leftMouseUp])
  }
}

@MainActor
private final class AppKitTrayPopoverSurface: NSObject, TrayPopoverSurface, NSPopoverDelegate {
  private let popover = NSPopover()
  private var didCloseHandler: (@MainActor () -> Void)?

  override init() {
    super.init()
    popover.delegate = self
    popover.animates = false
  }

  var behavior: NSPopover.Behavior {
    get { popover.behavior }
    set { popover.behavior = newValue }
  }

  var contentSize: NSSize {
    get { popover.contentSize }
    set { popover.contentSize = newValue }
  }

  var contentViewController: NSViewController? {
    get { popover.contentViewController }
    set { popover.contentViewController = newValue }
  }

  var isShown: Bool {
    popover.isShown
  }

  var contentWindow: NSWindow? {
    popover.contentViewController?.view.window
  }

  func setDidCloseHandler(_ handler: @escaping @MainActor () -> Void) {
    didCloseHandler = handler
  }

  func show(
    relativeTo positioningRect: NSRect,
    of positioningView: NSView,
    preferredEdge: NSRectEdge
  ) {
    popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
  }

  func performClose(_ sender: Any?) {
    popover.performClose(sender)
  }

  func popoverDidClose(_ notification: Notification) {
    didCloseHandler?()
  }
}

@MainActor
private final class AppKitTrayDismissalMonitor: TrayDismissalMonitoring {
  private var localMouseMonitor: Any?
  private var globalMouseMonitor: Any?
  private var deactivateObserver: NSObjectProtocol?

  func start(
    anchorView: NSView,
    contentWindow: @escaping @MainActor () -> NSWindow?,
    dismiss: @escaping @MainActor () -> Void
  ) {
    stop()
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
      if event.window === contentWindow() {
        return event
      }
      if event.window === anchorView.window,
        anchorView.bounds.contains(anchorView.convert(event.locationInWindow, from: nil))
      {
        return event
      }
      dismiss()
      return event
    }
    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in
      Task { @MainActor in dismiss() }
    }
    deactivateObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApplication.shared,
      queue: .main
    ) { _ in
      Task { @MainActor in dismiss() }
    }
  }

  func stop() {
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
    }
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
    }
    if let deactivateObserver {
      NotificationCenter.default.removeObserver(deactivateObserver)
    }
    localMouseMonitor = nil
    globalMouseMonitor = nil
    deactivateObserver = nil
  }

}

/// Owns the single status item, popover, hosting controller, anchor, monitor,
/// and immutable geometry for each open generation.
@MainActor
final class TrayPopoverController: NSObject, TraySurfaceRouting {
  private let statusItem: any TrayStatusItemSurface
  private let popover: any TrayPopoverSurface
  private let dismissalMonitor: any TrayDismissalMonitoring
  private let factory: any TraySurfaceFactory
  private let sessionState: any TraySessionStateUpdating
  private let hostingController: NSHostingController<AnyView>
  private var sessionGeometry: TrayOpenSessionGeometry
  private var generationCounter: UInt64 = 0

  private(set) var activeSessionGeneration: UInt64?

  init<Content: View>(
    rootView: Content,
    sessionState: any TraySessionStateUpdating,
    geometry: TrayGeometry = TrayGeometry(),
    factory: any TraySurfaceFactory = AppKitTraySurfaceFactory()
  ) {
    self.factory = factory
    self.sessionState = sessionState
    statusItem = factory.makeStatusItem()
    popover = factory.makePopover()
    dismissalMonitor = factory.makeDismissalMonitor()
    hostingController = NSHostingController(rootView: AnyView(rootView))
    sessionGeometry = TrayOpenSessionGeometry(policy: geometry)
    super.init()

    popover.behavior = .applicationDefined
    popover.contentViewController = hostingController
    popover.setDidCloseHandler { [weak self] in
      self?.finishClosingCurrentSession()
    }
    statusItem.configure(target: self, action: #selector(togglePopover(_:)))
  }

  var isTrayVisible: Bool {
    activeSessionGeneration != nil && popover.isShown
  }

  var contentSize: CGSize {
    popover.contentSize
  }

  var hostingViewBounds: CGRect {
    hostingController.view.bounds
  }

  var contentViewBounds: CGRect {
    popover.contentViewController?.view.bounds ?? .zero
  }

  var popoverBehavior: NSPopover.Behavior {
    popover.behavior
  }

  @objc private func togglePopover(_ sender: Any?) {
    if isTrayVisible {
      if let generation = activeSessionGeneration {
        requestClose(sessionGeneration: generation)
      }
    } else {
      show()
    }
  }

  func show() {
    guard activeSessionGeneration == nil, !popover.isShown,
      let anchorView = statusItem.anchorView
    else { return }

    generationCounter &+= 1
    let generation = generationCounter
    let viewport = sessionGeometry.open(
      context: sessionState.geometryContext,
      screen: factory.screenMetrics(for: anchorView)
    )
    activeSessionGeneration = generation

    popover.contentSize = viewport
    hostingController.view.frame = NSRect(origin: .zero, size: viewport)
    hostingController.view.autoresizingMask = [.width, .height]
    hostingController.view.needsLayout = true
    hostingController.view.layoutSubtreeIfNeeded()

    sessionState.trayDidOpen(sessionGeneration: generation, viewport: viewport)
    popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    dismissalMonitor.start(
      anchorView: anchorView,
      contentWindow: { [weak popover] in popover?.contentWindow },
      dismiss: { [weak self] in
        guard let self, let generation = self.activeSessionGeneration else { return }
        self.requestClose(sessionGeneration: generation)
      }
    )
  }

  func requestClose(sessionGeneration: UInt64) {
    guard activeSessionGeneration == sessionGeneration else { return }
    finishClosingCurrentSession()
    if popover.isShown {
      popover.performClose(nil)
    }
  }

  private func finishClosingCurrentSession() {
    guard let generation = activeSessionGeneration else { return }
    dismissalMonitor.stop()
    activeSessionGeneration = nil
    sessionGeometry.close()
    sessionState.trayDidClose(sessionGeneration: generation)
  }
}
