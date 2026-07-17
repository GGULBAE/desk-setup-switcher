import Combine
import CoreLocation
import SwiftUI
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("Workflow state and action policy", .serialized)
  @MainActor
  struct WorkflowStateActionPolicyTests {
    @Test("capture running and terminal phases expose one truthful non-execution action")
    func terminalCaptureActionsAreSingularAndNonExecuting() {
      let fixtures: [(TrayCapturePhase, PermissionWorkflowActionKind)] = [
        (.running, .closeWhileCaptureContinues),
        (.success("Captured"), .done),
        (.partial("Captured with omissions"), .done),
        (.failure("Capture failed"), .close),
      ]

      for workflow in allPermissionWorkflows {
        for (phase, expectedAction) in fixtures {
          let actions = PermissionWorkflowActionPolicy.actions(
            workflow: workflow,
            capturePhase: phase,
            isLocationAuthorized: false
          )
          #expect(actions.all == [expectedAction])
          #expect(!actions.all.contains(where: { $0.startsCapture }))
          #expect(!actions.all.contains(.continueWithLocationAccess))
          #expect(!actions.all.contains(.openSystemSettings))
        }
      }

      #expect(
        PermissionWorkflowActionPolicy.statusSymbol(for: .success("Captured"))
          == "checkmark.circle"
      )
      #expect(
        PermissionWorkflowActionPolicy.statusSymbol(for: .partial("Some items omitted"))
          == "exclamationmark.triangle"
      )
      #expect(
        PermissionWorkflowActionPolicy.statusSymbol(for: .partial("Some items omitted"))
          != "checkmark.circle"
      )
      #expect(
        PermissionWorkflowActionPolicy.statusSymbol(for: .failure("Failed"))
          == "xmark.octagon"
      )
    }

    @Test("authorized location replaces stale Settings CTA with capture")
    func authorizedLocationUsesCaptureAction() {
      for workflow in [TrayPermissionWorkflow.captureDenied, .systemSettings] {
        let denied = PermissionWorkflowActionPolicy.actions(
          workflow: workflow,
          capturePhase: .idle,
          isLocationAuthorized: false
        )
        #expect(denied.leading == .cancel)
        #expect(denied.trailing == [.captureWithoutWiFi, .openSystemSettings])

        let authorized = PermissionWorkflowActionPolicy.actions(
          workflow: workflow,
          capturePhase: .idle,
          isLocationAuthorized: true
        )
        #expect(authorized.leading == .cancel)
        #expect(authorized.trailing == [.captureCurrentSettings])
        #expect(!authorized.all.contains(.openSystemSettings))
      }

      let authorizedExplanation = PermissionWorkflowActionPolicy.actions(
        workflow: .captureExplanation,
        capturePhase: .idle,
        isLocationAuthorized: true
      )
      #expect(authorizedExplanation.leading == .cancel)
      #expect(authorizedExplanation.trailing == [.captureCurrentSettings])
      #expect(!authorizedExplanation.all.contains(.continueWithLocationAccess))
    }

    @Test("idle permission workflows retain only their relevant choices")
    func idlePermissionChoicesAreExplicit() {
      let explanation = PermissionWorkflowActionPolicy.actions(
        workflow: .captureExplanation,
        capturePhase: .idle,
        isLocationAuthorized: false
      )
      #expect(
        explanation.all
          == [.cancel, .captureWithoutWiFi, .continueWithLocationAccess]
      )

      let dirtyDraft = PermissionWorkflowActionPolicy.actions(
        workflow: .captureDirtyDraft,
        capturePhase: .idle,
        isLocationAuthorized: true
      )
      #expect(
        dirtyDraft.all
          == [.cancel, .discardChangesAndCapture, .saveAndCapture]
      )
    }

    @Test("workflow error footer never advertises a fake retry")
    func workflowErrorsOfferCloseOnly() {
      #expect(WorkflowErrorActionPolicy.actions == [.close])
    }

    @Test("permission and apply CTA copy stays exact in English and Korean")
    func localizedActionCopyMatchesVisibleOutcomes() {
      #expect(
        PermissionWorkflowActionCopy.title(
          for: .continueWithLocationAccess,
          languageCode: "en"
        ) == "Allow Location and Capture"
      )
      #expect(
        PermissionWorkflowActionCopy.title(
          for: .continueWithLocationAccess,
          languageCode: "ko"
        ) == "위치 접근 허용 후 캡처"
      )
      #expect(
        PermissionWorkflowCopy.title(
          for: .systemSettings,
          isLocationAuthorized: true,
          languageCode: "en"
        ) == "Location Access Is Ready"
      )
      #expect(
        PermissionWorkflowCopy.title(
          for: .systemSettings,
          isLocationAuthorized: true,
          languageCode: "ko"
        ) == "위치 접근을 사용할 수 있습니다"
      )
      #expect(
        PermissionWorkflowCopy.message(
          for: .captureDenied,
          isLocationAuthorized: true,
          languageCode: "en"
        )
          == "Location access is enabled. Capture the current settings to include the current Wi-Fi network."
      )
      #expect(
        PermissionWorkflowCopy.message(
          for: .captureExplanation,
          isLocationAuthorized: true,
          languageCode: "ko"
        )
          == "위치 접근이 허용되었습니다. 현재 Wi-Fi 네트워크를 포함하려면 현재 설정을 캡처하세요."
      )
      #expect(
        PermissionWorkflowFeedbackCopy.errorTitle(languageCode: "en")
          == "Could Not Continue"
      )
      #expect(
        PermissionWorkflowFeedbackCopy.errorTitle(languageCode: "ko")
          == "계속 진행할 수 없음"
      )
      #expect(
        PermissionWorkflowFeedbackCopy.recoveryGuidance(languageCode: "en")
          == "Close this window, or choose one of the available actions below."
      )
      #expect(
        PermissionWorkflowFeedbackCopy.recoveryGuidance(languageCode: "ko")
          == "이 창을 닫거나 아래에서 사용 가능한 작업을 다시 선택하세요."
      )
      #expect(
        PermissionWorkflowFeedbackCopy.savingTitle(languageCode: "en")
          == "Saving profile…"
      )
      #expect(
        PermissionWorkflowFeedbackCopy.savingTitle(languageCode: "ko")
          == "프로필 저장 중…"
      )
      #expect(
        PermissionWorkflowFeedbackCopy.savingCloseGuidance(languageCode: "en")
          == "Closing this window prevents capture from starting, even if the profile save finishes."
      )
      #expect(
        PermissionWorkflowFeedbackCopy.savingCloseGuidance(languageCode: "ko")
          == "이 창을 닫으면 프로필 저장이 끝나더라도 캡처는 시작되지 않습니다."
      )

      let englishNormal = ApplyPreviewActionCopy.actionTitle(
        for: .normal,
        languageCode: "en"
      )
      let englishForce = ApplyPreviewActionCopy.actionTitle(
        for: .force,
        languageCode: "en"
      )
      let koreanNormal = ApplyPreviewActionCopy.actionTitle(
        for: .normal,
        languageCode: "ko"
      )
      let koreanForce = ApplyPreviewActionCopy.actionTitle(
        for: .force,
        languageCode: "ko"
      )

      #expect(englishNormal == "Apply Profile")
      #expect(englishForce == "Apply Available Settings")
      #expect(koreanNormal == "프로필 적용")
      #expect(koreanForce == "사용 가능한 설정 적용")
      #expect(
        ApplyPreviewActionCopy.reviewNotice(
          for: .initial,
          actionTitle: englishNormal,
          languageCode: "en"
        ) == "This is a review. No setting changes until you press Apply Profile below."
      )
      #expect(
        ApplyPreviewActionCopy.reviewNotice(
          for: .refreshedSystemState,
          actionTitle: englishForce,
          languageCode: "en"
        )
          == "The Mac changed after this preview opened. Nothing was applied; review the refreshed plan and press Apply Available Settings again."
      )
      #expect(
        ApplyPreviewActionCopy.reviewNotice(
          for: .initial,
          actionTitle: koreanNormal,
          languageCode: "ko"
        ) == "현재 화면은 검토 단계입니다. 아래의 ‘프로필 적용’을 눌러야 설정이 변경됩니다."
      )
      #expect(
        ApplyPreviewActionCopy.reviewNotice(
          for: .refreshedSystemState,
          actionTitle: koreanForce,
          languageCode: "ko"
        )
          == "미리보기를 연 뒤 Mac 상태가 변경되었습니다. 아직 적용된 항목은 없습니다. 갱신된 계획을 검토한 후 ‘사용 가능한 설정 적용’을 다시 누르세요."
      )
    }

    @Test("location authorization updates permission copy and actions")
    func locationAuthorizationObservationDrivesPermissionPresentation() {
      let permission = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .denied
      )
      var publishedChangeCount = 0
      let observation = permission.objectWillChange.sink {
        publishedChangeCount += 1
      }
      defer { observation.cancel() }

      #expect(!permission.isAuthorized)
      #expect(
        PermissionWorkflowActionPolicy.actions(
          workflow: .systemSettings,
          capturePhase: .idle,
          isLocationAuthorized: permission.isAuthorized
        ).trailing == [.captureWithoutWiFi, .openSystemSettings]
      )
      #expect(
        PermissionWorkflowCopy.title(
          for: .systemSettings,
          isLocationAuthorized: permission.isAuthorized,
          languageCode: "en"
        ) == "Location Access Is Off"
      )

      permission.configureForUIAudit(authorizationStatus: .authorized)

      #expect(publishedChangeCount > 0)
      #expect(permission.isAuthorized)
      #expect(
        PermissionWorkflowActionPolicy.actions(
          workflow: .systemSettings,
          capturePhase: .idle,
          isLocationAuthorized: permission.isAuthorized
        ).trailing == [.captureCurrentSettings]
      )
      #expect(
        PermissionWorkflowCopy.title(
          for: .systemSettings,
          isLocationAuthorized: permission.isAuthorized,
          languageCode: "en"
        ) == "Location Access Is Ready"
      )
      #expect(
        PermissionWorkflowCopy.message(
          for: .systemSettings,
          isLocationAuthorized: permission.isAuthorized,
          languageCode: "en"
        ).contains("is enabled")
      )
    }

    @Test("open permission success stays terminal until one idempotent close consumes it")
    func permissionCaptureTerminalLifecycleIsStable() async throws {
      let fixture = UIAuditFixtures.fixture(.overview)
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      model.configureForUIAudit(fixture)
      let profile = try #require(fixture.profiles.first)
      let summary = try #require(fixture.captureSummary)
      #expect(summary.status == .complete)
      let permission = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .denied
      )
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: permission,
        profileEditor: ProfileEditorModel(),
        captureOperation: { .created(profile: profile, summary: summary) },
        successMessageDismissalDelay: .milliseconds(1)
      )
      presentation.setWorkflowDestination(.permission(.captureDenied))

      presentation.startCapture()
      for _ in 0..<100 where presentation.hasCaptureTask {
        await Task.yield()
      }
      guard case .success = presentation.capturePhase else {
        Issue.record("Expected a successful terminal capture phase")
        return
      }

      // A tray-only success timer must never rewrite an open workflow beneath
      // the user before they activate Done.
      try await Task.sleep(for: .milliseconds(20))
      guard case .success = presentation.capturePhase else {
        Issue.record("Open terminal workflow was rewritten by the tray timer")
        return
      }
      #expect(
        PermissionWorkflowActionPolicy.actions(
          workflow: .captureDenied,
          capturePhase: presentation.capturePhase,
          isLocationAuthorized: false
        ).all == [.done]
      )

      presentation.handleWorkflowWindowClose()
      #expect(presentation.capturePhase == .idle)
      #expect(presentation.workflowDestination == nil)

      // Native performClose invokes the same callback after the visible action;
      // a second cleanup pass is intentionally harmless.
      presentation.handleWorkflowWindowClose()
      #expect(presentation.capturePhase == .idle)
      #expect(presentation.workflowDestination == nil)

      presentation.setWorkflowDestination(.permission(.captureDenied))
      #expect(
        PermissionWorkflowActionPolicy.actions(
          workflow: .captureDenied,
          capturePhase: presentation.capturePhase,
          isLocationAuthorized: false
        ).trailing == [.captureWithoutWiFi, .openSystemSettings]
      )

      presentation.configureForUIAudit(capturePhase: .failure("Storage failed"))
      presentation.handleWorkflowWindowClose()
      #expect(presentation.capturePhase == .idle)
      #expect(presentation.workflowDestination == nil)
    }

    @Test("partial capture Review Permission opens a fresh actionable session")
    func partialCaptureReviewPermissionResetsTerminalState() async {
      let fixture = UIAuditFixtures.fixture(.overview)
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      model.configureForUIAudit(fixture)
      let permission = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .denied
      )
      let editor = ProfileEditorModel()
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: permission,
        profileEditor: editor
      )
      presentation.configureForUIAudit(
        capturePhase: .partial("Captured with location permission omitted.")
      )
      let workflowPresenter = ImmediateWorkflowPresenter()
      let coordinator = TrayDestinationCoordinator(
        model: model,
        profileEditor: editor,
        settingsNavigation: SettingsNavigationModel(selectedTab: .profiles),
        settingsController: nil,
        workflowController: workflowPresenter,
        presentation: presentation
      )

      let result = await coordinator.present(.permission(.systemSettings))

      #expect(result == .presented(isVisible: true, isKeyOrActive: true))
      #expect(workflowPresenter.presentationCount == 1)
      #expect(presentation.capturePhase == .idle)
      #expect(presentation.workflowDestination == .permission(.systemSettings))
      #expect(
        PermissionWorkflowActionPolicy.actions(
          workflow: .systemSettings,
          capturePhase: presentation.capturePhase,
          isLocationAuthorized: permission.isAuthorized
        ).all == [.cancel, .captureWithoutWiFi, .openSystemSettings]
      )
    }

    @Test("denied location never captures and authorization clears its stale notice")
    func deniedLocationRequiresExplicitCaptureWithoutWiFi() async {
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      let permission = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .denied
      )
      var captureInvocationCount = 0
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: permission,
        profileEditor: ProfileEditorModel(),
        captureOperation: {
          captureInvocationCount += 1
          return .rejected(message: "Capture must not start after denial.")
        }
      )
      presentation.setWorkflowDestination(.permission(.captureExplanation))

      presentation.requestLocationAccessAndCapture()
      #expect(await eventually { !presentation.hasPermissionTask })

      #expect(captureInvocationCount == 0)
      #expect(presentation.capturePhase == .idle)
      #expect(presentation.workflowDestination == .permission(.captureDenied))
      #expect(presentation.handoffError == nil)
      #expect(presentation.permissionWorkflowNotice != nil)
      #expect(
        PermissionWorkflowActionPolicy.actions(
          workflow: .captureDenied,
          capturePhase: presentation.capturePhase,
          isLocationAuthorized: permission.isAuthorized
        ).all == [.cancel, .captureWithoutWiFi, .openSystemSettings]
      )

      permission.configureForUIAudit(authorizationStatus: .authorized)
      #expect(await eventually { presentation.permissionWorkflowNotice == nil })
      #expect(
        PermissionWorkflowCopy.title(
          for: .captureDenied,
          isLocationAuthorized: permission.isAuthorized,
          languageCode: "en"
        ) == "Location Access Is Ready"
      )
      #expect(
        PermissionWorkflowActionPolicy.actions(
          workflow: .captureDenied,
          capturePhase: presentation.capturePhase,
          isLocationAuthorized: permission.isAuthorized
        ).all == [.cancel, .captureCurrentSettings]
      )
    }

    @Test("dirty capture save failure stays visible with Close and real choices")
    func permissionSaveFailureHasVisibleRecovery() async throws {
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      let profile = try #require(model.profiles.first)
      let editor = ProfileEditorModel()
      editor.initialize(profiles: model.profiles, preferredProfileID: profile.id)
      #expect(editor.updateDraft { $0.name += " Updated" })
      let error = appLocalized("A local profile storage operation failed.")
      var captureInvocationCount = 0
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: LocationPermissionController(
          allowsSystemRequests: false,
          syntheticAuthorizationStatus: .authorized
        ),
        profileEditor: editor,
        captureOperation: {
          captureInvocationCount += 1
          return .rejected(message: "Capture must not start after a failed save.")
        },
        saveOperation: { _ in .rejected(message: error) }
      )
      presentation.beginPermissionWorkflow(.captureDirtyDraft)

      presentation.saveDraftThenCapture()
      #expect(await eventually { !presentation.hasWorkflowTask })

      #expect(captureInvocationCount == 0)
      #expect(presentation.capturePhase == .idle)
      #expect(presentation.workflowDestination == .permission(.captureDirtyDraft))
      #expect(presentation.permissionWorkflowError == error)
      #expect(presentation.permissionWorkflowNotice == nil)
      #expect(presentation.handoffError == error)
      #expect(editor.activity == .error(error))

      let actions = PermissionWorkflowActionPolicy.actions(
        workflow: .captureDirtyDraft,
        capturePhase: presentation.capturePhase,
        isLocationAuthorized: true,
        hasWorkflowError: presentation.permissionWorkflowError != nil
      )
      #expect(actions.leading == .close)
      #expect(actions.trailing == [.discardChangesAndCapture, .saveAndCapture])

      presentation.handleWorkflowWindowClose()
      #expect(presentation.workflowDestination == nil)
      #expect(presentation.permissionWorkflowError == nil)
      // The tray can still explain the failed operation after the workflow
      // closes; a fresh permission session consumes that prior handoff error.
      #expect(presentation.handoffError == error)

      presentation.beginPermissionWorkflow(.captureDirtyDraft)
      #expect(presentation.permissionWorkflowError == nil)
      #expect(presentation.handoffError == nil)
    }

    @Test("System Settings launch failure stays visible and a real retry clears it")
    func permissionSystemSettingsFailureHasVisibleRetry() {
      let openGate = SystemSettingsOpenGate()
      let permission = LocationPermissionController(
        allowsSystemRequests: true,
        syntheticAuthorizationStatus: .denied,
        openSystemSettingsApplication: openGate.open
      )
      let presentation = TrayPresentationModel(
        model: UIAuditFixtures.makeModel(configuration: .disabled),
        locationPermission: permission,
        profileEditor: ProfileEditorModel()
      )
      presentation.beginPermissionWorkflow(.systemSettings)

      presentation.openLocationSystemSettings()

      let error = appLocalized("macOS System Settings could not be opened.")
      #expect(openGate.invocationCount == 1)
      #expect(presentation.permissionWorkflowError == error)
      #expect(presentation.permissionWorkflowNotice == nil)
      #expect(presentation.handoffError == error)
      let failedActions = PermissionWorkflowActionPolicy.actions(
        workflow: .systemSettings,
        capturePhase: presentation.capturePhase,
        isLocationAuthorized: false,
        hasWorkflowError: presentation.permissionWorkflowError != nil
      )
      #expect(failedActions.leading == .close)
      #expect(failedActions.trailing == [.captureWithoutWiFi, .openSystemSettings])

      openGate.shouldSucceed = true
      presentation.openLocationSystemSettings()

      #expect(openGate.invocationCount == 2)
      #expect(permission.lastError == nil)
      #expect(presentation.permissionWorkflowError == nil)
      #expect(presentation.handoffError == nil)
      let retriedActions = PermissionWorkflowActionPolicy.actions(
        workflow: .systemSettings,
        capturePhase: presentation.capturePhase,
        isLocationAuthorized: false,
        hasWorkflowError: false
      )
      #expect(retriedActions.leading == .cancel)
      #expect(retriedActions.trailing == [.captureWithoutWiFi, .openSystemSettings])
    }

    @Test("cancel and immediate permission retry keeps the new task owned")
    func permissionTaskStaleClearCannotEraseRetry() async {
      var accessRequestCount = 0
      let permission = LocationPermissionController(
        allowsSystemRequests: true,
        syntheticAuthorizationStatus: .notDetermined,
        requestWhenInUseAuthorization: { accessRequestCount += 1 }
      )
      let captureGate = WorkflowCaptureGate()
      let presentation = TrayPresentationModel(
        model: UIAuditFixtures.makeModel(configuration: .disabled),
        locationPermission: permission,
        profileEditor: ProfileEditorModel(),
        captureOperation: {
          await captureGate.enterAndWait()
          return .rejected(message: "Synthetic completion")
        }
      )
      presentation.setWorkflowDestination(.permission(.captureExplanation))

      presentation.requestLocationAccessAndCapture()
      #expect(
        await eventually {
          accessRequestCount == 1 && presentation.hasPermissionTask
        }
      )
      presentation.cancelPermissionWorkflow()
      presentation.requestLocationAccessAndCapture()
      #expect(
        await eventually {
          accessRequestCount == 2 && presentation.hasPermissionTask
        }
      )
      for _ in 0..<20 {
        await Task.yield()
      }
      #expect(presentation.hasPermissionTask)

      permission.configureForUIAudit(authorizationStatus: .authorized)
      await captureGate.waitUntilEntered()
      #expect(await eventually { !presentation.hasPermissionTask })
      #expect(presentation.hasCaptureTask)

      await captureGate.release()
      #expect(await eventually { !presentation.hasCaptureTask })
      #expect(presentation.capturePhase == .failure("Synthetic completion"))
    }

    @Test("native close rejects a late failed save without resurrecting apply UI")
    func nativeCloseSuppressesLateSaveFailure() async throws {
      try await assertNativeCloseSuppressesLateSave(succeeds: false)
    }

    @Test("native close rejects a late successful save without preparing apply")
    func nativeCloseSuppressesLateSaveSuccess() async throws {
      try await assertNativeCloseSuppressesLateSave(succeeds: true)
    }

    @Test("closing dirty capture during save blocks a late capture launch")
    func nativeCloseSuppressesLateSaveThenCapture() async throws {
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      let profile = try #require(model.profiles.first)
      let editor = ProfileEditorModel()
      editor.initialize(profiles: model.profiles, preferredProfileID: profile.id)
      #expect(editor.updateDraft { $0.name += " Updated" })
      let saveGate = WorkflowSaveGate()
      var captureInvocationCount = 0
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: LocationPermissionController(
          allowsSystemRequests: false,
          syntheticAuthorizationStatus: .authorized
        ),
        profileEditor: editor,
        captureOperation: {
          captureInvocationCount += 1
          return .rejected(message: "Capture must remain closed.")
        },
        saveOperation: { candidate in await saveGate.save(candidate) }
      )
      presentation.setWorkflowDestination(.permission(.captureDirtyDraft))

      presentation.saveDraftThenCapture()
      await saveGate.waitUntilEntered()
      #expect(presentation.hasWorkflowTask)
      #expect(editor.activity == .saving)
      let savingActions = PermissionWorkflowActionPolicy.actions(
        workflow: .captureDirtyDraft,
        capturePhase: presentation.capturePhase,
        isLocationAuthorized: true,
        isWorkflowTaskInFlight: presentation.hasWorkflowTask
      )
      #expect(savingActions.all == [.close])

      // A rapid second choice cannot race the in-flight persistence or launch
      // capture with a draft that the first choice is still saving.
      presentation.discardDraftThenCapture()
      presentation.saveDraftThenCapture()
      for _ in 0..<20 {
        await Task.yield()
      }
      #expect(await saveGate.invocationCount == 1)
      #expect(captureInvocationCount == 0)
      #expect(presentation.hasWorkflowTask)
      #expect(editor.activity == .saving)

      presentation.handleWorkflowWindowClose()
      #expect(presentation.workflowDestination == nil)
      #expect(!presentation.hasWorkflowTask)
      #expect(editor.activity == .changed)

      await saveGate.release(succeeds: true)
      await saveGate.waitUntilReturned()
      for _ in 0..<20 {
        await Task.yield()
      }
      #expect(captureInvocationCount == 0)
      #expect(presentation.capturePhase == .idle)
      #expect(presentation.handoffError == nil)
      #expect(editor.isDirty)
    }

    @Test("closing an apply error discards saved retry state and permits a fresh decision")
    func closingApplyErrorClearsRetryState() async throws {
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      let profile = try #require(model.profiles.first)
      let editor = ProfileEditorModel()
      editor.initialize(profiles: model.profiles, preferredProfileID: profile.id)
      #expect(
        editor.updateDraft { draft in
          draft.name += " Updated"
        }
      )
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: LocationPermissionController(
          allowsSystemRequests: false,
          syntheticAuthorizationStatus: .authorized
        ),
        profileEditor: editor
      )

      presentation.setWorkflowDestination(.applyPreview(profile.id, .normal))
      presentation.beginApplyWorkflow(profileID: profile.id, mode: .normal)
      let prompt = try #require(presentation.applyDraftPrompt)
      presentation.saveDraftThenApply(prompt)
      for _ in 0..<100 where presentation.applyDraftError == nil {
        await Task.yield()
      }
      #expect(presentation.applyDraftError != nil)

      presentation.closeApplyWorkflowAfterError()
      #expect(presentation.applyDraftError == nil)
      #expect(presentation.applyDraftPrompt == nil)

      // A stale saved retry must not reappear after the workflow is closed.
      presentation.dismissApplyDraftError()
      #expect(presentation.applyDraftPrompt == nil)

      presentation.beginApplyWorkflow(profileID: profile.id, mode: .normal)
      #expect(presentation.applyDraftError == nil)
      #expect(presentation.applyDraftPrompt != nil)
    }

    @Test("native workflow red-close clears apply error retry and pending selection")
    func nativeCloseClearsApplyErrorState() async throws {
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      let profiles = model.profiles
      let openProfile = try #require(profiles.first)
      let targetProfile = try #require(profiles.dropFirst().first)
      let editor = ProfileEditorModel()
      editor.initialize(profiles: profiles, preferredProfileID: openProfile.id)
      #expect(editor.updateDraft { $0.name += " Updated" })
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: LocationPermissionController(
          allowsSystemRequests: false,
          syntheticAuthorizationStatus: .authorized
        ),
        profileEditor: editor
      )

      presentation.setWorkflowDestination(.applyPreview(targetProfile.id, .normal))
      presentation.beginApplyWorkflow(profileID: targetProfile.id, mode: .normal)
      let prompt = try #require(presentation.applyDraftPrompt)
      guard case .otherDraft = prompt.kind else {
        Issue.record("Expected another-profile draft decision")
        return
      }
      #expect(editor.session.pendingSelection != nil)
      presentation.saveDraftThenApply(prompt)
      for _ in 0..<100 where presentation.applyDraftError == nil {
        await Task.yield()
      }
      #expect(presentation.applyDraftError != nil)
      #expect(editor.session.pendingSelection != nil)

      let controller = TrayWorkflowWindowController(
        rootView: Color.clear,
        onWindowClose: { presentation.handleWorkflowWindowClose() }
      )
      let window = try #require(controller.window)
      #expect(controller.windowShouldClose(window) == false)

      #expect(presentation.workflowDestination == nil)
      #expect(presentation.applyDraftError == nil)
      #expect(presentation.applyDraftPrompt == nil)
      #expect(editor.session.pendingSelection == nil)

      // Repeated delegate delivery or a button-close followed by performClose
      // cannot resurrect or further mutate the abandoned decision.
      #expect(controller.windowShouldClose(window) == false)
      #expect(presentation.workflowDestination == nil)
      #expect(presentation.applyDraftError == nil)
      #expect(editor.session.pendingSelection == nil)
    }

    private func assertNativeCloseSuppressesLateSave(succeeds: Bool) async throws {
      let model = UIAuditFixtures.makeModel(configuration: .disabled)
      let profiles = model.profiles
      let openProfile = try #require(profiles.first)
      let targetProfile = try #require(profiles.dropFirst().first)
      let editor = ProfileEditorModel()
      editor.initialize(profiles: profiles, preferredProfileID: openProfile.id)
      #expect(editor.updateDraft { $0.name += " Updated" })
      let saveGate = WorkflowSaveGate()
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: LocationPermissionController(
          allowsSystemRequests: false,
          syntheticAuthorizationStatus: .authorized
        ),
        profileEditor: editor,
        saveOperation: { candidate in await saveGate.save(candidate) }
      )
      presentation.setWorkflowDestination(.applyPreview(targetProfile.id, .normal))
      presentation.beginApplyWorkflow(profileID: targetProfile.id, mode: .normal)
      let prompt = try #require(presentation.applyDraftPrompt)
      guard case .otherDraft = prompt.kind else {
        Issue.record("Expected another-profile draft decision")
        return
      }

      presentation.saveDraftThenApply(prompt)
      await saveGate.waitUntilEntered()
      #expect(presentation.hasWorkflowTask)
      #expect(editor.activity == .saving)
      #expect(editor.session.pendingSelection?.profileID == targetProfile.id)

      let controller = TrayWorkflowWindowController(
        rootView: Color.clear,
        onWindowClose: { presentation.handleWorkflowWindowClose() }
      )
      let window = try #require(controller.window)
      #expect(controller.windowShouldClose(window) == false)
      #expect(presentation.workflowDestination == nil)
      #expect(!presentation.hasWorkflowTask)
      #expect(presentation.applyDraftError == nil)
      #expect(presentation.applyDraftPrompt == nil)
      #expect(editor.session.pendingSelection == nil)
      #expect(editor.activity == .changed)
      #expect(model.pendingApply == nil)

      await saveGate.release(succeeds: succeeds)
      await saveGate.waitUntilReturned()
      for _ in 0..<20 {
        await Task.yield()
      }
      #expect(presentation.workflowDestination == nil)
      #expect(presentation.applyDraftError == nil)
      #expect(presentation.applyDraftPrompt == nil)
      #expect(editor.session.pendingSelection == nil)
      #expect(editor.selectedProfileID == openProfile.id)
      #expect(editor.activity == .changed)
      #expect(model.pendingApply == nil)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
      for _ in 0..<2_000 {
        if condition() { return true }
        await Task.yield()
      }
      return condition()
    }

    private var allPermissionWorkflows: [TrayPermissionWorkflow] {
      [.captureExplanation, .captureDenied, .captureDirtyDraft, .systemSettings]
    }
  }

  @MainActor
  private final class ImmediateWorkflowPresenter: TrayWorkflowWindowPresenting {
    private(set) var presentationCount = 0

    func presentAndWaitUntilKey() async -> TrayDestinationPresentation {
      presentationCount += 1
      return .presented(isVisible: true, isKeyOrActive: true)
    }
  }

  private actor WorkflowCaptureGate {
    private var hasEntered = false
    private var isReleased = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
      hasEntered = true
      let waiters = entryWaiters
      entryWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      guard !isReleased else { return }
      await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
      guard !hasEntered else { return }
      await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
      isReleased = true
      let waiters = releaseWaiters
      releaseWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
    }
  }

  @MainActor
  private final class SystemSettingsOpenGate {
    var shouldSucceed = false
    private(set) var invocationCount = 0

    func open() -> Bool {
      invocationCount += 1
      return shouldSucceed
    }
  }

  private actor WorkflowSaveGate {
    private(set) var invocationCount = 0
    private var candidate: DeskProfile?
    private var continuation: CheckedContinuation<ProfileSaveResult, Never>?
    private var hasEntered = false
    private var hasReturned = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var returnWaiters: [CheckedContinuation<Void, Never>] = []

    func save(_ candidate: DeskProfile) async -> ProfileSaveResult {
      invocationCount += 1
      self.candidate = candidate
      hasEntered = true
      let waiters = entryWaiters
      entryWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      let result = await withCheckedContinuation { continuation = $0 }
      hasReturned = true
      let completedWaiters = returnWaiters
      returnWaiters.removeAll()
      for waiter in completedWaiters {
        waiter.resume()
      }
      return result
    }

    func waitUntilEntered() async {
      guard !hasEntered else { return }
      await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release(succeeds: Bool) {
      guard let candidate, let continuation else { return }
      self.continuation = nil
      continuation.resume(
        returning: succeeds
          ? .saved(candidate)
          : .rejected(message: "Synthetic save failure")
      )
    }

    func waitUntilReturned() async {
      guard !hasReturned else { return }
      await withCheckedContinuation { returnWaiters.append($0) }
    }
  }
#endif
