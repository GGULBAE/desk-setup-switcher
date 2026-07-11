import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupSystem

@Suite("Live input preference snapshot")
struct InputPreferencesLiveSnapshotTests {
  @Test("opt-in snapshot is read-only", .enabled(if: liveReadTestsEnabled))
  func snapshotIsReadOnly() async throws {
    let adapter = InputPreferencesAdapter()
    let snapshot = try await adapter.snapshot()

    #expect(snapshot.group == .input)
    #expect(snapshot.items.count == InputPreferenceKey.allCases.count)
  }

  private static var liveReadTestsEnabled: Bool {
    ProcessInfo.processInfo.environment["DESK_SETUP_LIVE_READ_TESTS"] == "1"
  }
}
