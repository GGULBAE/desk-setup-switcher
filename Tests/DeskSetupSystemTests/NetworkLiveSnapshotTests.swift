import DeskSetupCore
import Foundation
import XCTest

@testable import DeskSetupSystem

final class NetworkLiveSnapshotTests: XCTestCase {
  func testLiveReadOnlySnapshotIsExplicitlyOptedIn() async throws {
    guard ProcessInfo.processInfo.environment["DESK_SETUP_LIVE_READ_TESTS"] == "1" else {
      throw XCTSkip(
        "Set DESK_SETUP_LIVE_READ_TESTS=1 to run read-only local network discovery."
      )
    }

    let adapter = NetworkAdapter(systemAPI: LiveNetworkSystemAPI())
    let snapshot = try await adapter.snapshot()

    XCTAssertEqual(snapshot.group, .network)
    XCTAssertEqual(snapshot.payload?.group, .network)
    XCTAssertTrue(snapshot.items.contains(where: { $0.key.hasPrefix("interface.") }))
    // This test intentionally calls no planning, apply, rollback, scan, or
    // association API. It performs only local read operations.
  }
}
