import DeskSetupCore
import DeskSetupPresentation
import Foundation
import Testing

@Suite("Condition presentation")
struct ConditionPresentationTests {
  @Test("display choices use stable external ordinals and built-in ordering")
  func displayChoicesHaveStableOrdinals() {
    let builtIn = DisplayIdentity(productName: "Synthetic Built-in", isBuiltIn: true)
    let externalA = DisplayIdentity(
      uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
      vendorID: 100,
      modelID: 1,
      isBuiltIn: false
    )
    let externalB = DisplayIdentity(
      uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000002"),
      vendorID: 100,
      modelID: 2,
      isBuiltIn: false
    )

    let forward = ConditionChoiceBuilder.displayChoices(
      detectedValues: [externalB, builtIn, externalA],
      savedValue: nil
    )
    let reverse = ConditionChoiceBuilder.displayChoices(
      detectedValues: [externalA, builtIn, externalB, externalA],
      savedValue: nil
    )

    #expect(forward == reverse)
    #expect(forward.map(\.identity) == [builtIn, externalA, externalB])
    #expect(forward.map(\.externalOrdinal) == [nil, 1, 2])
    #expect(forward.allSatisfy { $0.isCurrentlyDetected })
  }

  @Test("a disconnected saved display remains first without a false ordinal")
  func disconnectedSavedDisplayIsRetained() {
    let detected = DisplayIdentity(vendorID: 100, modelID: 1, isBuiltIn: false)
    let saved = DisplayIdentity(vendorID: 200, modelID: 2, isBuiltIn: false)

    let choices = ConditionChoiceBuilder.displayChoices(
      detectedValues: [detected],
      savedValue: saved
    )

    #expect(choices.map(\.identity) == [saved, detected])
    #expect(choices.map(\.isCurrentlyDetected) == [false, true])
    #expect(choices.map(\.externalOrdinal) == [nil, nil])
  }

  @Test("a stable saved display match stays selected and is marked detected")
  func matchingSavedDisplayIsRetained() {
    let current = DisplayIdentity(
      uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000010"),
      vendorID: 300,
      modelID: 3,
      isBuiltIn: false
    )
    let saved = DisplayIdentity(vendorID: 300, modelID: 3, isBuiltIn: false)

    let choices = ConditionChoiceBuilder.displayChoices(
      detectedValues: [current],
      savedValue: saved
    )

    #expect(choices == [.init(identity: saved, isCurrentlyDetected: true)])
  }

  @Test("choices are nonblank deduplicated and independent of detection order")
  func choicesAreDeterministic() {
    let forward = ConditionChoiceBuilder.choices(
      detectedValues: [" synthetic-b ", "", "synthetic-a", "synthetic-b", "\n"],
      savedValue: "synthetic-a",
      baseLabel: "Output device",
      savedNotDetectedLabel: "Saved; not currently detected"
    )
    let reverse = ConditionChoiceBuilder.choices(
      detectedValues: ["synthetic-b", "synthetic-a", "synthetic-b"].reversed(),
      savedValue: " synthetic-a ",
      baseLabel: "Output device",
      savedNotDetectedLabel: "Saved; not currently detected"
    )

    #expect(forward == reverse)
    #expect(forward.map(\.value) == ["synthetic-a", "synthetic-b"])
    #expect(forward.map(\.label) == ["Output device 1", "Output device 2"])
    #expect(forward.map(\.isCurrentlyDetected) == [true, true])
  }

  @Test("a disconnected saved value is preserved without appearing in its label")
  func disconnectedSavedValueHasSafeLabel() {
    let privateIdentifier = "opaque-saved-device-identifier"
    let choices = ConditionChoiceBuilder.choices(
      detectedValues: ["synthetic-detected-device"],
      savedValue: "  \(privateIdentifier)  ",
      baseLabel: "Input device",
      savedNotDetectedLabel: "Saved; not currently detected"
    )

    #expect(choices.map(\.value) == [privateIdentifier, "synthetic-detected-device"])
    #expect(choices[0].label == "Input device — Saved; not currently detected")
    #expect(!choices[0].label.contains(privateIdentifier))
    #expect(!choices[0].isCurrentlyDetected)
    #expect(choices[1].label == "Input device")
    #expect(choices[1].isCurrentlyDetected)
  }

