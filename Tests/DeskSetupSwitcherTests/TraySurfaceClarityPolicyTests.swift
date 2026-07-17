import Testing

@testable import DeskSetupSwitcher

@Suite("Tray and profile surface clarity policies")
struct TraySurfaceClarityPolicyTests {
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
