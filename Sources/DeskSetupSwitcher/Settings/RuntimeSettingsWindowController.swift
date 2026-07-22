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
  navigation.routeToDefaultTab(
    startsNewPresentation: !presenter.isPresentationVisible
  )
  return await presenter.presentAndWaitUntilKey()
}

enum RuntimeSettingsWindowLayoutPolicy {
  static let initialContentSize = CGSize(width: 900, height: 568)
  static let minimumContentSize = CGSize(width: 680, height: 480)
}

enum AdvancedDiagnosticsLayoutPolicy {
  static let minimumContentSize = CGSize(width: 520, height: 360)
  static let idealContentSize = CGSize(width: 640, height: 460)

  static func isContained(in settingsViewport: CGSize) -> Bool {
    minimumContentSize.width <= settingsViewport.width
      && minimumContentSize.height <= settingsViewport.height
  }
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
    // This persistent native window owns its frame. The default SwiftUI
    // sizing options otherwise rewrite the NSWindow whenever a tab or model
    // transition changes the root view's intrinsic size.
    hostingController.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(
        origin: .zero,
        size: RuntimeSettingsWindowLayoutPolicy.initialContentSize
      ),
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
    window.contentMinSize = RuntimeSettingsWindowLayoutPolicy.minimumContentSize
    window.setContentSize(RuntimeSettingsWindowLayoutPolicy.initialContentSize)
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

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    let minimumFrameSize = sender.frameRect(
      forContentRect: NSRect(
        origin: .zero,
        size: RuntimeSettingsWindowLayoutPolicy.minimumContentSize
      )
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
    // Detach first so a same-turn reopen creates a fresh producer instead of
    // joining the request that red-close just cancelled. The old producer's
    // completion is identity-guarded and therefore cannot hide the new one.
    presentationRequest = nil
    request.cancelProducer()
  }

  func prepareForPresentation() {
    guard let window else { return }
    // SwiftUI/AppKit may recompute a hosted window's resizing constraints
    // after the controller is attached. Reassert the app-owned minimum on
    // every presentation before repairing any legacy undersized frame.
    window.contentMinSize = RuntimeSettingsWindowLayoutPolicy.minimumContentSize
    restoreMinimumContentSizeIfNeeded(window)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
  }

  private func restoreMinimumContentSizeIfNeeded(_ window: NSWindow) {
    let currentSize = window.contentRect(forFrameRect: window.frame).size
    let minimumSize = RuntimeSettingsWindowLayoutPolicy.minimumContentSize
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

  /// Routes every Settings command through one synchronous state transition.
  /// An older asynchronous presentation can settle later, but it never owns a
  /// tab write and therefore cannot restore a stale System or About selection.
  func routeToDefaultTab(startsNewPresentation: Bool) {
    selectedTab = .profiles
    if startsNewPresentation {
      beginPresentation()
    }
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
      minWidth: RuntimeSettingsWindowLayoutPolicy.minimumContentSize.width,
      idealWidth: RuntimeSettingsWindowLayoutPolicy.initialContentSize.width,
      maxWidth: .infinity,
      minHeight: RuntimeSettingsWindowLayoutPolicy.minimumContentSize.height,
      idealHeight: RuntimeSettingsWindowLayoutPolicy.initialContentSize.height,
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
        .tabItem { Label(appLocalized("Profiles"), systemImage: "rectangle.stack") }
        .tag(SettingsTab.profiles)

      SystemSettingsView()
        .environmentObject(model)
        .tabItem { Label(appLocalized("System"), systemImage: "gearshape.2") }
        .tag(SettingsTab.system)

      AboutSettingsView()
        .tabItem { Label(appLocalized("About"), systemImage: "info.circle") }
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
  @State private var isLoginExplanationExpanded = false

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
            Button(appLocalized("Retry Registration")) {
              model.retryLaunchAtLoginRegistration()
            }
          }
          Button(appLocalized("Refresh Status")) {
            model.refreshLoginItemStatusFromSystem()
          }
        }

