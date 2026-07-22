import AppKit
import SwiftUI
import Testing

@testable import DeskSetupCore
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
    #expect(factory.statusItem.presentations.count == 1)
    #expect(factory.popoverCreations == 1)
    #expect(factory.monitorCreations == 1)
    #expect(controller.popoverBehavior == .applicationDefined)
    #expect(controller.contentSize == CGSize(width: 368, height: 560))
    #expect(controller.hostingViewBounds.size == controller.contentSize)
    #expect(controller.hostingViewBounds.origin == .zero)
    #expect(controller.hostingViewFrame == CGRect(origin: .zero, size: controller.contentSize))
    #expect(controller.hostingViewSafeAreaInsets.top == 0)
    #expect(controller.hostingViewSafeAreaInsets.left == 0)
    #expect(controller.hostingViewSafeAreaInsets.bottom == 0)
    #expect(controller.hostingViewSafeAreaInsets.right == 0)
    #expect(controller.contentViewBounds.size == controller.contentSize)
    #expect(state.openEvents == [.init(generation: 1, viewport: controller.contentSize)])
    #expect(state.attachGenerations == [1])
    #expect(factory.monitor.startCount == 1)
  }

  @Test("status presentation uses fresh match, applying state, and safe fallbacks")
  func statusItemPresentationPolicy() {
    let builder = TrayStatusItemPresentationBuilder()
    let first = statusProfile(name: "Meeting", symbol: "video")
    let selected = statusProfile(
      name: "아주 긴 한국어 프로필 이름으로 메뉴 막대 폭을 확인",
      symbol: "not.a.real.symbol"
    )

    let noFreshMatch = builder.presentation(
      for: TrayStatusItemSnapshot(
        profiles: [first],
        selectedProfileID: first.id,
        visibleReadinessByProfile: [first.id: .ready],
        operationCountByProfile: [first.id: 0],
        hasFreshReadiness: false
      )
    )
    #expect(noFreshMatch.state == .noMatch)
    #expect(noFreshMatch.symbolName == TrayStatusItemPresentation.fallbackSymbolName)
    #expect(noFreshMatch.preferredLength == NSStatusItem.squareLength)

    let freshMatch = builder.presentation(
      for: TrayStatusItemSnapshot(
        profiles: [first, selected],
        selectedProfileID: selected.id,
        visibleReadinessByProfile: [first.id: .ready, selected.id: .ready],
        operationCountByProfile: [first.id: 0, selected.id: 0],
        hasFreshReadiness: true
      )
    )
    #expect(freshMatch.state == .matching(selected))
    #expect(freshMatch.symbolName == TrayStatusItemPresentation.fallbackSymbolName)
    #expect(freshMatch.title.count == TrayStatusItemPresentationBuilder.maximumDisplayedNameLength)
    #expect(freshMatch.title.hasSuffix("…"))
    #expect(freshMatch.preferredLength == NSStatusItem.variableLength)

    let applying = builder.presentation(
      for: TrayStatusItemSnapshot(
        profiles: [first, selected],
        selectedProfileID: selected.id,
        visibleReadinessByProfile: [first.id: .applying, selected.id: .ready],
        operationCountByProfile: [first.id: 1, selected.id: 0],
        hasFreshReadiness: true
      )
    )
    #expect(applying.state == .applying(first))
    #expect(applying.symbolName == "video")
    #expect(applying.title.contains("Applying") || applying.title.contains("적용 중"))

    let failed = builder.presentation(
      for: TrayStatusItemSnapshot(
        profiles: [first],
        selectedProfileID: first.id,
        visibleReadinessByProfile: [first.id: .unavailable],
        operationCountByProfile: [first.id: 0],
        hasFreshReadiness: true
      )
    )
    #expect(failed.state == .noMatch)
    #expect(failed.symbolName == TrayStatusItemPresentation.fallbackSymbolName)

    let deleted = builder.presentation(
      for: TrayStatusItemSnapshot(
        profiles: [],
        selectedProfileID: first.id,
        visibleReadinessByProfile: [first.id: .ready],
        operationCountByProfile: [first.id: 0],
        hasFreshReadiness: true
      )
    )
    #expect(deleted.state == .noMatch)
    #expect(deleted.title.isEmpty)
  }

  @Test("twenty reopen generations reset the hosting origin without duplicating ownership")
  func twentyReopensResetViewportOrigin() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 3))
    let factory = SurfaceFactorySpy()
    factory.popover.mutatesHostingOriginWhenShown = true
    factory.popover.attachedContentFrameOriginWhenShown = CGPoint(x: 13, y: 13)
    let controller = TrayPopoverController(
      rootView: Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity),
      sessionState: state,
      factory: factory
    )

    for expectedGeneration in UInt64(1)...20 {
      controller.show()
      let viewport = controller.contentSize
      #expect(controller.activeSessionGeneration == expectedGeneration)
      #expect(controller.hostingViewBounds == CGRect(origin: .zero, size: viewport))
      #expect(controller.hostingViewFrame == CGRect(origin: .zero, size: viewport))
      #expect(controller.hostingViewSafeAreaInsets.top == 0)
      #expect(controller.hostingViewSafeAreaInsets.left == 0)
      #expect(controller.hostingViewSafeAreaInsets.bottom == 0)
      #expect(controller.hostingViewSafeAreaInsets.right == 0)
      #expect(controller.contentViewBounds == CGRect(origin: .zero, size: viewport))
      #expect(
        factory.popover.contentViewController?.view.frame.origin
          == CGPoint(x: 13, y: 13)
      )
      controller.requestClose(sessionGeneration: expectedGeneration)
    }

    #expect(factory.statusItemCreations == 1)
    #expect(factory.popoverCreations == 1)
    #expect(factory.monitorCreations == 1)
    #expect(factory.monitor.startCount == 20)
    #expect(factory.monitor.stopCount == 20)
    #expect(state.openEvents.map(\.generation) == Array(UInt64(1)...20))
    #expect(state.attachGenerations == Array(UInt64(1)...20))
    #expect(state.closeGenerations == Array(UInt64(1)...20))
  }

  @Test("offscreen native NSPopover preserves its attached wrapper frame across reopens")
  func nativePopoverPreservesAttachedWrapperFrame() throws {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 2))
    let factory = NativePopoverFactory()
    let controller = TrayPopoverController(
      rootView: Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity),
      sessionState: state,
      factory: factory
    )
    defer {
      if let generation = controller.activeSessionGeneration {
        controller.requestClose(sessionGeneration: generation)
      }
      factory.tearDown()
    }

    for expectedGeneration in UInt64(1)...3 {
      controller.show()

      let before = try #require(factory.popover.wrapperFramesBeforeFirstLayout.last)
      let after = try #require(factory.popover.wrapperFramesAfterFirstLayout.last)
      let wrapper = try #require(factory.popover.contentViewController?.view)
      let shellContentRoot = try #require(wrapper.superview)
      let hostedView = try #require(
        (factory.popover.contentViewController as? TrayPopoverContentController)?
          .hostedController.view
      )
      let hostedFrameInShell = hostedView.convert(hostedView.bounds, to: shellContentRoot)

      // The native popover shell gives the attached content wrapper a nonzero
      // chrome inset (13 pt on current macOS). The exact value is AppKit's;
      // preserving it is the regression contract.
      #expect(before.origin.x > 0)
      #expect(before.origin.y > 0)
      #expect(after == before)
      #expect(wrapper.frame == before)
      #expect(controller.hostingViewFrame == wrapper.bounds)
      #expect(controller.hostingViewBounds == CGRect(origin: .zero, size: wrapper.bounds.size))
      #expect(shellContentRoot.bounds.midX == wrapper.frame.midX)
      #expect(shellContentRoot.bounds.midX == hostedFrameInShell.midX)
      #expect(controller.activeSessionGeneration == expectedGeneration)

      controller.requestClose(sessionGeneration: expectedGeneration)
    }

    #expect(factory.popover.wrapperFramesBeforeFirstLayout.count == 3)
    #expect(factory.popover.wrapperFramesAfterFirstLayout.count == 3)
  }

  @Test("late first-layout completion restores the viewport exactly once")
  func lateLayoutCompletionRestoresViewport() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 2))
    let factory = SurfaceFactorySpy()
    factory.popover.automaticallyCompletesPresentation = false
    let recorder = GeometryTraceRecorderSpy()
    let controller = TrayPopoverController(
      rootView: Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity),
      sessionState: state,
      factory: factory,
      traceRecorder: recorder
    )

    controller.show()
    factory.popover.mutateHostingOrigin()
    #expect(controller.hostingViewBounds.origin != .zero)

    factory.popover.trigger(.contentWindowAttached, generation: 1)
    factory.popover.trigger(.firstLayoutCompleted, generation: 1)
    factory.popover.trigger(.didBecomeKey, generation: 1)

    #expect(controller.contentSize.height == TrayGeometry.twoProfileHeight)
    #expect(controller.hostingViewBounds == CGRect(origin: .zero, size: controller.contentSize))
    #expect(controller.hostingViewFrame == CGRect(origin: .zero, size: controller.contentSize))
    #expect(state.attachGenerations == [1])
    #expect(
      recorder.records.count(where: { $0.stage == .finalViewportSynchronized }) == 1
    )
    #expect(recorder.records.allSatisfy { $0.anchorRect == factory.statusItem.anchor.bounds })
    #expect(recorder.records.allSatisfy { $0.screenScale == factory.metrics.backingScaleFactor })
  }

  @Test("stale presentation completion cannot alter a reopened generation")
  func staleLayoutCompletionIsIgnored() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 1))
    let factory = SurfaceFactorySpy()
    factory.popover.automaticallyCompletesPresentation = false
    let controller = TrayPopoverController(
      rootView: Color.clear,
      sessionState: state,
      factory: factory
    )

    controller.show()
    controller.requestClose(sessionGeneration: 1)
    controller.show()
    factory.popover.mutateHostingOrigin()

    factory.popover.trigger(.firstLayoutCompleted, generation: 1)
    #expect(controller.hostingViewBounds.origin != .zero)
    #expect(state.attachGenerations.isEmpty)

    factory.popover.trigger(.firstLayoutCompleted, generation: 2)
    #expect(controller.hostingViewBounds.origin == .zero)
    #expect(state.attachGenerations == [2])
  }

  @Test("native asymmetric safe area is filtered horizontally at the AppKit hosting boundary")
  func safeAreaOwnershipIsSymmetric() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 2))
    let factory = SurfaceFactorySpy()
    let contentProbe = HorizontalContentProbe()
    let recorder = GeometryTraceRecorderSpy()
    factory.popover.installContentWindow(
      safeAreaInsets: NSEdgeInsets(top: 3, left: 11, bottom: 5, right: 2)
    )
    let controller = TrayPopoverController(
      rootView: HorizontalContentProbeView(probe: contentProbe)
        .padding(TrayGeometry.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
      sessionState: state,
      factory: factory,
      traceRecorder: recorder
    )

    controller.show()

    #expect(controller.nativeContentViewSafeAreaInsets.top == 3)
    #expect(controller.nativeContentViewSafeAreaInsets.left == 11)
    #expect(controller.nativeContentViewSafeAreaInsets.bottom == 5)
    #expect(controller.nativeContentViewSafeAreaInsets.right == 2)
    // Only the inherited horizontal contribution is cancelled. SwiftUI still
    // receives the native top/bottom exclusion from the popover chrome.
    #expect(controller.hostingViewSafeAreaInsets.top == 3)
    #expect(controller.hostingViewSafeAreaInsets.left == 0)
    #expect(controller.hostingViewSafeAreaInsets.bottom == 5)
    #expect(controller.hostingViewSafeAreaInsets.right == 0)
    #expect(controller.hostingViewFrame == CGRect(origin: .zero, size: controller.contentSize))
    #expect(controller.hostingViewBounds == CGRect(origin: .zero, size: controller.contentSize))
    #expect(controller.rootHorizontalInsets.leading == TrayGeometry.outerPadding)
    #expect(controller.rootHorizontalInsets.trailing == TrayGeometry.outerPadding)

    let nativeContentView = factory.popover.contentWindow?.contentView
    let contentView = contentProbe.view
    #expect(nativeContentView != nil)
    #expect(contentView != nil)
    if let nativeContentView, let contentView {
      let contentFrame = contentView.convert(contentView.bounds, to: nativeContentView)
      #expect(contentFrame.minX == TrayGeometry.outerPadding)
      #expect(contentFrame.maxX == controller.contentSize.width - TrayGeometry.outerPadding)
      #expect(contentFrame.minY == 5 + TrayGeometry.outerPadding)
      #expect(contentFrame.maxY == controller.contentSize.height - 3 - TrayGeometry.outerPadding)
    }

    let attachmentRecord = recorder.records.first(where: {
      $0.stage == .contentWindowAttached
    })
    #expect(attachmentRecord?.hostingSafeArea.top == 3)
    #expect(attachmentRecord?.hostingSafeArea.leading == 0)
    #expect(attachmentRecord?.hostingSafeArea.bottom == 5)
    #expect(attachmentRecord?.hostingSafeArea.trailing == 0)
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

  @Test("status item anchor changes are coalesced until the tray closes")
  func statusItemAnchorIsFrozenWhileOpen() {
    let profile = statusProfile(name: "Meeting", symbol: "video")
    let matching = TrayStatusItemPresentationBuilder().presentation(
      for: TrayStatusItemSnapshot(
        profiles: [profile],
        selectedProfileID: profile.id,
        visibleReadinessByProfile: [profile.id: .ready],
        operationCountByProfile: [profile.id: 0],
        hasFreshReadiness: true
      )
    )
    let noMatch = TrayStatusItemPresentationBuilder().presentation(
      for: TrayStatusItemSnapshot(
        profiles: [profile],
        selectedProfileID: profile.id,
        visibleReadinessByProfile: [profile.id: .ready],
        operationCountByProfile: [profile.id: 0],
        hasFreshReadiness: false
      )
    )
    let state = SessionStateSpy(
      context: TrayGeometryContext(profileCount: 1),
      statusItemPresentation: matching
    )
    let factory = SurfaceFactorySpy()
    let controller = TrayPopoverController(
      rootView: Color.clear,
      sessionState: state,
      factory: factory
    )

    controller.show()
    let openAnchorWidth = factory.statusItem.anchor.bounds.width
    state.emitStatusItemPresentation(noMatch)
    state.emitStatusItemPresentation(noMatch)

    #expect(factory.statusItem.presentations == [matching])
    #expect(factory.statusItem.anchor.bounds.width == openAnchorWidth)

    controller.requestClose(sessionGeneration: 1)

    #expect(factory.statusItem.presentations == [matching, noMatch])
    #expect(factory.statusItem.anchor.bounds.width < openAnchorWidth)
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
  private(set) var attachGenerations: [UInt64] = []
  private(set) var closeGenerations: [UInt64] = []
  private var statusItemPresentationHandler: (@MainActor (TrayStatusItemPresentation) -> Void)?
  var statusItemPresentation: TrayStatusItemPresentation

  init(
    context: TrayGeometryContext,
    statusItemPresentation: TrayStatusItemPresentation =
      TrayStatusItemPresentationBuilder().presentation(
        for: TrayStatusItemSnapshot(
          profiles: [],
          selectedProfileID: nil,
          visibleReadinessByProfile: [:],
          operationCountByProfile: [:],
          hasFreshReadiness: false
        )
      )
  ) {
    self.context = context
    self.statusItemPresentation = statusItemPresentation
  }

  var geometryContext: TrayGeometryContext { context }

  func trayDidOpen(sessionGeneration: UInt64, viewport: CGSize) {
    openEvents.append(.init(generation: sessionGeneration, viewport: viewport))
  }

  func trayContentDidAttach(sessionGeneration: UInt64) {
    attachGenerations.append(sessionGeneration)
  }

  func trayDidClose(sessionGeneration: UInt64) {
    closeGenerations.append(sessionGeneration)
  }

  func setStatusItemPresentationHandler(
    _ handler: @escaping @MainActor (TrayStatusItemPresentation) -> Void
  ) {
    statusItemPresentationHandler = handler
  }

  func emitStatusItemPresentation(_ presentation: TrayStatusItemPresentation) {
    statusItemPresentation = presentation
    statusItemPresentationHandler?(presentation)
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
  private(set) var presentations: [TrayStatusItemPresentation] = []

  var anchorView: NSView? { anchor }

  func configure(target: AnyObject, action: Selector) {
    configurationCount += 1
  }

  func update(_ presentation: TrayStatusItemPresentation) {
    presentations.append(presentation)
    anchor.frame.size.width =
      presentation.title.isEmpty
      ? 24
      : min(172, max(48, CGFloat(presentation.title.count * 8 + 32)))
  }
}

@MainActor
private final class PopoverSurfaceSpy: TrayPopoverSurface {
  var behavior: NSPopover.Behavior = .transient
  var contentSize: NSSize = .zero {
    didSet {
      contentSizeAssignments.append(contentSize)
      sizeContentControllerLikeAppKit()
    }
  }
  var contentViewController: NSViewController? {
    didSet {
      sizeContentControllerLikeAppKit()
      if isShown {
        attachContentControllerView()
      }
    }
  }
  private(set) var isShown = false
  var contentWindow: NSWindow?
  private var didClose: (@MainActor () -> Void)?
  private var presentationStage: (@MainActor (UInt64, TrayPopoverPresentationStage) -> Void)?
  private(set) var contentSizeAssignments: [CGSize] = []
  var mutatesHostingOriginWhenShown = false
  var attachedContentFrameOriginWhenShown: CGPoint?
  var automaticallyCompletesPresentation = true

  func setDidCloseHandler(_ handler: @escaping @MainActor () -> Void) {
    didClose = handler
  }

  func setPresentationStageHandler(
    _ handler: @escaping @MainActor (UInt64, TrayPopoverPresentationStage) -> Void
  ) {
    presentationStage = handler
  }

  func show(
    relativeTo positioningRect: NSRect,
    of positioningView: NSView,
    preferredEdge: NSRectEdge,
    presentationGeneration: UInt64
  ) {
    isShown = true
    attachContentControllerView()
    if mutatesHostingOriginWhenShown {
      mutateHostingOrigin()
    }
    if let attachedContentFrameOriginWhenShown {
      contentViewController?.view.frame.origin = attachedContentFrameOriginWhenShown
    }
    presentationStage?(presentationGeneration, .showReturned)
    if automaticallyCompletesPresentation {
      presentationStage?(presentationGeneration, .contentWindowAttached)
      presentationStage?(presentationGeneration, .firstLayoutCompleted)
    }
  }

  func performClose(_ sender: Any?) {
    isShown = false
    didClose?()
  }

  func mutateHostingOrigin() {
    guard let contentViewController else { return }
    let view =
      (contentViewController as? TrayPopoverContentController)?.hostedController.view
      ?? contentViewController.view
    view.bounds.origin = CGPoint(x: 19, y: 23)
    view.frame.origin = CGPoint(x: 7, y: 11)
  }

  func trigger(_ stage: TrayPopoverPresentationStage, generation: UInt64) {
    presentationStage?(generation, stage)
  }

  func installContentWindow(safeAreaInsets: NSEdgeInsets) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 368, height: 316),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = SafeAreaContentView(
      frame: window.contentView?.bounds ?? .zero,
      insets: safeAreaInsets
    )
    contentWindow = window
    if isShown {
      attachContentControllerView()
    }
  }

  private func attachContentControllerView() {
    guard let nativeContentView = contentWindow?.contentView,
      let hostedView = contentViewController?.view
    else { return }
    hostedView.removeFromSuperview()
    hostedView.frame = nativeContentView.bounds
    hostedView.autoresizingMask = [.width, .height]
    nativeContentView.addSubview(hostedView)
    nativeContentView.needsLayout = true
    nativeContentView.layoutSubtreeIfNeeded()
  }

  private func sizeContentControllerLikeAppKit() {
    guard let contentViewController, contentSize != .zero else { return }
    contentViewController.view.frame.size = contentSize
    contentViewController.view.bounds.size = contentSize
  }
}

