import Foundation

public enum DisplayIdentityMatchResult: Equatable, Sendable {
  case matched(DisplayIdentity)
  case ambiguous(Set<DisplayIdentity>)
  case noMatch
}

/// Matches persisted identities without relying on a session display ID.
///
/// An exact UUID is authoritative. Otherwise, candidates with conflicting
/// stable attributes are rejected and the remaining vendor/model/serial data
/// is scored. Weak evidence and tied best scores are never silently accepted.
public struct DisplayIdentityMatcher: Sendable {
  private static let minimumFallbackScore = 60

  public init() {}

  public func match<S: Sequence>(
    _ desired: DisplayIdentity,
    among candidates: S
  ) -> DisplayIdentityMatchResult where S.Element == DisplayIdentity {
    let candidateArray = Array(candidates)

    if let desiredUUID = desired.uuid {
      let exactUUIDMatches = candidateArray.filter { $0.uuid == desiredUUID }
      if exactUUIDMatches.count == 1, let match = exactUUIDMatches.first {
        return .matched(match)
      }
      if exactUUIDMatches.count > 1 {
        return .ambiguous(Set(exactUUIDMatches))
      }
    }

    let scoredCandidates = candidateArray.compactMap { candidate -> (DisplayIdentity, Int)? in
      guard let score = fallbackScore(desired: desired, candidate: candidate) else {
        return nil
      }
      return (candidate, score)
    }
    guard let bestScore = scoredCandidates.map(\.1).max(),
      bestScore >= Self.minimumFallbackScore
    else {
      return .noMatch
    }

    let bestMatches =
      scoredCandidates
      .filter { $0.1 == bestScore }
      .map(\.0)
    guard bestMatches.count == 1, let match = bestMatches.first else {
      return .ambiguous(Set(bestMatches))
    }
    return .matched(match)
  }

  private func fallbackScore(
    desired: DisplayIdentity,
    candidate: DisplayIdentity
  ) -> Int? {
    let desiredVendor = meaningful(desired.vendorID)
    let candidateVendor = meaningful(candidate.vendorID)
    let desiredModel = meaningful(desired.modelID)
    let candidateModel = meaningful(candidate.modelID)
    let desiredSerial = meaningful(desired.serialNumber)
    let candidateSerial = meaningful(candidate.serialNumber)

    guard !conflicts(desiredVendor, candidateVendor),
      !conflicts(desiredModel, candidateModel),
      !conflicts(desiredSerial, candidateSerial),
      desired.isBuiltIn == candidate.isBuiltIn
    else {
      return nil
    }

    var score = 10  // Built-in/external class is known and equal.
    if matches(desiredVendor, candidateVendor) {
      score += 30
    }
    if matches(desiredModel, candidateModel) {
      score += 30
    }
    if matches(desiredSerial, candidateSerial) {
      score += 100
    }

    if let desiredName = normalized(desired.productName),
      let candidateName = normalized(candidate.productName),
      desiredName == candidateName
    {
      score += 10
    }

    return score
  }

  private func meaningful(_ value: UInt32?) -> UInt32? {
    guard let value, value != 0 else {
      return nil
    }
    return value
  }

  private func conflicts<T: Equatable>(_ lhs: T?, _ rhs: T?) -> Bool {
    guard let lhs, let rhs else {
      return false
    }
    return lhs != rhs
  }

  private func matches<T: Equatable>(_ lhs: T?, _ rhs: T?) -> Bool {
    guard let lhs, let rhs else {
      return false
    }
    return lhs == rhs
  }

  private func normalized(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let normalized =
      value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
    return normalized.isEmpty ? nil : normalized
  }
}
