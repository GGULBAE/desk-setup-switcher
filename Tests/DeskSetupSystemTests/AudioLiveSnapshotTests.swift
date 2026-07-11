import Foundation
import XCTest

@testable import DeskSetupSystem

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

final class AudioLiveSnapshotTests: XCTestCase {
  func testLiveSnapshotIsExplicitlyGatedAndReadOnly() async throws {
    guard ProcessInfo.processInfo.environment["DESK_SETUP_LIVE_READ_TESTS"] == "1" else {
      throw XCTSkip("Set DESK_SETUP_LIVE_READ_TESTS=1 to run read-only Core Audio discovery.")
    }

    let api = CoreAudioSystemAPI()
    let devices = try api.devices()
    let snapshot = try await CoreAudioAdapter(api: api).snapshot()

    XCTAssertEqual(snapshot.group, .audio)
    XCTAssertEqual(
      snapshot.items.filter { $0.key.hasPrefix("device:") }.count,
      devices.count
    )
    XCTAssertNotNil(snapshot.payload)
  }
}
