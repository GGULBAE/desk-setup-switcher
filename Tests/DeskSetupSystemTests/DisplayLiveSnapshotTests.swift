import CoreGraphics
import Foundation
import XCTest

@testable import DeskSetupSystem

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

final class DisplayLiveSnapshotTests: XCTestCase {
  func testLiveSnapshotIsReadOnlyAndExplicitlyOptIn() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["DESK_SETUP_LIVE_READ_TESTS"] == "1",
      "Set DESK_SETUP_LIVE_READ_TESTS=1 to run the read-only Core Graphics snapshot test."
    )

    let rawDisplayCount = try await MainActor.run { () throws -> UInt32 in
      var count: UInt32 = 0
      let error = CGGetActiveDisplayList(0, nil, &count)
      guard error == .success else {
        throw DisplayAdapterError.coreGraphics(
          operation: "count active displays in the live test",
          code: Int32(error.rawValue)
        )
      }
      return count
    }
    XCTAssertGreaterThan(rawDisplayCount, 0)

    let systemAPI = CoreGraphicsDisplaySystemAPI()
    let systemDisplays = try await systemAPI.activeDisplays()
    XCTAssertEqual(systemDisplays.count, Int(rawDisplayCount))
    XCTAssertTrue(systemDisplays.allSatisfy(\.isActive))

    let adapter = CoreGraphicsDisplayAdapter(systemAPI: systemAPI)
    let snapshot = try await adapter.snapshot()

    XCTAssertEqual(snapshot.group, .display)
    guard case .display(let settings)? = snapshot.payload else {
      return XCTFail("Expected a display snapshot payload.")
    }
    XCTAssertFalse(settings.displays.isEmpty)
    XCTAssertEqual(settings.displays.count, systemDisplays.count)
    XCTAssertEqual(settings.displays.count, snapshot.items.count)
    XCTAssertTrue(
      settings.displays.allSatisfy {
        $0.identity.uuid != nil
          || ($0.identity.vendorID != nil && $0.identity.modelID != nil)
      }
    )
  }
}
