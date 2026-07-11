import Testing

@testable import DeskSetupCore

@Suite("Profile readiness")
struct ReadinessEvaluatorTests {
  private let evaluator = ReadinessEvaluator()

  @Test("a safely planned no-op group is ready")
  func noOpGroupIsReady() {
    let result = evaluator.evaluate(
      includedGroups: [.audio],
      capabilities: [
        AdapterCapability(group: .audio, state: .supported, reason: "Available")
      ],
      viableGroups: [.audio],
      operations: [],
      omissions: [],
      issues: []
    )

    #expect(result.status == .ready)
    #expect(result.applicableGroups == [.audio])
    #expect(result.unavailableGroups.isEmpty)
  }

  @Test("available and omitted groups produce partial readiness")
  func mixedAvailabilityIsPartial() {
    let result = evaluator.evaluate(
      includedGroups: [.audio, .input],
      capabilities: [
        AdapterCapability(group: .audio, state: .supported, reason: "Available"),
        AdapterCapability(group: .input, state: .supported, reason: "Available"),
      ],
      viableGroups: [.audio, .input],
      operations: [
        PlannedOperation(group: .input, key: "pointerSpeed", summary: "Pointer speed")
      ],
      omissions: [
        PlanOmission(
          group: .audio,
          key: "defaultOutput",
          status: .skipped,
          reason: "The output device is missing."
        )
      ],
      issues: []
    )

    #expect(result.status == .partial)
    #expect(result.applicableGroups == [.input])
    #expect(result.unavailableGroups == [.audio])
  }

  @Test("no applicable group is unavailable")
  func noApplicableGroupIsUnavailable() {
    let result = evaluator.evaluate(
      includedGroups: [.display],
      capabilities: [
        AdapterCapability(
          group: .display,
          state: .unsupported,
          reason: "Display mutation is unavailable."
        )
      ],
      viableGroups: [],
      operations: [],
      omissions: [],
      issues: []
    )

    #expect(result.status == .unavailable)
    #expect(result.applicableGroups.isEmpty)
    #expect(result.unavailableGroups == [.display])
  }

  @Test("an unsatisfied condition makes an otherwise ready profile partial")
  func conditionsAffectReadiness() {
    let result = evaluator.evaluate(
      includedGroups: [.network],
      capabilities: [
        AdapterCapability(group: .network, state: .supported, reason: "Available")
      ],
      viableGroups: [.network],
      operations: [],
      omissions: [],
      issues: [],
      conditionsSatisfied: false
    )

    #expect(result.status == .partial)
    #expect(result.reasons.contains("One or more profile conditions are not satisfied."))
  }
}
