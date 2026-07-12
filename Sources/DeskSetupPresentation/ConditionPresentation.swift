import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

/// One selectable condition value with an identifier-free default label.
///
/// `value` is intended for picker identity and persistence. User interfaces
/// should render `label` by default and disclose `value` only in an explicit
/// advanced or technical-details affordance.
public struct ConditionValueChoice: Equatable, Identifiable, Sendable {
  public var value: String
  public var label: String
  public var isCurrentlyDetected: Bool

  public var id: String { value }

  public init(
    value: String,
    label: String,
    isCurrentlyDetected: Bool
  ) {
    self.value = value
    self.label = label
    self.isCurrentlyDetected = isCurrentlyDetected
  }
}

/// A friendly display-condition choice whose persisted identity remains hidden
/// from the default label. External ordinals are stable for the current set of
/// detected displays and a disconnected saved identity remains selectable.
public struct DisplayConditionChoice: Equatable, Identifiable, Sendable {
  public var identity: DisplayIdentity
  public var isCurrentlyDetected: Bool
  public var externalOrdinal: Int?

  public var id: DisplayIdentity { identity }

  public init(
    identity: DisplayIdentity,
    isCurrentlyDetected: Bool,
    externalOrdinal: Int? = nil
  ) {
    self.identity = identity
    self.isCurrentlyDetected = isCurrentlyDetected
    self.externalOrdinal = externalOrdinal
  }
}

/// Builds stable picker choices without making opaque identifiers the default UI.
public enum ConditionChoiceBuilder {
  /// Returns deterministic display choices while retaining a saved identity.
  ///
  /// If the saved identity matches a freshly detected identity through Core's
  /// stable matcher, the saved value remains the picker tag while being marked
  /// as currently detected. This avoids silently rewriting persisted identity
  /// fields merely because a runtime snapshot contains richer metadata.
  public static func displayChoices(
    detectedValues: [DisplayIdentity],
    savedValue: DisplayIdentity?
  ) -> [DisplayConditionChoice] {
    var detected = Array(Set(detectedValues)).sorted {
      displaySortKey($0) < displaySortKey($1)
    }
    var retainedDisconnectedValue: DisplayIdentity?

    if let savedValue, !detected.contains(savedValue) {
      switch DisplayIdentityMatcher().match(savedValue, among: detected) {
      case .matched(let currentIdentity):
        if let index = detected.firstIndex(of: currentIdentity) {
          detected[index] = savedValue
        }
      case .ambiguous, .noMatch:
        retainedDisconnectedValue = savedValue
      }
    }

    var choices = detected.map {
      DisplayConditionChoice(identity: $0, isCurrentlyDetected: true)
    }
    if let retainedDisconnectedValue {
      choices.insert(
        DisplayConditionChoice(
          identity: retainedDisconnectedValue,
          isCurrentlyDetected: false
        ),
        at: 0
      )
    }

    let detectedExternalIndices = choices.indices.filter {
      choices[$0].isCurrentlyDetected && !choices[$0].identity.isBuiltIn
    }
    if detectedExternalIndices.count > 1 {
      for (ordinal, index) in detectedExternalIndices.enumerated() {
        choices[index].externalOrdinal = ordinal + 1
      }
    }
    return choices
  }

  /// Returns nonblank, deduplicated choices in deterministic order.
  ///
  /// Detected values are trimmed, deduplicated, and sorted. A nonblank saved
  /// value that is no longer detected is retained as the first choice. Its
  /// label is composed only from the caller-supplied presentation strings and
  /// never contains the saved value itself.
  public static func choices(
    detectedValues: [String],
    savedValue: String?,
    baseLabel: String,
    savedNotDetectedLabel: String
  ) -> [ConditionValueChoice] {
    let detected = normalizedUnique(detectedValues).sorted()
    let normalizedSavedValue = normalized(savedValue)
    var result: [ConditionValueChoice] = []

    if let normalizedSavedValue, !detected.contains(normalizedSavedValue) {
      result.append(
        ConditionValueChoice(
          value: normalizedSavedValue,
          label: "\(baseLabel) — \(savedNotDetectedLabel)",
          isCurrentlyDetected: false
        )
      )
    }

    let usesOrdinals = detected.count > 1
    result.append(
      contentsOf: detected.enumerated().map { index, value in
        ConditionValueChoice(
          value: value,
          label: usesOrdinals ? "\(baseLabel) \(index + 1)" : baseLabel,
          isCurrentlyDetected: true
        )
      }
    )
    return result
  }

