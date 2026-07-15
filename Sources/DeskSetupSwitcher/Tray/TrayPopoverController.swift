import AppKit
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

enum TrayStatusItemState: Equatable, Sendable {
  case noMatch
  case matching(DeskProfile)
  case applying(DeskProfile)
}

struct TrayStatusItemSnapshot: Equatable, Sendable {
  var profiles: [DeskProfile]
  var selectedProfileID: UUID?
  var visibleReadinessByProfile: [UUID: ProfileReadiness]
  var operationCountByProfile: [UUID: Int]
  var hasFreshReadiness: Bool
}

struct TrayStatusItemPresentation: Equatable, Sendable {
  static let fallbackSymbolName = "square.stack.3d.up"

  var state: TrayStatusItemState
  var symbolName: String
  var title: String
  var toolTip: String
  var accessibilityValue: String
}

struct TrayStatusItemPresentationBuilder: Sendable {
  static let maximumDisplayedNameLength = 18

  func presentation(for snapshot: TrayStatusItemSnapshot) -> TrayStatusItemPresentation {
    if let applying = snapshot.profiles.first(where: {
      $0.isEnabled && snapshot.visibleReadinessByProfile[$0.id] == .applying
    }) {
      let displayName = compactName(applying.name)
      let status = appLocalized("Applying \(applying.name)…")
      return TrayStatusItemPresentation(
        state: .applying(applying),
        symbolName: resolvedSymbolName(applying.symbolName),
        title: appLocalized("\(displayName) · Applying…"),
        toolTip: status,
        accessibilityValue: status
      )
    }

    let matchingProfiles: [DeskProfile]
    if snapshot.hasFreshReadiness {
      matchingProfiles = snapshot.profiles.filter { profile in
        profile.isEnabled
          && snapshot.visibleReadinessByProfile[profile.id] == .ready
          && snapshot.operationCountByProfile[profile.id] == 0
          && snapshot.operationCountByProfile[profile.id] != nil
          && SettingGroup.allCases.contains { profile.settings.payload(for: $0) != nil }
      }
    } else {
      matchingProfiles = []
    }
    let matching =
      matchingProfiles.first(where: { $0.id == snapshot.selectedProfileID })
      ?? matchingProfiles.first
    if let matching {
      let status = appLocalized("Current Mac matches \(matching.name).")
      return TrayStatusItemPresentation(
        state: .matching(matching),
        symbolName: resolvedSymbolName(matching.symbolName),
        title: compactName(matching.name),
        toolTip: status,
        accessibilityValue: status
      )
    }

    let status = appLocalized("No current profile match")
    return TrayStatusItemPresentation(
      state: .noMatch,
      symbolName: TrayStatusItemPresentation.fallbackSymbolName,
      title: "",
      toolTip: appLocalized("Desk Setup Switcher — no enabled profile is confirmed to match"),
      accessibilityValue: status
    )
  }

  private func compactName(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = trimmed.isEmpty ? appLocalized("Profile") : trimmed
    guard safe.count > Self.maximumDisplayedNameLength else { return safe }
    return String(safe.prefix(Self.maximumDisplayedNameLength - 1)) + "…"
  }

  private func resolvedSymbolName(_ value: String) -> String {
    let resolved = appResolvedProfileSymbolName(value)
    return resolved == "questionmark.square.dashed"
      ? TrayStatusItemPresentation.fallbackSymbolName
      : resolved
  }
}

@MainActor
protocol TrayStatusItemSurface: AnyObject {
  var anchorView: NSView? { get }
  func configure(target: AnyObject, action: Selector)
  func update(_ presentation: TrayStatusItemPresentation)
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
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
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

  func update(_ presentation: TrayStatusItemPresentation) {
    guard let button = statusItem.button else { return }
    let requested = NSImage(
      systemSymbolName: presentation.symbolName,
      accessibilityDescription: nil
    )
    let fallback = NSImage(
      systemSymbolName: TrayStatusItemPresentation.fallbackSymbolName,
      accessibilityDescription: nil
    )
    let image = requested ?? fallback
    image?.isTemplate = true
    button.image = image
    button.title = presentation.title
    button.imagePosition = presentation.title.isEmpty ? .imageOnly : .imageLeading
    button.toolTip = presentation.toolTip
    button.setAccessibilityValue(presentation.accessibilityValue)
    statusItem.length =
      presentation.title.isEmpty
      ? NSStatusItem.squareLength
      : min(172, max(48, button.fittingSize.width + 8))
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
    hostingController.sizingOptions = []
    sessionGeometry = TrayOpenSessionGeometry(policy: geometry)
    super.init()

    popover.behavior = .applicationDefined
    popover.contentViewController = hostingController
    popover.setDidCloseHandler { [weak self] in
      self?.finishClosingCurrentSession()
    }
    statusItem.configure(target: self, action: #selector(togglePopover(_:)))
    statusItem.update(sessionState.statusItemPresentation)
    sessionState.setStatusItemPresentationHandler { [weak self] presentation in
      self?.statusItem.update(presentation)
    }
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

  var hostingViewFrame: CGRect {
    hostingController.view.frame
  }

  var hostingViewSafeAreaInsets: NSEdgeInsets {
    hostingController.view.safeAreaInsets
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

    synchronizeViewport(viewport)
    sessionState.trayDidOpen(sessionGeneration: generation, viewport: viewport)
    popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    // NSPopover attaches the hosting view to its private content window during
    // show. Reassert the explicit viewport after that attachment so an origin,
    // fitting-size, or safe-area value retained by AppKit from the previous
    // generation cannot shift the SwiftUI root on reopen.
    synchronizeViewport(viewport)
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

  private func synchronizeViewport(_ viewport: CGSize) {
    if popover.contentSize != viewport {
      popover.contentSize = viewport
    }
    let bounds = NSRect(origin: .zero, size: viewport)
    hostingController.view.frame = bounds
    hostingController.view.bounds = bounds
    hostingController.view.autoresizingMask = [.width, .height]
    hostingController.view.needsLayout = true
    hostingController.view.layoutSubtreeIfNeeded()
    popover.contentWindow?.contentView?.needsLayout = true
    popover.contentWindow?.contentView?.layoutSubtreeIfNeeded()
  }
}
