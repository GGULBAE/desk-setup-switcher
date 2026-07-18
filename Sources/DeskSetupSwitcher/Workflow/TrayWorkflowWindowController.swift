import AppKit
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

enum ApplyResultCountKind: String, CaseIterable, Hashable, Sendable {
  case succeeded
  case failed
  case skipped
  case unsupported
  case notVerified
  case rolledBack
  case rollbackFailed

  var title: String {
    switch self {
    case .succeeded: appLocalized("Succeeded")
    case .failed: appLocalized("Failed")
    case .skipped: appLocalized("Skipped")
    case .unsupported: appLocalized("Unsupported")
    case .notVerified: appLocalized("Not Verified")
    case .rolledBack: appLocalized("Rolled back")
    case .rollbackFailed: appLocalized("Rollback failed")
    }
  }

  func compactText(count: Int) -> String {
    switch self {
    case .succeeded: appLocalized("\(count) succeeded")
    case .failed: appLocalized("\(count) failed")
    case .skipped: appLocalized("\(count) skipped")
    case .unsupported: appLocalized("\(count) unsupported")
    case .notVerified: appLocalized("\(count) not verified")
    case .rolledBack: appLocalized("\(count) rolled back")
    case .rollbackFailed: appLocalized("\(count) rollback failed")
    }
  }
}

struct ApplyResultCountItem: Equatable, Identifiable, Sendable {
  let kind: ApplyResultCountKind
  let count: Int

  var id: ApplyResultCountKind { kind }
}

enum ApplyResultCountPresentation {
  static func nonzeroItems(for summary: ApplyResultSummary) -> [ApplyResultCountItem] {
    let counts: [ApplyResultCountKind: Int] = [
      .succeeded: summary.succeededCount,
      .failed: summary.failedCount,
      .skipped: summary.skippedCount,
      .unsupported: summary.unsupportedCount,
      .notVerified: summary.notVerifiedCount,
      .rolledBack: summary.rolledBackCount,
      .rollbackFailed: summary.rollbackFailedCount,
    ]
    return ApplyResultCountKind.allCases.compactMap { kind in
      guard let count = counts[kind], count > 0 else { return nil }
      return ApplyResultCountItem(kind: kind, count: count)
    }
  }

  static func compactText(for items: [ApplyResultCountItem]) -> String {
    items
      .map { $0.kind.compactText(count: $0.count) }
      .joined(separator: " · ")
  }

  static func accessibilityText(for items: [ApplyResultCountItem]) -> String {
    items
      .map { $0.kind.compactText(count: $0.count) }
      .joined(separator: ", ")
  }
}

private enum WorkflowFooterShortcut {
  case none
  case cancel
  case defaultAction
}

private struct WorkflowFooterAction: Identifiable {
  let id: String
  let title: String
  var accessibilityLabel: String?
  var accessibilityHint: String?
  var role: ButtonRole?
  var shortcut: WorkflowFooterShortcut
  var isDisabled: Bool
  var isProminent: Bool
  let perform: () -> Void

  init(
    id: String,
    title: String,
    accessibilityLabel: String? = nil,
    accessibilityHint: String? = nil,
    role: ButtonRole? = nil,
    shortcut: WorkflowFooterShortcut = .none,
    isDisabled: Bool = false,
    isProminent: Bool = false,
    perform: @escaping () -> Void
  ) {
    self.id = id
    self.title = title
    self.accessibilityLabel = accessibilityLabel
    self.accessibilityHint = accessibilityHint
    self.role = role
    self.shortcut = shortcut
    self.isDisabled = isDisabled
    self.isProminent = isProminent
    self.perform = perform
  }
}

enum WorkflowActionBarLayoutPolicy {
  static let horizontalItemSpacing: CGFloat = 8
  static let horizontalSectionSpacing: CGFloat = 12
  static let verticalSpacing: CGFloat = 8

  static func requiresStackedLayout(for dynamicTypeSize: DynamicTypeSize) -> Bool {
    dynamicTypeSize.isAccessibilitySize
  }

  static func requiresStackedLayout(
    forceStacked: Bool,
    availableWidth: CGFloat,
    idealItemWidths: [CGFloat]
  ) -> Bool {
    forceStacked || horizontalWidth(for: idealItemWidths) > availableWidth
  }

  static func frames(
    in bounds: CGRect,
    itemSizes: [CGSize],
    isStacked: Bool
  ) -> [CGRect] {
    guard !itemSizes.isEmpty else { return [] }
    if isStacked {
      var y = bounds.minY
      return itemSizes.enumerated().map { index, size in
        let constrainedSize = CGSize(width: min(size.width, bounds.width), height: size.height)
        let x = index == 0 ? bounds.minX : bounds.maxX - constrainedSize.width
        defer { y += constrainedSize.height + verticalSpacing }
        return CGRect(origin: CGPoint(x: x, y: y), size: constrainedSize)
      }
    }

    let firstSize = itemSizes[0]
    var result = [
      CGRect(
        x: bounds.minX,
        y: bounds.midY - firstSize.height / 2,
        width: firstSize.width,
        height: firstSize.height
      )
    ]
    guard itemSizes.count > 1 else { return result }
    let trailingWidth =
      itemSizes.dropFirst().reduce(0) { $0 + $1.width }
      + horizontalItemSpacing * CGFloat(max(0, itemSizes.count - 2))
    var x = bounds.maxX - trailingWidth
    for size in itemSizes.dropFirst() {
      result.append(
        CGRect(
          x: x,
          y: bounds.midY - size.height / 2,
          width: size.width,
          height: size.height
        ))
      x += size.width + horizontalItemSpacing
    }
    return result
  }

  static func horizontalWidth(for itemWidths: [CGFloat]) -> CGFloat {
    guard let first = itemWidths.first else { return 0 }
    guard itemWidths.count > 1 else { return first }
    return first + horizontalSectionSpacing + itemWidths.dropFirst().reduce(0, +)
      + horizontalItemSpacing * CGFloat(max(0, itemWidths.count - 2))
  }
}

enum WorkflowKeyboardFocusPolicy {
  static func initialActionID(
    cancelActionID: String,
    isCancelActionDisabled: Bool
  ) -> String? {
    isCancelActionDisabled ? nil : cancelActionID
  }
}

enum PermissionWorkflowActionKind: String, Equatable, Hashable, Sendable {
  case cancel
  case close
  case closeWhileCaptureContinues
  case done
  case discardChangesAndCapture
  case saveAndCapture
  case captureWithoutWiFi
  case continueWithLocationAccess
  case openSystemSettings
  case captureCurrentSettings

  var startsCapture: Bool {
    switch self {
    case .discardChangesAndCapture, .saveAndCapture, .captureWithoutWiFi,
      .continueWithLocationAccess, .captureCurrentSettings:
      true
    case .cancel, .close, .closeWhileCaptureContinues, .done, .openSystemSettings:
      false
    }
  }
}

struct PermissionWorkflowActionSet: Equatable, Sendable {
  let leading: PermissionWorkflowActionKind
  let trailing: [PermissionWorkflowActionKind]

  var all: [PermissionWorkflowActionKind] {
    [leading] + trailing
  }
}

