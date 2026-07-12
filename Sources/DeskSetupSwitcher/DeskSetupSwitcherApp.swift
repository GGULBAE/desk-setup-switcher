import AppKit
import Combine
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

@MainActor
private final class DeskSetupSwitcherAppDelegate: NSObject, NSApplicationDelegate {
  weak var model: ApplicationModel?
  weak var profileEditor: ProfileEditorModel?
  private var terminationObservation: AnyCancellable?
  private var isSavingBeforeTermination = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if isSavingBeforeTermination || terminationObservation != nil {
      return .terminateLater
    }

    if let profileEditor, profileEditor.activity.isBusy {
      terminationObservation = profileEditor.$activity
        .filter { !$0.isBusy }
        .prefix(1)
        .sink { [weak self, weak sender] _ in
          Task { @MainActor in
            self?.terminationObservation = nil
            sender?.reply(toApplicationShouldTerminate: false)
            sender?.terminate(nil)
          }
        }
      return .terminateLater
    }

    if let profileEditor, profileEditor.isDirty {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = appLocalized("Save profile changes before quitting?")
      alert.informativeText = appLocalized(
        "This profile has unsaved changes that will be lost if you quit without saving.")
      alert.addButton(withTitle: appLocalized("Save and Quit"))
      alert.addButton(withTitle: appLocalized("Quit Without Saving"))
      alert.addButton(withTitle: appLocalized("Cancel"))

      switch alert.runModal() {
      case .alertFirstButtonReturn:
        guard let model, let candidate = profileEditor.session.saveCandidate() else {
          return .terminateCancel
        }
        isSavingBeforeTermination = true
        profileEditor.beginSaving()
        Task {
          switch await model.updateProfile(candidate) {
          case .saved(let persisted):
            switch profileEditor.completeSave(with: persisted) {
            case .saved, .savedAndSelected:
              isSavingBeforeTermination = false
              sender.reply(toApplicationShouldTerminate: true)
            case .rejected:
              isSavingBeforeTermination = false
              presentTerminationSaveError(
                appLocalized("The saved profile did not match the active draft."),
                sender: sender
              )
            }
          case .rejected(let message):
            profileEditor.finishWithError(message)
            isSavingBeforeTermination = false
            presentTerminationSaveError(message, sender: sender)
          }
        }
        return .terminateLater
      case .alertSecondButtonReturn:
        profileEditor.revertDraft()
      default:
        return .terminateCancel
      }
    }

    guard model?.shouldDeferTermination == true else { return .terminateNow }
    model?.deferTerminationUntilApplyCompletes()
    return .terminateLater
  }

  private func presentTerminationSaveError(_ message: String, sender: NSApplication) {
    let errorAlert = NSAlert()
    errorAlert.alertStyle = .critical
    errorAlert.messageText = appLocalized("Could Not Save Profile")
    errorAlert.informativeText = message
    errorAlert.runModal()
    sender.reply(toApplicationShouldTerminate: false)
  }
}

@main
@MainActor
struct DeskSetupSwitcherApp: App {
  @NSApplicationDelegateAdaptor(DeskSetupSwitcherAppDelegate.self) private var appDelegate
  @StateObject private var model: ApplicationModel
  @StateObject private var locationPermission: LocationPermissionController
  @StateObject private var profileEditor: ProfileEditorModel
  @State private var selectedSettingsTab: SettingsTab = .profiles

