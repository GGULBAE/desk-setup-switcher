import AppKit
import OSLog
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

  var preferredLength: CGFloat {
    title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
  }
}

enum TrayPopoverPresentationStage: String, Equatable, Sendable {
  case beforeShow
  case showReturned
  case contentWindowAttached
  case firstLayoutCompleted
  case didBecomeKey
  case finalViewportSynchronized
}

struct TrayGeometryTraceRecord: Equatable, Sendable {
  let generation: UInt64
  let stage: TrayPopoverPresentationStage
  let policyViewport: CGSize
  let hostingFrame: CGRect
  let hostingBounds: CGRect
  let hostingSafeArea: TraySafeAreaInsets
  let contentViewFrame: CGRect
  let contentViewBounds: CGRect
  let contentViewSafeArea: TraySafeAreaInsets
  let anchorRect: CGRect
  let screenScale: CGFloat
}

@MainActor
protocol TrayGeometryTraceRecording: AnyObject {
  func record(_ value: TrayGeometryTraceRecord)
}

@MainActor
final class DebugTrayGeometryTraceRecorder: TrayGeometryTraceRecording {
  private let logger = Logger(
    subsystem: "DeskSetupSwitcher",
    category: "TrayGeometry"
  )

  func record(_ value: TrayGeometryTraceRecord) {
    #if DEBUG
      logger.debug(
        "generation=\(value.generation) stage=\(value.stage.rawValue, privacy: .public) viewport=\(String(describing: value.policyViewport), privacy: .public) hostFrame=\(String(describing: value.hostingFrame), privacy: .public) hostBounds=\(String(describing: value.hostingBounds), privacy: .public) hostSafeArea=\(String(describing: value.hostingSafeArea), privacy: .public) contentFrame=\(String(describing: value.contentViewFrame), privacy: .public) contentBounds=\(String(describing: value.contentViewBounds), privacy: .public) contentSafeArea=\(String(describing: value.contentViewSafeArea), privacy: .public) anchor=\(String(describing: value.anchorRect), privacy: .public) scale=\(value.screenScale)"
      )
    #endif
  }
}

struct TrayStatusItemPresentationBuilder: Sendable {
  static let maximumDisplayedNameLength = 18

