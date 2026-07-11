import Foundation

public struct ReadinessEvaluation: Codable, Hashable, Sendable {
  public var status: ProfileReadiness
  public var applicableGroups: [SettingGroup]
  public var unavailableGroups: [SettingGroup]
  public var reasons: [String]

  public init(
    status: ProfileReadiness,
    applicableGroups: [SettingGroup],
    unavailableGroups: [SettingGroup],
    reasons: [String]
  ) {
    self.status = status
    self.applicableGroups = applicableGroups
    self.unavailableGroups = unavailableGroups
    self.reasons = reasons
  }
}

public struct ReadinessEvaluator: Sendable {
  public init() {}

  public func evaluate(
    includedGroups: [SettingGroup],
    capabilities: [AdapterCapability],
    viableGroups: Set<SettingGroup>,
    operations: [PlannedOperation],
    omissions: [PlanOmission],
    issues: [ValidationIssue],
    conditionsSatisfied: Bool = true
  ) -> ReadinessEvaluation {
    let included = Set(includedGroups)
    let orderedIncluded = SettingGroup.safeApplicationSequence.filter(included.contains)
    let capabilityByGroup = Dictionary(
      capabilities.map { ($0.group, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let groupsWithOperations = Set(operations.map(\.group))
    let groupsWithOmissions = Set(omissions.map(\.group))
    let fatalGroups = Set(issues.lazy.filter(\.isFatal).map(\.group))

    var unavailable = Set<SettingGroup>()
    var applicable = Set<SettingGroup>()
    var reasons: [String] = []

    if orderedIncluded.isEmpty {
      appendUnique("No settings groups are included.", to: &reasons)
    }

    if !conditionsSatisfied {
      appendUnique("One or more profile conditions are not satisfied.", to: &reasons)
    }

    for group in orderedIncluded {
      guard let capability = capabilityByGroup[group] else {
        unavailable.insert(group)
        appendUnique("No adapter is registered for \(group.rawValue).", to: &reasons)
        continue
      }

      guard capability.canApply else {
        unavailable.insert(group)
        appendUnique(capability.reason, to: &reasons)
        continue
      }

      guard viableGroups.contains(group) else {
        unavailable.insert(group)
        appendUnique("The \(group.rawValue) settings could not be planned safely.", to: &reasons)
        continue
      }

      let hasUnavailableItems = groupsWithOmissions.contains(group) || fatalGroups.contains(group)
      if hasUnavailableItems {
        unavailable.insert(group)
      }

      if groupsWithOperations.contains(group) || !hasUnavailableItems {
        applicable.insert(group)
      }
    }

    for omission in omissions where included.contains(omission.group) {
      appendUnique(omission.reason, to: &reasons)
    }

    for issue in issues where issue.isFatal && included.contains(issue.group) {
      appendUnique(issue.message, to: &reasons)
    }

    let status: ProfileReadiness
    if applicable.isEmpty {
      status = .unavailable
    } else if !conditionsSatisfied || !unavailable.isEmpty {
      status = .partial
    } else {
      status = .ready
    }

    return ReadinessEvaluation(
      status: status,
      applicableGroups: SettingGroup.safeApplicationSequence.filter(applicable.contains),
      unavailableGroups: SettingGroup.safeApplicationSequence.filter(unavailable.contains),
      reasons: reasons
    )
  }

  private func appendUnique(_ value: String, to values: inout [String]) {
    guard !value.isEmpty, !values.contains(value) else { return }
    values.append(value)
  }
}
