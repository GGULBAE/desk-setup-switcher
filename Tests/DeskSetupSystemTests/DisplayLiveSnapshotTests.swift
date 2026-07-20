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
    XCTAssertEqual(settings.displays.count, systemDisplays.count)
    XCTAssertTrue(
      settings.displays.allSatisfy {
        $0.identity.uuid != nil
          || ($0.identity.vendorID != nil && $0.identity.modelID != nil)
      }
    )

    if rawDisplayCount == 0 {
      // CGGetActiveDisplayList legitimately returns zero while an online
      // session display is asleep. The adapter must preserve that as a typed,
      // nonfatal unsupported snapshot item instead of inventing a display.
      XCTAssertEqual(snapshot.items.count, 1)
      XCTAssertEqual(snapshot.items.first?.key, "display.active")
      XCTAssertEqual(snapshot.items.first?.state, .unsupported)
      XCTAssertEqual(snapshot.displayModeCatalog?.count, 0)
    } else {
      XCTAssertFalse(settings.displays.isEmpty)
      let colorProfileItems = snapshot.items.filter {
        $0.key.hasPrefix("display.colorProfile.")
      }
      XCTAssertEqual(
        colorProfileItems.count,
        settings.displays.count(where: { $0.colorProfile.isIncluded })
      )
      XCTAssertEqual(
        snapshot.items.count,
        settings.displays.count + colorProfileItems.count
      )
      XCTAssertEqual(snapshot.displayModeCatalog?.count, settings.displays.count)
    }
  }
}
