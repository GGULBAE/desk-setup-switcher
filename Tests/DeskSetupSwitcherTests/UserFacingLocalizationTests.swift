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
    XCTAssertEqual(appLocalizedRuntime("Review…", languageCode: "en"), "Review…")
    XCTAssertEqual(appLocalizedRuntime("Review…", languageCode: "ko"), "검토…")
  }

  func testLocationPermissionCopyDescribesSSIDAuthorizationWithoutCoordinates() {
    let key =
      "macOS can require Location Services to reveal the current Wi-Fi network name during Capture. Desk Setup Switcher does not request or store your coordinates."

    XCTAssertEqual(appLocalizedRuntime(key, languageCode: "en"), key)
    XCTAssertEqual(
      appLocalizedRuntime(key, languageCode: "ko"),
      "macOS에서는 Capture 중 현재 Wi-Fi 네트워크 이름을 확인할 때 위치 서비스 권한이 필요할 수 있습니다. 책상 설정 전환기는 사용자의 좌표를 요청하거나 저장하지 않습니다."
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
