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

  @Test("native asymmetric safe area does not add a second SwiftUI horizontal inset")
  func safeAreaOwnershipIsSymmetric() {
    let state = SessionStateSpy(context: TrayGeometryContext(profileCount: 2))
    let factory = SurfaceFactorySpy()
    factory.popover.installContentWindow(
      safeAreaInsets: NSEdgeInsets(top: 3, left: 11, bottom: 5, right: 2)
    )
    let controller = TrayPopoverController(
      rootView: Color.clear,
      sessionState: state,
      factory: factory
    )

    controller.show()

    #expect(controller.nativeContentViewSafeAreaInsets.left == 11)
    #expect(controller.nativeContentViewSafeAreaInsets.right == 2)
    #expect(controller.rootHorizontalInsets.leading == TrayGeometry.outerPadding)
    #expect(controller.rootHorizontalInsets.trailing == TrayGeometry.outerPadding)
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
    didSet { contentSizeAssignments.append(contentSize) }
  }
  var contentViewController: NSViewController?
  private(set) var isShown = false
  var contentWindow: NSWindow?
  private var didClose: (@MainActor () -> Void)?
  private var presentationStage: (@MainActor (UInt64, TrayPopoverPresentationStage) -> Void)?
  private(set) var contentSizeAssignments: [CGSize] = []
  var mutatesHostingOriginWhenShown = false
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
    if mutatesHostingOriginWhenShown {
      mutateHostingOrigin()
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
    guard let view = contentViewController?.view else { return }
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
