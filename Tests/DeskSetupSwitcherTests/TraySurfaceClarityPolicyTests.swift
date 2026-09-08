import Foundation
import Testing

@testable import DeskSetupPresentation
@testable import DeskSetupSwitcher

@Suite("Tray and profile surface clarity policies")
struct TraySurfaceClarityPolicyTests {
  @Test("compact profile actions ship concise English and Korean labels")
  func compactProfileActionCopy() {
    for (language, apply, edit) in [("en", "Apply", "Edit"), ("ko", "적용하기", "수정하기")] {
      #expect(
        appLocalizedRuntime(TrayProfileCardPolicy.applyLabelKey, languageCode: language) == apply)
      #expect(
        appLocalizedRuntime(TrayProfileCardPolicy.editLabelKey, languageCode: language) == edit)
    }
  }

  @Test("passive profile explanations become blank while actionable reasons remain")
  func compactProfileStatusSlot() {
    for reason: PrimaryApplyDisabledReason? in [nil, .alreadyMatches, .noAvailableOperations] {
      #expect(TrayProfileCardPolicy.visibleDisabledReason(reason) == nil)
    }
    for reason: PrimaryApplyDisabledReason in [
      .preparing, .readinessRefreshing, .applying, .transactionInProgress,
      .pendingSafetyConfirmation, .noIncludedSettings, .temporarilyUnavailable,
    ] {
      #expect(TrayProfileCardPolicy.visibleDisabledReason(reason) == reason)
    }
  }

  @Test("short Apply and direct trash keep preview and confirmation routing")
  func compactProfileActionRouting() {
    let profileID = UUID()
    for kind: PrimaryApplyActionKind in [.normal, .availableItems] {
      let state = PrimaryApplyActionState(kind: kind, isEnabled: true)
      #expect(
        TrayProfileCardPolicy.applyAction(profileID: profileID, state: state)
          == .openApplyPreview(profileID, kind.mode))
    }
    #expect(TrayProfileCardPolicy.deleteAction(profileID: profileID) == .requestDelete(profileID))
    #expect(TrayProfileCardPolicy.deleteAction(profileID: profileID).disposition == .stayOpen)
  }

  @Test("pristine empty tray exposes one primary capture action instead of a header icon")
  func pristineEmptyTrayCapturePlacement() {
    let placement = TrayCaptureAffordancePolicy.placement(
      profileCount: 0,
      capturePhase: .idle,
      hasCaptureSummary: false,
      hasApplySummary: false,
      hasHandoffError: false
    )

    #expect(placement == .emptyStatePrimary)
    #expect(placement.visibleActionCount == 1)
    #expect(placement.showsEmptyStatePrimary)
    #expect(!placement.showsCompactHeader)
    #expect(placement.focusTarget == .emptyState)
  }

  @Test("profiles and non-idle empty states retain one compact header capture action")
  func compactHeaderCapturePlacement() {
    let fixtures: [TrayCaptureAffordancePlacement] = [
      TrayCaptureAffordancePolicy.placement(
        profileCount: 1,
        capturePhase: .idle,
        hasCaptureSummary: false,
        hasApplySummary: false,
        hasHandoffError: false
      ),
      TrayCaptureAffordancePolicy.placement(
        profileCount: 0,
        capturePhase: .running,
        hasCaptureSummary: false,
        hasApplySummary: false,
        hasHandoffError: false
      ),
      TrayCaptureAffordancePolicy.placement(
        profileCount: 0,
        capturePhase: .failure("Synthetic failure"),
        hasCaptureSummary: false,
        hasApplySummary: false,
        hasHandoffError: false
      ),
      TrayCaptureAffordancePolicy.placement(
        profileCount: 0,
        capturePhase: .success("Synthetic success"),
        hasCaptureSummary: false,
        hasApplySummary: false,
        hasHandoffError: false
      ),
      TrayCaptureAffordancePolicy.placement(
        profileCount: 0,
        capturePhase: .partial("Synthetic partial result"),
        hasCaptureSummary: false,
        hasApplySummary: false,
        hasHandoffError: false
      ),
      TrayCaptureAffordancePolicy.placement(
        profileCount: 0,
        capturePhase: .idle,
        hasCaptureSummary: true,
        hasApplySummary: false,
        hasHandoffError: false
      ),
      TrayCaptureAffordancePolicy.placement(
        profileCount: 0,
        capturePhase: .idle,
        hasCaptureSummary: false,
        hasApplySummary: true,
        hasHandoffError: false
      ),
      TrayCaptureAffordancePolicy.placement(
        profileCount: 0,
        capturePhase: .idle,
        hasCaptureSummary: false,
        hasApplySummary: false,
        hasHandoffError: true
      ),
    ]

    for placement in fixtures {
      #expect(placement == .compactHeader)
      #expect(placement.visibleActionCount == 1)
      #expect(placement.showsCompactHeader)
      #expect(!placement.showsEmptyStatePrimary)
      #expect(placement.focusTarget == .capture)
    }
  }

  @Test("primary capture copy has matching English and Korean meaning")
  func primaryCaptureLocalizationParity() {
    #expect(
      appLocalizedRuntime(TrayAccessibilityCopy.captureLabel, languageCode: "en")
        == "Capture Current Settings"
    )
    #expect(
      appLocalizedRuntime(TrayAccessibilityCopy.captureLabel, languageCode: "ko")
        == "현재 설정 캡처"
    )
    #expect(
      appLocalizedRuntime(TrayAccessibilityCopy.captureHelp, languageCode: "en")
        == "Reads current settings without changing the Mac and creates a profile."
    )
    #expect(
      appLocalizedRuntime(TrayAccessibilityCopy.captureHelp, languageCode: "ko")
        == "Mac 설정을 변경하지 않고 현재 설정을 읽어 프로필을 만듭니다."
    )
  }

  @Test("quit uses a power symbol instead of a popover-close symbol")
  func quitSymbolCommunicatesApplicationExit() {
    #expect(TrayHeaderIconPolicy.quitSystemImage.hasPrefix("power"))
    #expect(TrayHeaderIconPolicy.quitSystemImage != "xmark")
  }

  @Test("terminal capture results use one card when a summary is available")
  func terminalCaptureResultVisibility() {
    #expect(
      TrayCaptureStatusPresentationPolicy.showsStatusBanner(
        for: .running,
        hasCaptureSummary: false
      )
    )
    #expect(
      TrayCaptureStatusPresentationPolicy.showsStatusBanner(
        for: .success("Saved"),
        hasCaptureSummary: true
      )
    )
    #expect(
      !TrayCaptureStatusPresentationPolicy.showsStatusBanner(
        for: .partial("Partially saved"),
        hasCaptureSummary: true
      )
    )
    #expect(
      !TrayCaptureStatusPresentationPolicy.showsStatusBanner(
        for: .failure("Failed"),
        hasCaptureSummary: true
      )
    )
    #expect(
      TrayCaptureStatusPresentationPolicy.showsStatusBanner(
        for: .failure("Failed without details"),
        hasCaptureSummary: false
      )
    )
  }

  @Test("empty tray becomes scrollable at accessibility text sizes")
  func emptyTrayAccessibilityContainment() {
    let standard = TrayBodyPresentationPolicy.usesStaticEmptyBody(
      profileCount: 0,
      hasCaptureSummary: false,
      hasApplySummary: false,
      hasHandoffError: false,
      capturePhase: .idle,
      usesAccessibilityTextSize: false
    )
    let accessibility = TrayBodyPresentationPolicy.usesStaticEmptyBody(
      profileCount: 0,
      hasCaptureSummary: false,
      hasApplySummary: false,
      hasHandoffError: false,
      capturePhase: .idle,
      usesAccessibilityTextSize: true
    )

    #expect(standard)
    #expect(!accessibility)
  }

  @Test("fixed-width tray stacks header and profile titles at accessibility sizes")
  func accessibilityLayoutProtectsActions() {
    #expect(!TrayAdaptiveLayoutPolicy.usesStackedHeader(for: .large))
    #expect(!TrayAdaptiveLayoutPolicy.usesStackedProfileCard(for: .large))
    #expect(TrayAdaptiveLayoutPolicy.usesStackedHeader(for: .accessibility1))
    #expect(TrayAdaptiveLayoutPolicy.usesStackedHeader(for: .accessibility3))
    #expect(TrayAdaptiveLayoutPolicy.usesStackedProfileCard(for: .accessibility1))
    #expect(TrayAdaptiveLayoutPolicy.usesStackedProfileCard(for: .accessibility3))
    #expect(TrayAdaptiveLayoutPolicy.usesStackedProfileCard(for: .accessibility4))
    #expect(TrayAdaptiveLayoutPolicy.usesStackedProfileCard(for: .accessibility5))
  }

  @Test("profile empty-state copy names only visible actions")
  func profileEmptyStateCopyUsesReachablePaths() {
    let noProfiles = ProfileEditorEmptyStateCopy.noProfilesDescription.lowercased()
    let noSelection = ProfileEditorEmptyStateCopy.noSelectionDescription.lowercased()

    #expect(noProfiles.contains("tray"))
    #expect(noProfiles.contains("capture"))
    #expect(noProfiles.contains("+"))
    #expect(!noProfiles.contains("update"))
    #expect(!noProfiles.contains("refresh"))
    #expect(!noProfiles.contains("snapshot"))
    #expect(noSelection.contains("select"))
    #expect(noSelection.contains("+"))
  }

  @Test("profile empty-state copy ships in English and Korean")
  func profileEmptyStateCopyLocalizationParity() {
    #expect(
      appLocalizedRuntime(
        ProfileEditorEmptyStateCopy.noProfilesDescription,
        languageCode: "en"
      ) == "Capture from the tray, or choose + to create a blank profile."
    )
    #expect(
      appLocalizedRuntime(
        ProfileEditorEmptyStateCopy.noProfilesDescription,
        languageCode: "ko"
      ) == "트레이에서 캡처하거나 +를 눌러 빈 프로필을 만드세요."
    )
    #expect(
      appLocalizedRuntime(
        ProfileEditorEmptyStateCopy.noSelectionDescription,
        languageCode: "en"
      ) == "Select a profile, or choose + to create one."
    )
    #expect(
      appLocalizedRuntime(
        ProfileEditorEmptyStateCopy.noSelectionDescription,
        languageCode: "ko"
      ) == "프로필을 선택하거나 +를 눌러 새 프로필을 만드세요."
    )
  }
}
