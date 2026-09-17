import XCTest

@testable import DeskSetupSwitcher

final class UserFacingLocalizationTests: XCTestCase {
  func testUnknownRuntimeValueRemainsVerbatim() {
    let value = "Synthetic Device Name"

    XCTAssertEqual(appLocalizedRuntime(value, languageCode: "en"), value)
    XCTAssertEqual(appLocalizedRuntime(value, languageCode: "ko"), value)
  }

  func testExactKeyResolvesEnglishAndKorean() {
    XCTAssertEqual(appLocalizedRuntime("Apply…", languageCode: "en"), "Apply…")
    XCTAssertEqual(appLocalizedRuntime("Apply…", languageCode: "ko"), "적용…")
    XCTAssertEqual(
      appLocalizedRuntime("Review Changes…", languageCode: "en"),
      "Review Changes…"
    )
    XCTAssertEqual(
      appLocalizedRuntime("Review Changes…", languageCode: "ko"),
      "변경 사항 검토…"
    )
  }

  func testLocationPermissionCopyDescribesSSIDAuthorizationWithoutCoordinates() {
    let key =
      "macOS can require Location Services to reveal the current Wi-Fi network name during Capture. Desk Setup Switcher does not request or store your coordinates."

    XCTAssertEqual(appLocalizedRuntime(key, languageCode: "en"), key)
    XCTAssertEqual(
      appLocalizedRuntime(key, languageCode: "ko"),
      "macOS에서는 캡처 중 현재 Wi-Fi 네트워크 이름을 확인할 때 위치 서비스 권한이 필요할 수 있습니다. 책상 설정 전환기는 사용자의 좌표를 요청하거나 저장하지 않습니다."
    )
  }

  func testAudioRoleTemplateLocalizesItsFormatArgument() {
    let value = "No default input device UID was saved."

    XCTAssertEqual(
      appLocalizedRuntime(value, languageCode: "en"),
      "No Default Input device UID was saved."
    )
    XCTAssertEqual(
      appLocalizedRuntime(value, languageCode: "ko"),
      "기본 입력 기기 UID가 저장되지 않았습니다."
    )
  }

  func testExperimentalInputTemplateLocalizesItsFormatArgument() {
    let value = "Updated the experimental com.apple.mouse.scaling preference."

    XCTAssertEqual(
      appLocalizedRuntime(value, languageCode: "en"),
      "Updated the experimental Pointer speed preference."
    )
    XCTAssertEqual(
      appLocalizedRuntime(value, languageCode: "ko"),
      "실험적 포인터 속도 환경설정을 업데이트했습니다."
    )
  }

  func testKeyboardEditorCopyResolvesExactlyInEnglishAndKorean() {
    let expectedTranslations = [
      ("Keyboard", "키보드"),
      ("Key repeat speed", "키 반복 속도"),
      ("Repeat delay", "반복 지연 시간"),
      ("Keyboard brightness", "키보드 밝기"),
      ("Fast", "빠르게"),
      ("Slow", "느리게"),
      ("Short", "짧게"),
      ("Long", "길게"),
      ("Dim", "어둡게"),
      ("Bright", "밝게"),
      ("Slow to fast, level %lld of %lld", "느리게에서 빠르게, %2$lld단계 중 %1$lld단계"),
      ("Long to short, level %lld of %lld", "길게에서 짧게, %2$lld단계 중 %1$lld단계"),
      ("Set key repeat speed from slow to fast", "키 반복 속도를 느리게에서 빠르게까지 설정합니다"),
      (
        "Set the delay before a held key begins repeating",
        "키를 길게 눌렀을 때 반복이 시작될 때까지의 시간을 설정합니다"
      ),
      (
        "Set keyboard brightness from 0 to 100 percent",
        "키보드 밝기를 0~100퍼센트로 설정합니다"
      ),
      ("Change key repeat speed", "키 반복 속도 변경"),
      ("Change repeat delay", "반복 지연 시간 변경"),
      ("Change keyboard brightness", "키보드 밝기 변경"),
      (
        "The keyboard control requires permission before it can be changed.",
        "키보드 제어를 변경하려면 먼저 권한이 필요합니다."
      ),
      (
        "Input Monitoring access must be granted in System Settings",
        "시스템 설정에서 입력 모니터링 접근을 허용해야 합니다"
      ),
      (
        "Updated keyboard brightness and confirmed it with public CoreHID.",
        "키보드 밝기를 업데이트하고 공개 CoreHID로 확인했습니다."
      ),
      ("Input Monitoring Needed", "입력 모니터링 필요"),
      ("Capture Incomplete", "캡처 미완료"),
      (
        "Input Monitoring access is needed to include keyboard brightness. Keyboard brightness was omitted.",
        "키보드 밝기를 포함하려면 입력 모니터링 접근이 필요합니다. 키보드 밝기는 제외했습니다."
      ),
      (
        "Keyboard brightness is unavailable right now and was omitted.",
        "현재 키보드 밝기를 사용할 수 없어 제외했습니다."
      ),
      ("Review Location Permission", "위치 권한 검토"),
    ]

    for (english, korean) in expectedTranslations {
      XCTAssertEqual(appLocalizedRuntime(english, languageCode: "en"), english)
      XCTAssertEqual(appLocalizedRuntime(english, languageCode: "ko"), korean)
    }

    XCTAssertEqual(
      appLocalizedRuntime(
        "Updated the experimental KeyboardBrightness preference.",
        languageCode: "ko"
      ),
      "실험적 키보드 밝기 환경설정을 업데이트했습니다."
    )
  }

