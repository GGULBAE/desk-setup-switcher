import AppKit
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

struct ApplyPreviewView: View {
  @EnvironmentObject private var model: ApplicationModel
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

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(
          request.preparation.mode == .force
            ? appLocalized("Available Settings Preview") : appLocalized("Apply Preview"),
          systemImage: request.preparation.mode == .force
            ? "exclamationmark.shield" : "list.bullet.clipboard"
        )
        .font(.title2.bold())
        Spacer()
        Text(request.profile.name)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .layoutPriority(0)
      }

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
                VStack(alignment: .leading, spacing: 5) {
                  HStack(alignment: .firstTextBaseline) {
                    Text(appSettingGroupTitle(operation.group))
                      .font(.caption.bold())
                      .frame(width: 70, alignment: .leading)
                    Text(appLocalizedRuntime(operation.summary))
                    Spacer()
                    Text(
                      operation.risk == .high
                        ? appLocalized("High risk")
                        : operation.risk == .moderate
                          ? appLocalized("Review") : appLocalized("Low risk")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  if let preview = presentationBuilder.operationPreview(for: operation) {
                    operationPreview(preview, operation: operation)
                      .padding(.leading, 80)
                  }
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
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
      HStack {
        Button("Cancel") {
          onCancel()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button(
          request.preparation.mode == .force
            ? appLocalized("Apply Available Settings") : appLocalized("Apply Profile")
        ) {
          onConfirm()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(!request.preparation.canExecute || model.isProfileMutationLocked)
        .accessibilityHint(
          appLocalized("Executes the reviewed operations and then shows itemized results."))
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        appLocalized(
          "This is a review. No setting changes until you press Apply Profile below."),
        systemImage: "info.circle"
      )
      .padding(10)
      .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    case .refreshedSystemState:
      Label(
        appLocalized(
          "The Mac changed after this preview opened. Nothing was applied; review the refreshed plan and press Apply Profile again."
        ),
        systemImage: "arrow.clockwise.circle"
      )
      .padding(10)
      .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    if request.preparation.operations.contains(where: { $0.risk == .high }) {
      Label(
        appLocalized(
          "High-risk display and network changes remain temporary and will be restored if the safety window closes, the app exits, or you do not confirm within 15 seconds."
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
    .font(.caption)
    .foregroundStyle(.secondary)
    .textSelection(.enabled)

    let previousDetails = preview.previousValue.technicalDetails
    let desiredDetails = preview.desiredValue.technicalDetails
    if !previousDetails.isEmpty || !desiredDetails.isEmpty {
      DisclosureGroup("Technical Information") {
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

  private var presentationBuilder: ProfilePresentationBuilder {
    ProfilePresentationBuilder()
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
      HStack(alignment: .firstTextBaseline) {
        Label(statusTitle, systemImage: statusSymbol)
          .font(.title2.bold())
        Spacer()
        Text(summary.profileName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Text(recoveryGuidance)
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

      Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
        resultCount("Succeeded", summary.succeededCount)
        resultCount("Failed", summary.failedCount)
        resultCount("Skipped", summary.skippedCount)
        resultCount("Unsupported", summary.unsupportedCount)
        resultCount("Not verified", summary.notVerifiedCount)
        resultCount("Rolled back", summary.rolledBackCount)
        resultCount("Rollback failed", summary.rollbackFailedCount)
      }
      .font(.caption)

      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          resultSection("Apply Results", items: result.itemResults)
          if !result.rollbackResults.isEmpty {
            resultSection("Rollback Results", items: result.rollbackResults)
          }

          if let unexpected = verification?.unexpectedRemainingOperations,
            !unexpected.isEmpty
          {
            VStack(alignment: .leading, spacing: 6) {
              Label("Additional Read-back Changes", systemImage: "questionmark.circle")
                .font(.headline)
              Text(
                "Read-back found additional changes that were not part of the completed operation. Refresh readiness before applying again."
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

      Divider()
      HStack {
        Text(summary.appliedAt.formatted())
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Close") { onClose() }
          .keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func resultCount(_ title: LocalizedStringKey, _ count: Int) -> some View {
    GridRow {
      Text(title)
      Text(count, format: .number)
        .monospacedDigit()
    }
  }

  @ViewBuilder
  private func resultSection(
    _ title: LocalizedStringKey,
    items: [ApplicationItemSummary]
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.headline)
      if items.isEmpty {
        Text("No item results were recorded.")
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
      HStack(alignment: .firstTextBaseline) {
        Text(appSettingGroupTitle(item.group))
          .font(.caption.bold())
        Text(appApplicationItemTitle(item.key))
        Spacer()
        Label(
          isNotVerified
            ? appLocalized("Not Verified") : appApplicationItemStatusTitle(item.status),
          systemImage: isNotVerified ? "questionmark.circle" : itemStatusSymbol(item.status)
        )
        .font(.caption.bold())
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
  let state: SafetyConfirmationState

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.shield")
        .font(.system(size: 42))
        .accessibilityHidden(true)
      Text("Keep these protected settings?")
        .font(.headline)
      Text(
        appLocalized(
          "The previous configuration will return in \(state.secondsRemaining) seconds.")
      )
      .monospacedDigit()
      .multilineTextAlignment(.center)
      .accessibilityLabel(
        appLocalized("Automatic rollback in \(state.secondsRemaining) seconds"))

      if !state.changeSummaries.isEmpty {
        ScrollView {
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
        }
        .defaultScrollAnchor(.top)
        .scrollBounceBehavior(.basedOnSize)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
      }

      ProgressView(value: Double(state.secondsRemaining), total: 15)
        .accessibilityLabel("Protected change confirmation time remaining")
        .accessibilityValue(appLocalized("\(state.secondsRemaining) seconds remaining"))

      HStack {
        Button("Revert Now") { model.revertHighRiskChanges() }
          .keyboardShortcut(.cancelAction)
          .disabled(model.isApplyTransactionInProgress)
        Button("Keep Changes") { model.confirmHighRiskChanges() }
          .keyboardShortcut(.defaultAction)
          .disabled(model.isApplyTransactionInProgress)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
  private var presentationRequest: (id: UUID, task: Task<TrayDestinationPresentation, Never>)?
  private let activationCoordinator: ApplicationWindowActivationCoordinator?
  private let onWindowClose: @MainActor () -> Void

  init<Content: View>(
    rootView: Content,
    activationCoordinator: ApplicationWindowActivationCoordinator? = nil,
    onWindowClose: @escaping @MainActor () -> Void = {}
  ) {
    self.activationCoordinator = activationCoordinator
    self.onWindowClose = onWindowClose
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    window.title = appLocalized("Desk Setup Switcher Workflow")
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.contentMinSize = CGSize(width: 520, height: 360)
    window.collectionBehavior = [.managed, .participatesInCycle]
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  func presentAndWaitUntilKey() async -> TrayDestinationPresentation {
    if let presentationRequest {
      return await presentationRequest.task.value
    }
    let id = UUID()
    let task = Task { @MainActor [weak self] in
      guard let self, let window = self.window else {
        return TrayDestinationPresentation.failed(
          appLocalized("The workflow window is unavailable."))
      }
      let waiter = WindowPresentationAwaiter(window: window)
      return await waiter.present {
        self.prepareForPresentation()
        self.activationCoordinator?.windowWillPresent(window)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
      }
    }
    presentationRequest = (id, task)
    let result = await task.value
    switch result {
    case .presented:
      break
    case .failed, .cancelled:
      if let window {
        activationCoordinator?.windowDidHide(window)
      }
    }
    if presentationRequest?.id == id {
      presentationRequest = nil
    }
    return result
  }

  func closeWorkflow() {
    window?.performClose(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    onWindowClose()
    sender.orderOut(nil)
    activationCoordinator?.windowDidHide(sender)
    return false
  }

  func prepareForPresentation() {
    if window?.isMiniaturized == true {
      window?.deminiaturize(nil)
    }
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

struct TrayWorkflowRootView: View {
  @EnvironmentObject private var model: ApplicationModel
  @ObservedObject var presentation: TrayPresentationModel
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
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func permissionWorkflow(_ workflow: TrayPermissionWorkflow) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(permissionTitle(workflow), systemImage: "hand.raised")
        .font(.title2.bold())
        .accessibilityAddTraits(.isHeader)
      Text(permissionMessage(workflow))
        .foregroundStyle(.secondary)

      capturePhaseStatus

      Spacer(minLength: 8)
      Divider()
      HStack {
        Button("Cancel", role: .cancel) {
          presentation.cancelPermissionWorkflow()
          onClose()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        permissionActions(workflow)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func permissionActions(_ workflow: TrayPermissionWorkflow) -> some View {
    switch workflow {
    case .captureDirtyDraft:
      Button("Discard Changes and Capture", role: .destructive) {
        presentation.discardDraftThenCapture()
      }
      Button("Save and Capture") {
        presentation.saveDraftThenCapture()
      }
      .keyboardShortcut(.defaultAction)
      .disabled(!presentation.openDraftIsValid)

    case .captureExplanation:
      Button("Capture Without Wi-Fi") {
        presentation.startCapture()
      }
      Button("Continue") {
        presentation.requestLocationAccessAndCapture()
      }
      .keyboardShortcut(.defaultAction)

    case .captureDenied:
      Button("Capture Without Wi-Fi") {
        presentation.startCapture()
      }
      Button("Open macOS System Settings") {
        presentation.openLocationSystemSettings()
      }
      .keyboardShortcut(.defaultAction)

    case .systemSettings:
      Button("Capture Without Wi-Fi") {
        presentation.startCapture()
      }
      Button("Open macOS System Settings") {
        presentation.openLocationSystemSettings()
      }
      .keyboardShortcut(.defaultAction)
    }
  }

  @ViewBuilder
  private var capturePhaseStatus: some View {
    switch presentation.capturePhase {
    case .idle:
      Label(
        "No system setting changes occur until you choose the next step.",
        systemImage: "info.circle"
      )
      .font(.caption)
    case .running:
      HStack {
        ProgressView()
        Text("Reading current settings without changing them…")
      }
      .accessibilityElement(children: .combine)
    case .success(let message), .partial(let message):
      Label(message, systemImage: "checkmark.circle")
    case .failure(let message):
      Label(message, systemImage: "xmark.octagon")
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
      }
    }
  }

  private func dirtyApplyPrompt(_ prompt: TrayApplyDraftPrompt) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(presentation.applyDraftTitle, systemImage: "square.and.pencil")
        .font(.title2.bold())
      Text(presentation.applyDraftMessage)
        .foregroundStyle(.secondary)
      Spacer()
      Divider()
      HStack {
        Button("Cancel", role: .cancel) {
          presentation.cancelApplyDraftPrompt()
          onClose()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        switch prompt.kind {
        case .targetDraft:
          Button("Save and Apply") {
            presentation.saveDraftThenApply(prompt)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!presentation.openDraftIsValid)
        case .otherDraft(let openProfileID, let openProfileName):
          Button(
            appLocalized(
              "Discard Changes to \(openProfileName) and Apply \(prompt.targetProfileName)"),
            role: .destructive
          ) {
            presentation.discardDraftThenApply(
              prompt,
              expectedOpenProfileID: openProfileID
            )
          }
          Button(appLocalized("Save \(openProfileName) and Apply \(prompt.targetProfileName)")) {
            presentation.saveDraftThenApply(prompt)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!presentation.openDraftIsValid)
        }
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func workflowError(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Could Not Continue", systemImage: "exclamationmark.triangle")
        .font(.title2.bold())
      Text(message)
      Spacer()
      HStack {
        Button("Close") { onClose() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Try Again") {
          presentation.dismissApplyDraftError()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func permissionTitle(_ workflow: TrayPermissionWorkflow) -> String {
    switch workflow {
    case .captureDirtyDraft: appLocalized("Save changes before capturing a new profile?")
    case .captureExplanation: appLocalized("Allow Location Access?")
    case .captureDenied, .systemSettings: appLocalized("Location Access Is Off")
    }
  }

  private func permissionMessage(_ workflow: TrayPermissionWorkflow) -> String {
    switch workflow {
    case .captureDirtyDraft:
      appLocalized("The open profile has changes that have not been saved.")
    case .captureExplanation:
      appLocalized(
        "Location access lets macOS reveal the current Wi-Fi network name during capture. Desk Setup Switcher does not track location continuously, log it, or send it anywhere."
      )
    case .captureDenied, .systemSettings:
      appLocalized(
        "macOS cannot reveal the current Wi-Fi network name until Location access is enabled. You can enable it in Privacy & Security, or continue without Wi-Fi."
      )
    }
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
      settingsNavigation.selectedTab = .profiles
      if !settingsController.isPresentationVisible {
        settingsNavigation.beginPresentation()
      }
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
      settingsNavigation.selectedTab = .profiles
      if !settingsController.isPresentationVisible {
        settingsNavigation.beginPresentation()
      }
      return await settingsController.presentAndWaitUntilKey()

    case .permission:
      presentation.setWorkflowDestination(destination)
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