        AccessibleDisclosureGroup(
          appLocalized("Why can these states differ?"),
          accessibilityIdentifier: "settings.login-state-explanation",
          isExpanded: $isLoginExplanationExpanded
        ) {
          Text(
            "macOS accepts login-item registration only for an eligible installed and code-signed app. The app setting does not guarantee registration."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Section("System permissions") {
        Text(
          "macOS can require Location Services to reveal the current Wi-Fi network name during Capture. Desk Setup Switcher does not request or store your coordinates."
        )
        LabeledContent("Location", value: locationPermission.statusText)
        if let locationPermissionActionTitle {
          Button(locationPermissionActionTitle) {
            performLocationPermissionAction()
          }
          .accessibilityHint(locationPermissionActionHint)
        }
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
        Button(appLocalized("Open Advanced Diagnostics…")) {
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

  private var locationPermissionActionTitle: String? {
    switch locationPermission.authorizationStatus {
    case .notDetermined:
      appLocalized("Request Location Access")
    case .denied, .restricted:
      appLocalized("Open macOS System Settings")
    case .authorizedAlways, .authorized:
      nil
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
      ""
    @unknown default:
      appLocalized("Opens macOS System Settings to change Location access")
    }
  }

  private func performLocationPermissionAction() {
    switch locationPermission.authorizationStatus {
    case .notDetermined:
      locationPermission.requestAccess()
    case .authorizedAlways, .authorized:
      break
    case .denied, .restricted:
      locationPermission.openSystemSettings()
    @unknown default:
      locationPermission.openSystemSettings()
    }
  }
}

struct AdvancedDiagnosticsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @AccessibilityFocusState private var isHeadingAccessibilityFocused: Bool
  @FocusState private var isDoneKeyboardFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      diagnosticsHeader
        .padding(.horizontal, 20)
        .padding(.vertical, 14)

      Divider()
      DiagnosticsSettingsView()
    }
    .frame(
      minWidth: AdvancedDiagnosticsLayoutPolicy.minimumContentSize.width,
      idealWidth: AdvancedDiagnosticsLayoutPolicy.idealContentSize.width,
      maxWidth: .infinity,
      minHeight: AdvancedDiagnosticsLayoutPolicy.minimumContentSize.height,
      idealHeight: AdvancedDiagnosticsLayoutPolicy.idealContentSize.height,
      maxHeight: .infinity
    )
    .task {
      await Task.yield()
      isHeadingAccessibilityFocused = true
      isDoneKeyboardFocused = true
    }
  }

  @ViewBuilder
  private var diagnosticsHeader: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 10) {
        diagnosticsTitle
        HStack {
          Spacer(minLength: 0)
          doneButton
        }
      }
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          diagnosticsTitle
          Spacer(minLength: 0)
          doneButton
        }
        VStack(alignment: .leading, spacing: 10) {
          diagnosticsTitle
          HStack {
            Spacer(minLength: 0)
            doneButton
          }
        }
      }
    }
  }

  private var diagnosticsTitle: some View {
    Label(appLocalized("Advanced Diagnostics"), systemImage: "stethoscope")
      .font(.title3.bold())
      .accessibilityAddTraits(.isHeader)
      .accessibilityFocused($isHeadingAccessibilityFocused)
  }

  private var doneButton: some View {
    Button(appLocalized("Done")) { dismiss() }
      .keyboardShortcut(.cancelAction)
      .focused($isDoneKeyboardFocused)
  }
}

struct DiagnosticsSettingsView: View {
  @EnvironmentObject private var model: ApplicationModel
  @State private var confirmClear = false
  @State private var expandedDisclosureIDs: Set<String> = []

