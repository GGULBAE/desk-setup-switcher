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
  @StateObject private var settingsNavigation: SettingsNavigationModel
  @StateObject private var trayPresentation: TrayPresentationModel
  private let uiAuditConfiguration: UIAuditConfiguration
  private let windowActivationCoordinator: ApplicationWindowActivationCoordinator
  private let settingsWindowController: RuntimeSettingsWindowController
  private let workflowWindowController: TrayWorkflowWindowController
  private let destinationCoordinator: TrayDestinationCoordinator
  private let trayActionRouter: TrayActionRouter
  private let trayPopoverController: TrayPopoverController?
  #if DEBUG
    private let auditWindowController: UIAuditWindowController?
  #endif

  init() {
    let uiAuditConfiguration = UIAuditConfiguration.current
    let model: ApplicationModel
    let locationPermission: LocationPermissionController
    #if DEBUG
      if uiAuditConfiguration.isEnabled {
        model = UIAuditFixtures.makeModel(configuration: uiAuditConfiguration)
        locationPermission = LocationPermissionController(
          allowsSystemRequests: false,
          syntheticAuthorizationStatus: .denied
        )
      } else {
        model = ApplicationModel()
        locationPermission = LocationPermissionController()
      }
    #else
      model = ApplicationModel()
      locationPermission = LocationPermissionController()
    #endif
    let profileEditor = ProfileEditorModel()
    self.uiAuditConfiguration = uiAuditConfiguration
    _model = StateObject(wrappedValue: model)
    _locationPermission = StateObject(wrappedValue: locationPermission)
    _profileEditor = StateObject(wrappedValue: profileEditor)
    let initialSettingsTab: SettingsTab
    switch uiAuditConfiguration.variant {
    case .permissions, .diagnostics: initialSettingsTab = .system
    case .overview, .menuPolish, .trayEmpty, .traySingle, .trayOverflow, .trayDelete,
      .trayCapturePermission, .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult,
      .editor, .editorPolish, .editorDisplay, .editorDisplayColor, .editorAudio,
      .editorAudioUnsupported,
      .editorNetwork, .editorNetworkEthernetDHCP, .editorNetworkEthernetManual,
      .editorNetworkWiFiDHCP, .editorNetworkWiFiManual, .validation:
      initialSettingsTab = .profiles
    }
    let settingsNavigation = SettingsNavigationModel(selectedTab: initialSettingsTab)
    _settingsNavigation = StateObject(wrappedValue: settingsNavigation)
    let initialDeletionProfileID: UUID?
    #if DEBUG
      initialDeletionProfileID =
        uiAuditConfiguration.variant == .menuPolish
          || uiAuditConfiguration.variant == .trayDelete
        ? UIAuditFixtures.readyProfileID
        : nil
    #else
      initialDeletionProfileID = nil
    #endif
    let presentation = TrayPresentationModel(
      model: model,
      locationPermission: locationPermission,
      profileEditor: profileEditor,
      initialDeletionProfileID: initialDeletionProfileID
    )
    _trayPresentation = StateObject(wrappedValue: presentation)
    #if DEBUG
      switch uiAuditConfiguration.variant {
      case .trayCaptureSuccess:
        presentation.configureForUIAudit(
          capturePhase: .success(
            appLocalized("Captured current settings without changing the Mac."))
        )
      case .trayCaptureFailure:
        presentation.configureForUIAudit(
          capturePhase: .failure(
            appLocalized("No settings could be added safely from this snapshot."))
        )
      default:
        break
      }
    #endif

    let settingsRoot = RuntimeSettingsRoot(
      navigation: settingsNavigation,
      uiAuditConfiguration: uiAuditConfiguration
    )
    .environmentObject(model)
    .environmentObject(locationPermission)
    .environmentObject(profileEditor)
    let windowActivationCoordinator = ApplicationWindowActivationCoordinator()
    self.windowActivationCoordinator = windowActivationCoordinator
    let settingsController = RuntimeSettingsWindowController(
      rootView: settingsRoot,
      activationCoordinator: windowActivationCoordinator
    )
    settingsWindowController = settingsController

    let workflowCloseRelay = TrayWorkflowCloseRelay()
    let workflowRoot = TrayWorkflowRootView(
      presentation: presentation,
      onClose: { workflowCloseRelay.close() }
    )
    .environmentObject(model)
    .environmentObject(locationPermission)
    .environmentObject(profileEditor)
    let workflowController = TrayWorkflowWindowController(
      rootView: workflowRoot,
      activationCoordinator: windowActivationCoordinator,
      onWindowClose: {
        presentation.handleWorkflowWindowClose()
      }
    )
    workflowCloseRelay.controller = workflowController
    workflowWindowController = workflowController

    let destinationCoordinator = TrayDestinationCoordinator(
      model: model,
      profileEditor: profileEditor,
      settingsNavigation: settingsNavigation,
      settingsController: settingsController,
      workflowController: workflowController,
      presentation: presentation
    )
    self.destinationCoordinator = destinationCoordinator
    let actionRouter = TrayActionRouter(
      executor: presentation,
      destinationPresenter: destinationCoordinator
    )
    trayActionRouter = actionRouter

    if !uiAuditConfiguration.isEnabled || uiAuditConfiguration.showsStatusPopover {
      let trayRoot = TrayRootView(
        presentation: presentation,
        router: actionRouter
      )
      .environmentObject(model)
      .environmentObject(locationPermission)
      .environmentObject(profileEditor)
      .uiAuditEnvironment(uiAuditConfiguration)
      let popoverController = TrayPopoverController(
        rootView: trayRoot,
        sessionState: presentation
      )
      trayPopoverController = popoverController
      actionRouter.surface = popoverController
      presentation.setSurfaceDismissRequest { [weak popoverController] generation in
        popoverController?.requestClose(sessionGeneration: generation)
      }
    } else {
      trayPopoverController = nil
    }
    #if DEBUG
      if uiAuditConfiguration.isEnabled, !uiAuditConfiguration.showsStatusPopover {
        if uiAuditConfiguration.variant.isTraySurface {
          let viewport = TrayGeometry().viewport(
            for: presentation.geometryContext,
            on: TrayScreenMetrics(
              visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
              backingScaleFactor: 2
            )
          )
          presentation.trayDidOpen(sessionGeneration: 1, viewport: viewport)
          presentation.trayContentDidAttach(sessionGeneration: 1)
        }
        let auditRoot = UIAuditHostView(
          configuration: uiAuditConfiguration,
          trayPresentation: presentation,
          trayActionRouter: actionRouter
        )
        .environmentObject(model)
        .environmentObject(locationPermission)
        .environmentObject(profileEditor)
        .uiAuditEnvironment(uiAuditConfiguration)
        auditWindowController = UIAuditWindowController(
          rootView: auditRoot,
          initialContentSize: uiAuditConfiguration.auditSettingsSize
        )
      } else {
        auditWindowController = nil
      }
    #endif
    if uiAuditConfiguration.isEnabled, !uiAuditConfiguration.showsStatusPopover {
      NSApplication.shared.setActivationPolicy(.regular)
    } else {
      if !uiAuditConfiguration.isEnabled {
        appDelegate.model = model
        appDelegate.profileEditor = profileEditor
      }
      NSApplication.shared.setActivationPolicy(.accessory)
      if !uiAuditConfiguration.isEnabled {
        model.start()
      }
    }
    #if DEBUG
      if let auditWindowController {
        DispatchQueue.main.async {
          auditWindowController.showWindow(nil)
          auditWindowController.window?.makeKeyAndOrderFront(nil)
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
      }
    #endif
  }

  var body: some Scene {
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") {
          Task {
            await presentApplicationSettings(
              navigation: settingsNavigation,
              presenter: settingsWindowController
            )
          }
        }
        .keyboardShortcut(",")
      }
    }
  }
}

