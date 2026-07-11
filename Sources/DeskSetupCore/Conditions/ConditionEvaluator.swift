import Foundation

public struct ConditionEvaluator: Sendable {
  private enum TruthValue {
    case matched
    case notMatched
    case unavailable

    var isMatched: Bool {
      self == .matched
    }

    var inverted: TruthValue {
      switch self {
      case .matched:
        return .notMatched
      case .notMatched:
        return .matched
      case .unavailable:
        return .unavailable
      }
    }
  }

  private struct ItemEvaluation {
    var truth: TruthValue
    var explanation: String
  }

  private let displayMatcher: DisplayIdentityMatcher

  public init(displayMatcher: DisplayIdentityMatcher = .init()) {
    self.displayMatcher = displayMatcher
  }

  public func evaluate(
    _ conditionSet: ProfileConditionSet,
    in context: ConditionContext
  ) -> ConditionEvaluation {
    let evaluatedItems = conditionSet.conditions.map { condition in
      var evaluation = evaluate(condition.kind, in: context)

      if condition.isInverted {
        evaluation.truth = evaluation.truth.inverted
        evaluation.explanation = "Inverted condition: \(evaluation.explanation)"
      }

      return (
        truth: evaluation.truth,
        result: ConditionItemResult(
          id: condition.id,
          isMatched: evaluation.truth.isMatched,
          explanation: evaluation.explanation
        )
      )
    }

    var aggregate = aggregate(
      evaluatedItems.map(\.truth),
      mode: conditionSet.mode
    )
    if conditionSet.isInverted {
      // A set inversion must not turn a result that contains an unknown fact
      // into a positive match. This is deliberately conservative for
      // readiness: successful observation, rather than a failed reader, must
      // establish every inverted match.
      aggregate =
        evaluatedItems.contains { $0.truth == .unavailable }
        ? .unavailable
        : aggregate.inverted
    }

    return ConditionEvaluation(
      isMatched: aggregate.isMatched,
      items: evaluatedItems.map(\.result)
    )
  }

  private func aggregate(
    _ values: [TruthValue],
    mode: ConditionMatchMode
  ) -> TruthValue {
    // A profile with no conditions has no readiness restriction.
    guard !values.isEmpty else {
      return .matched
    }

    switch mode {
    case .all:
      if values.contains(.notMatched) {
        return .notMatched
      }
      return values.contains(.unavailable) ? .unavailable : .matched
    case .any:
      if values.contains(.matched) {
        return .matched
      }
      return values.contains(.unavailable) ? .unavailable : .notMatched
    }
  }

