import AppKit
import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// Keeps app-owned destinations in the ordinary macOS window cycle while any
/// one is visible, then restores menu-bar-only behavior after the last window
/// is explicitly hidden.
@MainActor
final class ApplicationWindowActivationCoordinator {
  typealias PolicySetter = @MainActor (NSApplication.ActivationPolicy) -> Void

  private var presentedWindowIDs: Set<ObjectIdentifier> = []
  private let setActivationPolicy: PolicySetter

  init(
    setActivationPolicy: @escaping PolicySetter = { policy in
      _ = NSApplication.shared.setActivationPolicy(policy)
    }
  ) {
    self.setActivationPolicy = setActivationPolicy
  }

  var presentedWindowCount: Int { presentedWindowIDs.count }

  func windowWillPresent(_ window: NSWindow) {
    let wasEmpty = presentedWindowIDs.isEmpty
    presentedWindowIDs.insert(ObjectIdentifier(window))
    if wasEmpty {
      setActivationPolicy(.regular)
    }
  }

  func windowDidHide(_ window: NSWindow) {
    guard presentedWindowIDs.remove(ObjectIdentifier(window)) != nil else { return }
    if presentedWindowIDs.isEmpty {
      setActivationPolicy(.accessory)
    }
  }
}

@MainActor
protocol RuntimeSettingsWindowPresenting: AnyObject {
  var isPresentationVisible: Bool { get }
  func presentAndWaitUntilKey() async -> TrayDestinationPresentation
}

/// One window presentation producer with independently cancellable consumers.
/// Repeated commands can share the same AppKit presentation without allowing
/// cancellation of one command to tear down the destination for the others.
@MainActor
final class WindowPresentationRequest {
  let window: NSWindow
  let waiter: WindowPresentationAwaiter
  var producer: Task<Void, Never>?

  private var result: TrayDestinationPresentation?
  private var consumers: [UUID: CheckedContinuation<TrayDestinationPresentation, Never>] = [:]

  init(window: NSWindow, waiter: WindowPresentationAwaiter) {
    self.window = window
    self.waiter = waiter
  }

  var consumerCount: Int { consumers.count }

  func value(
    onLastConsumerCancelled: @escaping @MainActor () -> Void
  ) async -> TrayDestinationPresentation {
    let consumerID = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if let result {
          continuation.resume(returning: result)
        } else if Task.isCancelled {
          continuation.resume(returning: .cancelled)
          if consumers.isEmpty {
            onLastConsumerCancelled()
          }
        } else {
          consumers[consumerID] = continuation
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.cancelConsumer(
          id: consumerID,
          onLastConsumerCancelled: onLastConsumerCancelled
        )
      }
    }
  }

  func resolve(_ result: TrayDestinationPresentation) {
    guard self.result == nil else { return }
    self.result = result
    let continuations = Array(consumers.values)
    consumers.removeAll()
    producer = nil
    for continuation in continuations {
      continuation.resume(returning: result)
    }
  }

  func cancelProducer() {
    waiter.cancel()
    producer?.cancel()
  }

  private func cancelConsumer(
    id: UUID,
    onLastConsumerCancelled: @MainActor () -> Void
  ) {
    guard let continuation = consumers.removeValue(forKey: id) else { return }
    continuation.resume(returning: .cancelled)
    if consumers.isEmpty, result == nil {
      onLastConsumerCancelled()
    }
  }
}

@MainActor
func presentApplicationSettings(
  navigation: SettingsNavigationModel,
  presenter: any RuntimeSettingsWindowPresenting
) async -> TrayDestinationPresentation {
  navigation.selectedTab = .profiles
  if !presenter.isPresentationVisible {
    navigation.beginPresentation()
  }
  return await presenter.presentAndWaitUntilKey()
}