  private static func normalizedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      guard let value = normalized(value), seen.insert(value).inserted else {
        return nil
      }
      return value
    }
  }

  private static func displaySortKey(_ identity: DisplayIdentity) -> String {
    let builtInOrder = identity.isBuiltIn ? "0" : "1"
    let name = identity.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let uuid = identity.uuid?.uuidString ?? ""
    let vendor = identity.vendorID.map(String.init) ?? ""
    let model = identity.modelID.map(String.init) ?? ""
    let serial = identity.serialNumber.map(String.init) ?? ""
    return "\(builtInOrder)|\(name)|\(uuid)|\(vendor)|\(model)|\(serial)"
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

/// A validated, normalized value or a typed reason why input is not usable.
public enum ConditionInputValidation<
  Value: Equatable & Sendable,
  Issue: Equatable & Sendable
>: Equatable, Sendable {
  case valid(Value)
  case invalid(Issue)

  public var validatedValue: Value? {
    guard case .valid(let value) = self else { return nil }
    return value
  }

  public var issue: Issue? {
    guard case .invalid(let issue) = self else { return nil }
    return issue
  }

  public var isValid: Bool {
    guard case .valid = self else { return false }
    return true
  }
}

public enum AddressOrCIDRValidationIssue: Equatable, Sendable {
  case missingValue
  case malformedValue
}

public enum LocationInputField: CaseIterable, Equatable, Hashable, Sendable {
  case latitude
  case longitude
  case radiusMeters
}

public enum LocationValidationIssue: Equatable, Sendable {
  case missingFields([LocationInputField])
  case nonFinite(LocationInputField)
  case outOfRange(LocationInputField)
}

/// Pure validation for condition editor input.
public enum ConditionInputValidator {
  /// Ranges shared with `DeskSetupCore` profile-document validation.
  public static let latitudeRange: ClosedRange<Double> = -90...90
  public static let longitudeRange: ClosedRange<Double> = -180...180
  public static let radiusMetersRange: ClosedRange<Double> = 0...40_000_000

  /// Accepts either a single IPv4/IPv6 address or a CIDR network.
  ///
  /// The returned value is trimmed for persistence. Network parsing is
  /// delegated to `DeskSetupCore.CIDR`, keeping editor and runtime semantics
  /// aligned.
  public static func validateAddressOrCIDR(
    _ input: String
  ) -> ConditionInputValidation<String, AddressOrCIDRValidationIssue> {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      return .invalid(.missingValue)
    }
    guard (try? CIDR(value)) != nil else {
      return .invalid(.malformedValue)
    }
    return .valid(value)
  }

  /// Validates optional editor fields and returns a Core location model.
  ///
  /// Missing fields are reported together in stable field order. Supplied
  /// values then follow Core's finite-value and inclusive range requirements.
  public static func validateLocation(
    latitude: Double?,
    longitude: Double?,
    radiusMeters: Double?
  ) -> ConditionInputValidation<LocationRegion, LocationValidationIssue> {
    var missingFields: [LocationInputField] = []
    if latitude == nil { missingFields.append(.latitude) }
    if longitude == nil { missingFields.append(.longitude) }
    if radiusMeters == nil { missingFields.append(.radiusMeters) }
    guard missingFields.isEmpty else {
      return .invalid(.missingFields(missingFields))
    }

    guard let latitude, let longitude, let radiusMeters else {
      // The missing-field guard above makes this unreachable while retaining
      // complete optional unwrapping under Swift's definite-initialization rules.
      return .invalid(.missingFields(LocationInputField.allCases))
    }

    guard latitude.isFinite else { return .invalid(.nonFinite(.latitude)) }
    guard latitudeRange.contains(latitude) else {
      return .invalid(.outOfRange(.latitude))
    }
    guard longitude.isFinite else { return .invalid(.nonFinite(.longitude)) }
    guard longitudeRange.contains(longitude) else {
      return .invalid(.outOfRange(.longitude))
    }
    guard radiusMeters.isFinite else { return .invalid(.nonFinite(.radiusMeters)) }
    guard radiusMetersRange.contains(radiusMeters) else {
      return .invalid(.outOfRange(.radiusMeters))
    }

    return .valid(
      LocationRegion(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters
      )
    )
  }
}