enum PermissionWorkflowActionPolicy {
  static func actions(
    workflow: TrayPermissionWorkflow,
    capturePhase: TrayCapturePhase,
    isLocationAuthorized: Bool,
    hasWorkflowError: Bool = false,
    isWorkflowTaskInFlight: Bool = false
  ) -> PermissionWorkflowActionSet {
    switch capturePhase {
    case .running:
      return PermissionWorkflowActionSet(leading: .closeWhileCaptureContinues, trailing: [])
    case .success, .partial:
      return PermissionWorkflowActionSet(leading: .done, trailing: [])
    case .failure:
      return PermissionWorkflowActionSet(leading: .close, trailing: [])
    case .idle:
      break
    }
    if isWorkflowTaskInFlight {
      return PermissionWorkflowActionSet(leading: .close, trailing: [])
    }

    let trailing: [PermissionWorkflowActionKind]
    switch workflow {
    case .captureDirtyDraft:
      trailing = [.discardChangesAndCapture, .saveAndCapture]
    case .captureExplanation:
      trailing =
        isLocationAuthorized
        ? [.captureCurrentSettings]
        : [.captureWithoutWiFi, .continueWithLocationAccess]
    case .captureDenied, .systemSettings:
      trailing =
        isLocationAuthorized
        ? [.captureCurrentSettings]
        : [.captureWithoutWiFi, .openSystemSettings]
    }
    return PermissionWorkflowActionSet(
      leading: hasWorkflowError ? .close : .cancel,
      trailing: trailing
    )
  }

  static func statusSymbol(for capturePhase: TrayCapturePhase) -> String? {
    switch capturePhase {
    case .idle: "info.circle"
    case .running: nil
    case .success: "checkmark.circle"
    case .partial: "exclamationmark.triangle"
    case .failure: "xmark.octagon"
    }
  }
}

enum PermissionWorkflowFeedbackCopy {
  static let recoveryGuidanceKey =
    "Close this window, or choose one of the available actions below."
  static let savingCloseGuidanceKey =
    "Closing this window prevents capture from starting, even if the profile save finishes."

  static func errorTitle(languageCode: String? = nil) -> String {
    localized("Could Not Continue", languageCode: languageCode)
  }

  static func recoveryGuidance(languageCode: String? = nil) -> String {
    localized(recoveryGuidanceKey, languageCode: languageCode)
  }

  static func savingTitle(languageCode: String? = nil) -> String {
    localized("Saving profile…", languageCode: languageCode)
  }

  static func savingCloseGuidance(languageCode: String? = nil) -> String {
    localized(savingCloseGuidanceKey, languageCode: languageCode)
  }

  private static func localized(_ key: String, languageCode: String?) -> String {
    if let languageCode {
      return appLocalizedRuntime(key, languageCode: languageCode)
    }
    return appLocalizedRuntime(key)
  }
}

enum PermissionWorkflowActionCopy {
  static func title(
    for action: PermissionWorkflowActionKind,
    languageCode: String? = nil
  ) -> String {
    let key =
      switch action {
      case .cancel: "Cancel"
      case .close, .closeWhileCaptureContinues: "Close"
      case .done: "Done"
      case .discardChangesAndCapture: "Discard Changes and Capture"
      case .saveAndCapture: "Save and Capture"
      case .captureWithoutWiFi: "Capture Without Wi-Fi"
      case .continueWithLocationAccess: "Allow Location and Capture"
      case .openSystemSettings: "Open macOS System Settings"
      case .captureCurrentSettings: "Capture Current Settings"
      }
    if let languageCode {
      return appLocalizedRuntime(key, languageCode: languageCode)
    }
    return appLocalizedRuntime(key)
  }
}

enum PermissionWorkflowCopy {
  static func title(
    for workflow: TrayPermissionWorkflow,
    isLocationAuthorized: Bool,
    languageCode: String? = nil
  ) -> String {
    let key =
      switch workflow {
      case .captureDirtyDraft:
        "Save changes before capturing a new profile?"
      case .captureExplanation:
        isLocationAuthorized ? "Location Access Is Ready" : "Allow Location Access?"
      case .captureDenied, .systemSettings:
        isLocationAuthorized ? "Location Access Is Ready" : "Location Access Is Off"
      }
    return localized(key, languageCode: languageCode)
  }

  static func message(
    for workflow: TrayPermissionWorkflow,
    isLocationAuthorized: Bool,
    languageCode: String? = nil
  ) -> String {
    let key =
      switch workflow {
      case .captureDirtyDraft:
        "The open profile has changes that have not been saved."
      case .captureExplanation:
        isLocationAuthorized
          ? "Location access is enabled. Capture the current settings to include the current Wi-Fi network."
          : "Location access lets macOS reveal the current Wi-Fi network name during Capture. Desk Setup Switcher does not request or store your coordinates."
      case .captureDenied, .systemSettings:
        isLocationAuthorized
          ? "Location access is enabled. Capture the current settings to include the current Wi-Fi network."
          : "macOS cannot reveal the current Wi-Fi network name until Location access is enabled. You can enable it in Privacy & Security, or continue without Wi-Fi."
      }
    return localized(key, languageCode: languageCode)
  }

  private static func localized(_ key: String, languageCode: String?) -> String {
    if let languageCode {
      return appLocalizedRuntime(key, languageCode: languageCode)
    }
    return appLocalizedRuntime(key)
  }
}

enum WorkflowErrorActionKind: String, Equatable, Hashable, Sendable {
  case close
}

enum WorkflowErrorActionPolicy {
  // Apply-draft errors currently expose no operation that retries the failed
  // work. Keep the footer truthful until a real retry transition exists.
  static let actions: [WorkflowErrorActionKind] = [.close]
}

enum ApplyPreviewActionCopy {
  static func actionTitle(
    for mode: ApplyMode,
    languageCode: String? = nil
  ) -> String {
    localized(
      mode == .force ? "Apply Available Settings" : "Apply Profile",
      languageCode: languageCode
    )
  }

  static func reviewNotice(
    for reason: ApplyPreviewReviewReason,
    actionTitle: String,
    languageCode: String? = nil
  ) -> String {
    let key =
      switch reason {
      case .initial:
        "This is a review. No setting changes until you press %@ below."
      case .refreshedSystemState:
        "The Mac changed after this preview opened. Nothing was applied; review the refreshed plan and press %@ again."
      }
    let format = localized(key, languageCode: languageCode)
    let locale = languageCode.map(Locale.init(identifier:)) ?? .current
    return String(format: format, locale: locale, actionTitle)
  }

  private static func localized(_ key: String, languageCode: String?) -> String {
    if let languageCode {
      return appLocalizedRuntime(key, languageCode: languageCode)
    }
    return appLocalizedRuntime(key)
  }
}

private struct AdaptiveWorkflowActionLayout: Layout {
  struct Cache {
    var sizes: [CGSize] = []
    var isStacked = false
  }

  let forceStacked: Bool

  func makeCache(subviews: Subviews) -> Cache {
    Cache()
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Cache
  ) -> CGSize {
    guard !subviews.isEmpty else { return .zero }
    let idealSizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let idealHorizontalWidth = WorkflowActionBarLayoutPolicy.horizontalWidth(
      for: idealSizes.map(\.width)
    )
    let proposedWidth = proposal.width ?? idealHorizontalWidth
    let availableWidth = proposedWidth.isFinite ? proposedWidth : idealHorizontalWidth
    cache.isStacked = WorkflowActionBarLayoutPolicy.requiresStackedLayout(
      forceStacked: forceStacked,
      availableWidth: availableWidth,
      idealItemWidths: idealSizes.map(\.width)
    )
    cache.sizes =
      cache.isStacked
      ? subviews.map {
        $0.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil))
      }
      : idealSizes

    let height =
      if cache.isStacked {
        cache.sizes.reduce(0) { $0 + $1.height }
          + WorkflowActionBarLayoutPolicy.verticalSpacing
          * CGFloat(max(0, cache.sizes.count - 1))
      } else {
        cache.sizes.map(\.height).max() ?? 0
      }
    return CGSize(width: availableWidth, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Cache
  ) {
    guard !subviews.isEmpty, cache.sizes.count == subviews.count else { return }
    let frames = WorkflowActionBarLayoutPolicy.frames(
      in: bounds,
      itemSizes: cache.sizes,
      isStacked: cache.isStacked
    )
    for index in subviews.indices {
      let frame = frames[index]
      subviews[index].place(
        at: frame.origin,
        anchor: .topLeading,
        proposal: ProposedViewSize(frame.size)
      )
    }
  }
}

