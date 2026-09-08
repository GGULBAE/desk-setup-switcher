import CoreGraphics
import Foundation

struct TrayScreenMetrics: Equatable, Sendable {
  let visibleFrame: CGRect
  let backingScaleFactor: CGFloat
}

struct TrayHorizontalInsets: Equatable, Sendable {
  let leading: CGFloat
  let trailing: CGFloat
}

struct TraySafeAreaInsets: Equatable, Sendable {
  let top: CGFloat
  let leading: CGFloat
  let bottom: CGFloat
  let trailing: CGFloat
}

enum TrayCaptureGeometryPhase: Equatable, Sendable {
  case idle
  case pending
  case result
  case error
}

struct TrayGeometryContext: Equatable, Sendable {
  var profileCount: Int
  var deletionConfirmationVisible: Bool
  var capturePhase: TrayCaptureGeometryPhase
  var applyBannerVisible: Bool
  var usesLargeText: Bool
  var fittedContentHeight: CGFloat?

  init(
    profileCount: Int,
    deletionConfirmationVisible: Bool = false,
    capturePhase: TrayCaptureGeometryPhase = .idle,
    applyBannerVisible: Bool = false,
    usesLargeText: Bool = false,
    fittedContentHeight: CGFloat? = nil
  ) {
    self.profileCount = max(0, profileCount)
    self.deletionConfirmationVisible = deletionConfirmationVisible
    self.capturePhase = capturePhase
    self.applyBannerVisible = applyBannerVisible
    self.usesLargeText = usesLargeText
    self.fittedContentHeight = fittedContentHeight
  }
}

/// Owns every value that can affect the outer tray viewport. SwiftUI content
/// may scroll within this viewport. A one-shot pre-open content measurement
/// can replace the fallback size; attached content never resizes an open tray.
struct TrayGeometry: Equatable, Sendable {
  static let width: CGFloat = 368
  static let compactHeight: CGFloat = 260
  // Empty and first-profile states share a viewport so capture does not make
  // the popover grow on the next open and a single compact card has no large
  // unused tail.
  static let singleProfileHeight: CGFloat = compactHeight
  static let twoProfileHeight: CGFloat = 316
  // Three standard cards fit without consuming the maximum scroll viewport.
  // Keep a small visual tail instead of the large empty area produced by the
  // former 3+ bucket; four or more profiles still use the scrollable maximum.
  static let threeProfileHeight: CGFloat = 480
  static let maximumHeight: CGFloat = 560
  static let screenMargin: CGFloat = 32

  static let outerPadding: CGFloat = 16
  static let sectionGap: CGFloat = 12
  static let cardGap: CGFloat = 10
  static let cardPadding: CGFloat = 12
  static let headerHeight: CGFloat = 32
  static let footerHeight: CGFloat = 0

  /// The AppKit hosting boundary neutralizes native horizontal safe-area insets.
  /// The SwiftUI root therefore applies exactly one symmetric content inset.
  func rootHorizontalInsets(nativeSafeArea _: TraySafeAreaInsets) -> TrayHorizontalInsets {
    TrayHorizontalInsets(leading: Self.outerPadding, trailing: Self.outerPadding)
  }

  func viewport(for context: TrayGeometryContext, on screen: TrayScreenMetrics) -> CGSize {
    var idealHeight: CGFloat
    switch context.profileCount {
    case 0:
      idealHeight = Self.compactHeight
    case 1:
      idealHeight = Self.singleProfileHeight
    case 2:
      idealHeight = Self.twoProfileHeight
    case 3:
      idealHeight = Self.threeProfileHeight
    default:
      idealHeight = Self.maximumHeight
    }

    if (1...3).contains(context.profileCount),
      let fittedHeight = context.fittedContentHeight,
      fittedHeight.isFinite, fittedHeight > 0
    {
      idealHeight = max(Self.headerHeight + Self.outerPadding * 2, ceil(fittedHeight))
    }

    // Banners, inline confirmation, and large text intentionally do not
    // expand the outer surface. They consume the internal scroll viewport.
    let availableHeight = max(1, screen.visibleFrame.height - (Self.screenMargin * 2))
    return CGSize(
      width: Self.width,
      height: min(idealHeight, Self.maximumHeight, availableHeight)
    )
  }
}

/// Captures a viewport once for an open generation. State and display changes
/// are observed only when the next generation is opened.
struct TrayOpenSessionGeometry: Equatable, Sendable {
  let policy: TrayGeometry
  private(set) var viewport: CGSize?

  init(policy: TrayGeometry = TrayGeometry()) {
    self.policy = policy
  }

  mutating func open(context: TrayGeometryContext, screen: TrayScreenMetrics) -> CGSize {
    if let viewport {
      return viewport
    }
    let next = policy.viewport(for: context, on: screen)
    viewport = next
    return next
  }

  func viewportAfterStateChange(
    context: TrayGeometryContext,
    screen: TrayScreenMetrics
  ) -> CGSize {
    viewport ?? policy.viewport(for: context, on: screen)
  }

  mutating func close() {
    viewport = nil
  }
}
