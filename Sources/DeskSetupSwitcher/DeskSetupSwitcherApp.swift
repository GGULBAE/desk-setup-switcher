import AppKit
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

@MainActor
private final class DeskSetupSwitcherAppDelegate: NSObject, NSApplicationDelegate {
  weak var model: ApplicationModel?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard model?.shouldDeferTermination == true else { return .terminateNow }
    model?.deferTerminationUntilApplyCompletes()
    return .terminateLater
  }
}

@main
@MainActor
struct DeskSetupSwitcherApp: App {
  @NSApplicationDelegateAdaptor(DeskSetupSwitcherAppDelegate.self) private var appDelegate
  @StateObject private var model: ApplicationModel
  @StateObject private var locationPermission: LocationPermissionController

  init() {
    let model = ApplicationModel()
    let locationPermission = LocationPermissionController()
    _model = StateObject(wrappedValue: model)
    _locationPermission = StateObject(wrappedValue: locationPermission)
    appDelegate.model = model
    locationPermission.onReadinessFactsChanged = { [weak model] in
      model?.refreshReadinessFacts()
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    model.start()
  }

  var body: some Scene {
    MenuBarExtra {
      MenuContentView()
        .environmentObject(model)
        .environmentObject(locationPermission)
    } label: {
      Label("Desk Setup Switcher", systemImage: "switch.2")
        .labelStyle(.iconOnly)
        .accessibilityLabel("Desk Setup Switcher")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environmentObject(model)
        .environmentObject(locationPermission)
        .frame(minWidth: 680, minHeight: 480)
    }
  }
}

private struct MenuContentView: View {
  @EnvironmentObject private var model: ApplicationModel

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
        .frame(width: 320, height: 150)
      } else {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(model.profiles.filter(\.isEnabled)) { profile in
            let readiness = model.readiness(for: profile)
            HStack {
              Label(profile.name, systemImage: profile.symbolName)
              Spacer()
              Label(readinessTitle(readiness), systemImage: readinessSymbol(readiness))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                  appLocalized("Profile status: \(readinessTitle(readiness))"))
            }

            HStack {
              Button("Review Availability…") {
                model.reviewAvailability(profile: profile)
              }
              .disabled(model.isProfileMutationLocked)
              .help("Shows a current read-only plan and every availability explanation.")

              Spacer()

              Button("Apply") {
                model.prepareApply(profile: profile, mode: .normal)
              }
              .disabled(!model.canApplyNormally(profile))
              .help("Normal apply requires every included setting and condition to be ready.")

              Button("Force Apply…") {
                model.prepareApply(profile: profile, mode: .force)
              }
              .disabled(!model.canForceApply(profile))
              .help("Previews omissions, then applies only the currently available settings.")
            }
          }
        }
        .frame(width: 320)
      }

      Label(model.lastMessage, systemImage: "info.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(appLocalized("Last result: \(model.lastMessage)"))

      HStack {
        Button {
          model.refreshReadinessFacts()
        } label: {
          Label("Refresh Readiness", systemImage: "arrow.clockwise")
        }
        .disabled(model.isProfileMutationLocked)
        .accessibilityLabel("Refresh Readiness")
        .help("Reads current system facts without changing any setting.")

        Spacer()

        if let refreshedAt = model.readinessLastRefreshedAt {
          Text(appLocalized("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      HStack {
        Button {
          model.createProfileFromCurrentSettings()
        } label: {
          Label("Capture Current Settings", systemImage: "camera.metering.center.weighted")
        }
        .disabled(model.isProfileMutationLocked)
        .accessibilityLabel("Capture Current Settings")
        .help("Reads current settings without changing the Mac and creates a profile.")

        Spacer()

        SettingsLink {
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
                  if let preview = operation.preview {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                      GridRow {
                        Text("Current")
                          .font(.caption.bold())
                        Text(
                          appOperationPreviewValue(
                            preview.previousValue,
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
                            preview.desiredValue,
                            operation: operation,
                            isPreviousValue: false
                          )
                        )
                      }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
          .disabled(!request.preparation.canExecute || model.isProfileMutationLocked)
        }
      }
    }
    .padding(20)
    .frame(minWidth: 560, idealWidth: 620, minHeight: 500, idealHeight: 580)
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

      HStack {
        Button("Revert Now") { model.revertHighRiskChanges() }
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

private struct SettingsView: View {
  @EnvironmentObject private var model: ApplicationModel

  var body: some View {
    TabView {
      ProfilesSettingsView()
        .tabItem { Label("Profiles", systemImage: "rectangle.stack") }

      PermissionsSettingsView()
        .environmentObject(model)
        .tabItem { Label("Permissions", systemImage: "lock.shield") }

      DiagnosticsSettingsView()
        .environmentObject(model)
        .tabItem { Label("Diagnostics", systemImage: "stethoscope") }

      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
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
          "Requested",
          value: model.launchAtLoginDesired ? appLocalized("On") : appLocalized("Off")
        )
        LabeledContent(
          "Effective macOS state",
          value: model.loginItemEnabled ? appLocalized("Enabled") : appLocalized("Not enabled")
        )
        Text(model.loginItemStatus)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel(appLocalized("Login item status: \(model.loginItemStatus)"))

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

        Text(
          "macOS accepts login-item registration only for an eligible installed and code-signed app. The requested preference does not guarantee registration."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
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
                appLocalized("\(entry.component): \(entry.code)"),
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
    VStack(spacing: 12) {
      Image(systemName: "switch.2")
        .font(.system(size: 56))
        .accessibilityHidden(true)
      Text("Desk Setup Switcher")
        .font(.title2.bold())
      Text(appLocalized("Version \(appVersion)"))
        .foregroundStyle(.secondary)
      Text("Free and open source under the MIT License")
        .font(.caption)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
  }
}