private struct AdaptiveWorkflowActionBar: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @FocusState private var keyboardFocusedActionID: String?
  let cancelAction: WorkflowFooterAction
  let trailingActions: [WorkflowFooterAction]
  let focusRequestID: String

  var body: some View {
    AdaptiveWorkflowActionLayout(
      forceStacked: WorkflowActionBarLayoutPolicy.requiresStackedLayout(for: dynamicTypeSize)
    ) {
      actionButton(cancelAction)
      ForEach(trailingActions) { action in
        actionButton(action)
      }
    }
    .focusSection()
    .task(id: focusRequestID) {
      await Task.yield()
      keyboardFocusedActionID = WorkflowKeyboardFocusPolicy.initialActionID(
        cancelActionID: cancelAction.id,
        isCancelActionDisabled: cancelAction.isDisabled
      )
    }
    .onChange(of: cancelAction.isDisabled) { _, isDisabled in
      if isDisabled, keyboardFocusedActionID == cancelAction.id {
        keyboardFocusedActionID = nil
      }
    }
  }

  @ViewBuilder
  private func actionButton(_ action: WorkflowFooterAction) -> some View {
    let labeledButton = Button(role: action.role, action: action.perform) {
      Text(action.title)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .disabled(action.isDisabled)
    .accessibilityLabel(action.accessibilityLabel ?? action.title)
    .focused($keyboardFocusedActionID, equals: action.id)

    let button = Group {
      if let hint = action.accessibilityHint {
        labeledButton.accessibilityHint(hint)
      } else {
        labeledButton
      }
    }

    let shortcutButton = Group {
      switch action.shortcut {
      case .none:
        button
      case .cancel:
        button.keyboardShortcut(.cancelAction)
      case .defaultAction:
        button.keyboardShortcut(.defaultAction)
      }
    }

    if action.isProminent {
      shortcutButton.buttonStyle(.borderedProminent)
    } else {
      shortcutButton
    }
  }
}

struct ApplyPreviewView: View {
  @EnvironmentObject private var model: ApplicationModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @AccessibilityFocusState private var isHeadingAccessibilityFocused: Bool
  @State private var expandedTechnicalOperationIDs: Set<UUID> = []
  let request: PendingApplyRequest
  let onCancel: () -> Void
  let onConfirm: () -> Void

  init(
    request: PendingApplyRequest,
    onCancel: @escaping () -> Void = {},
    onConfirm: @escaping () -> Void
  ) {
    self.request = request
    self.onCancel = onCancel
    self.onConfirm = onConfirm
  }

