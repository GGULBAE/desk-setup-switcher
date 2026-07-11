import XCTest

@testable import DeskSetupCore

final class DisplayIdentityMatcherTests: XCTestCase {
  private let matcher = DisplayIdentityMatcher()

  func testExactUUIDTakesPrecedenceOverFallbackScore() {
    let expectedUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let desired = DisplayIdentity(
      uuid: expectedUUID,
      vendorID: 100,
      modelID: 200,
      serialNumber: 300,
      productName: "Reference Panel"
    )
    let uuidMatch = DisplayIdentity(
      uuid: expectedUUID,
      vendorID: 999,
      modelID: 999,
      serialNumber: 999,
      productName: "Changed Metadata"
    )
    let fallbackMatch = DisplayIdentity(
      uuid: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
      vendorID: 100,
      modelID: 200,
      serialNumber: 300,
      productName: "Reference Panel"
    )

    XCTAssertEqual(
      matcher.match(desired, among: [fallbackMatch, uuidMatch]),
      .matched(uuidMatch)
    )
  }

  func testSerialDisambiguatesOtherwiseIdenticalDisplays() {
    let desired = DisplayIdentity(vendorID: 100, modelID: 200, serialNumber: 302)
    let first = DisplayIdentity(vendorID: 100, modelID: 200, serialNumber: 301)
    let second = DisplayIdentity(vendorID: 100, modelID: 200, serialNumber: 302)

    XCTAssertEqual(matcher.match(desired, among: [first, second]), .matched(second))
  }

  func testUniqueVendorAndModelCanProvideFallbackMatch() {
    let desired = DisplayIdentity(
      vendorID: 100,
      modelID: 200,
      productName: "Studio Panel"
    )
    let candidate = DisplayIdentity(
      vendorID: 100,
      modelID: 200,
      productName: "studio panel"
    )

    XCTAssertEqual(matcher.match(desired, among: [candidate]), .matched(candidate))
  }

  func testTiedFallbackEvidenceIsAmbiguous() {
    let desired = DisplayIdentity(vendorID: 100, modelID: 200)
    let first = DisplayIdentity(
      vendorID: 100,
      modelID: 200,
      productName: "Panel A"
    )
    let second = DisplayIdentity(
      vendorID: 100,
      modelID: 200,
      productName: "Panel B"
    )

    XCTAssertEqual(
      matcher.match(desired, among: [first, second]),
      .ambiguous([first, second])
    )
  }

  func testConflictingStableAttributesDoNotMatch() {
    let desired = DisplayIdentity(vendorID: 100, modelID: 200, serialNumber: 300)
    let candidate = DisplayIdentity(vendorID: 100, modelID: 200, serialNumber: 999)

    XCTAssertEqual(matcher.match(desired, among: [candidate]), .noMatch)
  }

  func testWeakIdentityDoesNotMatchByExternalClassAlone() {
    let desired = DisplayIdentity(productName: "Generic Display")
    let candidate = DisplayIdentity(productName: "Generic Display")

    XCTAssertEqual(matcher.match(desired, among: [candidate]), .noMatch)
  }
}