  init() {
    let model = ApplicationModel()
    let locationPermission = LocationPermissionController()
    let profileEditor = ProfileEditorModel()
    _model = StateObject(wrappedValue: model)
    _locationPermission = StateObject(wrappedValue: locationPermission)
    _profileEditor = StateObject(wrappedValue: profileEditor)
    appDelegate.model = model
    appDelegate.profileEditor = profileEditor
    locationPermission.onReadinessFactsChanged = { [weak model] in
      model?.refreshReadinessFacts()
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    model.start()
  }

  var body: some Scene {
    MenuBarExtra {
      MenuContentView(selectedSettingsTab: $selectedSettingsTab)
        .environmentObject(model)
        .environmentObject(locationPermission)
        .environmentObject(profileEditor)
    } label: {
      Label("Desk Setup Switcher", systemImage: "switch.2")
        .labelStyle(.iconOnly)
        .accessibilityLabel("Desk Setup Switcher")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(selectedTab: $selectedSettingsTab)
        .environmentObject(model)
        .environmentObject(locationPermission)
        .environmentObject(profileEditor)
        .frame(minWidth: 680, minHeight: 480)
    }
  }
}

private struct MenuContentView: View {
  @Environment(\.openSettings) private var openSettings
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var profileEditor: ProfileEditorModel
  @Binding var selectedSettingsTab: SettingsTab
  @State private var isCaptureDraftPromptPresented = false
  @State private var captureDraftSaveError: String?

  var body: some View {
    Group {
      if let safety = model.safetyConfirmation {
        SafetyConfirmationView(state: safety)
          .environmentObject(model)
      } else {
        menuBody
      }
    }
    .sheet(
      item: Binding(
        get: { model.pendingApply },
        set: { if $0 == nil { model.cancelPendingApply() } }
      )
    ) { request in
      ApplyPreviewView(request: request)
        .environmentObject(model)
    }
    .confirmationDialog(
      "Save changes before capturing a new profile?",
      isPresented: $isCaptureDraftPromptPresented
    ) {
      Button("Save and Capture") {
        Task { await saveDraftThenCaptureCurrentSettings() }
      }
      Button("Discard Changes and Capture", role: .destructive) {
        profileEditor.revertDraft()
        model.createProfileFromCurrentSettings()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The open profile has changes that have not been saved.")
    }
    .alert(
      "Could Not Save Profile",
      isPresented: Binding(
        get: { captureDraftSaveError != nil },
        set: { if !$0 { captureDraftSaveError = nil } }
      )
    ) {
      Button("OK") { captureDraftSaveError = nil }
    } message: {
      Text(captureDraftSaveError ?? "")
    }
    .onAppear {
      // Opening the menu is an explicit, read-only refresh point so hot-plugged
      // devices and network changes do not leave readiness permanently stale.
      model.refreshReadinessFacts()
    }
  }

  private var menuBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Desk Setup Switcher", systemImage: "switch.2")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)

      Divider()

      if model.profiles.isEmpty {
        ContentUnavailableView(
          "No Profiles",
          systemImage: "rectangle.stack.badge.plus",
          description: Text("Capture the current Mac to create your first editable profile.")
        )
        .frame(width: 340, height: 150)
      } else if enabledProfiles.isEmpty {
        VStack(spacing: 10) {
          ContentUnavailableView(
            "No Enabled Profiles",
            systemImage: "pause.rectangle",
            description: Text("Enable a profile in Settings before applying it.")
          )
          Button {
            presentSettings()
          } label: {
            Label("Manage Profiles", systemImage: "slider.horizontal.3")
          }
        }
        .frame(width: 340, height: 170)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(enabledProfiles) { profile in
              profileRow(profile)
            }
          }
          .padding(.trailing, 2)
        }
        .frame(width: 340, height: profileListHeight)
      }

      Label(model.lastMessage, systemImage: "info.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(appLocalized("Last result: \(model.lastMessage)"))

      HStack {
        Button {
          requestCaptureCurrentSettings()
        } label: {
          Label("Capture Current Settings", systemImage: "camera.metering.center.weighted")
        }
        .disabled(
          model.isProfileMutationLocked || profileEditor.session.pendingSelection != nil
        )
        .accessibilityLabel("Capture Current Settings")
        .help("Reads current settings without changing the Mac and creates a profile.")

        Spacer()

        Button {
          presentSettings()
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .keyboardShortcut(",")
        .accessibilityLabel("Settings")
        .help("Settings")
      }

      Divider()

      Button("Quit Desk Setup Switcher") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
      .disabled(model.isProfileMutationLocked)
      .accessibilityLabel("Quit Desk Setup Switcher")
      .help(
        model.isProfileMutationLocked
          ? "Quit becomes available after the current apply transaction is safely recorded."
          : "Quit Desk Setup Switcher"
      )
    }
    .padding(14)
  }