@MainActor
final class RuntimeSettingsWindowController: NSWindowController,
  RuntimeSettingsWindowPresenting, NSWindowDelegate
{
  typealias AwaiterFactory = @MainActor (NSWindow) -> WindowPresentationAwaiter

  private var presentationRequest: WindowPresentationRequest?
  private let activationCoordinator: ApplicationWindowActivationCoordinator?
  private let makePresentationAwaiter: AwaiterFactory
  private let presentationAction: (@MainActor (NSWindow) -> Void)?

  // Treat the short key-window handoff as visible for generation ownership so
  // repeated Cmd+, requests cannot recreate the editor subtree mid-present.
  var isPresentationVisible: Bool {
    window?.isVisible == true || presentationRequest != nil
  }

  #if DEBUG
    var inFlightPresentationConsumerCount: Int {
      presentationRequest?.consumerCount ?? 0
    }
  #endif

  init<Content: View>(
    rootView: Content,
    activationCoordinator: ApplicationWindowActivationCoordinator? = nil,
    makePresentationAwaiter: @escaping AwaiterFactory = {
      WindowPresentationAwaiter(window: $0)
    },
    presentationAction: (@MainActor (NSWindow) -> Void)? = nil
  ) {
    self.activationCoordinator = activationCoordinator
    self.makePresentationAwaiter = makePresentationAwaiter
    self.presentationAction = presentationAction
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 568),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hostingController
    window.title = appLocalized("Settings")
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.collectionBehavior = [.managed, .participatesInCycle]
    window.contentMinSize = CGSize(width: 680, height: 480)
    window.setContentSize(CGSize(width: 900, height: 568))
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  func showSettings() {
    prepareForPresentation()
    guard let window else { return }
    activationCoordinator?.windowWillPresent(window)
    if let presentationAction {
      presentationAction(window)
      return
    }
    NSApplication.shared.activate(ignoringOtherApps: true)
    showWindow(nil)
    window.makeKeyAndOrderFront(nil)
  }

  func presentAndWaitUntilKey() async -> TrayDestinationPresentation {
    guard !Task.isCancelled else { return .cancelled }
    if let request = presentationRequest {
      return await awaitPresentation(request)
    }
    guard let window else {
      return TrayDestinationPresentation.failed(
        appLocalized("The Settings window is unavailable."))
    }
    let waiter = makePresentationAwaiter(window)
    let request = WindowPresentationRequest(window: window, waiter: waiter)
    presentationRequest = request
    request.producer = Task { @MainActor [weak self] in
      guard let self else {
        request.resolve(
          .failed(appLocalized("The Settings window is unavailable.")))
        return
      }
      let result = await waiter.present {
        self.showSettings()
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

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Red-close hides this app-owned destination instead of invalidating the
    // controller/root view graph. The same window and app-lifetime draft can
    // therefore be made key again from the tray or Cmd+,.
    cancelInFlightPresentation()
    sender.orderOut(nil)
    activationCoordinator?.windowDidHide(sender)
    return false
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
    // Detach first so a same-turn reopen creates a fresh producer instead of
    // joining the request that red-close just cancelled. The old producer's
    // completion is identity-guarded and therefore cannot hide the new one.
    presentationRequest = nil
    request.cancelProducer()
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

/// Completes from concrete window state, window notifications, cancellation,
/// or a bounded liveness deadline. The deadline is only a final escape from a
/// visible window that cannot become key; ordinary success is notification- or
/// state-driven and never depends on waiting out the deadline.
@MainActor
final class WindowPresentationAwaiter {
  typealias LivenessDeadlineScheduler =
    @MainActor (@escaping @MainActor () -> Void) -> Task<Void, Never>?

  private weak var window: NSWindow?
  private var observers: [NSObjectProtocol] = []
  private var livenessDeadlineTask: Task<Void, Never>?
  private var continuation: CheckedContinuation<TrayDestinationPresentation, Never>?
  private var isCancellationRequested = false
  private var isFinished = false
  private let stateProvider: @MainActor () -> (isVisible: Bool, isKey: Bool)
  private let scheduleLivenessDeadline: LivenessDeadlineScheduler

  init(window: NSWindow) {
    self.window = window
    stateProvider = { [weak window] in
      (window?.isVisible == true, window?.isKeyWindow == true)
    }
    scheduleLivenessDeadline = { completion in
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        completion()
      }
    }
  }

  #if DEBUG
    init(
      window: NSWindow,
      stateProvider: @escaping @MainActor () -> (isVisible: Bool, isKey: Bool),
      scheduleLivenessDeadline: @escaping LivenessDeadlineScheduler = { completion in
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(2))
          guard !Task.isCancelled else { return }
          completion()
        }
      }
    ) {
      self.window = window
      self.stateProvider = stateProvider
      self.scheduleLivenessDeadline = scheduleLivenessDeadline
    }
  #endif

  func present(_ action: @MainActor () -> Void) async -> TrayDestinationPresentation {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        isFinished = false
        self.continuation = continuation
        guard let window else {
          finish(.failed(appLocalized("The destination window is unavailable.")))
          return
        }
        guard !isCancellationRequested, !Task.isCancelled else {
          finish(.cancelled)
          return
        }
        observers = [
          NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated {
              self?.completeFromWindowState()
            }
          },
          NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated {
              self?.finish(.cancelled)
            }
          },
        ]
        action()
        completeFromWindowState()
        guard !isFinished else { return }
        if !stateProvider().isVisible {
          finish(.failed(appLocalized("The destination window could not be shown.")))
          return
        }
        livenessDeadlineTask = scheduleLivenessDeadline { [weak self] in
          self?.completeAtLivenessDeadline()
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.cancel()
      }
    }
  }

  func cancel() {
    isCancellationRequested = true
    finish(.cancelled)
  }

  private func completeFromWindowState() {
    guard window != nil else {
      finish(.failed(appLocalized("The destination window is unavailable.")))
      return
    }
    let state = stateProvider()
    guard state.isVisible, state.isKey else { return }
    finish(.presented(isVisible: true, isKeyOrActive: true))
  }

  private func completeAtLivenessDeadline() {
    guard window != nil else {
      finish(.failed(appLocalized("The destination window is unavailable.")))
      return
    }
    let state = stateProvider()
    guard state.isVisible else {
      finish(.cancelled)
      return
    }
    finish(.presented(isVisible: true, isKeyOrActive: state.isKey))
  }

  private func finish(_ result: TrayDestinationPresentation) {
    guard !isFinished else { return }
    isFinished = true
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
    livenessDeadlineTask?.cancel()
    livenessDeadlineTask = nil
    continuation?.resume(returning: result)
    continuation = nil
  }
}