  func presentation(for snapshot: TrayStatusItemSnapshot) -> TrayStatusItemPresentation {
    if let applying = snapshot.profiles.first(where: {
      snapshot.visibleReadinessByProfile[$0.id] == .applying
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
        snapshot.visibleReadinessByProfile[profile.id] == .ready
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
      toolTip: appLocalized("Desk Setup Switcher — no profile is confirmed to match"),
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
  func setPresentationStageHandler(
    _ handler: @escaping @MainActor (UInt64, TrayPopoverPresentationStage) -> Void
  )
  func show(
    relativeTo positioningRect: NSRect,
    of positioningView: NSView,
    preferredEdge: NSRectEdge,
    presentationGeneration: UInt64
  )
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
      button.cell?.wraps = false
      button.cell?.lineBreakMode = .byTruncatingTail
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
    statusItem.length = presentation.preferredLength
  }
}

@MainActor
private final class AppKitTrayPopoverSurface: NSObject, TrayPopoverSurface, NSPopoverDelegate {
  private let popover = NSPopover()
  private var didCloseHandler: (@MainActor () -> Void)?
  private var presentationStageHandler: (@MainActor (UInt64, TrayPopoverPresentationStage) -> Void)?
  private var didBecomeKeyObserver: NSObjectProtocol?

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

  func setPresentationStageHandler(
    _ handler: @escaping @MainActor (UInt64, TrayPopoverPresentationStage) -> Void
  ) {
    presentationStageHandler = handler
  }

  func show(
    relativeTo positioningRect: NSRect,
    of positioningView: NSView,
    preferredEdge: NSRectEdge,
    presentationGeneration: UInt64
  ) {
    popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
    presentationStageHandler?(presentationGeneration, .showReturned)
    observePresentationCompletion(generation: presentationGeneration)
  }

  func performClose(_ sender: Any?) {
    popover.performClose(sender)
  }

  func popoverDidClose(_ notification: Notification) {
    stopObservingPresentationCompletion()
    didCloseHandler?()
  }

  private func observePresentationCompletion(generation: UInt64) {
    stopObservingPresentationCompletion()
    guard let window = contentWindow else { return }
    presentationStageHandler?(generation, .contentWindowAttached)

    didBecomeKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.presentationStageHandler?(generation, .didBecomeKey)
      }
    }
    if window.isKeyWindow {
      presentationStageHandler?(generation, .didBecomeKey)
    }

    // The next main-run-loop turn is AppKit's first opportunity to finish the
    // native popover attachment/layout pass. This is event ordering, not a
    // timing delay, and the controller rejects stale generations.
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window, window === self.contentWindow else { return }
      window.contentView?.layoutSubtreeIfNeeded()
      self.presentationStageHandler?(generation, .firstLayoutCompleted)
    }
  }

  private func stopObservingPresentationCompletion() {
    if let didBecomeKeyObserver {
      NotificationCenter.default.removeObserver(didBecomeKeyObserver)
    }
    didBecomeKeyObserver = nil
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

/// Filters the native popover safe area before the hosted SwiftUI tree receives
/// its attached layout proposal. Top/bottom chrome exclusions are preserved;
/// asymmetric left/right values cannot shift the fixed tray root.
@MainActor
final class TrayPopoverHorizontalSafeAreaView: NSView {
  override var safeAreaInsets: NSEdgeInsets {
    let inherited = super.safeAreaInsets
    return NSEdgeInsets(
      top: inherited.top,
      left: 0,
      bottom: inherited.bottom,
      right: 0
    )
  }
}

@MainActor
final class TrayPopoverContentController: NSViewController {
  let hostedController: NSViewController

  init(hostedController: NSViewController) {
    self.hostedController = hostedController
    super.init(nibName: nil, bundle: nil)

    let containerView = TrayPopoverHorizontalSafeAreaView()
    containerView.autoresizingMask = [.width, .height]
    view = containerView
    addChild(hostedController)
    let hostedView = hostedController.view
    hostedView.frame = containerView.bounds
    hostedView.autoresizingMask = [.width, .height]
    containerView.addSubview(hostedView)
  }

  /// Keeps the SwiftUI host in the wrapper's local coordinate space without
  /// changing the wrapper geometry that `NSPopover` owns after attachment.
  func synchronizeHostedViewToContainerBounds() {
    let containerBounds = view.bounds
    let hostedView = hostedController.view
    hostedView.frame = containerBounds
    hostedView.bounds = NSRect(origin: .zero, size: containerBounds.size)
    hostedView.autoresizingMask = [.width, .height]
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
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
  private let popoverContentController: TrayPopoverContentController
  private let traceRecorder: any TrayGeometryTraceRecording
  private var sessionGeometry: TrayOpenSessionGeometry
  private var generationCounter: UInt64 = 0
  private var finalizedPresentationGeneration: UInt64?
  private var currentAnchorRect: CGRect = .zero
  private var currentScreenScale: CGFloat = 1
  private var appliedStatusItemPresentation: TrayStatusItemPresentation?
  private var deferredStatusItemPresentation: TrayStatusItemPresentation?

  private(set) var activeSessionGeneration: UInt64?

  init<Content: View>(
    rootView: Content,
    sessionState: any TraySessionStateUpdating,
    geometry: TrayGeometry = TrayGeometry(),
    factory: any TraySurfaceFactory = AppKitTraySurfaceFactory(),
    traceRecorder: any TrayGeometryTraceRecording = DebugTrayGeometryTraceRecorder()
  ) {
    self.factory = factory
    self.sessionState = sessionState
    statusItem = factory.makeStatusItem()
    popover = factory.makePopover()
    dismissalMonitor = factory.makeDismissalMonitor()
    hostingController = NSHostingController(rootView: AnyView(rootView))
    hostingController.sizingOptions = []
    popoverContentController = TrayPopoverContentController(
      hostedController: hostingController
    )
    self.traceRecorder = traceRecorder
    sessionGeometry = TrayOpenSessionGeometry(policy: geometry)
    super.init()

    popover.behavior = .applicationDefined
    popover.contentViewController = popoverContentController
    popover.setDidCloseHandler { [weak self] in
      self?.finishClosingCurrentSession()
    }
    popover.setPresentationStageHandler { [weak self] generation, stage in
      self?.handlePresentationStage(stage, generation: generation)
    }
    statusItem.configure(target: self, action: #selector(togglePopover(_:)))
    applyStatusItemPresentation(sessionState.statusItemPresentation)
    sessionState.setStatusItemPresentationHandler { [weak self] presentation in
      self?.receiveStatusItemPresentation(presentation)
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

  var nativeContentViewBounds: CGRect {
    popover.contentWindow?.contentView?.bounds ?? .zero
  }

  var nativeContentViewSafeAreaInsets: NSEdgeInsets {
    popover.contentWindow?.contentView?.safeAreaInsets
      ?? NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }

  var rootHorizontalInsets: TrayHorizontalInsets {
    sessionGeometry.policy.rootHorizontalInsets(
      nativeSafeArea: traySafeAreaInsets(nativeContentViewSafeAreaInsets)
    )
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
    let screen = factory.screenMetrics(for: anchorView)
    let viewport = sessionGeometry.open(
      context: sessionState.geometryContext,
      screen: screen
    )
    activeSessionGeneration = generation
    finalizedPresentationGeneration = nil
    currentAnchorRect = anchorView.bounds
    currentScreenScale = screen.backingScaleFactor

    synchronizeViewport(viewport)
    sessionState.trayDidOpen(sessionGeneration: generation, viewport: viewport)
    trace(stage: .beforeShow, generation: generation, viewport: viewport)
    popover.show(
      relativeTo: currentAnchorRect,
      of: anchorView,
      preferredEdge: .minY,
      presentationGeneration: generation
    )
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
    if popover.isShown {
      popover.performClose(nil)
      if !popover.isShown {
        finishClosingCurrentSession()
      }
    } else {
      finishClosingCurrentSession()
    }
  }

  private func finishClosingCurrentSession() {
    guard let generation = activeSessionGeneration else { return }
    dismissalMonitor.stop()
    activeSessionGeneration = nil
    finalizedPresentationGeneration = nil
    sessionGeometry.close()
    sessionState.trayDidClose(sessionGeneration: generation)
    applyDeferredStatusItemPresentation()
  }

  /// The status-item button is the popover anchor. Changing its title while the
  /// popover is visible changes the anchor bounds and makes the tray jump. Keep
  /// the latest presentation, then apply it once AppKit has closed the popover.
  private func receiveStatusItemPresentation(_ presentation: TrayStatusItemPresentation) {
    if presentation == appliedStatusItemPresentation {
      deferredStatusItemPresentation = nil
      return
    }
    if activeSessionGeneration != nil || popover.isShown {
      deferredStatusItemPresentation = presentation
      return
    }
    applyStatusItemPresentation(presentation)
  }

  private func applyDeferredStatusItemPresentation() {
    guard let deferredStatusItemPresentation else { return }
    self.deferredStatusItemPresentation = nil
    applyStatusItemPresentation(deferredStatusItemPresentation)
  }

  private func applyStatusItemPresentation(_ presentation: TrayStatusItemPresentation) {
    guard presentation != appliedStatusItemPresentation else { return }
    appliedStatusItemPresentation = presentation
    statusItem.update(presentation)
  }

  private func synchronizeViewport(_ viewport: CGSize) {
    if popover.contentSize != viewport {
      popover.contentSize = viewport
    }
    // Once attached, NSPopover positions this wrapper inside its asymmetric
    // arrow/chrome shell. Rewriting the wrapper frame origin to zero shifts the
    // complete SwiftUI tree left relative to that shell. AppKit owns the
    // wrapper geometry; this controller owns only the hosted child geometry.
    popoverContentController.synchronizeHostedViewToContainerBounds()
    layoutPopoverContent()
  }

  private func layoutPopoverContent() {
    if let nativeContentView = popover.contentWindow?.contentView {
      nativeContentView.needsLayout = true
      nativeContentView.layoutSubtreeIfNeeded()
    }
    popoverContentController.view.needsLayout = true
    popoverContentController.view.layoutSubtreeIfNeeded()
    hostingController.view.needsLayout = true
    hostingController.view.layoutSubtreeIfNeeded()
  }

  private func handlePresentationStage(
    _ stage: TrayPopoverPresentationStage,
    generation: UInt64
  ) {
    guard activeSessionGeneration == generation,
      let viewport = sessionGeometry.viewport
    else { return }

    trace(stage: stage, generation: generation, viewport: viewport)
    guard stage == .firstLayoutCompleted,
      finalizedPresentationGeneration != generation
    else { return }

    finalizedPresentationGeneration = generation
    synchronizeViewport(viewport)
    trace(stage: .finalViewportSynchronized, generation: generation, viewport: viewport)
    sessionState.trayContentDidAttach(sessionGeneration: generation)
  }

  private func trace(
    stage: TrayPopoverPresentationStage,
    generation: UInt64,
    viewport: CGSize
  ) {
    let contentView = popover.contentWindow?.contentView
    traceRecorder.record(
      TrayGeometryTraceRecord(
        generation: generation,
        stage: stage,
        policyViewport: viewport,
        hostingFrame: hostingController.view.frame,
        hostingBounds: hostingController.view.bounds,
        hostingSafeArea: traySafeAreaInsets(hostingController.view.safeAreaInsets),
        contentViewFrame: contentView?.frame ?? .zero,
        contentViewBounds: contentView?.bounds ?? .zero,
        contentViewSafeArea: traySafeAreaInsets(
          contentView?.safeAreaInsets
            ?? NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        ),
        anchorRect: currentAnchorRect,
        screenScale: currentScreenScale
      )
    )
  }

  private func traySafeAreaInsets(_ insets: NSEdgeInsets) -> TraySafeAreaInsets {
    TraySafeAreaInsets(
      top: insets.top,
      leading: insets.left,
      bottom: insets.bottom,
      trailing: insets.right
    )
  }
}