  private var enabledProfiles: [DeskProfile] {
    model.profiles.filter(\.isEnabled)
  }

  private func requestCaptureCurrentSettings() {
    guard profileEditor.session.pendingSelection == nil else { return }
    guard profileEditor.isDirty else {
      model.createProfileFromCurrentSettings()
      return
    }
    isCaptureDraftPromptPresented = true
  }

  private func editProfile(_ profile: DeskProfile) {
    switch profileEditor.requestSelection(profile) {
    case .selected(let target):
      model.selectProfile(id: target.profileID)
    case .requiresDecision, .unchanged:
      break
    }
    presentSettings()
  }

  private func presentSettings() {
    selectedSettingsTab = .profiles
    NSApplication.shared.activate(ignoringOtherApps: true)
    openSettings()
  }

  private func saveDraftThenCaptureCurrentSettings() async {
    guard profileEditor.session.pendingSelection == nil,
      let candidate = profileEditor.session.saveCandidate()
    else { return }

    profileEditor.beginSaving()
    switch await model.updateProfile(candidate) {
    case .saved(let persisted):
      guard case .saved = profileEditor.completeSave(with: persisted) else {
        captureDraftSaveError = appLocalized(
          "The saved profile did not match the active draft."
        )
        return
      }
      model.createProfileFromCurrentSettings()
    case .rejected(let message):
      profileEditor.finishWithError(message)
      captureDraftSaveError = message
    }
  }

  private var profileListHeight: CGFloat {
    min(max(CGFloat(enabledProfiles.count) * 132, 124), 360)
  }

  private func profileRow(_ profile: DeskProfile) -> some View {
    let readiness = model.readiness(for: profile)
    let actions = profileActionState(profile, readiness: readiness)

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(profile.name, systemImage: appResolvedProfileSymbolName(profile.symbolName))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Label(readinessTitle(readiness), systemImage: readinessSymbol(readiness))
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            appLocalized("Profile status: \(readinessTitle(readiness))"))
      }

      if let reason = actions.apply.disabledReason {
        Label(appLocalizedRuntime(reason.defaultMessage), systemImage: reason.symbolName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Button("Apply") {
          model.prepareApply(profile: profile, mode: .normal)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!actions.apply.isEnabled)
        .help(
          actions.apply.disabledReason.map { appLocalizedRuntime($0.defaultMessage) }
            ?? appLocalized("Preview and apply this complete profile."))

        Spacer()

        Button {
          editProfile(profile)
        } label: {
          Label("Edit Profile", systemImage: "pencil")
        }
        .disabled(model.isProfileMutationLocked || profileEditor.activity.isBusy)
        .accessibilityLabel(appLocalized("Edit \(profile.name)"))
        .help("Edit Profile")

        Menu {
          Button("Apply Available Settings…") {
            model.prepareApply(profile: profile, mode: .force)
          }
          .disabled(!actions.forceApply.isEnabled)

          if let reason = actions.forceApply.disabledReason {
            Text(appLocalizedRuntime(reason.defaultMessage))
          }
        } label: {
          Label("More Profile Actions", systemImage: "ellipsis.circle")
            .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("More Profile Actions")
        .help("Previews omissions, then applies only the currently available settings.")
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .contain)
  }

  private func profileActionState(
    _ profile: DeskProfile,
    readiness: ProfileReadiness
  ) -> MenuProfileActionState {
    MenuProfileActionState(
      profile: profile,
      readiness: readiness,
      normalApplyAvailable: model.canApplyNormally(profile),
      forceApplyAvailable: model.canForceApply(profile),
      isRefreshing: model.isReadinessRefreshInProgress,
      isTransactionLocked: model.isProfileMutationLocked,
      rejectionReasons: model.normalApplyRejectionReasonsByProfile[profile.id] ?? [],
      forceRejectionReasons: model.forceApplyRejectionReasonsByProfile[profile.id]
    )
  }

  private func readinessTitle(_ readiness: ProfileReadiness) -> String {
    appReadinessTitle(readiness)
  }

  private func readinessSymbol(_ readiness: ProfileReadiness) -> String {
    switch readiness {
    case .ready: "checkmark.circle"
    case .partial: "exclamationmark.circle"
    case .unavailable: "xmark.circle"
    case .applying: "hourglass"
    case .applied: "checkmark.seal"
    case .failed: "exclamationmark.triangle"
    }
  }
}

