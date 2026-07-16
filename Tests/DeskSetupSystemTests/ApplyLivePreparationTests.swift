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

    for mode in [ApplyMode.normal, .force] {
      let first = await engine.prepare(profile: profile, mode: mode)
      let second = await engine.prepare(profile: profile, mode: mode)
      let operationContracts = zip(first.operations, second.operations).map { lhs, rhs in
        "\(lhs.group.rawValue):summary=\(lhs.summary == rhs.summary),preview=\(lhs.preview == rhs.preview),payload=\(lhs.payload == rhs.payload),rollback=\(lhs.rollbackPayload == rhs.rollbackPayload)"
      }
      let sanitizedComparison = [
        "mode=\(mode.rawValue)",
        "groups=\(first.includedGroups == second.includedGroups)",
        "capabilities=\(first.capabilities == second.capabilities)",
        "readiness=\(first.readiness == second.readiness)",
        "rejections=\(first.rejectionReasons == second.rejectionReasons)",
        "validation-count=\(first.validationIssues.count == second.validationIssues.count)",
        "operation-count=\(first.operations.count == second.operations.count)",
        "omission-count=\(first.omissions.count == second.omissions.count)",
        "operations=[\(operationContracts.joined(separator: ";"))]",
      ].joined(separator: ",")
      let isEquivalent = first.isExecutionEquivalent(to: second)

      #expect(isEquivalent, Comment(rawValue: sanitizedComparison))
    }
  }

  private static var liveReadTestsEnabled: Bool {
    ProcessInfo.processInfo.environment["DESK_SETUP_LIVE_READ_TESTS"] == "1"
  }
}
