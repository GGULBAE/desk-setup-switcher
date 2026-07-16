import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupSystem

@Suite("Live adjacent apply preparation")
struct ApplyLivePreparationTests {
  @Test(
    "adjacent read-only plans are execution-equivalent",
    .enabled(if: liveReadTestsEnabled)
  )
  func adjacentPreparationsAreEquivalent() async throws {
    let locations = ProfileStoreLocations(directoryURL: ProfileStore.defaultDirectoryURL)
    let decoded = try ProfileJSONCodec().decode(contentsOf: locations.primaryURL)
    let document = decoded.document
    let profile = try #require(
      document.selectedProfileID.flatMap { selectedID in
        document.profiles.first { $0.id == selectedID }
      } ?? document.profiles.first
    )
    let engine = ApplyEngine(
      registry: try AdapterRegistry(LiveAdapterFactory.makeAdapters())
    )

    let first = await engine.prepare(profile: profile, mode: .normal)
    let second = await engine.prepare(profile: profile, mode: .normal)
    let operationContracts = zip(first.operations, second.operations).map { lhs, rhs in
      "\(lhs.group.rawValue):summary=\(lhs.summary == rhs.summary),preview=\(lhs.preview == rhs.preview),payload=\(lhs.payload == rhs.payload),rollback=\(lhs.rollbackPayload == rhs.rollbackPayload)"
    }
    let sanitizedComparison = [
      "groups=\(first.includedGroups == second.includedGroups)",
      "capabilities=\(first.capabilities == second.capabilities)",
      "readiness=\(first.readiness == second.readiness)",
      "rejections=\(first.rejectionReasons == second.rejectionReasons)",
      "validations=\(first.validationIssues == second.validationIssues)",
      "operation-count=\(first.operations.count == second.operations.count)",
      "omissions=\(first.omissions == second.omissions)",
      "operations=[\(operationContracts.joined(separator: ";"))]",
    ].joined(separator: ",")

    #expect(
      first.isExecutionEquivalent(to: second),
      Comment(rawValue: sanitizedComparison)
    )
  }

  private static var liveReadTestsEnabled: Bool {
    ProcessInfo.processInfo.environment["DESK_SETUP_LIVE_READ_TESTS"] == "1"
  }
}
