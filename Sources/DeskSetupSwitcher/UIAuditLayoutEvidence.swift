import SwiftUI

#if DEBUG
  /// Actual SwiftUI bounds, collected only by an opted-in synthetic audit host.
  /// No screen access, accessibility automation, or system adapter is involved.
  struct UIAuditLayoutAnchorsKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
      value: inout [String: Anchor<CGRect>],
      nextValue: () -> [String: Anchor<CGRect>]
    ) {
      value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
  }

  private struct UIAuditLayoutAnchorModifier: ViewModifier {
    @Environment(\.uiAuditConfiguration) private var configuration
    let identifier: String

    @ViewBuilder
    func body(content: Content) -> some View {
      if configuration.isEnabled {
        content.transformAnchorPreference(key: UIAuditLayoutAnchorsKey.self, value: .bounds) {
          anchors, bounds in
          anchors[identifier] = bounds
        }
      } else {
        content
      }
    }
  }
#endif

extension View {
  @ViewBuilder
  func uiAuditLayoutAnchor(_ identifier: String) -> some View {
    #if DEBUG
      modifier(UIAuditLayoutAnchorModifier(identifier: identifier))
    #else
      self
    #endif
  }
}
