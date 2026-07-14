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
}
