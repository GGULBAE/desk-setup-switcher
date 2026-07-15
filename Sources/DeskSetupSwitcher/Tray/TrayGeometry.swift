import CoreGraphics
import Foundation

struct TrayScreenMetrics: Equatable, Sendable {
  let visibleFrame: CGRect
  let backingScaleFactor: CGFloat
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

  init(
    profileCount: Int,
    deletionConfirmationVisible: Bool = false,
    capturePhase: TrayCaptureGeometryPhase = .idle,
    applyBannerVisible: Bool = false,
    usesLargeText: Bool = false
  ) {
    self.profileCount = max(0, profileCount)
    self.deletionConfirmationVisible = deletionConfirmationVisible
    self.capturePhase = capturePhase
    self.applyBannerVisible = applyBannerVisible
    self.usesLargeText = usesLargeText
  }
}

/// Owns every value that can affect the outer tray viewport. SwiftUI content
/// may scroll within this viewport but never feeds a measured height back here.
struct TrayGeometry: Equatable, Sendable {
  static let width: CGFloat = 368
  static let compactHeight: CGFloat = 300
  static let singleProfileHeight: CGFloat = 350
  static let maximumHeight: CGFloat = 560
  static let screenMargin: CGFloat = 32

  static let outerPadding: CGFloat = 16
  static let sectionGap: CGFloat = 12
  static let cardGap: CGFloat = 10
  static let cardPadding: CGFloat = 12
  static let headerHeight: CGFloat = 32
  static let footerHeight: CGFloat = 0

  func viewport(for context: TrayGeometryContext, on screen: TrayScreenMetrics) -> CGSize {
    let idealHeight: CGFloat
    switch context.profileCount {
    case 0:
      idealHeight = Self.compactHeight
    case 1:
      idealHeight = Self.singleProfileHeight
    default:
      idealHeight = Self.maximumHeight
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
