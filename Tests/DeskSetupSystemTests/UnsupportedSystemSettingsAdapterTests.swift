import DeskSetupCore
import Testing

@testable import DeskSetupSystem

@Suite("Safe placeholder adapter")
struct UnsupportedSystemSettingsAdapterTests {
  @Test("never plans a live operation")
  func neverPlansLiveOperation() async throws {
    let adapter = UnsupportedSystemSettingsAdapter(group: .audio, reason: "Not implemented")
    let snapshot = try await adapter.snapshot()
    let plan = try await adapter.plan(
      .audio(.init()),
      from: snapshot,
      mode: .force
    )

    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.count == 1)
    #expect(await adapter.capability().state == .unsupported)
  }
}