  private var applyActionTitle: String {
    ApplyPreviewActionCopy.actionTitle(for: request.preparation.mode)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      previewHeader

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          applyNotices

          previewSection(
            appLocalized("Planned changes"),
            systemImage: "arrow.triangle.2.circlepath"
          ) {
            if request.preparation.operations.isEmpty {
              Text(appLocalized("No setting needs to change."))
                .foregroundStyle(.secondary)
            } else {
              ForEach(request.preparation.operations) { operation in
                operationRow(operation)
              }
            }
          }

          if !request.preparation.omissions.isEmpty {
            previewSection(
              appLocalized("Skipped or unsupported"),
              systemImage: "forward.end"
            ) {
              ForEach(request.preparation.omissions) { omission in
                Label(appLocalizedRuntime(omission.reason), systemImage: "minus.circle")
              }
            }
          }

          if !request.preparation.validationIssues.isEmpty {
            previewSection(
              appLocalized("Validation"),
              systemImage: "exclamationmark.bubble"
            ) {
              ForEach(request.preparation.validationIssues) { issue in
                Label(
                  appLocalizedRuntime(issue.message),
                  systemImage: issue.isFatal ? "xmark.octagon" : "exclamationmark.circle"
                )
              }
            }
          }

          if !request.preparation.rejectionReasons.isEmpty {
            previewSection(appLocalized("Cannot apply"), systemImage: "hand.raised") {
              ForEach(request.preparation.rejectionReasons, id: \.self) { reason in
                Text(rejectionText(reason))
              }
            }
          }
        }
      }
      .id(request.id)
      .defaultScrollAnchor(.top)
      .scrollBounceBehavior(.basedOnSize)

      Divider()
      AdaptiveWorkflowActionBar(
        cancelAction: WorkflowFooterAction(
          id: "cancel",
          title: appLocalized("Cancel"),
          role: .cancel,
          shortcut: .cancel,
          perform: onCancel
        ),
        trailingActions: [
          WorkflowFooterAction(
            id: "apply",
            title: applyActionTitle,
            accessibilityHint: appLocalized(
              "Executes the reviewed operations and then shows itemized results."),
            shortcut: .defaultAction,
            isDisabled: !request.preparation.canExecute || model.isProfileMutationLocked,
            isProminent: true,
            perform: onConfirm
          )
        ],
        focusRequestID: request.id.uuidString
      )
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: request.id) {
      await Task.yield()
      isHeadingAccessibilityFocused = true
    }
  }

  @ViewBuilder
  private var previewHeader: some View {
    if dynamicTypeSize.isAccessibilitySize {
      stackedPreviewHeader
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          previewTitle
            .fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 0)
          Text(request.profile.name)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        stackedPreviewHeader
      }
    }
  }

  private var stackedPreviewHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      previewTitle
      Text(request.profile.name)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .truncationMode(.tail)
    }
  }

  private var previewTitle: some View {
    Label(
      request.preparation.mode == .force
        ? appLocalized("Available Settings Preview") : appLocalized("Apply Preview"),
      systemImage: request.preparation.mode == .force
        ? "exclamationmark.shield" : "list.bullet.clipboard"
    )
    .font(.title2.bold())
    .accessibilityAddTraits(.isHeader)
    .accessibilityFocused($isHeadingAccessibilityFocused)
  }

  @ViewBuilder
  private func operationRow(_ operation: PlannedOperation) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 5) {
          Text(appSettingGroupTitle(operation.group))
            .font(.caption.bold())
          operationDetails(operation)
        }
      } else {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
          GridRow(alignment: .top) {
            Text(appSettingGroupTitle(operation.group))
              .font(.caption.bold())
              .fixedSize(horizontal: true, vertical: false)
              .gridColumnAlignment(.leading)
            operationDetails(operation)
              .gridColumnAlignment(.leading)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
    .accessibilityCustomContent(
      Text(verbatim: appLocalized("Change risk")),
      Text(verbatim: riskTitle(operation.risk)),
      importance: operation.risk == .high ? .high : .default
    )
  }

  private func operationDetails(_ operation: PlannedOperation) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(appLocalizedRuntime(operation.summary))
          Spacer(minLength: 4)
          if operation.risk != .low {
            riskLabel(operation.risk)
              .fixedSize(horizontal: true, vertical: false)
          }
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(appLocalizedRuntime(operation.summary))
          if operation.risk != .low {
            riskLabel(operation.risk)
          }
        }
      }
      if let preview = presentationBuilder.operationPreview(for: operation) {
        operationPreview(preview, operation: operation)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func riskLabel(_ risk: OperationRisk) -> some View {
    Text(riskTitle(risk))
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var applyNotices: some View {
    if request.preparation.mode == .force {
      Label(
        appLocalized(
          "Only available operations will run. Review every skipped item before continuing."),
        systemImage: "exclamationmark.triangle"
      )
      .padding(10)
      .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    switch request.reviewReason {
    case .initial:
      Label(
        ApplyPreviewActionCopy.reviewNotice(
          for: request.reviewReason,
          actionTitle: applyActionTitle
        ),
        systemImage: "info.circle"
      )
      .padding(10)
      .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    case .refreshedSystemState:
      Label(
        ApplyPreviewActionCopy.reviewNotice(
          for: request.reviewReason,
          actionTitle: applyActionTitle
        ),
        systemImage: "arrow.clockwise.circle"
      )
      .padding(10)
      .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    if request.preparation.operations.contains(where: { $0.risk == .high }) {
      Label(
        appLocalized(
          "High-risk display and network changes remain temporary. Desk Setup Switcher will attempt to restore the previous configuration if the safety window closes, the app exits, or you do not confirm within 15 seconds."
        ),
        systemImage: "exclamationmark.shield"
      )
      .padding(10)
      .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  @ViewBuilder
  private func operationPreview(
    _ preview: FriendlyOperationPreview,
    operation: PlannedOperation
  ) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 5) {
          operationPreviewValue(
            title: appLocalized("Current"),
            value: appOperationPreviewValue(
              preview.previousValue.compactText,
              operation: operation,
              isPreviousValue: true
            )
          )
          operationPreviewValue(
            title: appLocalized("After apply"),
            value: appOperationPreviewValue(
              preview.desiredValue.compactText,
              operation: operation,
              isPreviousValue: false
            )
          )
        }
      } else {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
          GridRow {
            Text(appLocalized("Current"))
              .font(.caption.bold())
            Text(
              appOperationPreviewValue(
                preview.previousValue.compactText,
                operation: operation,
                isPreviousValue: true
              )
            )
          }
          GridRow {
            Text(appLocalized("After apply"))
              .font(.caption.bold())
            Text(
              appOperationPreviewValue(
                preview.desiredValue.compactText,
                operation: operation,
                isPreviousValue: false
              )
            )
          }
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .textSelection(.enabled)

    let previousDetails = preview.previousValue.technicalDetails
    let desiredDetails = preview.desiredValue.technicalDetails
    if !previousDetails.isEmpty || !desiredDetails.isEmpty {
      AccessibleDisclosureGroup(
        appLocalized("Technical Information"),
        accessibilityIdentifier: "apply-preview.technical-information.\(operation.id.uuidString)",
        isExpanded: technicalInformationBinding(for: operation.id)
      ) {
        ForEach(Array(previousDetails.enumerated()), id: \.offset) { _, detail in
          LabeledContent(
            appLocalized("Current \(appLocalizedPresentationText(detail.label))")
          ) {
            Text(detail.value)
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
        }
        ForEach(Array(desiredDetails.enumerated()), id: \.offset) { _, detail in
          LabeledContent(
            appLocalized("After apply \(appLocalizedPresentationText(detail.label))")
          ) {
            Text(detail.value)
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
        }
      }
      .font(.caption)
    }
  }

  private func technicalInformationBinding(for operationID: UUID) -> Binding<Bool> {
    Binding(
      get: { expandedTechnicalOperationIDs.contains(operationID) },
      set: { isExpanded in
        if isExpanded {
          expandedTechnicalOperationIDs.insert(operationID)
        } else {
          expandedTechnicalOperationIDs.remove(operationID)
        }
      }
    )
  }

  private func operationPreviewValue(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title)
        .font(.caption.bold())
      Text(value)
    }
  }

  private var presentationBuilder: ProfilePresentationBuilder {
    ProfilePresentationBuilder()
  }

  private func riskTitle(_ risk: OperationRisk) -> String {
    switch risk {
    case .low: appLocalized("Low risk")
    case .moderate: appLocalized("Review")
    case .high: appLocalized("High risk")
    }
  }

  private func previewSection<Content: View>(
    _ title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: systemImage)
        .font(.headline)
      content()
        .padding(.leading, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func rejectionText(_ reason: ApplyRejectionReason) -> String {
    switch reason {
    case .noIncludedSettings: appLocalized("The profile has no included settings.")
    case .conditionsUnsatisfied:
      appLocalized("One or more readiness conditions are not satisfied.")
    case .unavailableItems:
      appLocalized("Normal apply requires every included item to be available.")
    case .fatalValidationIssues:
      appLocalized("The profile contains a setting that cannot be applied safely.")
    case .noOperations: appLocalized("There is no available operation to apply.")
    case .transactionInProgress: appLocalized("Another apply transaction is running.")
    case .safetyConfirmationCapacityReached:
      appLocalized(
        "Confirm or revert the previous protected change first.")
    }
  }
}

struct ApplyResultDetailsView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @AccessibilityFocusState private var isHeadingAccessibilityFocused: Bool
  @FocusState private var isCloseKeyboardFocused: Bool
  let summary: ApplyResultSummary
  let result: ApplyExecutionResult
  let verification: PostApplyVerificationResult?
  let onClose: () -> Void

  init(
    summary: ApplyResultSummary,
    result: ApplyExecutionResult,
    verification: PostApplyVerificationResult?,
    onClose: @escaping () -> Void = {}
  ) {
    self.summary = summary
    self.result = result
    self.verification = verification
    self.onClose = onClose
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          resultHeader

          Text(recoveryGuidance)
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

          let countItems = ApplyResultCountPresentation.nonzeroItems(for: summary)
          if !countItems.isEmpty {
            if dynamicTypeSize.isAccessibilitySize {
              VStack(alignment: .leading, spacing: 5) {
                ForEach(countItems) { item in
                  HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.kind.title)
                    Spacer(minLength: 8)
                    Text(item.count, format: .number)
                      .monospacedDigit()
                  }
                }
              }
              .font(.caption)
            } else {
              Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                ForEach(countItems) { item in
                  resultCount(item.kind.title, item.count)
                }
              }
              .font(.caption)
            }
          }

          Divider()
          VStack(alignment: .leading, spacing: 24) {
            resultSection(appLocalized("Apply Results"), items: result.itemResults)
            if !result.rollbackResults.isEmpty {
              resultSection(appLocalized("Rollback Results"), items: result.rollbackResults)
            }

            if let unexpected = verification?.unexpectedRemainingOperations,
              !unexpected.isEmpty
            {
              VStack(alignment: .leading, spacing: 6) {
                Label(
                  appLocalized("Additional Read-back Changes"),
                  systemImage: "questionmark.circle"
                )
                .font(.headline)
                Text(
                  appLocalized(
                    "Read-back found additional changes that were not part of the completed operation. Refresh readiness before applying again."
                  )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(Array(unexpected.enumerated()), id: \.offset) { _, reference in
                  Label(
                    appLocalized(
                      "\(appSettingGroupTitle(reference.group)): \(appApplicationItemTitle(reference.key))"
                    ),
                    systemImage: "arrow.clockwise"
                  )
                  .font(.caption)
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .defaultScrollAnchor(.top)
      .scrollBounceBehavior(.basedOnSize)

      Divider()
      resultFooter
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: summary.appliedAt) {
      await Task.yield()
      isHeadingAccessibilityFocused = true
      isCloseKeyboardFocused = true
    }
  }

  @ViewBuilder
  private var resultFooter: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 8) {
        appliedAtText
        HStack {
          Spacer(minLength: 0)
          closeButton
        }
      }
      .focusSection()
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          appliedAtText
          Spacer(minLength: 0)
          closeButton
            .fixedSize(horizontal: true, vertical: false)
        }
        VStack(alignment: .leading, spacing: 8) {
          appliedAtText
          HStack {
            Spacer(minLength: 0)
            closeButton
          }
        }
      }
      .focusSection()
    }
  }

  @ViewBuilder
  private var resultHeader: some View {
    if dynamicTypeSize.isAccessibilitySize {
      stackedResultHeader
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          statusLabel
            .fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 0)
          Text(summary.profileName)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        stackedResultHeader
      }
    }
  }

  private var stackedResultHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      statusLabel
      Text(summary.profileName)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .truncationMode(.tail)
    }
  }

  private var statusLabel: some View {
    Label(statusTitle, systemImage: statusSymbol)
      .font(.title2.bold())
      .accessibilityAddTraits(.isHeader)
      .accessibilityFocused($isHeadingAccessibilityFocused)
  }

  private var appliedAtText: some View {
    Text(summary.appliedAt.formatted())
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  private var closeButton: some View {
    Button(appLocalized("Close")) { onClose() }
      .keyboardShortcut(.cancelAction)
      .focused($isCloseKeyboardFocused)
  }

  @ViewBuilder
  private func resultCount(_ title: String, _ count: Int) -> some View {
    GridRow {
      Text(title)
      Text(count, format: .number)
        .monospacedDigit()
    }
  }

  @ViewBuilder
  private func resultSection(
    _ title: String,
    items: [ApplicationItemSummary]
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.headline)
      if items.isEmpty {
        Text(appLocalized("No item results were recorded."))
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          resultItem(item)
        }
      }
    }
  }

  private func resultItem(_ item: ApplicationItemSummary) -> some View {
    let operation = ApplyOperationReference(item)
    let verificationFailure = verification?.failureReason(for: operation)
    let rollbackOperationIDs = Set(result.rollbackResults.map(\.id))
    let isNotVerified =
      item.status == .succeeded
      && !rollbackOperationIDs.contains(item.id)
      && verificationFailure != nil
    return VStack(alignment: .leading, spacing: 3) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          resultItemTitle(item)
          Spacer(minLength: 4)
          resultItemStatus(item, isNotVerified: isNotVerified)
            .fixedSize(horizontal: true, vertical: false)
        }
        VStack(alignment: .leading, spacing: 3) {
          resultItemTitle(item)
          resultItemStatus(item, isNotVerified: isNotVerified)
        }
      }
      Text(
        isNotVerified
          ? verificationFailure == .readBackUnavailable
            ? appLocalized(
              "The write completed, but the current setting could not be read back safely."
            )
            : appLocalized("The write completed, but read-back still requires this change.")
          : appLocalizedRuntime(item.message)
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
  }

  private func resultItemTitle(_ item: ApplicationItemSummary) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(appSettingGroupTitle(item.group))
        .font(.caption.bold())
      Text(appApplicationItemTitle(item.key))
    }
  }

  private func resultItemStatus(
    _ item: ApplicationItemSummary,
    isNotVerified: Bool
  ) -> some View {
    Label(
      isNotVerified
        ? appLocalized("Not Verified") : appApplicationItemStatusTitle(item.status),
      systemImage: isNotVerified ? "questionmark.circle" : itemStatusSymbol(item.status)
    )
    .font(.caption.bold())
  }

  private var statusTitle: String {
    switch summary.status {
    case .success: appLocalized("Applied")
    case .partial: appLocalized("Partially Applied")
    case .failure: appLocalized("Apply Failed")
    case .rolledBack: appLocalized("Rolled Back")
    case .rollbackFailed: appLocalized("Rollback Failed")
    case .notVerified: appLocalized("Not Verified")
    }
  }

  private var statusSymbol: String {
    switch summary.status {
    case .success: "checkmark.circle"
    case .partial: "exclamationmark.circle"
    case .failure: "xmark.octagon"
    case .rolledBack: "arrow.uturn.backward.circle"
    case .rollbackFailed: "exclamationmark.arrow.triangle.2.circlepath"
    case .notVerified: "questionmark.circle"
    }
  }

  private var recoveryGuidance: String {
    switch summary.status {
    case .success:
      appLocalized("All completed operations were confirmed by their result and read-back.")
    case .partial:
      appLocalized(
        "Some settings were skipped, failed, or not verified. Review the items below before trying again."
      )
    case .failure:
      appLocalized(
        "No complete result was confirmed. Review failed items and current permissions before trying again."
      )
    case .rolledBack:
      appLocalized(
        "The previous configuration was restored. Review the rollback items before applying again.")
    case .rollbackFailed:
      appLocalized(
        "The previous configuration may not be fully restored. Verify the affected settings in macOS now."
      )
    case .notVerified:
      appLocalized(
        "The write completed, but read-back could not confirm the requested state. Refresh and inspect the current settings."
      )
    }
  }

  private func itemStatusSymbol(_ status: ApplicationItemStatus) -> String {
    switch status {
    case .succeeded: "checkmark.circle"
    case .failed: "xmark.octagon"
    case .skipped: "forward.end"
    case .unsupported: "nosign"
    case .rolledBack: "arrow.uturn.backward.circle"
    case .rollbackFailed: "exclamationmark.arrow.triangle.2.circlepath"
    }
  }
}