#if DEBUG
  @MainActor
  private final class UIAuditWindowController: NSWindowController {
    init<Content: View>(rootView: Content, initialContentSize: CGSize?) {
      let hostingController = NSHostingController(rootView: rootView)
      let window = NSWindow(contentViewController: hostingController)
      window.title = "Desk Setup Switcher UI Audit"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.isMovableByWindowBackground = true
      window.isReleasedWhenClosed = false
      hostingController.view.layoutSubtreeIfNeeded()
      window.setContentSize(initialContentSize ?? hostingController.view.fittingSize)
      if initialContentSize != nil {
        window.contentMinSize = CGSize(width: 680, height: 480)
      }
      window.center()
      super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  private struct UIAuditHostView: View {
    let configuration: UIAuditConfiguration
    @ObservedObject var trayPresentation: TrayPresentationModel
    let trayActionRouter: TrayActionRouter
    @State private var selectedSettingsTab: SettingsTab

    init(
      configuration: UIAuditConfiguration,
      trayPresentation: TrayPresentationModel,
      trayActionRouter: TrayActionRouter
    ) {
      self.configuration = configuration
      self.trayPresentation = trayPresentation
      self.trayActionRouter = trayActionRouter
      let initialTab: SettingsTab
      switch configuration.variant {
      case .permissions, .diagnostics: initialTab = .system
      case .overview, .menuPolish, .trayEmpty, .traySingle, .trayOverflow, .trayDelete,
        .trayCapturePermission, .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult,
        .editor, .editorPolish, .editorDisplay, .editorDisplayColor, .editorAudio,
        .editorAudioUnsupported,
        .editorNetwork, .editorNetworkEthernetDHCP, .editorNetworkEthernetManual,
        .editorNetworkWiFiDHCP, .editorNetworkWiFiManual, .validation:
        initialTab = .profiles
      }
      _selectedSettingsTab = State(initialValue: initialTab)
    }

    @ViewBuilder
    var body: some View {
      switch configuration.variant {
      case .overview, .menuPolish, .trayEmpty, .traySingle, .trayOverflow, .trayDelete,
        .trayCapturePermission, .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult:
        TrayRootView(
          presentation: trayPresentation,
          router: trayActionRouter
        )
        .frame(width: TrayGeometry.width, height: trayPresentation.viewport.height)
      case .editor, .editorPolish, .editorDisplay, .editorDisplayColor, .editorAudio,
        .editorAudioUnsupported,
        .editorNetwork, .editorNetworkEthernetDHCP, .editorNetworkEthernetManual,
        .editorNetworkWiFiDHCP, .editorNetworkWiFiManual, .validation, .permissions,
        .diagnostics:
        SettingsView(selectedTab: $selectedSettingsTab)
          .frame(minWidth: 680, minHeight: 480)
      }
    }

  }

  extension UIAuditConfiguration {
    fileprivate var auditSettingsSize: CGSize? {
      guard !variant.isTraySurface else { return nil }
      return switch displayMode {
      case .standard: CGSize(width: 980, height: 720)
      case .minimum: CGSize(width: 680, height: 480)
      case .largeText: CGSize(width: 1_100, height: 820)
      }
    }
  }
#endif