private struct ApplyPreviewView: View {
  @EnvironmentObject private var model: ApplicationModel
  let request: PendingApplyRequest

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(
          request.isReviewOnly
            ? appLocalized("Availability Review")
            : request.preparation.mode == .force
              ? appLocalized("Force Apply Preview") : appLocalized("Apply Preview"),
          systemImage: request.isReviewOnly
            ? "eye"
            : request.preparation.mode == .force
              ? "exclamationmark.shield" : "list.bullet.clipboard"
        )
        .font(.title2.bold())
        Spacer()
        Text(request.profile.name)
          .foregroundStyle(.secondary)
      }

      if request.isReviewOnly {
        Label(
          "Read-only review. No settings can be changed from this preview.",
          systemImage: "eye"
        )
        .padding(10)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      }

      if request.preparation.mode == .force {
        Label(
          "Only available operations will run. Review every skipped item before continuing.",
          systemImage: "exclamationmark.triangle"
        )
        .padding(10)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
      }

      if request.preparation.operations.contains(where: { $0.risk == .high }) {
        Label(
          "Display changes remain temporary and will be restored if the app exits or you do not confirm within 15 seconds.",
          systemImage: "display.trianglebadge.exclamationmark"
        )
        .padding(10)
        .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          previewSection(appLocalized("Conditions"), systemImage: "checklist") {
            if request.conditions.items.isEmpty {
              Text("No readiness conditions.")
            } else {
              ForEach(request.conditions.items) { item in
                Label(
                  appLocalizedRuntime(item.explanation),
                  systemImage: item.isMatched ? "checkmark.circle" : "xmark.circle"
                )
              }
            }
          }

          previewSection(
            appLocalized("Planned changes"),
            systemImage: "arrow.triangle.2.circlepath"
          ) {
            if request.preparation.operations.isEmpty {
              Text("No setting needs to change.")
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

      Divider()
      HStack {
        Button(request.isReviewOnly ? appLocalized("Close") : appLocalized("Cancel")) {
          model.cancelPendingApply()
        }
        .keyboardShortcut(.cancelAction)
        if !request.isReviewOnly {
          Spacer()
          Button(
            request.preparation.mode == .force
              ? appLocalized("Apply Available Settings") : appLocalized("Apply Profile")
          ) {
            model.executePendingApply()
          }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(!request.preparation.canExecute || model.isProfileMutationLocked)
        }
      }
    }
    .padding(20)
    .frame(
      minWidth: 560,
      idealWidth: 620,
      minHeight: 320,
      idealHeight: 420,
      maxHeight: 620
    )
  }

  @ViewBuilder
  private func operationPreview(
    _ preview: FriendlyOperationPreview,
    operation: PlannedOperation
  ) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
      GridRow {
        Text("Current")
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
        Text("After apply")
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
    case .profileDisabled: appLocalized("The profile is disabled.")
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
        "Confirm or revert the previous display change before starting another high-risk change.")
    }
  }
}