struct SafetyConfirmationView: View {
  @EnvironmentObject private var model: ApplicationModel
  @AccessibilityFocusState private var isHeadingAccessibilityFocused: Bool
  let state: SafetyConfirmationState

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ScrollView {
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.shield")
            .font(.system(size: 42))
            .accessibilityHidden(true)
          Text(appLocalized("Keep these protected settings?"))
            .font(.headline)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($isHeadingAccessibilityFocused)
          Text(
            appLocalized(
              "Desk Setup Switcher will attempt to restore the previous configuration in \(state.secondsRemaining) seconds."
            )
          )
          .monospacedDigit()
          .multilineTextAlignment(.center)
          .accessibilityHidden(true)

          if !state.changeSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              if !state.guardedGroups.isEmpty {
                Text(state.guardedGroups.map(appSettingGroupTitle).joined(separator: " · "))
                  .font(.caption.bold())
              }
              ForEach(Array(state.changeSummaries.enumerated()), id: \.offset) { _, summary in
                Label(
                  appLocalizedRuntime(summary),
                  systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
          }

          ProgressView(value: Double(state.secondsRemaining), total: 15)
            .accessibilityLabel(appLocalized("Protected change confirmation time remaining"))
            .accessibilityValue(appLocalized("\(state.secondsRemaining) seconds remaining"))
        }
        .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(.top)
      .scrollBounceBehavior(.basedOnSize)

      Divider()
      AdaptiveWorkflowActionBar(
        cancelAction: WorkflowFooterAction(
          id: "revert",
          title: appLocalized("Revert Now"),
          shortcut: .cancel,
          isDisabled: model.isApplyTransactionInProgress,
          perform: { model.revertHighRiskChanges() }
        ),
        trailingActions: [
          WorkflowFooterAction(
            id: "keep",
            title: appLocalized("Keep Changes"),
            shortcut: .defaultAction,
            isDisabled: model.isApplyTransactionInProgress,
            perform: { model.confirmHighRiskChanges() }
          )
        ],
        focusRequestID: state.id.uuidString
      )
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: state.id) {
      await Task.yield()
      isHeadingAccessibilityFocused = true
    }
  }
}

@MainActor
protocol TrayWorkflowWindowPresenting: AnyObject {
  func presentAndWaitUntilKey() async -> TrayDestinationPresentation
}