@MainActor
private final class NativePopoverFactory: TraySurfaceFactory {
  let popover = NativePopoverSurface()
  private let statusItem = NativeStatusItemSurface()
  private let monitor = DismissalMonitorSpy()
  private let anchorWindow: NSWindow

  init() {
    _ = NSApplication.shared
    anchorWindow = NSWindow(
      contentRect: NSRect(x: 0, y: -10_000, width: 24, height: 24),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    anchorWindow.contentView = statusItem.anchor
    anchorWindow.orderFront(nil)
  }

  func makeStatusItem() -> any TrayStatusItemSurface { statusItem }

  func makePopover() -> any TrayPopoverSurface { popover }

  func makeDismissalMonitor() -> any TrayDismissalMonitoring { monitor }

  func screenMetrics(for anchorView: NSView) -> TrayScreenMetrics {
    TrayScreenMetrics(
      visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
      backingScaleFactor: 2
    )
  }

  func tearDown() {
    popover.performClose(nil)
    anchorWindow.orderOut(nil)
    anchorWindow.close()
  }
}

@MainActor
private final class NativeStatusItemSurface: TrayStatusItemSurface {
  let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))

  var anchorView: NSView? { anchor }

  func configure(target: AnyObject, action: Selector) {}

  func update(_ presentation: TrayStatusItemPresentation) {}
}