  @Test("blank saved and detected values never create choices")
  func blankValuesAreDiscarded() {
    let choices = ConditionChoiceBuilder.choices(
      detectedValues: ["", "  ", "\n\t"],
      savedValue: " \n ",
      baseLabel: "Detected hardware",
      savedNotDetectedLabel: "Saved; not currently detected"
    )

    #expect(choices.isEmpty)
  }

  @Test("IP and CIDR validation returns trimmed documentation addresses")
  func addressAndCIDRValidation() {
    let address = ConditionInputValidator.validateAddressOrCIDR(" 192.0.2.17 ")
    let ipv4Network = ConditionInputValidator.validateAddressOrCIDR(" 192.0.2.0/24\n")
    let ipv6Network = ConditionInputValidator.validateAddressOrCIDR("2001:db8::/32")

    #expect(address == .valid("192.0.2.17"))
    #expect(ipv4Network.validatedValue == "192.0.2.0/24")
    #expect(ipv6Network == .valid("2001:db8::/32"))
    #expect(ipv6Network.isValid)
    #expect(ipv6Network.issue == nil)
  }

  @Test("IP and CIDR validation distinguishes missing and malformed input")
  func invalidAddressAndCIDRValidation() {
    let missing = ConditionInputValidator.validateAddressOrCIDR(" \n ")
    let malformedAddress = ConditionInputValidator.validateAddressOrCIDR(
      "192.0.2.999"
    )
    let malformedPrefix = ConditionInputValidator.validateAddressOrCIDR(
      "192.0.2.1/33"
    )

    #expect(missing == .invalid(.missingValue))
    #expect(malformedAddress == .invalid(.malformedValue))
    #expect(malformedPrefix == .invalid(.malformedValue))
    #expect(!malformedPrefix.isValid)
    #expect(malformedPrefix.validatedValue == nil)
    #expect(malformedPrefix.issue == .malformedValue)
  }

  @Test("location validation reports all missing optional fields in stable order")
  func missingLocationFields() {
    let allMissing = ConditionInputValidator.validateLocation(
      latitude: nil,
      longitude: nil,
      radiusMeters: nil
    )
    let someMissing = ConditionInputValidator.validateLocation(
      latitude: 0,
      longitude: nil,
      radiusMeters: nil
    )

    #expect(
      allMissing
        == .invalid(.missingFields([.latitude, .longitude, .radiusMeters]))
    )
    #expect(someMissing == .invalid(.missingFields([.longitude, .radiusMeters])))
  }

  @Test("location validation accepts every inclusive Core boundary")
  func validLocationBoundaries() {
    let minimum = ConditionInputValidator.validateLocation(
      latitude: ConditionInputValidator.latitudeRange.lowerBound,
      longitude: ConditionInputValidator.longitudeRange.lowerBound,
      radiusMeters: ConditionInputValidator.radiusMetersRange.lowerBound
    )
    let maximum = ConditionInputValidator.validateLocation(
      latitude: ConditionInputValidator.latitudeRange.upperBound,
      longitude: ConditionInputValidator.longitudeRange.upperBound,
      radiusMeters: ConditionInputValidator.radiusMetersRange.upperBound
    )

    #expect(
      minimum
        == .valid(LocationRegion(latitude: -90, longitude: -180, radiusMeters: 0))
    )
    #expect(
      maximum
        == .valid(
          LocationRegion(latitude: 90, longitude: 180, radiusMeters: 40_000_000)
        )
    )
  }

  @Test(
    "location validation reports nonfinite and out-of-range fields with Core precedence",
    arguments: [
      (Double.nan, 0.0, 0.0, LocationValidationIssue.nonFinite(.latitude)),
      (-90.1, 0.0, 0.0, .outOfRange(.latitude)),
      (0.0, Double.infinity, 0.0, .nonFinite(.longitude)),
      (0.0, 180.1, 0.0, .outOfRange(.longitude)),
      (0.0, 0.0, -Double.infinity, .nonFinite(.radiusMeters)),
      (0.0, 0.0, 40_000_000.1, .outOfRange(.radiusMeters)),
    ]
  )
  func invalidLocationRanges(
    latitude: Double,
    longitude: Double,
    radiusMeters: Double,
    issue: LocationValidationIssue
  ) {
    let result = ConditionInputValidator.validateLocation(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters
    )

    #expect(result == .invalid(issue))
  }
}