  var body: some View {
    Form {
      LabeledContent(appLocalized("Last result"), value: model.lastMessage)
      LabeledContent(appLocalized("Last snapshot"), value: model.snapshotStatus)
      LabeledContent(appLocalized("Storage"), value: appLocalized("Local Application Support only"))
      LabeledContent(appLocalized("Telemetry"), value: appLocalized("None"))
      LabeledContent(appLocalized("Live mutations"), value: appLocalized("User-confirmed only"))
      Section(appLocalized("Readiness facts")) {
        ViewThatFits(in: .horizontal) {
          HStack {
            readinessStatus
            Spacer(minLength: 12)
            refreshReadinessButton
          }
          VStack(alignment: .leading, spacing: 8) {
            readinessStatus
            refreshReadinessButton
          }
        }

        LabeledContent(
          appLocalized("Connected displays"),
          value: appLocalized("\(model.lastConditionContext.displays.count) detected")
        )
        LabeledContent(
          appLocalized("Wi-Fi SSID"),
          value: model.lastConditionContext.wifiSSID ?? appLocalized("Unavailable")
        )
        LabeledContent(
          appLocalized("Ethernet"),
          value: model.lastConditionContext.ethernetConnected
            ? appLocalized("Connected") : appLocalized("Not connected")
        )
        factList(
          id: "audio-input-uids",
          title: appLocalized("Audio input UIDs"),
          values: model.lastConditionContext.audioInputUIDs.sorted()
        )
        factList(
          id: "audio-output-uids",
          title: appLocalized("Audio output UIDs"),
          values: model.lastConditionContext.audioOutputUIDs.sorted()
        )
        factList(
          id: "usb-hardware-identifiers",
          title: appLocalized("USB hardware identifiers"),
          values: model.lastConditionContext.hardwareIdentifiers.sorted()
        )
        factList(
          id: "local-ip-addresses",
          title: appLocalized("Local IP addresses"),
          values: model.lastConditionContext.ipAddresses.sorted()
        )
      }
      if let snapshot = model.lastSnapshot {
        Section(appLocalized("Snapshot details")) {
          LabeledContent(appLocalized("Captured"), value: snapshot.capturedAt.formatted())
          ForEach(snapshot.groups, id: \.group) { group in
            let disclosureID = "snapshot-\(group.group.rawValue)"
            AccessibleDisclosureGroup(
              appSettingGroupTitle(group.group),
              accessibilityIdentifier: "diagnostics.\(disclosureID)",
              isExpanded: expansionBinding(for: disclosureID)
            ) {
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
        Section(appLocalized("Last apply details")) {
          LabeledContent(
            appLocalized("Status"),
            value: appApplicationStatusTitle(
              result.status,
              isAwaitingSafetyConfirmation: result.safetyConfirmationID != nil
            )
          )
          LabeledContent(
            appLocalized("Executed"),
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

      Section(appLocalized("Redacted local events")) {
        Text(model.diagnosticStatus)
          .font(.caption)
          .foregroundStyle(.secondary)

        ViewThatFits(in: .horizontal) {
          HStack {
            diagnosticActionButtons
          }
          VStack(alignment: .leading, spacing: 8) {
            diagnosticActionButtons
          }
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
      Button(appLocalized("Remove Events"), role: .destructive) { model.clearDiagnostics() }
      Button(appLocalized("Cancel"), role: .cancel) {}
    } message: {
      Text("This removes only Desk Setup Switcher’s rotated, redacted diagnostic files.")
    }
  }

  private var readinessStatus: some View {
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
  }

  private var refreshReadinessButton: some View {
    Button(appLocalized("Refresh Readiness")) { model.refreshReadinessFacts() }
      .disabled(model.isApplyTransactionInProgress)
      .accessibilityHint("Reads current system facts without changing any setting")
  }

  @ViewBuilder
  private var diagnosticActionButtons: some View {
    Button(appLocalized("Refresh")) { model.refreshDiagnostics() }
    Button(appLocalized("Clear Events…"), role: .destructive) { confirmClear = true }
      .disabled(model.diagnosticEntries.isEmpty)
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
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          applicationItemTitle(item)
          Spacer(minLength: 8)
          applicationItemStatus(item)
        }
        VStack(alignment: .leading, spacing: 3) {
          applicationItemTitle(item)
          applicationItemStatus(item)
        }
      }
      Text(appLocalizedRuntime(item.message))
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  private func applicationItemTitle(_ item: ApplicationItemSummary) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(appSettingGroupTitle(item.group))
        .font(.caption.bold())
      Text(appApplicationItemTitle(item.key))
    }
  }

  private func applicationItemStatus(_ item: ApplicationItemSummary) -> some View {
    Text(appApplicationItemStatusTitle(item.status))
      .font(.caption.bold())
  }

  @ViewBuilder
  private func factList(id: String, title: String, values: [String]) -> some View {
    AccessibleDisclosureGroup(
      appLocalized("\(title) (\(values.count))"),
      accessibilityIdentifier: "diagnostics.fact-list.\(id)",
      isExpanded: expansionBinding(for: id)
    ) {
      if values.isEmpty {
        Text(appLocalized("None detected"))
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

  private func expansionBinding(for id: String) -> Binding<Bool> {
    Binding(
      get: { expandedDisclosureIDs.contains(id) },
      set: { isExpanded in
        if isExpanded {
          expandedDisclosureIDs.insert(id)
        } else {
          expandedDisclosureIDs.remove(id)
        }
      }
    )
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

struct AboutSettingsView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @AccessibilityFocusState private var isHeadingAccessibilityFocused: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        Image(systemName: "switch.2")
          .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 42 : 56))
          .accessibilityHidden(true)
        Text(appLocalized("Desk Setup Switcher"))
          .font(.title2.bold())
          .accessibilityAddTraits(.isHeader)
          .accessibilityFocused($isHeadingAccessibilityFocused)
        Text(appLocalized("Version \(appVersion)"))
          .foregroundStyle(.secondary)
        Text(appLocalized("Free and open source under the MIT License"))
          .font(.caption)

        Divider()
          .frame(maxWidth: 360)

        LazyVGrid(columns: linkColumns, alignment: .leading, spacing: 12) {
          aboutLink(
            title: appLocalized("Source Code"),
            systemImage: "chevron.left.forwardslash.chevron.right",
            destination: repositoryURL,
            identifier: "about.source-code"
          )
          aboutLink(
            title: appLocalized("Report an Issue"),
            systemImage: "exclamationmark.bubble",
            destination: issuesURL,
            identifier: "about.report-issue"
          )
          aboutLink(
            title: appLocalized("MIT License"),
            systemImage: "doc.text",
            destination: licenseURL,
            identifier: "about.license"
          )
          aboutLink(
            title: appLocalized("Privacy Principles"),
            systemImage: "hand.raised",
            destination: privacyURL,
            identifier: "about.privacy"
          )
        }
        .frame(maxWidth: 480)
        .focusSection()

        Text(appLocalized("Links open only when you choose them and use your default browser."))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity)
    }
    .defaultScrollAnchor(.top)
    .scrollBounceBehavior(.basedOnSize)
    .task {
      await Task.yield()
      isHeadingAccessibilityFocused = true
    }
  }

  private var linkColumns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize {
      return [GridItem(.flexible(), alignment: .leading)]
    }
    return [
      GridItem(.flexible(), alignment: .leading),
      GridItem(.flexible(), alignment: .leading),
    ]
  }

  private func aboutLink(
    title: String,
    systemImage: String,
    destination: URL,
    identifier: String
  ) -> some View {
    Link(destination: destination) {
      Label(title, systemImage: systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityLabel(title)
    .accessibilityIdentifier(identifier)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
  }

  private let repositoryURL = URL(string: "https://github.com/GGULBAE/desk-setup-switcher")!
  private let issuesURL = URL(string: "https://github.com/GGULBAE/desk-setup-switcher/issues")!
  private let licenseURL = URL(
    string: "https://github.com/GGULBAE/desk-setup-switcher/blob/master/LICENSE")!
  private let privacyURL = URL(
    string: "https://github.com/GGULBAE/desk-setup-switcher/blob/master/docs/PRIVACY.md")!
}
