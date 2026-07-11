import XCTest

@testable import DeskSetupCore

final class SensitiveDataRedactorTests: XCTestCase {
  private let redactor = SensitiveDataRedactor(
    homeDirectory: URL(fileURLWithPath: "/custom/home/synthetic-user", isDirectory: true)
  )

  func testRedactsCredentialKeyValueForms() {
    let source =
      #"password=hunter2 token: abc.def credential='desk-secret' api_key="api-secret" Authorization: Bearer bearer-secret"#

    let result = redactor.redact(source)

    XCTAssertFalse(result.contains("hunter2"))
    XCTAssertFalse(result.contains("abc.def"))
    XCTAssertFalse(result.contains("desk-secret"))
    XCTAssertFalse(result.contains("api-secret"))
    XCTAssertFalse(result.contains("bearer-secret"))
    XCTAssertEqual(result.components(separatedBy: SensitiveDataRedactor.replacement).count - 1, 5)
  }

  func testRedactsInjectedAndConventionalHomeDirectories() {
    let source =
      "first=/custom/home/synthetic-user/Documents/report.json second=/Users/example/Library/Logs/app.log"

    let result = redactor.redact(source)

    XCTAssertEqual(
      result,
      "first=<home>/Documents/report.json second=<home>/Library/Logs/app.log"
    )
  }

  func testRedactsLabeledCoordinatesAndSSIDs() {
    let source =
      #"latitude=37.123456 longitude: 127.654321 SSID="Synthetic Lab" wifi_ssid=PrivateNetwork"#

    let result = redactor.redact(source)

    XCTAssertFalse(result.contains("37.123456"))
    XCTAssertFalse(result.contains("127.654321"))
    XCTAssertFalse(result.contains("Synthetic Lab"))
    XCTAssertFalse(result.contains("PrivateNetwork"))
    XCTAssertTrue(result.contains("latitude=<redacted>"))
    XCTAssertTrue(result.contains("SSID=<redacted>"))
  }

  func testRedactsIPHostPortionsAndRetainsUsefulPrefixes() {
    let source = "addresses 192.168.42.99, 10.2.3.4/16, 2001:db8:abcd:12::beef, fe80::1234%en0/128"

    let result = redactor.redact(source)

    XCTAssertFalse(result.contains("192.168.42.99"))
    XCTAssertFalse(result.contains("10.2.3.4"))
    XCTAssertFalse(result.contains("::beef"))
    XCTAssertFalse(result.contains("::1234"))
    XCTAssertTrue(result.contains("192.168.42.0/24"))
    XCTAssertTrue(result.contains("10.2.0.0/16"))
    XCTAssertTrue(result.contains("2001:db8:abcd:12::/64"))
    XCTAssertTrue(result.contains("fe80::/64"))
  }

  func testEntryFieldsAreRedactedDeterministically() {
    let entry = DiagnosticEntry(
      id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
      timestamp: Date(timeIntervalSince1970: 1_000),
      severity: .warning,
      component: "/Users/example/component",
      code: "token=code-secret",
      message: "password=message-secret at 203.0.113.42"
    )

    let first = redactor.redact(entry)
    let second = redactor.redact(first)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.component, "<home>/component")
    XCTAssertEqual(first.code, "token=<redacted>")
    XCTAssertEqual(first.message, "password=<redacted> at 203.0.113.0/24")
  }
}
