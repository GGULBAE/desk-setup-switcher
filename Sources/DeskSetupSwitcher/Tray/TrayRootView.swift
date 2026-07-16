import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

enum TrayAccessibilityCopy {
  static let captureLabel = "Capture Current Settings"
  static let captureHelp = "Reads current settings without changing the Mac and creates a profile."
  static let settingsLabel = "Settings"
  static let settingsHelp = "Opens persistent Desk Setup Switcher settings."
  static let quitLabel = "Quit Desk Setup Switcher"
  static let quitHelp = "Quit Desk Setup Switcher"
}

enum TraySurfaceStylePolicy {
  /// NSPopover owns the only full-surface material/chrome layer.
  static let swiftUIFullSurfaceBackgroundLayerCount = 0
}

struct TrayRootView: View {
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var profileEditor: ProfileEditorModel
  @ObservedObject var presentation: TrayPresentationModel
  let router: TrayActionRouter

  @FocusState private var focusedControl: TrayFocusTarget?

  var body: some View {
    VStack(alignment: .leading, spacing: TrayGeometry.sectionGap) {
      header
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: TrayGeometry.sectionGap) {
            profileContent
              .id(TrayScrollAnchor.top)
            captureStatus
            captureSummary
            applySummary
            handoffError
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, 2)
        }
        .scrollIndicators(.automatic)
        .onChange(of: presentation.scrollResetRequest) { _, request in
          guard request?.anchor == .top else { return }
          proxy.scrollTo(TrayScrollAnchor.top, anchor: .top)
        }
        .onChange(of: presentation.focusTarget) { _, target in
          focusedControl = target
          if let target {
            withAnimation(.easeInOut(duration: 0.16)) {
              proxy.scrollTo(target.scrollProfileID, anchor: .center)
            }
          }
        }
      }
    }
    .padding(TrayGeometry.outerPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onExitCommand {
      presentation.requestEscape()
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Label(appLocalized("Desk Setup Switcher"), systemImage: "switch.2")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)

      Spacer(minLength: 8)

      Button {
        route(presentation.captureAction)
      } label: {
        Label(appLocalized("Capture"), systemImage: "camera.metering.center.weighted")
      }
      .controlSize(.regular)
      .disabled(
        model.isProfileMutationLocked || profileEditor.session.pendingSelection != nil
          || presentation.hasCaptureTask
      )
      .focused($focusedControl, equals: .capture)
      .accessibilityLabel(appLocalizedRuntime(TrayAccessibilityCopy.captureLabel))
      .help(appLocalizedRuntime(TrayAccessibilityCopy.captureHelp))

      iconButton(
        action: .openSettings,
        title: TrayAccessibilityCopy.settingsLabel,
        help: TrayAccessibilityCopy.settingsHelp,
        systemImage: "gearshape"
      )
      .keyboardShortcut(",")

      iconButton(
        action: .quit,
        title: TrayAccessibilityCopy.quitLabel,
        help: model.isProfileMutationLocked
          ? "Quit becomes available after the current apply transaction is safely recorded."
          : TrayAccessibilityCopy.quitHelp,
        systemImage: "xmark",
        isDisabled: model.isProfileMutationLocked
      )
      .keyboardShortcut("q")
    }
    .frame(minHeight: TrayGeometry.headerHeight)
  }

  @ViewBuilder
  private var profileContent: some View {
    if model.profiles.isEmpty {
      ContentUnavailableView(
        appLocalized("No Profiles"),
        systemImage: "rectangle.stack.badge.plus",
        description: Text(
          appLocalized("Capture the current Mac to create your first editable profile."))
      )
      .frame(maxWidth: .infinity, minHeight: 170)
      .id(TrayFocusTarget.emptyState)
    } else if enabledProfiles.isEmpty {
      VStack(spacing: 10) {
        ContentUnavailableView(
          appLocalized("No Enabled Profiles"),
          systemImage: "pause.rectangle",
          description: Text(appLocalized("Enable a profile in Settings before applying it."))
        )
        Button {
          route(.openSettings)
        } label: {
          Label(appLocalized("Manage Profiles"), systemImage: "slider.horizontal.3")
        }
      }
      .frame(maxWidth: .infinity, minHeight: 190)
    } else {
      TrayProfileListView(
        profiles: enabledProfiles,
        presentation: presentation,
        router: router,
        focusedControl: $focusedControl
      )
    }
  }

  @ViewBuilder
  private var captureStatus: some View {
    switch presentation.capturePhase {
    case .idle:
      EmptyView()
    case .running:
      statusBanner(
        appLocalized("Reading current settings without changing them…"),
        systemImage: "camera.metering.center.weighted",
        tint: .blue,
        includesProgress: true
      )
    case .success(let message):
      statusBanner(message, systemImage: "checkmark.circle", tint: .green)
    case .partial(let message):
      statusBanner(message, systemImage: "exclamationmark.circle", tint: .orange)
    case .failure(let message):
      statusBanner(message, systemImage: "xmark.octagon", tint: .red)
    }
  }

  @ViewBuilder
  private var captureSummary: some View {
    if let summary = model.lastCaptureSummary, summary.status != .complete {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline) {
          Label(
            summary.permissionRequiredCount > 0
              ? appLocalized("Location Access Needed") : appLocalized("Capture Failed"),
            systemImage: summary.permissionRequiredCount > 0
              ? "location.slash" : "xmark.octagon"
          )
          .font(.caption.bold())
          Spacer()
          Button {
            route(.dismissCaptureBanner)
          } label: {
            Label(appLocalized("Dismiss Capture Result"), systemImage: "xmark")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.plain)
          .frame(minWidth: 28, minHeight: 28)
          .accessibilityLabel(appLocalized("Dismiss Capture Result"))
          .help(appLocalized("Dismiss Capture Result"))
        }
        Text(appLocalized("\(summary.applicableCount) applicable settings saved."))
          .font(.caption)
          .foregroundStyle(.secondary)
        if summary.permissionRequiredCount > 0 {
          Button(appLocalized("Review Permission")) {
            route(.openPermissionWorkflow(.systemSettings))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(TrayGeometry.cardPadding)
      .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
      .accessibilityElement(children: .contain)
    }
  }

  @ViewBuilder
  private var applySummary: some View {
    if let summary = model.lastApplySummary {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline) {
          Label(
            appApplyResultStatusTitle(summary.status),
            systemImage: applyResultStatusSymbol(summary.status)
          )
          .font(.caption.bold())
          Spacer()
          Button {
            route(.dismissApplyBanner)
          } label: {
            Label(appLocalized("Dismiss Apply Result"), systemImage: "xmark")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.plain)
          .frame(minWidth: 28, minHeight: 28)
          .accessibilityLabel(appLocalized("Dismiss Apply Result"))
          .help(appLocalized("Dismiss Apply Result"))
        }
        Text(summary.profileName)
          .font(.caption)
          .lineLimit(2)
        Text(
          appLocalized(
            "\(summary.succeededCount) succeeded · \(summary.failedCount) failed · \(summary.skippedCount) skipped · \(summary.unsupportedCount) unsupported"
          )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        HStack {
          Text(summary.appliedAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.secondary)
          Spacer()
          Button(appLocalized("Details")) {
            route(.openResultDetails)
          }
          .font(.caption)
          .accessibilityHint("Shows itemized apply and read-back results")
        }
      }
      .padding(TrayGeometry.cardPadding)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
      .accessibilityElement(children: .contain)
    }
  }

  @ViewBuilder
  private var handoffError: some View {
    if let message = presentation.handoffError {
      VStack(alignment: .leading, spacing: 7) {
        Label(appLocalized("Could Not Open Destination"), systemImage: "exclamationmark.triangle")
          .font(.caption.bold())
        Text(message)
          .font(.caption)
        Button(appLocalized("Dismiss")) {
          presentation.dismissHandoffError()
        }
        .controlSize(.small)
      }
      .padding(TrayGeometry.cardPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
      .accessibilityElement(children: .contain)
    }
  }

  private var enabledProfiles: [DeskProfile] {
    model.profiles.filter(\.isEnabled)
  }

  private func route(_ action: TrayAction) {
    guard let generation = presentation.activeSessionGeneration else { return }
    Task { await router.route(action, sessionGeneration: generation) }
  }

  private func iconButton(
    action: TrayAction,
    title: String,
    help: String,
    systemImage: String,
    isDisabled: Bool = false
  ) -> some View {
    Button {
      route(action)
    } label: {
      Label(appLocalizedRuntime(title), systemImage: systemImage)
        .labelStyle(.iconOnly)
        .frame(width: 20, height: 20)
    }
    .buttonStyle(.bordered)
    .controlSize(.regular)
    .frame(minWidth: 32, minHeight: 32)
    .disabled(isDisabled)
    .accessibilityLabel(appLocalizedRuntime(title))
    .help(appLocalizedRuntime(help))
  }

  private func statusBanner(
    _ message: String,
    systemImage: String,
    tint: Color,
    includesProgress: Bool = false
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if includesProgress {
        ProgressView()
          .controlSize(.small)
          .accessibilityHidden(true)
      } else {
        Image(systemName: systemImage)
          .accessibilityHidden(true)
      }
      Text(message)
        .font(.caption)
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .combine)
  }

  private func applyResultStatusSymbol(_ status: ApplyResultOverallStatus) -> String {
    switch status {
    case .success: "checkmark.circle"
    case .partial: "exclamationmark.circle"
    case .failure: "xmark.octagon"
    case .rolledBack: "arrow.uturn.backward.circle"
    case .rollbackFailed: "exclamationmark.arrow.triangle.2.circlepath"
    case .notVerified: "questionmark.circle"
    }
  }
}

extension TrayFocusTarget {
  fileprivate var scrollProfileID: UUID? {
    switch self {
    case .delete(let profileID), .cancelDelete(let profileID), .profile(let profileID):
      profileID
    case .capture, .emptyState:
      nil
    }
  }
}