private struct SafetyConfirmationView: View {
  @EnvironmentObject private var model: ApplicationModel
  let state: SafetyConfirmationState

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "display.trianglebadge.exclamationmark")
        .font(.system(size: 42))
        .accessibilityHidden(true)
      Text("Keep these display settings?")
        .font(.headline)
      Text(
        appLocalized(
          "The previous display configuration will return in \(state.secondsRemaining) seconds.")
      )
      .multilineTextAlignment(.center)
      .accessibilityLabel(
        appLocalized("Automatic rollback in \(state.secondsRemaining) seconds"))

      ProgressView(value: Double(state.secondsRemaining), total: 15)
        .accessibilityLabel("Display confirmation time remaining")
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
    .frame(width: 340)
  }
}

private enum SettingsTab: Hashable {
  case profiles
  case permissions
  case diagnostics
  case about
}

private struct SettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @Binding var selectedTab: SettingsTab

  var body: some View {
    TabView(selection: $selectedTab) {
      ProfilesSettingsView()
        .tabItem { Label("Profiles", systemImage: "rectangle.stack") }
        .tag(SettingsTab.profiles)

      PermissionsSettingsView()
        .environmentObject(model)
        .tabItem { Label("Permissions", systemImage: "lock.shield") }
        .tag(SettingsTab.permissions)

      DiagnosticsSettingsView()
        .environmentObject(model)
        .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        .tag(SettingsTab.diagnostics)

      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
        .tag(SettingsTab.about)
    }
    .padding(20)
  }
}