enum SettingsTab: Hashable {
  case profiles
  case system
  case about
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
  @Published var selectedTab: SettingsTab
  @Published private(set) var presentationGeneration: UInt64 = 0

  init(selectedTab: SettingsTab) {
    self.selectedTab = selectedTab
  }

  func beginPresentation() {
    presentationGeneration &+= 1
  }
}

struct RuntimeSettingsRoot: View {
  @ObservedObject var navigation: SettingsNavigationModel
  let uiAuditConfiguration: UIAuditConfiguration

  var body: some View {
    SettingsView(
      selectedTab: $navigation.selectedTab,
      presentationGeneration: navigation.presentationGeneration
    )
    .uiAuditEnvironment(uiAuditConfiguration)
    .frame(
      minWidth: 680,
      idealWidth: 900,
      maxWidth: .infinity,
      minHeight: 480,
      idealHeight: 568,
      maxHeight: .infinity
    )
  }
}

struct SettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @Binding var selectedTab: SettingsTab
  let presentationGeneration: UInt64

  init(
    selectedTab: Binding<SettingsTab>,
    presentationGeneration: UInt64 = 0
  ) {
    _selectedTab = selectedTab
    self.presentationGeneration = presentationGeneration
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      ProfilesSettingsView(presentationGeneration: presentationGeneration)
        .tabItem { Label("Profiles", systemImage: "rectangle.stack") }
        .tag(SettingsTab.profiles)

      SystemSettingsView()
        .environmentObject(model)
        .tabItem { Label("System", systemImage: "gearshape.2") }
        .tag(SettingsTab.system)

      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
        .tag(SettingsTab.about)
    }
    .padding(20)
  }
}

private struct SystemSettingsView: View {
  @Environment(\.uiAuditConfiguration) private var uiAuditConfiguration
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var locationPermission: LocationPermissionController
  @State private var showsAdvancedDiagnostics = false

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
          "macOS registration",
          value: model.loginItemEnabled ? appLocalized("Enabled") : appLocalized("Not enabled")
        )

        if loginItemStatesDiffer || model.canRetryLoginItemRegistration {
          Label(model.loginItemStatus, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(appLocalized("Login item status: \(model.loginItemStatus)"))
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
        Button(locationPermissionActionTitle) {
          performLocationPermissionAction()
        }
        .accessibilityHint(locationPermissionActionHint)
        if !locationPermission.isAuthorized {
          Text("After changing Location access, return to the menu bar and capture again.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Troubleshooting") {
        Text(
          "Diagnostics are only needed when a capture or apply does not behave as expected. They contain redacted local status and no telemetry."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Button("Open Advanced Diagnostics…") {
          showsAdvancedDiagnostics = true
        }
        .accessibilityHint("Shows redacted local status, snapshot details, and recent events")
      }
    }
    .formStyle(.grouped)
    .sheet(isPresented: $showsAdvancedDiagnostics) {
      AdvancedDiagnosticsSheet()
        .environmentObject(model)
    }
    .onAppear {
      if uiAuditConfiguration.isEnabled, uiAuditConfiguration.variant == .diagnostics {
        showsAdvancedDiagnostics = true
      }
    }
  }

  private var loginItemStatesDiffer: Bool {
    model.launchAtLoginDesired != model.loginItemEnabled
  }

  private var locationPermissionActionTitle: String {
    switch locationPermission.authorizationStatus {
    case .notDetermined:
      appLocalized("Request Location Access")
    case .denied, .restricted:
      appLocalized("Open macOS System Settings")
    case .authorizedAlways, .authorized:
      appLocalized("Refresh Current Location")
    @unknown default:
      appLocalized("Open macOS System Settings")
    }
  }

  private var locationPermissionActionHint: String {
    switch locationPermission.authorizationStatus {
    case .notDetermined:
      appLocalized("Shows the macOS permission prompt only after this explanation")
    case .denied, .restricted:
      appLocalized("Opens macOS System Settings to change Location access")
    case .authorizedAlways, .authorized:
      appLocalized("Refreshes the current location used by readiness checks")
    @unknown default:
      appLocalized("Opens macOS System Settings to change Location access")
    }
  }

  private func performLocationPermissionAction() {
    switch locationPermission.authorizationStatus {
    case .notDetermined, .authorizedAlways, .authorized:
      locationPermission.requestAccess()
    case .denied, .restricted:
      locationPermission.openSystemSettings()
    @unknown default:
      locationPermission.openSystemSettings()
    }
  }
}

private struct AdvancedDiagnosticsSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Label("Advanced Diagnostics", systemImage: "stethoscope")
          .font(.title3.bold())
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)

      Divider()
      DiagnosticsSettingsView()
    }
    .frame(minWidth: 700, minHeight: 560)
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
              isAwaitingSafetyConfirmation: result.safetyConfirmationID != nil
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