@MainActor
private final class NativePopoverSurface: NSObject, TrayPopoverSurface, NSPopoverDelegate {
  private let popover = NSPopover()
  private var didClose: (@MainActor () -> Void)?
  private var presentationStage: (@MainActor (UInt64, TrayPopoverPresentationStage) -> Void)?
  private(set) var wrapperFramesBeforeFirstLayout: [CGRect] = []
  private(set) var wrapperFramesAfterFirstLayout: [CGRect] = []

  override init() {
    super.init()
    popover.animates = false
    popover.delegate = self
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

  var isShown: Bool { popover.isShown }

  var contentWindow: NSWindow? { popover.contentViewController?.view.window }

  func setDidCloseHandler(_ handler: @escaping @MainActor () -> Void) {
    didClose = handler
  }

  func setPresentationStageHandler(
    _ handler: @escaping @MainActor (UInt64, TrayPopoverPresentationStage) -> Void
  ) {
    presentationStage = handler
  }

  func show(
    relativeTo positioningRect: NSRect,
    of positioningView: NSView,
    preferredEdge: NSRectEdge,
    presentationGeneration: UInt64
  ) {
    popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
    contentWindow?.contentView?.layoutSubtreeIfNeeded()
    presentationStage?(presentationGeneration, .showReturned)
    presentationStage?(presentationGeneration, .contentWindowAttached)

    guard let wrapper = contentViewController?.view else { return }
    wrapperFramesBeforeFirstLayout.append(wrapper.frame)
    presentationStage?(presentationGeneration, .firstLayoutCompleted)
    wrapperFramesAfterFirstLayout.append(wrapper.frame)
  }

  func performClose(_ sender: Any?) {
    popover.performClose(sender)
  }

  func popoverDidClose(_ notification: Notification) {
    didClose?()
  }
}

@MainActor
private final class GeometryTraceRecorderSpy: TrayGeometryTraceRecording {
  private(set) var records: [TrayGeometryTraceRecord] = []

  func record(_ value: TrayGeometryTraceRecord) {
    records.append(value)
  }
}

private final class SafeAreaContentView: NSView {
  private let insets: NSEdgeInsets

  init(frame: NSRect, insets: NSEdgeInsets) {
    self.insets = insets
    super.init(frame: frame)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var safeAreaInsets: NSEdgeInsets {
    insets
  }
}

@MainActor
private final class HorizontalContentProbe {
  weak var view: NSView?
}

private struct HorizontalContentProbeView: NSViewRepresentable {
  let probe: HorizontalContentProbe

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    probe.view = view
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
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

private func statusProfile(name: String, symbol: String) -> DeskProfile {
  var profile = DeskProfile(name: name, symbolName: symbol)
  profile.settings.audio.isIncluded = true
  profile.settings.audio.value.defaultOutputUID = .init(
    isIncluded: true,
    value: "synthetic-output"
  )
  return profile
}
