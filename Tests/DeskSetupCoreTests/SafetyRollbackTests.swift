import Foundation
import Testing

@testable import DeskSetupCore

@Suite("High-risk safety rollback")
struct SafetyRollbackTests {
  @Test("successful low-risk work returns no safety token")
  func lowRiskWorkHasNoToken() async throws {
    let low = PlannedOperation(group: .audio, key: "low", summary: "Low")
    let (engine, _) = try makeSafetyEngine(operations: [low])

    let result = await engine.apply(profile: safetyProfile(), mode: .normal)
    let unknown = await engine.confirmSafetyRollback(UUID())

    #expect(result.status == .applied)
    #expect(result.safetyConfirmationID == nil)
    #expect(unknown.status == .unknownOrExpired)
    #expect(unknown.rollbackResults.isEmpty)
  }

  @Test("confirmation discards a token without rollback")
  func confirmationDiscardsToken() async throws {
    let high = highRiskOperation(key: "display")
    let (engine, adapter) = try makeSafetyEngine(operations: [high])
    let result = await engine.apply(profile: safetyProfile(), mode: .normal)
    let confirmationID = try #require(result.safetyConfirmationID)
    await adapter.resetInvocations()

    let confirmed = await engine.confirmSafetyRollback(confirmationID)
    let secondUse = await engine.revertSafetyRollback(confirmationID)

    #expect(confirmed.status == .confirmed)
    #expect(secondUse.status == .unknownOrExpired)
    #expect(await adapter.recordedInvocations() == [.confirm(high.id)])
  }

  @Test("a failed high-risk confirmation restores the temporary configuration")
  func confirmationFailureRollsBack() async throws {
    let high = highRiskOperation(key: "temporary-display")
    let (engine, adapter) = try makeSafetyEngine(
      operations: [high],
      confirmResults: [
        high.id: OperationResult(
          operationID: high.id,
          status: .failed,
          message: "Synthetic confirmation commit failure."
        )
      ]
    )
    let result = await engine.apply(profile: safetyProfile(), mode: .normal)
    let confirmationID = try #require(result.safetyConfirmationID)
    await adapter.resetInvocations()

    let resolution = await engine.confirmSafetyRollback(confirmationID)
    let secondUse = await engine.confirmSafetyRollback(confirmationID)

    #expect(resolution.status == .confirmationFailed)
    #expect(resolution.rollbackResults.map(\.status) == [.rolledBack])
    #expect(secondUse.status == .unknownOrExpired)
    #expect(
      await adapter.recordedInvocations() == [
        .confirm(high.id),
        .rollback(high.id),
      ])
  }

  @Test("revert rolls back only completed high-risk operations in reverse order")
  func revertUsesReverseHighRiskOrder() async throws {
    let low = PlannedOperation(group: .audio, key: "low", summary: "Low")
    let firstHigh = highRiskOperation(key: "first-high")
    let secondHigh = highRiskOperation(key: "second-high")
    let (engine, adapter) = try makeSafetyEngine(
      operations: [firstHigh, low, secondHigh]
    )
    let result = await engine.apply(profile: safetyProfile(), mode: .normal)
    let confirmationID = try #require(result.safetyConfirmationID)
    await adapter.resetInvocations()

    let reverted = await engine.revertSafetyRollback(confirmationID)

    #expect(reverted.status == .reverted)
    #expect(reverted.rollbackResults.map(\.key) == ["second-high", "first-high"])
    #expect(reverted.rollbackResults.allSatisfy { $0.status == .rolledBack })
    #expect(
      await adapter.recordedInvocations() == [
        .rollback(secondHigh.id),
        .rollback(firstHigh.id),
      ])
  }

  @Test("network applies last and is the first protected operation rolled back")
  func networkIsLastAppliedAndFirstRolledBack() async throws {
    let audio = PlannedOperation(group: .audio, key: "audio", summary: "Audio")
    let display = PlannedOperation(
      group: .display,
      key: "display",
      summary: "Display",
      risk: .high,
      isFatalOnFailure: true,
      rollbackPayload: Data([0x01])
    )
    let network = PlannedOperation(
      group: .network,
      key: "network",
      summary: "Network",
      risk: .high,
      isFatalOnFailure: true,
      rollbackPayload: Data([0x02])
    )
    let audioAdapter = MockSystemSettingsAdapter(
      group: .audio,
      plan: AdapterPlan(group: .audio, operations: [audio])
    )
    let displayAdapter = MockSystemSettingsAdapter(
      group: .display,
      plan: AdapterPlan(group: .display, operations: [display])
    )
    let networkAdapter = MockSystemSettingsAdapter(
      group: .network,
      plan: AdapterPlan(group: .network, operations: [network])
    )
    let engine = ApplyEngine(
      registry: try AdapterRegistry([networkAdapter, audioAdapter, displayAdapter])
    )

    let result = await engine.apply(profile: multiGroupSafetyProfile(), mode: .normal)
    let confirmationID = try #require(result.safetyConfirmationID)
    let reverted = await engine.revertSafetyRollback(confirmationID)

    #expect(result.itemResults.map(\.key) == ["audio", "display", "network"])
    #expect(reverted.rollbackResults.map(\.key) == ["network", "display"])
    #expect(await audioAdapter.recordedInvocations().last == .apply(audio.id))
    #expect(
      await displayAdapter.recordedInvocations().suffix(2) == [
        .apply(display.id),
        .rollback(display.id),
      ])
    #expect(
      await networkAdapter.recordedInvocations().suffix(2) == [
        .apply(network.id),
        .rollback(network.id),
      ])
  }

  @Test("rollback failure is reported and still consumes the token")
  func rollbackFailureIsOneShot() async throws {
    let high = highRiskOperation(key: "high")
    let (engine, _) = try makeSafetyEngine(
      operations: [high],
      rollbackResults: [
        high.id: OperationResult(
          operationID: high.id,
          status: .failed,
          message: "Synthetic rollback failure."
        )
      ]
    )
    let result = await engine.apply(profile: safetyProfile(), mode: .normal)
    let confirmationID = try #require(result.safetyConfirmationID)

    let failed = await engine.revertSafetyRollback(confirmationID)
    let secondUse = await engine.revertSafetyRollback(confirmationID)

    #expect(failed.status == .rollbackFailed)
    #expect(failed.rollbackResults.map(\.status) == [.rollbackFailed])
    #expect(secondUse.status == .unknownOrExpired)
    #expect(secondUse.rollbackResults.isEmpty)
  }

  @Test("pending safety transactions are bounded and replaceable explicitly")
  func pendingTransactionsAreBounded() async throws {
    let high = highRiskOperation(key: "bounded-high")
    let (engine, adapter) = try makeSafetyEngine(
      operations: [high],
      maximumPendingSafetyRollbacks: 1
    )

    let first = await engine.apply(profile: safetyProfile(), mode: .normal)
    let firstID = try #require(first.safetyConfirmationID)
    let blocked = await engine.apply(profile: safetyProfile(), mode: .normal)

    #expect(!blocked.didExecute)
    #expect(blocked.safetyConfirmationID == nil)
    #expect(
      blocked.preparation.rejectionReasons.contains(
        .safetyConfirmationCapacityReached
      )
    )
    #expect(
      await adapter.recordedInvocations().filter {
        if case .apply = $0 { return true }
        return false
      }.count == 1
    )

    let firstRevert = await engine.revertSafetyRollback(firstID)
    let replacement = await engine.apply(profile: safetyProfile(), mode: .normal)
    let replacementID = try #require(replacement.safetyConfirmationID)

    #expect(firstRevert.status == .reverted)
    #expect(replacement.didExecute)
    #expect(replacementID != firstID)
    #expect((await engine.confirmSafetyRollback(replacementID)).status == .confirmed)
  }
}

