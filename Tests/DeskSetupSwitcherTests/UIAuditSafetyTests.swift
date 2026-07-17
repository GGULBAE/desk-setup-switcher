import Foundation
import ServiceManagement
import SwiftUI
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher
@testable import DeskSetupSystem

#if DEBUG
  @Suite("Synthetic UI audit safety", .serialized)
  @MainActor
  struct UIAuditSafetyTests {
    @Test("public audit actions never reach adapters, stores, diagnostics, or login items")
    func publicActionsRemainSideEffectFree() async throws {
      let identifier = "DeskSetupSwitcherTests.UIAudit.\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: identifier))
      defaults.removePersistentDomain(forName: identifier)
      defer { defaults.removePersistentDomain(forName: identifier) }

      let storeDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(identifier, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: storeDirectory) }

      let adapter = MockSystemSettingsAdapter(group: .display)
      let conditionReaders = RecordingConditionReaders()
      let conditionProvider = ConditionContextProvider(
        displayReader: conditionReaders,
        audioReader: conditionReaders,
        networkReader: conditionReaders,
        hardwareReader: conditionReaders,
        locationReader: conditionReaders
      )
      let loginItem = RecordingLoginItemService()
      let diagnosticLog = RecordingDiagnosticLog()
      let model = ApplicationModel(
        profileStore: ProfileStore(directoryURL: storeDirectory),
        snapshotCoordinator: SystemSnapshotCoordinator(adapters: [adapter]),
        conditionContextProvider: conditionProvider,
        applyEngine: ApplyEngine(registry: try AdapterRegistry([adapter])),
        diagnosticLog: diagnosticLog,
        defaults: defaults,
        loginItemService: loginItem
      )
      let fixture = UIAuditFixtures.fixture(.editor)
      model.configureForUIAudit(fixture)
      let selected = try #require(fixture.profiles.first)

      model.start()
      model.refreshReadinessFacts()
      model.createProfile()
      model.duplicateProfile(id: selected.id)
      let deleteResult = await model.deleteProfile(id: selected.id)
      model.moveProfile(id: selected.id, by: 1)
      model.setLaunchAtLogin(false)
      model.retryLaunchAtLoginRegistration()
      model.refreshLoginItemStatusFromSystem()
      model.refreshDiagnostics()
      model.clearDiagnostics()
      model.prepareApply(profile: selected, mode: .normal)
      model.executePendingApply()
      model.confirmHighRiskChanges()
      model.revertHighRiskChanges()

      let saveResult = await model.updateProfile(selected)
      let createResult = await model.createProfileFromCurrentSettings()
      let captureResult = await model.captureCurrentProfileSettings()

      #expect(
        saveResult
          == .rejected(
            message: appLocalized("System access is disabled for this synthetic review."))
      )
      #expect(
        deleteResult
          == .rejected(
            message: appLocalized("System access is disabled for this synthetic review."))
      )
      #expect(
        createResult
          == .rejected(
            message: appLocalized("System access is disabled for this synthetic review."),
            summary: fixture.captureSummary
          )
      )
      #expect(
        captureResult
          == .rejected(
            message: appLocalized("System access is disabled for this synthetic review."),
            summary: fixture.captureSummary
          )
      )
      #expect(model.profiles == fixture.profiles)
      #expect(model.launchAtLoginDesired)
      #expect(await adapter.recordedInvocations().isEmpty)
      #expect(await conditionReaders.invocationCount == 0)
      #expect(loginItem.invocations.isEmpty)
      #expect(await diagnosticLog.invocations.isEmpty)
      #expect(defaults.persistentDomain(forName: identifier) == nil)
      #expect(!FileManager.default.fileExists(atPath: storeDirectory.path))
    }

    @Test("synthetic permission requests never call Core Location request closures")
    func permissionRequestRemainsSideEffectFree() {
      let recorder = PermissionRequestRecorder()
      let controller = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .notDetermined,
        requestWhenInUseAuthorization: recorder.requestAuthorization,
        requestLocation: recorder.requestLocation
      )

      controller.requestAccess()

      #expect(recorder.invocations.isEmpty)
      #expect(
        controller.lastError
          == appLocalized("System access is disabled for this synthetic review."))
    }

    @Test("explicit capture permission action calls the injected macOS request")
    func explicitPermissionRequestUsesInjectedClosure() {
      let recorder = PermissionRequestRecorder()
      let controller = LocationPermissionController(
        allowsSystemRequests: true,
        syntheticAuthorizationStatus: .notDetermined,
        requestWhenInUseAuthorization: recorder.requestAuthorization,
        requestLocation: recorder.requestLocation,
        openSystemSettingsApplication: recorder.openSystemSettings
      )

      controller.requestAccess()

      #expect(recorder.invocations == ["authorization"])
    }

    @Test("denied capture permission opens only the injected System Settings action")
    func deniedPermissionUsesInjectedSystemSettingsAction() {
      let recorder = PermissionRequestRecorder()
      let controller = LocationPermissionController(
        allowsSystemRequests: true,
        syntheticAuthorizationStatus: .denied,
        requestWhenInUseAuthorization: recorder.requestAuthorization,
        requestLocation: recorder.requestLocation,
        openSystemSettingsApplication: recorder.openSystemSettings
      )

      controller.openSystemSettings()

      #expect(recorder.invocations == ["settings"])
      #expect(controller.lastError == nil)
    }

    @Test("tray deletion request, cancel, and confirmation are deterministic")
    func trayDeletionStateTransitions() {
      let first = UUID()
      let second = UUID()
      var state = MenuProfileDeletionState()

      state.request(profileID: first)
      #expect(state.isPending(profileID: first))
      let wrongConfirmation = state.confirm(profileID: second)
      #expect(!wrongConfirmation)
      #expect(state.pendingProfileID == first)

      state.cancel()
      #expect(state.pendingProfileID == nil)

      state.request(profileID: first)
      let matchingConfirmation = state.confirm(profileID: first)
      #expect(matchingConfirmation)
      #expect(state.pendingProfileID == nil)
    }

    @Test("settings workspace and invalid-save handoff remain structurally stable")
    func stableSettingsWorkspacePolicy() {
      #expect(ProfileWorkspaceLayoutPolicy.sidebarWidth == 210)
      #expect(ProfileWorkspaceLayoutPolicy.minimumEditorWidth == 390)
      #expect(ProfileWorkspaceLayoutPolicy.minimumContentWidth <= 640)
      #expect(ProfileEditorSurfacePolicy.visibleGroups == [.display, .audio, .network])
      #expect(!ProfileEditorSurfacePolicy.visibleGroups.contains(.input))
      #expect(!ProfileEditorSurfacePolicy.showsActivationControl)
      #expect(!ProfileEditorSurfacePolicy.showsUnsupportedControls)
      #expect(!ProfileEditorSurfacePolicy.showsDescription)
      #expect(!ProfileEditorSurfacePolicy.showsConditions)
      #expect(!ProfileEditorSurfacePolicy.showsCurrentSettingsDraftRefresh)
      #expect(
        ProfileEditorSavePolicy.canAttemptSave(
          hasDraft: true,
          isDirty: true,
          isBusy: false
        )
      )
      #expect(
        !ProfileEditorSavePolicy.canAttemptSave(
          hasDraft: true,
          isDirty: true,
          isBusy: true
        )
      )

      var handoff = UnsavedPromptValidationHandoff()
      #expect(
        handoff.rejectInvalidSave(firstInvalidField: .profileName)
          == .cancelDeferredActionAndDismiss
      )
      #expect(handoff.presentationChanged(isPresented: true) == .none)
      #expect(
        handoff.presentationChanged(isPresented: false)
          == .focusAndShowValidationSummary(.profileName)
      )
      #expect(handoff.presentationChanged(isPresented: false) == .none)
    }

    @Test("apply result count presentation hides zero outcomes without losing safety states")
    func applyResultCountPresentationFiltersOnlyZeros() throws {
      var summary = try #require(UIAuditFixtures.fixture(.trayApplyResult).applySummary)
      summary.succeededCount = 3
      summary.failedCount = 0
      summary.skippedCount = 2
      summary.unsupportedCount = 0
      summary.notVerifiedCount = 1
      summary.rolledBackCount = 0
      summary.rollbackFailedCount = 1

      #expect(
        ApplyResultCountPresentation.nonzeroItems(for: summary) == [
          ApplyResultCountItem(kind: .succeeded, count: 3),
          ApplyResultCountItem(kind: .skipped, count: 2),
          ApplyResultCountItem(kind: .notVerified, count: 1),
          ApplyResultCountItem(kind: .rollbackFailed, count: 1),
        ])

      summary.failedCount = 1
      summary.unsupportedCount = 1
      summary.rolledBackCount = 1
      #expect(
        ApplyResultCountPresentation.nonzeroItems(for: summary).map(\.kind)
          == ApplyResultCountKind.allCases
      )
    }

    @Test("audio volume capability follows the device the profile will target")
    func audioVolumeCapabilityUsesTargetDevice() {
      let catalog = [
        AudioVolumeControlCatalogEntry(
          role: .output,
          deviceUID: "writable-output",
          currentValue: 0.42,
          canApply: true
        ),
        AudioVolumeControlCatalogEntry(
          role: .output,
          deviceUID: "read-only-output",
          currentValue: 0.8,
          canApply: false
        ),
      ]

      #expect(
        ProfileEditorAudioVolumeCapabilityResolver.resolve(
          role: .output,
          selectedDevice: SettingOption(isIncluded: false, value: nil),
          currentDeviceUID: "writable-output",
          catalog: catalog
        ) == ProfileEditorAudioVolumeCapability(isWritable: true, suggestedValue: 0.42)
      )
      #expect(
        ProfileEditorAudioVolumeCapabilityResolver.resolve(
          role: .output,
          selectedDevice: SettingOption(isIncluded: true, value: "read-only-output"),
          currentDeviceUID: "writable-output",
          catalog: catalog
        ) == ProfileEditorAudioVolumeCapability(isWritable: false, suggestedValue: 0.8)
      )
    }

    @Test("only included unavailable settings receive an editor repair control")
    func unavailableIncludedSettingsRemainRepairable() {
      let savedColorProfile = ColorSyncProfileTarget(
        registeredProfileID: "saved-profile",
        fileSHA256: String(repeating: "a", count: 64),
        displayName: "Saved synthetic ICC"
      )
      let otherColorProfile = ColorSyncProfileTarget(
        registeredProfileID: "other-profile",
        fileSHA256: String(repeating: "b", count: 64),
        displayName: "Other synthetic ICC"
      )

      #expect(
        ProfileEditorUnavailableIncludedSettingPolicy.isSelectedColorProfileAvailable(
          savedColorProfile,
          in: [savedColorProfile, otherColorProfile]
        )
      )
      #expect(
        !ProfileEditorUnavailableIncludedSettingPolicy.isSelectedColorProfileAvailable(
          savedColorProfile,
          in: [otherColorProfile]
        )
      )
      #expect(
        ProfileEditorUnavailableIncludedSettingPolicy.isSelectedColorProfileAvailable(
          nil,
          in: [otherColorProfile]
        )
      )
      #expect(
        !ProfileEditorUnavailableIncludedSettingPolicy.isSelectedColorProfileAvailable(
          nil,
          in: []
        )
      )

      #expect(
        ProfileEditorUnavailableIncludedSettingPolicy.showsRepairControl(
          isIncluded: true,
          isRuntimeAvailable: false,
          hasRuntimeEvidence: true
        )
      )
      #expect(
        !ProfileEditorUnavailableIncludedSettingPolicy.showsRepairControl(
          isIncluded: false,
          isRuntimeAvailable: false,
          hasRuntimeEvidence: true
        )
      )
      #expect(
        !ProfileEditorUnavailableIncludedSettingPolicy.showsRepairControl(
          isIncluded: true,
          isRuntimeAvailable: true,
          hasRuntimeEvidence: true
        )
      )
      #expect(
        !ProfileEditorUnavailableIncludedSettingPolicy.showsRepairControl(
          isIncluded: true,
          isRuntimeAvailable: false,
          hasRuntimeEvidence: false
        )
      )

      let available = NetworkServiceIdentity(
        kind: .ethernet,
        serviceName: "Available synthetic service",
        interfaceType: "Ethernet"
      )
      let unavailable = NetworkServiceIdentity(
        kind: .ethernet,
        serviceName: "Unavailable synthetic service",
        interfaceType: "Ethernet"
      )
      let excluded = NetworkServiceIdentity(
        kind: .ethernet,
        serviceName: "Excluded synthetic service",
        interfaceType: "Ethernet"
      )
      let otherKind = NetworkServiceIdentity(
        kind: .wifi,
        serviceName: "Unavailable synthetic Wi-Fi",
        interfaceType: "IEEE80211"
      )
      let targets = [
        NetworkServiceIPv4Settings(
          identity: available,
          configuration: .init(value: .dhcp)
        ),
        NetworkServiceIPv4Settings(
          identity: unavailable,
          configuration: .init(value: .dhcp)
        ),
        NetworkServiceIPv4Settings(
          identity: excluded,
          configuration: .init(isIncluded: false, value: .dhcp)
        ),
        NetworkServiceIPv4Settings(
          identity: otherKind,
          configuration: .init(value: .dhcp)
        ),
      ]

      #expect(
        ProfileEditorUnavailableIncludedSettingPolicy.unavailableNetworkServiceIndices(
          in: targets,
          kind: .ethernet,
          availableIdentities: [available]
        ) == [1]
      )
    }

    @Test("settings catalog stays stable within a presentation and refreshes on reopen")
    func settingsCatalogSessionLifetime() {
      let first = UIAuditFixtures.fixture(.editorDisplay).snapshot
      let refreshed = UIAuditFixtures.fixture(.editorAudioUnsupported).snapshot
      var session = ProfileEditorCatalogSession()

      session.beginPresentation(
        generation: 1,
        snapshot: first,
        isRefreshInProgress: false
      )
      session.observe(snapshot: refreshed)
      #expect(session.snapshot == first)

      session.beginRefresh()
      session.observe(snapshot: refreshed)
      #expect(session.snapshot == refreshed)
      #expect(session.hasConsumedRefresh)

      session.beginRefresh()
      #expect(!session.isAwaitingRefresh)
      session.observe(snapshot: first)
      #expect(session.snapshot == refreshed)

      session.beginPresentation(
        generation: 2,
        snapshot: first,
        isRefreshInProgress: true
      )
      #expect(session.snapshot == first)
      #expect(session.isAwaitingRefresh)
      session.observe(snapshot: refreshed)
      #expect(session.snapshot == refreshed)
      #expect(!session.isAwaitingRefresh)
      #expect(session.hasConsumedRefresh)

      session.beginPresentation(
        generation: 3,
        snapshot: first,
        isRefreshInProgress: true
      )
      session.finishRefresh(snapshot: refreshed)
      #expect(session.snapshot == refreshed)
      #expect(session.hasConsumedRefresh)
    }

    @Test("runtime settings window exposes stable resizable geometry")
    func runtimeSettingsWindowGeometry() throws {
      let controller = RuntimeSettingsWindowController(rootView: Color.clear)
      let window = try #require(controller.window)

      #expect(window.styleMask.contains(.resizable))
      #expect(window.contentMinSize == CGSize(width: 680, height: 480))
      #expect(window.contentView?.bounds.width == 900)
      #expect(window.contentView?.bounds.height == 568)
      let minimumFrameSize = window.frameRect(
        forContentRect: NSRect(origin: .zero, size: window.contentMinSize)
      ).size
      #expect(
        controller.windowWillResize(window, to: CGSize(width: 500, height: 300))
          == minimumFrameSize
      )
      #expect(
        controller.windowWillResize(window, to: CGSize(width: 760, height: 520))
          == CGSize(width: 760, height: 520)
      )
      #expect(!window.isReleasedWhenClosed)
      #expect(window.collectionBehavior.contains(.managed))
      #expect(window.collectionBehavior.contains(.participatesInCycle))
    }

    @Test("settings red-close preserves one controller and root for ten reopen cycles")
    func runtimeSettingsWindowReopenLifecycle() throws {
      let activation = ApplicationWindowActivationCoordinator { _ in }
      let controller = RuntimeSettingsWindowController(
        rootView: Color.clear,
        activationCoordinator: activation
      )
      let window = try #require(controller.window)
      let contentController = try #require(window.contentViewController)

      for _ in 0..<10 {
        activation.windowWillPresent(window)
        #expect(controller.windowShouldClose(window) == false)
        #expect(activation.presentedWindowCount == 0)
        #expect(controller.window === window)
        #expect(window.contentViewController === contentController)
        #expect(!window.isReleasedWhenClosed)
        controller.prepareForPresentation()
      }
    }

    @Test("settings red-close cancels an in-flight request and immediate reopen stays fresh")
    func runtimeSettingsInFlightCloseIsDeterministic() async throws {
      var policies: [NSApplication.ActivationPolicy] = []
      let activation = ApplicationWindowActivationCoordinator { policy in
        policies.append(policy)
      }
      var syntheticState = (isVisible: true, isKey: false)
      var scheduledSettlement: (@MainActor () -> Void)?
      var presentationActionCount = 0
      let controller = RuntimeSettingsWindowController(
        rootView: Color.clear,
        activationCoordinator: activation,
        makePresentationAwaiter: { window in
          WindowPresentationAwaiter(
            window: window,
            stateProvider: { syntheticState },
            scheduleLivenessDeadline: {
              scheduledSettlement = $0
              return nil
            }
          )
        },
        presentationAction: { _ in presentationActionCount += 1 }
      )
      let window = try #require(controller.window)
      let pending = Task { @MainActor in
        await controller.presentAndWaitUntilKey()
      }

      while presentationActionCount == 0 { await Task.yield() }
      #expect(scheduledSettlement != nil)
      #expect(activation.presentedWindowCount == 1)
      #expect(policies == [.regular])

      #expect(controller.windowShouldClose(window) == false)

      syntheticState = (isVisible: true, isKey: true)
      let reopenedResult = await controller.presentAndWaitUntilKey()

      #expect(await pending.value == .cancelled)
      #expect(
        reopenedResult == .presented(isVisible: true, isKeyOrActive: true)
      )
      #expect(presentationActionCount == 2)
      #expect(activation.presentedWindowCount == 1)
      #expect(policies == [.regular, .accessory, .regular])

      #expect(controller.windowShouldClose(window) == false)
      #expect(activation.presentedWindowCount == 0)
      #expect(policies == [.regular, .accessory, .regular, .accessory])
    }

    @Test("workflow window is persistent and strongly retains its content window")
    func workflowWindowGeometry() throws {
      let controller = TrayWorkflowWindowController(rootView: Color.clear)
      let window = try #require(controller.window)
      let expectedContentSize = CGSize(width: 620, height: 500)
      let expectedFrameSize = window.frameRect(
        forContentRect: NSRect(origin: .zero, size: expectedContentSize)
      ).size

      #expect(window.styleMask.contains(.resizable))
      #expect(window.contentMinSize == CGSize(width: 520, height: 360))
      #expect(window.contentRect(forFrameRect: window.frame).size == expectedContentSize)
      #expect(window.contentView?.bounds.size == expectedContentSize)
      #expect(window.frame.size == expectedFrameSize)
      let minimumFrameSize = window.frameRect(
        forContentRect: NSRect(origin: .zero, size: window.contentMinSize)
      ).size
      #expect(
        controller.windowWillResize(window, to: CGSize(width: 112, height: 248))
          == minimumFrameSize
      )
      #expect(
        controller.windowWillResize(window, to: expectedFrameSize) == expectedFrameSize
      )
      #expect(!window.isReleasedWhenClosed)
      #expect(window.collectionBehavior.contains(.managed))
      #expect(window.collectionBehavior.contains(.participatesInCycle))
    }

    @Test("workflow root transitions preserve default and user-owned window geometry")
    func workflowDynamicRootDoesNotResizeWindow() throws {
      let probe = DynamicWindowGeometryProbe()
      let controller = TrayWorkflowWindowController(
        rootView: DynamicWindowGeometryProbeView(probe: probe)
      )
      let window = try #require(controller.window)
      let hostingController = try #require(
        window.contentViewController
          as? NSHostingController<DynamicWindowGeometryProbeView>
      )
      let initialFrame = window.frame

      #expect(hostingController.sizingOptions.isEmpty)
      #expect(
        window.contentRect(forFrameRect: initialFrame).size
          == CGSize(width: 620, height: 500)
      )

      probe.phase = .workflow
      settleDynamicHostingLayout(window)
      #expect(window.frame == initialFrame)
      #expect(window.contentView?.bounds.size == CGSize(width: 620, height: 500))

      let userContentSize = CGSize(width: 570, height: 420)
      window.setContentSize(userContentSize)
      let userFrame = window.frame
      probe.phase = .alternateWorkflow
      settleDynamicHostingLayout(window)
      #expect(window.frame == userFrame)
      #expect(window.contentView?.bounds.size == userContentSize)
    }

    @Test("workflow presentation repairs only an undersized content window")
    func workflowPresentationClampsUndersizedWindow() throws {
      let controller = TrayWorkflowWindowController(rootView: Color.clear)
      let window = try #require(controller.window)
      let minimumContentSize = CGSize(width: 520, height: 360)

      window.contentMinSize = .zero
      window.setContentSize(CGSize(width: 112, height: 248))
      #expect(window.contentMinSize == .zero)
      #expect(
        window.contentRect(forFrameRect: window.frame).size == CGSize(width: 112, height: 248))

      controller.prepareForPresentation()
      #expect(window.contentMinSize == minimumContentSize)
      #expect(window.contentRect(forFrameRect: window.frame).size == minimumContentSize)
      #expect(window.contentView?.bounds.size == minimumContentSize)

      let validUserContentSize = CGSize(width: 570, height: 420)
      window.setContentSize(validUserContentSize)
      let validUserFrame = window.frame

      controller.prepareForPresentation()
      #expect(window.contentRect(forFrameRect: window.frame).size == validUserContentSize)
      #expect(window.frame == validUserFrame)
    }

    @Test("settings root transitions preserve default and user-owned window geometry")
    func settingsDynamicRootDoesNotResizeWindow() throws {
      let probe = DynamicWindowGeometryProbe()
      let controller = RuntimeSettingsWindowController(
        rootView: DynamicWindowGeometryProbeView(probe: probe)
      )
      let window = try #require(controller.window)
      let hostingController = try #require(
        window.contentViewController
          as? NSHostingController<DynamicWindowGeometryProbeView>
      )
      let initialFrame = window.frame

      #expect(hostingController.sizingOptions.isEmpty)
      #expect(
        window.contentRect(forFrameRect: initialFrame).size
          == CGSize(width: 900, height: 568)
      )

      probe.phase = .workflow
      settleDynamicHostingLayout(window)
      #expect(window.frame == initialFrame)
      #expect(window.contentView?.bounds.size == CGSize(width: 900, height: 568))

      let userContentSize = CGSize(width: 760, height: 520)
      window.setContentSize(userContentSize)
      let userFrame = window.frame
      probe.phase = .alternateWorkflow
      settleDynamicHostingLayout(window)
      #expect(window.frame == userFrame)
      #expect(window.contentView?.bounds.size == userContentSize)
    }

    @Test("settings presentation repairs only an undersized content window")
    func settingsPresentationClampsUndersizedWindow() throws {
      let controller = RuntimeSettingsWindowController(rootView: Color.clear)
      let window = try #require(controller.window)
      let minimumContentSize = CGSize(width: 680, height: 480)

      window.contentMinSize = .zero
      window.setContentSize(CGSize(width: 500, height: 300))
      #expect(window.contentMinSize == .zero)
      #expect(
        window.contentRect(forFrameRect: window.frame).size == CGSize(width: 500, height: 300)
      )

      controller.prepareForPresentation()
      #expect(window.contentMinSize == minimumContentSize)
      #expect(window.contentRect(forFrameRect: window.frame).size == minimumContentSize)
      #expect(window.contentView?.bounds.size == minimumContentSize)

      let validUserContentSize = CGSize(width: 760, height: 520)
      window.setContentSize(validUserContentSize)
      let validUserFrame = window.frame

      controller.prepareForPresentation()
      #expect(window.contentRect(forFrameRect: window.frame).size == validUserContentSize)
      #expect(window.frame == validUserFrame)
    }

    @Test("closing the persistent safety host invokes its rollback hook")
    func workflowCloseInvokesSafetyHook() throws {
      var closeRequests = 0
      let controller = TrayWorkflowWindowController(
        rootView: Color.clear,
        onWindowClose: { closeRequests += 1 }
      )
      let window = try #require(controller.window)

      #expect(controller.windowShouldClose(window) == false)
      #expect(closeRequests == 1)
      #expect(!window.isReleasedWhenClosed)
    }

    @Test("workflow red-close cancels an in-flight request and immediate reopen stays fresh")
    func workflowInFlightCloseIsDeterministic() async throws {
      var policies: [NSApplication.ActivationPolicy] = []
      let activation = ApplicationWindowActivationCoordinator { policy in
        policies.append(policy)
      }
      var syntheticState = (isVisible: true, isKey: false)
      var scheduledSettlement: (@MainActor () -> Void)?
      var presentationActionCount = 0
      var closeRequests = 0
      let controller = TrayWorkflowWindowController(
        rootView: Color.clear,
        activationCoordinator: activation,
        onWindowClose: { closeRequests += 1 },
        makePresentationAwaiter: { window in
          WindowPresentationAwaiter(
            window: window,
            stateProvider: { syntheticState },
            scheduleLivenessDeadline: {
              scheduledSettlement = $0
              return nil
            }
          )
        },
        presentationAction: { _ in presentationActionCount += 1 }
      )
      let window = try #require(controller.window)
      let pending = Task { @MainActor in
        await controller.presentAndWaitUntilKey()
      }

      while presentationActionCount == 0 { await Task.yield() }
      #expect(scheduledSettlement != nil)
      #expect(activation.presentedWindowCount == 1)
      #expect(policies == [.regular])

      #expect(controller.windowShouldClose(window) == false)

      syntheticState = (isVisible: true, isKey: true)
      let reopenedResult = await controller.presentAndWaitUntilKey()

      #expect(await pending.value == .cancelled)
      #expect(
        reopenedResult == .presented(isVisible: true, isKeyOrActive: true)
      )
      #expect(presentationActionCount == 2)
      #expect(closeRequests == 1)
      #expect(activation.presentedWindowCount == 1)
      #expect(policies == [.regular, .accessory, .regular])

      #expect(controller.windowShouldClose(window) == false)
      #expect(closeRequests == 2)
      #expect(activation.presentedWindowCount == 0)
      #expect(policies == [.regular, .accessory, .regular, .accessory])
    }

    @Test("safety state records network scope and sanitized change summaries")
    func safetyStateDescribesNetworkChanges() {
      let state = SafetyConfirmationState(
        id: UUID(),
        profileID: UUID(),
        guardedGroups: [.network],
        changeSummaries: ["Apply the service IPv4 configuration with authorization."],
        secondsRemaining: 15
      )

      #expect(state.guardedGroups == [.network])
      #expect(state.changeSummaries.count == 1)
      #expect(state.secondsRemaining == 15)
    }

    @Test("ordinary app activation remains until the last destination is hidden")
    func persistentWindowActivationLifetime() {
      var policies: [NSApplication.ActivationPolicy] = []
      let activation = ApplicationWindowActivationCoordinator { policy in
        policies.append(policy)
      }
      let settings = NSWindow()
      let workflow = NSWindow()

      activation.windowWillPresent(settings)
      activation.windowWillPresent(settings)
      activation.windowWillPresent(workflow)
      #expect(activation.presentedWindowCount == 2)
      #expect(policies == [.regular])

      activation.windowDidHide(settings)
      activation.windowDidHide(settings)
      #expect(activation.presentedWindowCount == 1)
      #expect(policies == [.regular])

      activation.windowDidHide(workflow)
      #expect(activation.presentedWindowCount == 0)
      #expect(policies == [.regular, .accessory])
    }

    @Test("workflow red-close preserves one controller and root for ten reopen cycles")
    func workflowWindowReopenLifecycle() throws {
      let activation = ApplicationWindowActivationCoordinator { _ in }
      let controller = TrayWorkflowWindowController(
        rootView: Color.clear,
        activationCoordinator: activation
      )
      let window = try #require(controller.window)
      let contentController = try #require(window.contentViewController)

      for _ in 0..<10 {
        activation.windowWillPresent(window)
        #expect(controller.windowShouldClose(window) == false)
        #expect(activation.presentedWindowCount == 0)
        #expect(controller.window === window)
        #expect(window.contentViewController === contentController)
        #expect(!window.isReleasedWhenClosed)
        controller.prepareForPresentation()
      }
    }

    @Test("settings and profile destinations remain presentable across ten reopen cycles")
    func destinationCoordinatorReopensSettingsAndEditor() async throws {
      let fixture = UIAuditFixtures.fixture(.overview)
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      model.configureForUIAudit(fixture)
      let profile = try #require(fixture.profiles.first)
      let editor = ProfileEditorModel()
      editor.initialize(profiles: fixture.profiles, preferredProfileID: profile.id)
      let navigation = SettingsNavigationModel(selectedTab: .system)
      let presenter = ReopenableSettingsPresenter()
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: LocationPermissionController(
          allowsSystemRequests: false,
          syntheticAuthorizationStatus: .authorized
        ),
        profileEditor: editor
      )
      let coordinator = TrayDestinationCoordinator(
        model: model,
        profileEditor: editor,
        settingsNavigation: navigation,
        settingsController: presenter,
        workflowController: nil,
        presentation: presentation
      )

      for _ in 0..<10 {
        #expect(
          await coordinator.present(.settings) == .presented(isVisible: true, isKeyOrActive: true))
        presenter.close()
      }
      for _ in 0..<10 {
        #expect(
          await coordinator.present(.profileEditor(profile.id))
            == .presented(isVisible: true, isKeyOrActive: true)
        )
        presenter.close()
      }

      #expect(presenter.presentationCount == 20)
      #expect(navigation.selectedTab == .profiles)
      #expect(navigation.presentationGeneration == 20)
      #expect(editor.selectedProfileID == profile.id)
    }

    @Test("closing a destination before it becomes key reports cancellation")
    func destinationCloseBeforeKey() async {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      let waiter = WindowPresentationAwaiter(window: window)

      let result = await waiter.present {
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
      }

      #expect(result == .cancelled)
      #expect(!window.isVisible)
    }

    @Test("already-key and visible non-key destination states complete exactly once")
    func destinationStateTransitionsAreDeterministic() async {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      var state = (isVisible: true, isKey: true)
      var actionCount = 0
      var waiter = WindowPresentationAwaiter(window: window, stateProvider: { state })

      let alreadyKey = await waiter.present { actionCount += 1 }

      #expect(alreadyKey == .presented(isVisible: true, isKeyOrActive: true))
      #expect(actionCount == 1)

      state = (isVisible: true, isKey: false)
      var scheduledSettlement: (@MainActor () -> Void)?
      waiter = WindowPresentationAwaiter(
        window: window,
        stateProvider: { state },
        scheduleLivenessDeadline: {
          scheduledSettlement = $0
          return nil
        }
      )
      var actionStarted = false
      let pending = Task { @MainActor in
        await waiter.present { actionStarted = true }
      }
      while !actionStarted { await Task.yield() }
      #expect(scheduledSettlement != nil)
      state = (isVisible: true, isKey: true)
      NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
      NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

      #expect(await pending.value == .presented(isVisible: true, isKeyOrActive: true))
    }

    @Test("visible non-key destination resolves at the injected liveness deadline")
    func visibleNonKeyDestinationSettles() async throws {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      let state = (isVisible: true, isKey: false)
      var scheduledSettlement: (@MainActor () -> Void)?
      var actionStarted = false
      let waiter = WindowPresentationAwaiter(
        window: window,
        stateProvider: { state },
        scheduleLivenessDeadline: {
          scheduledSettlement = $0
          return nil
        }
      )
      let pending = Task { @MainActor in
        await waiter.present { actionStarted = true }
      }

      while !actionStarted { await Task.yield() }
      let settle = try #require(scheduledSettlement)
      settle()

      #expect(
        await pending.value == .presented(isVisible: true, isKeyOrActive: false)
      )
    }

    @Test("cancellation before waiter startup never performs the presentation action")
    func preCancelledWaiterDoesNotPresent() async {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      let waiter = WindowPresentationAwaiter(
        window: window,
        stateProvider: { (isVisible: true, isKey: false) }
      )
      var presentationActionCount = 0
      let pending = Task { @MainActor in
        await waiter.present { presentationActionCount += 1 }
      }

      pending.cancel()

      #expect(await pending.value == .cancelled)
      #expect(presentationActionCount == 0)
    }

    @Test("pre-cancelled controller request never starts its waiter or activation")
    func preCancelledControllerDoesNotPresent() async {
      var policies: [NSApplication.ActivationPolicy] = []
      let activation = ApplicationWindowActivationCoordinator { policy in
        policies.append(policy)
      }
      var awaiterFactoryCount = 0
      var presentationActionCount = 0
      let controller = RuntimeSettingsWindowController(
        rootView: Color.clear,
        activationCoordinator: activation,
        makePresentationAwaiter: { window in
          awaiterFactoryCount += 1
          return WindowPresentationAwaiter(
            window: window,
            stateProvider: { (isVisible: true, isKey: false) }
          )
        },
        presentationAction: { _ in presentationActionCount += 1 }
      )
      let pending = Task { @MainActor in
        await controller.presentAndWaitUntilKey()
      }

      pending.cancel()

      #expect(await pending.value == .cancelled)
      #expect(awaiterFactoryCount == 0)
      #expect(presentationActionCount == 0)
      #expect(activation.presentedWindowCount == 0)
      #expect(policies.isEmpty)
    }

    @Test("cancelling a controller presentation task finishes and balances activation")
    func controllerPresentationTaskCancellationIsDeterministic() async {
      var policies: [NSApplication.ActivationPolicy] = []
      let activation = ApplicationWindowActivationCoordinator { policy in
        policies.append(policy)
      }
      let state = (isVisible: true, isKey: false)
      var scheduledSettlement: (@MainActor () -> Void)?
      var actionStarted = false
      let controller = RuntimeSettingsWindowController(
        rootView: Color.clear,
        activationCoordinator: activation,
        makePresentationAwaiter: { window in
          WindowPresentationAwaiter(
            window: window,
            stateProvider: { state },
            scheduleLivenessDeadline: {
              scheduledSettlement = $0
              return nil
            }
          )
        },
        presentationAction: { _ in actionStarted = true }
      )
      let pending = Task { @MainActor in
        await controller.presentAndWaitUntilKey()
      }

      while !actionStarted { await Task.yield() }
      #expect(scheduledSettlement != nil)
      #expect(activation.presentedWindowCount == 1)
      pending.cancel()

      #expect(await pending.value == .cancelled)
      #expect(activation.presentedWindowCount == 0)
      #expect(policies == [.regular, .accessory])
      #expect(!controller.isPresentationVisible)
    }

    @Test("cancelling one coalesced caller preserves the shared presentation")
    func coalescedCallerCancellationIsConsumerLocal() async throws {
      var policies: [NSApplication.ActivationPolicy] = []
      let activation = ApplicationWindowActivationCoordinator { policy in
        policies.append(policy)
      }
      var state = (isVisible: true, isKey: false)
      var scheduledDeadline: (@MainActor () -> Void)?
      var presentationActionCount = 0
      let controller = RuntimeSettingsWindowController(
        rootView: Color.clear,
        activationCoordinator: activation,
        makePresentationAwaiter: { window in
          WindowPresentationAwaiter(
            window: window,
            stateProvider: { state },
            scheduleLivenessDeadline: {
              scheduledDeadline = $0
              return nil
            }
          )
        },
        presentationAction: { _ in presentationActionCount += 1 }
      )
      let window = try #require(controller.window)
      let first = Task { @MainActor in
        await controller.presentAndWaitUntilKey()
      }

      while controller.inFlightPresentationConsumerCount != 1
        || presentationActionCount != 1
        || scheduledDeadline == nil
      {
        await Task.yield()
      }
      #expect(presentationActionCount == 1)
      #expect(scheduledDeadline != nil)

      let second = Task { @MainActor in
        await controller.presentAndWaitUntilKey()
      }
      while controller.inFlightPresentationConsumerCount != 2 {
        await Task.yield()
      }

      second.cancel()

      #expect(await second.value == .cancelled)
      #expect(controller.inFlightPresentationConsumerCount == 1)
      #expect(presentationActionCount == 1)
      #expect(activation.presentedWindowCount == 1)
      #expect(policies == [.regular])

      state = (isVisible: true, isKey: true)
      NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

      #expect(
        await first.value == .presented(isVisible: true, isKeyOrActive: true)
      )
      #expect(controller.inFlightPresentationConsumerCount == 0)
      #expect(presentationActionCount == 1)
      #expect(activation.presentedWindowCount == 1)
      #expect(policies == [.regular])

      #expect(controller.windowShouldClose(window) == false)
      #expect(activation.presentedWindowCount == 0)
      #expect(policies == [.regular, .accessory])
    }

    @Test("application Settings command preserves an already-visible presentation")
    func commandSettingsUsesPersistentPresenter() async {
      let navigation = SettingsNavigationModel(selectedTab: .system)
      let presenter = ReopenableSettingsPresenter()

      let firstResult = await presentApplicationSettings(
        navigation: navigation,
        presenter: presenter
      )
      let secondResult = await presentApplicationSettings(
        navigation: navigation,
        presenter: presenter
      )

      #expect(firstResult == .presented(isVisible: true, isKeyOrActive: true))
      #expect(secondResult == .presented(isVisible: true, isKeyOrActive: true))
      #expect(navigation.selectedTab == .profiles)
      #expect(navigation.presentationGeneration == 1)
      #expect(presenter.presentationCount == 2)
    }
  }

  private actor RecordingConditionReaders: ConditionDisplayReading, ConditionAudioReading,
    ConditionNetworkReading, ConditionHardwareReading, ConditionLocationReading
  {
    private(set) var invocationCount = 0

    func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity> {
      invocationCount += 1
      return []
    }

    func readAudioFacts() async throws -> ConditionAudioFacts {
      invocationCount += 1
      return .init()
    }

    func readNetworkFacts() async throws -> ConditionNetworkFacts {
      invocationCount += 1
      return .init()
    }

    func readHardwareIdentifiers() async throws -> Set<String> {
      invocationCount += 1
      return []
    }

    func readAuthorizedLocation() async throws -> LocationRegion? {
      invocationCount += 1
      return nil
    }
  }

  @MainActor
  private final class ReopenableSettingsPresenter: RuntimeSettingsWindowPresenting {
    private(set) var presentationCount = 0
    private(set) var isPresentationVisible = false

    func presentAndWaitUntilKey() async -> TrayDestinationPresentation {
      presentationCount += 1
      isPresentationVisible = true
      return .presented(isVisible: true, isKeyOrActive: true)
    }

    func close() {
      isPresentationVisible = false
    }
  }

  private actor RecordingDiagnosticLog: DiagnosticLogStoring {
    enum Invocation: Equatable {
      case append
      case entries
      case removeAll
    }

    private(set) var invocations: [Invocation] = []

    func append(_ entry: DiagnosticEntry) async throws {
      invocations.append(.append)
    }

    func entries() async throws -> [DiagnosticEntry] {
      invocations.append(.entries)
      return []
    }

    func removeAll() async throws {
      invocations.append(.removeAll)
    }
  }

  @MainActor
  private final class RecordingLoginItemService: LoginItemServicing {
    private(set) var invocations: [String] = []

    var status: SMAppService.Status {
      invocations.append("status")
      return .notRegistered
    }

    func register() throws {
      invocations.append("register")
    }

    func unregister() throws {
      invocations.append("unregister")
    }
  }

  @MainActor
  private final class PermissionRequestRecorder {
    private(set) var invocations: [String] = []

    func requestAuthorization() {
      invocations.append("authorization")
    }

    func requestLocation() {
      invocations.append("location")
    }

    func openSystemSettings() -> Bool {
      invocations.append("settings")
      return true
    }
  }

  private enum DynamicWindowGeometryPhase {
    case noWorkflow
    case workflow
    case alternateWorkflow
  }

  @MainActor
  private final class DynamicWindowGeometryProbe: ObservableObject {
    @Published var phase: DynamicWindowGeometryPhase = .noWorkflow
  }

  private struct DynamicWindowGeometryProbeView: View {
    @ObservedObject var probe: DynamicWindowGeometryProbe

    var body: some View {
      Group {
        switch probe.phase {
        case .noWorkflow:
          Text("No Workflow")
        case .workflow:
          VStack {
            ForEach(0..<18, id: \.self) { index in
              Text("Workflow row \(index)")
            }
          }
          .frame(width: 311, height: 277)
        case .alternateWorkflow:
          HStack {
            ForEach(0..<8, id: \.self) { index in
              Text("\(index)")
            }
          }
          .frame(width: 419, height: 193)
        }
      }
    }
  }

  @MainActor
  private func settleDynamicHostingLayout(_ window: NSWindow) {
    // Pump actual AppKit/SwiftUI layout turns. Without explicit sizing
    // ownership, these intrinsic-size transitions resize NSWindow here and
    // reproduce the installed first-open regression.
    for _ in 0..<12 {
      window.contentView?.needsLayout = true
      window.contentView?.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
  }
#endif
