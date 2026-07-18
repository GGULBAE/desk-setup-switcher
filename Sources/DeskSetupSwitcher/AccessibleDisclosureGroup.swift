import SwiftUI

/// A disclosure whose expansion state belongs to its containing screen.
///
/// SwiftUI's default disclosure accessibility representation has varied across
/// macOS releases. Keeping the state explicit gives VoiceOver a stable value,
/// keeps collapsed children out of the reading order, preserves ordinary
/// Button Space activation, and handles Return explicitly.
struct AccessibleDisclosureGroup<Content: View>: View {
  let label: String
  let accessibilityIdentifier: String
  @Binding var isExpanded: Bool
  @ViewBuilder let content: () -> Content

  init(
    _ label: String,
    accessibilityIdentifier: String,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.label = label
    self.accessibilityIdentifier = accessibilityIdentifier
    _isExpanded = isExpanded
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Button {
        isExpanded.toggle()
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: "chevron.right")
            .font(.caption.bold())
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .accessibilityHidden(true)
          Text(label)
            .multilineTextAlignment(.leading)
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(label)
      .accessibilityValue(DisclosureAccessibilityPolicy.value(isExpanded: isExpanded))
      .accessibilityHint(DisclosureAccessibilityPolicy.actionHint(isExpanded: isExpanded))
      .accessibilityIdentifier(accessibilityIdentifier)
      .onKeyPress(.return) {
        isExpanded.toggle()
        return .handled
      }

      if isExpanded {
        content()
          .padding(.leading, 18)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

enum DisclosureAccessibilityPolicy {
  static func value(isExpanded: Bool) -> String {
    isExpanded ? appLocalized("Expanded") : appLocalized("Collapsed")
  }

  static func actionHint(isExpanded: Bool) -> String {
    isExpanded
      ? appLocalized("Collapses this section")
      : appLocalized("Expands this section")
  }
}