private func makeSafetyEngine(
  operations: [PlannedOperation],
  confirmResults: [UUID: OperationResult] = [:],
  rollbackResults: [UUID: OperationResult] = [:],
  maximumPendingSafetyRollbacks: Int = 1
) throws -> (ApplyEngine, MockSystemSettingsAdapter) {
  let adapter = MockSystemSettingsAdapter(
    group: .audio,
    plan: AdapterPlan(group: .audio, operations: operations),
    confirmResults: confirmResults,
    rollbackResults: rollbackResults
  )
  let engine = ApplyEngine(
    registry: try AdapterRegistry([adapter]),
    maximumPendingSafetyRollbacks: maximumPendingSafetyRollbacks
  )
  return (engine, adapter)
}

private func highRiskOperation(key: String) -> PlannedOperation {
  PlannedOperation(
    group: .audio,
    key: key,
    summary: key,
    risk: .high,
    isFatalOnFailure: true,
    rollbackPayload: Data([0x01])
  )
}

private func safetyProfile() -> DeskProfile {
  var settings = ProfileSettings()
  settings.audio.isIncluded = true
  settings.audio.value.defaultOutputUID = .init(isIncluded: true, value: "test-output")
  return DeskProfile(name: "Safety profile", settings: settings)
}

private func multiGroupSafetyProfile() -> DeskProfile {
  var profile = safetyProfile()
  profile.settings.display.isIncluded = true
  profile.settings.display.value.displays = [
    DisplayTargetSettings(
      identity: DisplayIdentity(uuid: UUID()),
      isPrimary: .init(value: true),
      origin: .init(isIncluded: false, value: DisplayPoint(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: DisplayMode(width: 1, height: 1, refreshRate: 0)
      ),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
  ]
  profile.settings.network.isIncluded = true
  profile.settings.network.value.serviceIPv4 = [
    NetworkServiceIPv4Settings(
      identity: NetworkServiceIdentity(
        kind: .ethernet,
        serviceName: "Synthetic Ethernet",
        interfaceType: "Ethernet"
      ),
      configuration: .init(value: .dhcp)
    )
  ]
  return profile
}
