import DeskSetupCore
import DeskSetupPresentation
import Foundation
import Testing

@Suite("Profile status lifetime")
struct ProfileStatusLifetimeTests {
  @Test("historical applied and failed states never mask refreshed readiness")
  func historicalStatusDoesNotMaskReadiness() {
    #expect(
      ProfileStatusLifetime.visibleReadiness(
        calculated: .partial,
        operational: .applied
      ) == .partial
    )
    #expect(
      ProfileStatusLifetime.visibleReadiness(
        calculated: .ready,
        operational: .failed
      ) == .ready
    )
  }

  @Test("only an active apply temporarily overrides readiness")
  func applyingIsRetained() {
    let applyingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let appliedID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let failedID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    #expect(
      ProfileStatusLifetime.visibleReadiness(
        calculated: .ready,
        operational: .applying
      ) == .applying
    )
    #expect(
      ProfileStatusLifetime.retainingActiveOperations([
        applyingID: .applying,
        appliedID: .applied,
        failedID: .failed,
      ]) == [applyingID: .applying]
    )
  }
}