@MainActor
final class TrayWorkflowWindowController: NSWindowController,
  TrayWorkflowWindowPresenting, NSWindowDelegate
{
  typealias AwaiterFactory = @MainActor (NSWindow) -> WindowPresentationAwaiter

  private static let initialContentSize = CGSize(width: 620, height: 500)
  private static let minimumContentSize = CGSize(width: 520, height: 360)

  private var presentationRequest: WindowPresentationRequest?
  private let activationCoordinator: ApplicationWindowActivationCoordinator?
  private let onWindowClose: @MainActor () -> Void
  private let makePresentationAwaiter: AwaiterFactory
  private let presentationAction: (@MainActor (NSWindow) -> Void)?

  #if DEBUG
    var inFlightPresentationConsumerCount: Int {
      presentationRequest?.consumerCount ?? 0
    }
  #endif

  init<Content: View>(
    rootView: Content,
    activationCoordinator: ApplicationWindowActivationCoordinator? = nil,
    onWindowClose: @escaping @MainActor () -> Void = {},
    makePresentationAwaiter: @escaping AwaiterFactory = {
      WindowPresentationAwaiter(window: $0)
    },
    presentationAction: (@MainActor (NSWindow) -> Void)? = nil
  ) {
    self.activationCoordinator = activationCoordinator
    self.onWindowClose = onWindowClose
    self.makePresentationAwaiter = makePresentationAwaiter
    self.presentationAction = presentationAction
    let hostingController = NSHostingController(rootView: rootView)
    // Workflow state replaces the hosted subtree after this controller is
    // created. Keep those intrinsic-size changes inside the window's content
    // viewport instead of allowing NSHostingController to resize NSWindow.
    hostingController.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    window.title = appLocalized("Desk Setup Switcher Workflow")
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.contentMinSize = Self.minimumContentSize
    // Assigning an NSHostingController can replace the requested content size
    // with its tiny intrinsic fitting size. Restore the intended viewport only
    // after AppKit has attached the controller.
    window.setContentSize(Self.initialContentSize)
    window.collectionBehavior = [.managed, .participatesInCycle]
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  func presentAndWaitUntilKey() async -> TrayDestinationPresentation {
    guard !Task.isCancelled else { return .cancelled }
    if let request = presentationRequest {
      return await awaitPresentation(request)
    }
    guard let window else {
      return TrayDestinationPresentation.failed(
        appLocalized("The workflow window is unavailable."))
    }
    let waiter = makePresentationAwaiter(window)
    let request = WindowPresentationRequest(window: window, waiter: waiter)
    presentationRequest = request
    request.producer = Task { @MainActor [weak self] in
      guard let self else {
        request.resolve(
          .failed(appLocalized("The workflow window is unavailable.")))
        return
      }
      let result = await waiter.present {
        self.prepareForPresentation()
        self.activationCoordinator?.windowWillPresent(window)
        if let presentationAction = self.presentationAction {
          presentationAction(window)
          return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
      }
      self.completePresentation(request, result: result, window: window)
    }
    return await awaitPresentation(request)
  }

  private func completePresentation(
    _ request: WindowPresentationRequest,
    result: TrayDestinationPresentation,
    window: NSWindow
  ) {
    let isCurrentRequest = presentationRequest === request
    if isCurrentRequest {
      switch result {
      case .presented:
        break
      case .failed, .cancelled:
        window.orderOut(nil)
        activationCoordinator?.windowDidHide(window)
      }
    }
    request.resolve(result)
    if isCurrentRequest {
      presentationRequest = nil
    }
  }

  func closeWorkflow() {
    window?.performClose(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    onWindowClose()
    cancelInFlightPresentation()
    sender.orderOut(nil)
    activationCoordinator?.windowDidHide(sender)
    return false
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    let minimumFrameSize = sender.frameRect(
      forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)
    ).size
    return NSSize(
      width: max(frameSize.width, minimumFrameSize.width),
      height: max(frameSize.height, minimumFrameSize.height)
    )
  }

  private func awaitPresentation(
    _ request: WindowPresentationRequest
  ) async -> TrayDestinationPresentation {
    await request.value { [weak self, weak request] in
      guard let self, let request else { return }
      self.cancelProducerForLastConsumer(request)
    }
  }

  private func cancelProducerForLastConsumer(_ request: WindowPresentationRequest) {
    guard presentationRequest === request, request.consumerCount == 0 else { return }
    request.cancelProducer()
    request.window.orderOut(nil)
    activationCoordinator?.windowDidHide(request.window)
    if presentationRequest === request {
      presentationRequest = nil
    }
  }

  private func cancelInFlightPresentation() {
    guard let request = presentationRequest else { return }
    // A red-close and immediate reopen can share one MainActor turn. Detach
    // the cancelled request first so the reopen owns a fresh producer; stale
    // completion is already guarded by request identity.
    presentationRequest = nil
    request.cancelProducer()
  }

  func prepareForPresentation() {
    guard let window else { return }
    // Hosted root transitions can recompute native constraints. Reassert the
    // app-owned minimum each time before repairing a legacy undersized frame.
    window.contentMinSize = Self.minimumContentSize
    restoreMinimumContentSizeIfNeeded(window)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
  }

  private func restoreMinimumContentSizeIfNeeded(_ window: NSWindow) {
    let currentSize = window.contentRect(forFrameRect: window.frame).size
    let minimumSize = Self.minimumContentSize
    guard currentSize.width < minimumSize.width || currentSize.height < minimumSize.height else {
      return
    }
    window.setContentSize(
      CGSize(
        width: max(currentSize.width, minimumSize.width),
        height: max(currentSize.height, minimumSize.height)
      ))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@MainActor
final class TrayWorkflowCloseRelay {
  weak var controller: TrayWorkflowWindowController?

  func close() {
    controller?.closeWorkflow()
  }
}

struct WorkflowErrorView: View {
  @AccessibilityFocusState private var isHeadingAccessibilityFocused: Bool
  let message: String
  let onClose: () -> Void

  init(message: String, onClose: @escaping () -> Void = {}) {
    self.message = message
    self.onClose = onClose
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Label(appLocalized("Could Not Continue"), systemImage: "exclamationmark.triangle")
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($isHeadingAccessibilityFocused)
          Text(message)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .defaultScrollAnchor(.top)
      .scrollBounceBehavior(.basedOnSize)

      Divider()
      AdaptiveWorkflowActionBar(
        cancelAction: WorkflowFooterAction(
          id: "close",
          title: appLocalized("Close"),
          role: .cancel,
          shortcut: .cancel,
          perform: onClose
        ),
        trailingActions: [],
        focusRequestID: message
      )
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: message) {
      await Task.yield()
      isHeadingAccessibilityFocused = true
    }
  }
}

private enum WorkflowRootAccessibilityFocusTarget: Hashable {
  case permission(TrayPermissionWorkflow)
  case dirtyApply(UUID)
  case preparing(UUID)
  case calculating(UUID)
  case noResult
  case noWorkflow
}

struct TrayWorkflowRootView: View {
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var locationPermission: LocationPermissionController
  @ObservedObject var presentation: TrayPresentationModel
  @AccessibilityFocusState private var accessibilityFocusTarget:
    WorkflowRootAccessibilityFocusTarget?
  let onClose: @MainActor () -> Void

  var body: some View {
    Group {
      switch presentation.workflowDestination {
      case .permission(let workflow):
        permissionWorkflow(workflow)
      case .applyPreview(let profileID, _):
        applyWorkflow(profileID: profileID)
      case .resultDetails:
        resultDetails
      case .settings, .profileEditor, .none:
        ContentUnavailableView(
          "No Workflow",
          systemImage: "rectangle.on.rectangle.slash",
          description: Text("Return to the tray and choose an action.")
        )
        .accessibilityFocused($accessibilityFocusTarget, equals: .noWorkflow)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: requestedAccessibilityFocusTarget) {
      guard let target = requestedAccessibilityFocusTarget else {
        accessibilityFocusTarget = nil
        return
      }
      await Task.yield()
      accessibilityFocusTarget = target
    }
  }

  private func permissionWorkflow(_ workflow: TrayPermissionWorkflow) -> some View {
    let actionSet = PermissionWorkflowActionPolicy.actions(
      workflow: workflow,
      capturePhase: presentation.capturePhase,
      isLocationAuthorized: locationPermission.isAuthorized,
      hasWorkflowError: presentation.permissionWorkflowError != nil,
      isWorkflowTaskInFlight: presentation.hasWorkflowTask
    )
    return VStack(alignment: .leading, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Label(permissionTitle(workflow), systemImage: "hand.raised")
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused(
              $accessibilityFocusTarget,
              equals: .permission(workflow)
            )
          Text(permissionMessage(workflow))
            .foregroundStyle(.secondary)

          capturePhaseStatus
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .defaultScrollAnchor(.top)
      .scrollBounceBehavior(.basedOnSize)

      Divider()
      AdaptiveWorkflowActionBar(
        cancelAction: permissionAction(actionSet.leading),
        trailingActions: actionSet.trailing.map(permissionAction),
        focusRequestID:
          "permission-\(String(describing: workflow))-\(actionSet.leading.rawValue)"
      )
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .id(workflow)
  }

  private func permissionAction(_ kind: PermissionWorkflowActionKind) -> WorkflowFooterAction {
    switch kind {
    case .cancel:
      WorkflowFooterAction(
        id: kind.rawValue,
        title: PermissionWorkflowActionCopy.title(for: kind),
        role: .cancel,
        shortcut: .cancel,
        perform: {
          presentation.handleWorkflowWindowClose()
          onClose()
        }
      )

    case .close:
      WorkflowFooterAction(
        id: kind.rawValue,
        title: PermissionWorkflowActionCopy.title(for: kind),
        shortcut: .cancel,
        perform: {
          presentation.handleWorkflowWindowClose()
          onClose()
        }
      )

    case .closeWhileCaptureContinues:
      WorkflowFooterAction(
        id: kind.rawValue,
        title: PermissionWorkflowActionCopy.title(for: kind),
        accessibilityHint: appLocalized(
          "Capture continues safely after this window closes."),
        shortcut: .cancel,
        perform: {
          presentation.handleWorkflowWindowClose()
          onClose()
        }
      )

    case .done:
      WorkflowFooterAction(
        id: kind.rawValue,
        title: PermissionWorkflowActionCopy.title(for: kind),
        shortcut: .cancel,
        perform: {
          presentation.handleWorkflowWindowClose()
          onClose()
        }
      )

    case .discardChangesAndCapture:
      WorkflowFooterAction(
        id: "discard-capture",
        title: PermissionWorkflowActionCopy.title(for: kind),
        role: .destructive,
        perform: { presentation.discardDraftThenCapture() }
      )

    case .saveAndCapture:
      WorkflowFooterAction(
        id: "save-capture",
        title: PermissionWorkflowActionCopy.title(for: kind),
        shortcut: .defaultAction,
        isDisabled: !presentation.openDraftIsValid,
        perform: { presentation.saveDraftThenCapture() }
      )

    case .captureWithoutWiFi:
      WorkflowFooterAction(
        id: "capture-without-wifi",
        title: PermissionWorkflowActionCopy.title(for: kind),
        perform: { presentation.startCapture() }
      )

    case .continueWithLocationAccess:
      WorkflowFooterAction(
        id: "continue",
        title: PermissionWorkflowActionCopy.title(for: kind),
        shortcut: .defaultAction,
        perform: { presentation.requestLocationAccessAndCapture() }
      )

    case .openSystemSettings:
      WorkflowFooterAction(
        id: "open-system-settings",
        title: PermissionWorkflowActionCopy.title(for: kind),
        shortcut: .defaultAction,
        perform: { presentation.openLocationSystemSettings() }
      )

    case .captureCurrentSettings:
      WorkflowFooterAction(
        id: "capture-current-settings",
        title: PermissionWorkflowActionCopy.title(for: kind),
        shortcut: .defaultAction,
        perform: { presentation.startCapture() }
      )
    }
  }

  @ViewBuilder
  private var capturePhaseStatus: some View {
    switch presentation.capturePhase {
    case .idle:
      if presentation.hasWorkflowTask {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
              .accessibilityHidden(true)
            Text(PermissionWorkflowFeedbackCopy.savingTitle())
              .font(.caption.bold())
          }
          .accessibilityElement(children: .combine)
          Text(PermissionWorkflowFeedbackCopy.savingCloseGuidance())
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      } else if let error = presentation.permissionWorkflowError {
        VStack(alignment: .leading, spacing: 6) {
          Label(
            PermissionWorkflowFeedbackCopy.errorTitle(),
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption.bold())
          Text(error)
            .font(.caption)
          Text(PermissionWorkflowFeedbackCopy.recoveryGuidance())
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
      } else if let notice = presentation.permissionWorkflowNotice {
        Label(notice, systemImage: "location.slash")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Label(
          appLocalized("No system setting changes occur until you choose the next step."),
          systemImage: "info.circle"
        )
        .font(.caption)
      }
    case .running:
      HStack {
        ProgressView()
        Text("Reading current settings without changing them…")
      }
      .accessibilityElement(children: .combine)
    case .success(let message):
      Label(
        message,
        systemImage: PermissionWorkflowActionPolicy.statusSymbol(
          for: presentation.capturePhase) ?? "checkmark.circle"
      )
    case .partial(let message):
      Label(
        message,
        systemImage: PermissionWorkflowActionPolicy.statusSymbol(
          for: presentation.capturePhase) ?? "exclamationmark.triangle"
      )
    case .failure(let message):
      Label(
        message,
        systemImage: PermissionWorkflowActionPolicy.statusSymbol(
          for: presentation.capturePhase) ?? "xmark.octagon"
      )
    }
  }

  @ViewBuilder
  private func applyWorkflow(profileID: UUID) -> some View {
    if let error = presentation.applyDraftError {
      workflowError(error)
    } else if let prompt = presentation.applyDraftPrompt {
      dirtyApplyPrompt(prompt)
    } else if let safety = model.safetyConfirmation {
      SafetyConfirmationView(state: safety)
        .environmentObject(model)
    } else if let request = model.pendingApply, request.profile.id == profileID {
      ApplyPreviewView(
        request: request,
        onCancel: {
          presentation.cancelApplyWorkflow()
          onClose()
        },
        onConfirm: {
          presentation.confirmPendingApply(request)
        }
      )
      .environmentObject(model)
    } else if model.isApplyTransactionInProgress
      || model.profiles.first(where: { $0.id == profileID }).map(model.isPreparingApply) == true
    {
      VStack(spacing: 14) {
        ProgressView()
        Text("Preparing and recording the protected apply workflow…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .combine)
      .accessibilityFocused($accessibilityFocusTarget, equals: .preparing(profileID))
    } else if let summary = model.lastApplySummary,
      summary.profileID == profileID,
      let result = model.lastApplyResult
    {
      ApplyResultDetailsView(
        summary: summary,
        result: result,
        verification: model.lastApplyVerification,
        onClose: { onClose() }
      )
    } else {
      VStack(spacing: 14) {
        ProgressView()
        Text("Calculating a read-only change plan…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .combine)
      .accessibilityFocused($accessibilityFocusTarget, equals: .calculating(profileID))
    }
  }

  private var resultDetails: some View {
    Group {
      if let summary = model.lastApplySummary, let result = model.lastApplyResult {
        ApplyResultDetailsView(
          summary: summary,
          result: result,
          verification: model.lastApplyVerification,
          onClose: { onClose() }
        )
      } else {
        ContentUnavailableView(
          "No Apply Result",
          systemImage: "clock.arrow.circlepath",
          description: Text("Apply a profile to see itemized results.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityFocused($accessibilityFocusTarget, equals: .noResult)
      }
    }
  }

  private func dirtyApplyPrompt(_ prompt: TrayApplyDraftPrompt) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Label(presentation.applyDraftTitle, systemImage: "square.and.pencil")
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused(
              $accessibilityFocusTarget,
              equals: .dirtyApply(prompt.id)
            )
          Text(presentation.applyDraftMessage)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .defaultScrollAnchor(.top)
      .scrollBounceBehavior(.basedOnSize)

      Divider()
      AdaptiveWorkflowActionBar(
        cancelAction: WorkflowFooterAction(
          id: "cancel",
          title: appLocalized("Cancel"),
          role: .cancel,
          shortcut: .cancel,
          perform: {
            presentation.cancelApplyDraftPrompt()
            onClose()
          }
        ),
        trailingActions: dirtyApplyActions(prompt),
        focusRequestID: "dirty-apply-\(prompt.id.uuidString)"
      )
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func dirtyApplyActions(_ prompt: TrayApplyDraftPrompt) -> [WorkflowFooterAction] {
    switch prompt.kind {
    case .targetDraft:
      [
        WorkflowFooterAction(
          id: "save-apply",
          title: appLocalized("Save and Apply"),
          shortcut: .defaultAction,
          isDisabled: !presentation.openDraftIsValid,
          perform: { presentation.saveDraftThenApply(prompt) }
        )
      ]
    case .otherDraft(let openProfileID, let openProfileName):
      [
        WorkflowFooterAction(
          id: "discard-apply",
          title: appLocalized("Discard Changes"),
          accessibilityLabel: appLocalized(
            "Discard Changes to \(openProfileName) and Apply \(prompt.targetProfileName)"),
          role: .destructive,
          perform: {
            presentation.discardDraftThenApply(
              prompt,
              expectedOpenProfileID: openProfileID
            )
          }
        ),
        WorkflowFooterAction(
          id: "save-apply",
          title: appLocalized("Save and Apply"),
          accessibilityLabel: appLocalized(
            "Save \(openProfileName) and Apply \(prompt.targetProfileName)"),
          shortcut: .defaultAction,
          isDisabled: !presentation.openDraftIsValid,
          perform: { presentation.saveDraftThenApply(prompt) }
        ),
      ]
    }
  }

  private func workflowError(_ message: String) -> some View {
    WorkflowErrorView(message: message) {
      presentation.closeApplyWorkflowAfterError()
      onClose()
    }
  }

  private var requestedAccessibilityFocusTarget: WorkflowRootAccessibilityFocusTarget? {
    switch presentation.workflowDestination {
    case .permission(let workflow):
      .permission(workflow)
    case .applyPreview(let profileID, _):
      if presentation.applyDraftError != nil {
        nil
      } else if let prompt = presentation.applyDraftPrompt {
        .dirtyApply(prompt.id)
      } else if model.safetyConfirmation != nil || model.pendingApply?.profile.id == profileID {
        nil
      } else if model.isApplyTransactionInProgress
        || model.profiles.first(where: { $0.id == profileID }).map(model.isPreparingApply) == true
      {
        .preparing(profileID)
      } else if model.lastApplySummary?.profileID == profileID, model.lastApplyResult != nil {
        nil
      } else {
        .calculating(profileID)
      }
    case .resultDetails:
      model.lastApplySummary != nil && model.lastApplyResult != nil ? nil : .noResult
    case .settings, .profileEditor, .none:
      .noWorkflow
    }
  }

  private func permissionTitle(_ workflow: TrayPermissionWorkflow) -> String {
    PermissionWorkflowCopy.title(
      for: workflow,
      isLocationAuthorized: locationPermission.isAuthorized
    )
  }

  private func permissionMessage(_ workflow: TrayPermissionWorkflow) -> String {
    PermissionWorkflowCopy.message(
      for: workflow,
      isLocationAuthorized: locationPermission.isAuthorized
    )
  }
}

@MainActor
final class TrayDestinationCoordinator: TrayDestinationPresenting {
  private let model: ApplicationModel
  private let profileEditor: ProfileEditorModel
  private let settingsNavigation: SettingsNavigationModel
  private weak var settingsController: (any RuntimeSettingsWindowPresenting)?
  private weak var workflowController: (any TrayWorkflowWindowPresenting)?
  private let presentation: TrayPresentationModel

  init(
    model: ApplicationModel,
    profileEditor: ProfileEditorModel,
    settingsNavigation: SettingsNavigationModel,
    settingsController: (any RuntimeSettingsWindowPresenting)?,
    workflowController: (any TrayWorkflowWindowPresenting)?,
    presentation: TrayPresentationModel
  ) {
    self.model = model
    self.profileEditor = profileEditor
    self.settingsNavigation = settingsNavigation
    self.settingsController = settingsController
    self.workflowController = workflowController
    self.presentation = presentation
  }

  func present(_ destination: TrayDestination) async -> TrayDestinationPresentation {
    switch destination {
    case .settings:
      guard let settingsController else {
        return .failed(appLocalized("The Settings window is unavailable."))
      }
      settingsNavigation.routeToDefaultTab(
        startsNewPresentation: !settingsController.isPresentationVisible
      )
      return await settingsController.presentAndWaitUntilKey()

    case .profileEditor(let profileID):
      guard let profile = model.profiles.first(where: { $0.id == profileID }) else {
        return .failed(appLocalized("The selected profile no longer exists."))
      }
      switch profileEditor.requestSelection(profile) {
      case .selected(let target):
        model.selectProfile(id: target.profileID)
      case .requiresDecision, .unchanged:
        break
      }
      guard let settingsController else {
        return .failed(appLocalized("The Settings window is unavailable."))
      }
      settingsNavigation.routeToDefaultTab(
        startsNewPresentation: !settingsController.isPresentationVisible
      )
      return await settingsController.presentAndWaitUntilKey()

    case .permission(let workflow):
      presentation.beginPermissionWorkflow(workflow)
      guard let workflowController else {
        return .failed(appLocalized("The permission workflow window is unavailable."))
      }
      return await workflowController.presentAndWaitUntilKey()

    case .applyPreview(let profileID, let mode):
      guard model.profiles.contains(where: { $0.id == profileID }) else {
        return .failed(appLocalized("The target profile is no longer available to apply."))
      }
      presentation.setWorkflowDestination(destination)
      guard let workflowController else {
        return .failed(appLocalized("The apply workflow window is unavailable."))
      }
      let result = await workflowController.presentAndWaitUntilKey()
      if case .presented(true, true) = result {
        presentation.beginApplyWorkflow(profileID: profileID, mode: mode)
      }
      return result

    case .resultDetails:
      guard model.lastApplySummary != nil, model.lastApplyResult != nil else {
        return .failed(appLocalized("No apply result is available."))
      }
      presentation.setWorkflowDestination(destination)
      guard let workflowController else {
        return .failed(appLocalized("The result window is unavailable."))
      }
      return await workflowController.presentAndWaitUntilKey()
    }
  }
}