  private func evaluate(
    _ condition: ProfileConditionKind,
    in context: ConditionContext
  ) -> ItemEvaluation {
    let source = source(for: condition)
    guard !context.unavailableSources.contains(source) else {
      return .init(
        truth: .unavailable,
        explanation: "The required \(source.explanationName) readiness facts are unavailable."
      )
    }

    switch condition {
    case .displayConnected(let identity):
      switch displayMatcher.match(identity, among: context.displays) {
      case .matched:
        return .init(
          truth: .matched,
          explanation: "The required display is connected."
        )
      case .ambiguous:
        return .init(
          truth: .unavailable,
          explanation: "More than one connected display matches this identity."
        )
      case .noMatch:
        return .init(
          truth: .notMatched,
          explanation: "The required display is not connected."
        )
      }

    case .audioInputConnected(let uid):
      return membershipEvaluation(
        context.audioInputUIDs.contains(uid),
        matched: "The required audio input is connected.",
        notMatched: "The required audio input is not connected."
      )

    case .audioOutputConnected(let uid):
      return membershipEvaluation(
        context.audioOutputUIDs.contains(uid),
        matched: "The required audio output is connected.",
        notMatched: "The required audio output is not connected."
      )

    case .hardwareConnected(let identifier):
      return membershipEvaluation(
        context.hardwareIdentifiers.contains(identifier),
        matched: "The required hardware is connected.",
        notMatched: "The required hardware is not connected."
      )

    case .wifiSSID(let requiredSSID):
      guard let currentSSID = context.wifiSSID else {
        return .init(
          truth: .unavailable,
          explanation: "The current Wi-Fi SSID is unavailable."
        )
      }
      return membershipEvaluation(
        currentSSID == requiredSSID,
        matched: "The current Wi-Fi SSID matches.",
        notMatched: "The current Wi-Fi SSID does not match."
      )

    case .ethernetConnected:
      return membershipEvaluation(
        context.ethernetConnected,
        matched: "Ethernet is connected.",
        notMatched: "Ethernet is not connected."
      )

    case .ipAddressOrCIDR(let value):
      guard let network = try? CIDR(value) else {
        return .init(
          truth: .unavailable,
          explanation: "The saved IP address or CIDR is invalid."
        )
      }
      let matched = context.ipAddresses.contains { network.contains($0) }
      return membershipEvaluation(
        matched,
        matched: "A local IP address matches the required address range.",
        notMatched: "No local IP address matches the required address range."
      )

    case .location(let requiredRegion):
      guard let currentLocation = context.location else {
        return .init(
          truth: .unavailable,
          explanation: "The current location is unavailable."
        )
      }
      guard isValid(requiredRegion), isValid(currentLocation) else {
        return .init(
          truth: .unavailable,
          explanation: "The saved or current location region is invalid."
        )
      }

      // Treat the context radius as horizontal uncertainty. Requiring the
      // entire uncertainty circle to fit avoids declaring Ready on an
      // imprecise location fix near the boundary.
      let distance = distanceMeters(
        from: currentLocation,
        to: requiredRegion
      )
      let matched = distance + currentLocation.radiusMeters <= requiredRegion.radiusMeters
      return membershipEvaluation(
        matched,
        matched: "The current location is inside the required region.",
        notMatched: "The current location is outside the required region."
      )
    }
  }

  private func source(for condition: ProfileConditionKind) -> ConditionContextSource {
    switch condition {
    case .displayConnected:
      return .displays
    case .audioInputConnected, .audioOutputConnected:
      return .audio
    case .hardwareConnected:
      return .hardware
    case .wifiSSID, .ethernetConnected, .ipAddressOrCIDR:
      return .network
    case .location:
      return .location
    }
  }

  private func membershipEvaluation(
    _ matches: Bool,
    matched: String,
    notMatched: String
  ) -> ItemEvaluation {
    .init(
      truth: matches ? .matched : .notMatched,
      explanation: matches ? matched : notMatched
    )
  }

  private func isValid(_ region: LocationRegion) -> Bool {
    region.latitude.isFinite
      && (-90...90).contains(region.latitude)
      && region.longitude.isFinite
      && (-180...180).contains(region.longitude)
      && region.radiusMeters.isFinite
      && region.radiusMeters >= 0
  }

  private func distanceMeters(
    from start: LocationRegion,
    to end: LocationRegion
  ) -> Double {
    let earthRadiusMeters = 6_371_008.8
    let startLatitude = start.latitude * .pi / 180
    let endLatitude = end.latitude * .pi / 180
    let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
    let longitudeDelta = (end.longitude - start.longitude) * .pi / 180

    let haversine =
      pow(sin(latitudeDelta / 2), 2)
      + cos(startLatitude) * cos(endLatitude)
      * pow(sin(longitudeDelta / 2), 2)
    let centralAngle =
      2
      * atan2(
        sqrt(min(1, haversine)),
        sqrt(max(0, 1 - haversine))
      )
    return earthRadiusMeters * centralAngle
  }
}

extension ConditionContextSource {
  fileprivate var explanationName: String {
    switch self {
    case .displays:
      return "display"
    case .audio:
      return "audio"
    case .network:
      return "network"
    case .hardware:
      return "hardware"
    case .location:
      return "location"
    }
  }
}
