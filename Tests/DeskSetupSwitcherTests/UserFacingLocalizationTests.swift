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
}