private struct PermissionsSettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var locationPermission: LocationPermissionController

  var body: some View {
    Form {
      Section("Login") {
        Toggle(
          "Launch Desk Setup Switcher at login",
          isOn: Binding(
            get: { model.launchAtLoginDesired },
            set: { model.setLaunchAtLogin($0) }
          )
        )

        LabeledContent(
          "App setting",
          value: model.launchAtLoginDesired ? appLocalized("On") : appLocalized("Off")
        )
        LabeledContent(
          "macOS registration",
          value: model.loginItemEnabled ? appLocalized("Enabled") : appLocalized("Not enabled")
        )

        if loginItemStatesDiffer || model.canRetryLoginItemRegistration {
          Label(model.loginItemStatus, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(appLocalized("Login item status: \(model.loginItemStatus)"))
        } else {
          Label(
            "The app setting matches the macOS registration state.", systemImage: "checkmark.circle"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        HStack {
          if model.canRetryLoginItemRegistration {
            Button("Retry Registration") {
              model.retryLaunchAtLoginRegistration()
            }
          }
          Button("Refresh Status") {
            model.refreshLoginItemStatusFromSystem()
          }
        }

        DisclosureGroup("Why can these states differ?") {
          Text(
            "macOS accepts login-item registration only for an eligible installed and code-signed app. The app setting does not guarantee registration."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Section("System permissions") {
        Text(
          "macOS can require Location Services to reveal a Wi-Fi network name and evaluate a location readiness condition. Desk Setup Switcher does not track location continuously."
        )
        LabeledContent("Location", value: locationPermission.statusText)
        Button(
          locationPermission.isAuthorized
            ? appLocalized("Refresh Current Location") : appLocalized("Request Location Access")
        ) {
          locationPermission.requestAccess()
        }
        .accessibilityHint("Shows the macOS permission prompt only after this explanation")
      }
    }
    .formStyle(.grouped)
  }

  private var loginItemStatesDiffer: Bool {
    model.launchAtLoginDesired != model.loginItemEnabled
  }
}

private struct DiagnosticsSettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @State private var confirmClear = false

  var body: some View {
    Form {
      LabeledContent("Last result", value: model.lastMessage)
      LabeledContent("Last snapshot", value: model.snapshotStatus)
      LabeledContent("Storage", value: appLocalized("Local Application Support only"))
      LabeledContent("Telemetry", value: appLocalized("None"))
      LabeledContent("Live mutations", value: appLocalized("User-confirmed only"))
      Section("Readiness facts") {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(model.conditionContextStatus)
              .font(.caption)
              .foregroundStyle(.secondary)
            if let refreshedAt = model.readinessLastRefreshedAt {
              Text(appLocalized("Last refreshed \(refreshedAt.formatted())"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          Spacer()
          Button("Refresh Readiness") { model.refreshReadinessFacts() }
            .disabled(model.isApplyTransactionInProgress)
            .accessibilityHint("Reads current system facts without changing any setting")
        }

        LabeledContent(
          "Connected displays",
          value: appLocalized("\(model.lastConditionContext.displays.count) detected")
        )
        LabeledContent(
          "Wi-Fi SSID",
          value: model.lastConditionContext.wifiSSID ?? appLocalized("Unavailable")
        )
        LabeledContent(
          "Ethernet",
          value: model.lastConditionContext.ethernetConnected
            ? appLocalized("Connected") : appLocalized("Not connected")
        )
        LabeledContent(
          "Cached location",
          value: model.lastConditionContext.location == nil
            ? appLocalized("Unavailable") : appLocalized("Available; coordinates hidden")
        )

        factList(
          appLocalized("Audio input UIDs"),
          values: model.lastConditionContext.audioInputUIDs.sorted()
        )
        factList(
          appLocalized("Audio output UIDs"),
          values: model.lastConditionContext.audioOutputUIDs.sorted()
        )
        factList(
          appLocalized("USB hardware identifiers"),
          values: model.lastConditionContext.hardwareIdentifiers.sorted()
        )
        factList(
          appLocalized("Local IP addresses"),
          values: model.lastConditionContext.ipAddresses.sorted()
        )
      }
      if let snapshot = model.lastSnapshot {
        Section("Snapshot details") {
          LabeledContent("Captured", value: snapshot.capturedAt.formatted())
          ForEach(snapshot.groups, id: \.group) { group in
            DisclosureGroup(appSettingGroupTitle(group.group)) {
              Text(appLocalizedRuntime(group.capability.reason))
                .font(.caption)
                .foregroundStyle(.secondary)
              ForEach(group.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                  Label(appSnapshotItemLabel(item), systemImage: snapshotSymbol(item.state))
                  Text(snapshotStateTitle(item.state))
                    .font(.caption.bold())
                  if !item.detail.isEmpty {
                    Text(appLocalizedRuntime(item.detail))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
                .accessibilityElement(children: .combine)
              }
              ForEach(group.failures, id: \.stage) { failure in
                Label(
                  appLocalizedRuntime(failure.message),
                  systemImage: "exclamationmark.triangle"
                )
              }
            }
          }
        }
      }
      if let result = model.lastApplyResult {
        Section("Last apply details") {
          LabeledContent(
            "Status",
            value: appApplicationStatusTitle(
              result.status,
              isAwaitingDisplayConfirmation: result.safetyConfirmationID != nil
            )
          )
          LabeledContent(
            "Executed",
            value: result.didExecute ? appLocalized("Yes") : appLocalized("No")
          )
          ForEach(
            Array((result.itemResults + result.rollbackResults).enumerated()),
            id: \.offset
          ) { _, item in
            applicationItemRow(item)
          }
        }
      }

      Section("Redacted local events") {
        Text(model.diagnosticStatus)
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          Button("Refresh") { model.refreshDiagnostics() }
          Button("Clear Events…", role: .destructive) { confirmClear = true }
            .disabled(model.diagnosticEntries.isEmpty)
        }

        if !model.diagnosticEntries.isEmpty {
          ForEach(model.diagnosticEntries) { entry in
            VStack(alignment: .leading, spacing: 3) {
              Label(
                appLocalized(
                  "\(diagnosticSeverityTitle(entry.severity)): \(entry.component): \(entry.code)"),
                systemImage: diagnosticSymbol(entry.severity)
              )
              .font(.caption.bold())
              Text(entry.message)
                .font(.caption)
              Text(entry.timestamp.formatted())
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
    .formStyle(.grouped)
    .confirmationDialog("Remove all local diagnostic events?", isPresented: $confirmClear) {
      Button("Remove Events", role: .destructive) { model.clearDiagnostics() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes only Desk Setup Switcher’s rotated, redacted diagnostic files.")
    }
  }

  private func diagnosticSymbol(_ severity: DiagnosticSeverity) -> String {
    switch severity {
    case .debug: "ladybug"
    case .info: "info.circle"
    case .warning: "exclamationmark.triangle"
    case .error: "xmark.octagon"
    }
  }

  private func diagnosticSeverityTitle(_ severity: DiagnosticSeverity) -> String {
    switch severity {
    case .debug: appLocalized("Debug")
    case .info: appLocalized("Information")
    case .warning: appLocalized("Warning")
    case .error: appLocalized("Error")
    }
  }

  private func applicationItemRow(_ item: ApplicationItemSummary) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline) {
        Text(appSettingGroupTitle(item.group))
          .font(.caption.bold())
        Text(appApplicationItemTitle(item.key))
        Spacer()
        Text(appApplicationItemStatusTitle(item.status))
          .font(.caption.bold())
      }
      Text(appLocalizedRuntime(item.message))
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func factList(_ title: String, values: [String]) -> some View {
    DisclosureGroup(appLocalized("\(title) (\(values.count))")) {
      if values.isEmpty {
        Text("None detected")
          .foregroundStyle(.secondary)
      } else {
        ForEach(values, id: \.self) { value in
          Text(value)
            .font(.caption.monospaced())
            .textSelection(.enabled)
        }
      }
    }
  }

  private func snapshotSymbol(_ state: SnapshotItemState) -> String {
    switch state {
    case .detected: "sensor"
    case .storable: "checkmark.circle"
    case .unreadable: "eye.slash"
    case .permissionRequired: "lock.trianglebadge.exclamationmark"
    case .unsupported: "nosign"
    }
  }

  private func snapshotStateTitle(_ state: SnapshotItemState) -> String {
    switch state {
    case .detected: appLocalized("Detected")
    case .storable: appLocalized("Storable")
    case .unreadable: appLocalized("Unreadable")
    case .permissionRequired: appLocalized("Permission required")
    case .unsupported: appLocalized("Unsupported")
    }
  }
}

private struct AboutSettingsView: View {
  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "switch.2")
        .font(.system(size: 56))
        .accessibilityHidden(true)
      Text("Desk Setup Switcher")
        .font(.title2.bold())
      Text(appLocalized("Version \(appVersion)"))
        .foregroundStyle(.secondary)
      Text("Free and open source under the MIT License")
        .font(.caption)

      Divider()
        .frame(maxWidth: 360)

      HStack(spacing: 16) {
        Link(destination: repositoryURL) {
          Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
        }
        Link(destination: issuesURL) {
          Label("Report an Issue", systemImage: "exclamationmark.bubble")
        }
      }

      HStack(spacing: 16) {
        Link(destination: licenseURL) {
          Label("MIT License", systemImage: "doc.text")
        }
        Link(destination: privacyURL) {
          Label("Privacy Principles", systemImage: "hand.raised")
        }
      }

      Text("Links open only when you choose them and use your default browser.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
  }

  private let repositoryURL = URL(string: "https://github.com/GGULBAE/desk-setup-switcher")!
  private let issuesURL = URL(string: "https://github.com/GGULBAE/desk-setup-switcher/issues")!
  private let licenseURL = URL(
    string: "https://github.com/GGULBAE/desk-setup-switcher/blob/master/LICENSE")!
  private let privacyURL = URL(
    string: "https://github.com/GGULBAE/desk-setup-switcher/blob/master/docs/PRIVACY.md")!
}