  func testNumericRuntimeTemplatePreservesItsFormatArgument() {
    let value = "Core Audio reported 12 device(s)."

    XCTAssertEqual(
      appLocalizedRuntime(value, languageCode: "en"),
      "Core Audio reported 12 device(s)."
    )
    XCTAssertEqual(
      appLocalizedRuntime(value, languageCode: "ko"),
      "Core Audio에서 기기 12개를 감지했습니다."
    )
  }

  func testTraySurfaceCopyResolvesExactlyInEnglishAndKorean() {
    XCTAssertEqual(appLocalizedRuntime("Settings…", languageCode: "en"), "Settings…")
    XCTAssertEqual(appLocalizedRuntime("Settings…", languageCode: "ko"), "설정…")
    XCTAssertEqual(
      appLocalizedRuntime(
        "Opens or closes the Desk Setup Switcher tray.",
        languageCode: "en"
      ),
      "Opens or closes the Desk Setup Switcher tray."
    )
    XCTAssertEqual(
      appLocalizedRuntime(
        "Opens or closes the Desk Setup Switcher tray.",
        languageCode: "ko"
      ),
      "책상 설정 전환기 트레이를 열거나 닫습니다."
    )
    XCTAssertEqual(
      appLocalizedRuntime("Current Mac matches this profile", languageCode: "ko"),
      "현재 Mac이 이 프로필과 일치함"
    )
    XCTAssertEqual(
      appLocalizedRuntime("Current Mac matches Meeting.", languageCode: "en"),
      "Current Mac matches ‘Meeting’."
    )
    XCTAssertEqual(
      appLocalizedRuntime("Current Mac matches Meeting.", languageCode: "ko"),
      "현재 Mac이 ‘Meeting’ 프로필과 일치합니다."
    )
    XCTAssertEqual(
      appLocalizedRuntime("Meeting · Applying…", languageCode: "en"),
      "Meeting · Applying…"
    )
    XCTAssertEqual(
      appLocalizedRuntime("Meeting · Applying…", languageCode: "ko"),
      "Meeting · 적용 중…"
    )
  }

  func testNestedSurfaceCopyResolvesExactlyInEnglishAndKorean() {
    let expectedTranslations = [
      (
        "Desk Setup Switcher — no profile is confirmed to match",
        "책상 설정 전환기 — 일치하는 프로필이 확인되지 않음"
      ),
      ("When applying", "프로필 적용 시"),
      ("Dismiss", "닫기"),
      ("Could Not Delete Profile", "프로필을 삭제할 수 없음"),
      ("Could Not Complete Action", "작업을 완료할 수 없음"),
      ("The Settings window is unavailable.", "설정 창을 사용할 수 없습니다."),
      ("The destination window could not be shown.", "대상 창을 표시할 수 없습니다."),
      ("The destination window is unavailable.", "대상 창을 사용할 수 없습니다."),
    ]

    for (english, korean) in expectedTranslations {
      XCTAssertEqual(appLocalizedRuntime(english, languageCode: "en"), english)
      XCTAssertEqual(appLocalizedRuntime(english, languageCode: "ko"), korean)
    }
  }

  func testExplicitLanguageResolutionDoesNotDependOnAuditEnvironment() {
    setenv("DESK_SETUP_UI_AUDIT_LANGUAGE", "en", 1)
    defer { unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE") }

    XCTAssertEqual(
      appLocalizedRuntime(
        "The destination window could not be shown.",
        languageCode: "ko"
      ),
      "대상 창을 표시할 수 없습니다."
    )
  }
}
