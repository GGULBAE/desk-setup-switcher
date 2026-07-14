import DeskSetupCore
import Foundation
import XCTest

@testable import DeskSetupSystem

final class ConditionContextLiveTests: XCTestCase {
  func testLiveConditionDiscoveryIsReadOnlyAndExplicitlyOptedIn() async throws {
    guard ProcessInfo.processInfo.environment["DESK_SETUP_LIVE_READ_TESTS"] == "1" else {
      throw XCTSkip(
        "Set DESK_SETUP_LIVE_READ_TESTS=1 to run read-only readiness-context discovery."
      )
    }

    let result = await ConditionContextProvider().discover()

    XCTAssertFalse(result.unavailableSources.contains(.displays))
    // An online display can temporarily be absent from the active list while
    // the session display sleeps. That is an available empty fact set, not a
    // reader failure; the dedicated display live test covers both states.
    XCTAssertTrue(
      result.context.displays.allSatisfy {
        $0.uuid != nil || ($0.vendorID != nil && $0.modelID != nil)
      }
    )
    XCTAssertTrue(result.context.audioInputUIDs.allSatisfy { !$0.isEmpty })
    XCTAssertTrue(result.context.audioOutputUIDs.allSatisfy { !$0.isEmpty })
    XCTAssertTrue(result.context.hardwareIdentifiers.allSatisfy { $0.hasPrefix("usb:") })
    XCTAssertTrue(result.context.ipAddresses.allSatisfy { !$0.isEmpty })
    XCTAssertEqual(result.diagnostics.count, result.unavailableSources.count)

    // The default provider performs only local property reads. In particular,
    // it does not request location permission, start location updates, scan or
    // associate Wi-Fi, open audio capture, or mutate any system setting.
  }
}
