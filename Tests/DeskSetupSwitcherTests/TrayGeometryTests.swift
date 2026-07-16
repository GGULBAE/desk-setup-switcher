import CoreGraphics
import Testing

@testable import DeskSetupSwitcher

@Suite("Tray geometry policy")
struct TrayGeometryTests {
  private let policy = TrayGeometry()
  private let primaryScreen = TrayScreenMetrics(
    visibleFrame: CGRect(x: 0, y: 0, width: 1_728, height: 1_080),
    backingScaleFactor: 2
  )

  @Test("zero, one, two, three, and overflow profile fixtures use deterministic policy sizes")
  func profileCountSizes() {
    let sizes = [0, 1, 2, 3, 10].map {
      policy.viewport(
        for: TrayGeometryContext(profileCount: $0),
        on: primaryScreen
      )
    }

    #expect(sizes.map(\.width) == Array(repeating: TrayGeometry.width, count: 5))
    #expect(sizes[0].height == TrayGeometry.compactHeight)
    #expect(sizes[1].height == TrayGeometry.singleProfileHeight)
    #expect(sizes[2].height == TrayGeometry.twoProfileHeight)
    #expect(sizes[3].height == TrayGeometry.maximumHeight)
    #expect(sizes[4].height == TrayGeometry.maximumHeight)
  }

  @Test("two-profile standard fixture leaves no more than twenty-four points below cards")
  func twoProfileBottomGap() {
    // The fixture height is the deterministic root/card layout captured from
    // the standard two-profile synthetic state; it is not child-size feedback.
    let standardFixtureContentHeight: CGFloat = 294
    let viewport = policy.viewport(
      for: TrayGeometryContext(profileCount: 2),
      on: primaryScreen
    )

    #expect(viewport.height - standardFixtureContentHeight <= 24)
    #expect(viewport.height - standardFixtureContentHeight >= 0)
  }

  @Test("native safe-area values never become a second root horizontal inset")
  func horizontalInsetOwnership() {
    let insets = policy.rootHorizontalInsets(
      nativeSafeArea: TraySafeAreaInsets(top: 4, leading: 13, bottom: 6, trailing: 1)
    )

    #expect(insets.leading == TrayGeometry.outerPadding)
    #expect(insets.trailing == TrayGeometry.outerPadding)
  }

  @Test("all state changes preserve the current open-session viewport")
  func openSessionIsImmutable() {
    var session = TrayOpenSessionGeometry(policy: policy)
    let opened = session.open(
      context: TrayGeometryContext(profileCount: 3),
      screen: primaryScreen
    )
    let mutations = [
      TrayGeometryContext(profileCount: 3, deletionConfirmationVisible: true),
      TrayGeometryContext(profileCount: 2),
      TrayGeometryContext(profileCount: 2, capturePhase: .pending),
      TrayGeometryContext(profileCount: 2, capturePhase: .result),
      TrayGeometryContext(profileCount: 2, capturePhase: .error),
      TrayGeometryContext(profileCount: 2, applyBannerVisible: true),
      TrayGeometryContext(profileCount: 10, usesLargeText: true),
    ]

    for mutation in mutations {
      let current = session.viewportAfterStateChange(context: mutation, screen: primaryScreen)
      #expect(abs(current.width - opened.width) <= 1)
      #expect(abs(current.height - opened.height) <= 1)
    }
  }

  @Test("small and secondary displays clamp in points without scale-factor drift")
  func screenClampAndScale() {
    let small = TrayScreenMetrics(
      visibleFrame: CGRect(x: -1_280, y: 140, width: 1_280, height: 360),
      backingScaleFactor: 1
    )
    let retina = TrayScreenMetrics(
      visibleFrame: small.visibleFrame,
      backingScaleFactor: 2
    )
    let context = TrayGeometryContext(profileCount: 10, usesLargeText: true)

    let oneX = policy.viewport(for: context, on: small)
    let twoX = policy.viewport(for: context, on: retina)

    #expect(oneX == twoX)
    #expect(oneX.height == small.visibleFrame.height - (TrayGeometry.screenMargin * 2))
    #expect(oneX.width == TrayGeometry.width)
  }

  @Test("display changes affect only the next session")
  func displayChangeAppliesAfterReopen() {
    var session = TrayOpenSessionGeometry(policy: policy)
    let context = TrayGeometryContext(profileCount: 10)
    let first = session.open(context: context, screen: primaryScreen)
    let smaller = TrayScreenMetrics(
      visibleFrame: CGRect(x: 1_728, y: 0, width: 1_024, height: 420),
      backingScaleFactor: 1
    )

    #expect(session.viewportAfterStateChange(context: context, screen: smaller) == first)
    session.close()
    let reopened = session.open(context: context, screen: smaller)
    #expect(reopened.height < first.height)
    #expect(reopened.height == smaller.visibleFrame.height - (TrayGeometry.screenMargin * 2))
  }
}
