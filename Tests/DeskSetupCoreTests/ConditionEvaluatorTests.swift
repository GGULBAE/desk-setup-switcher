import XCTest

@testable import DeskSetupCore

final class ConditionEvaluatorTests: XCTestCase {
  private let evaluator = ConditionEvaluator()

  func testAllModeEvaluatesEverySupportedConditionKind() {
    let display = DisplayIdentity(
      vendorID: 100,
      modelID: 200,
      serialNumber: 300,
      productName: "Synthetic Display"
    )
    let conditions = ProfileConditionSet(
      mode: .all,
      conditions: [
        .init(kind: .displayConnected(display)),
        .init(kind: .audioInputConnected(uid: "audio-input-synthetic")),
        .init(kind: .audioOutputConnected(uid: "audio-output-synthetic")),
        .init(kind: .hardwareConnected(identifier: "usb-synthetic")),
        .init(kind: .wifiSSID("Synthetic Wi-Fi")),
        .init(kind: .ethernetConnected),
        .init(kind: .ipAddressOrCIDR("2001:db8:42::/48")),
        .init(
          kind: .location(
            .init(
              latitude: 37.0,
              longitude: 127.0,
              radiusMeters: 1_000
            ))),
      ])
    let context = ConditionContext(
      displays: [display],
      audioInputUIDs: ["audio-input-synthetic"],
      audioOutputUIDs: ["audio-output-synthetic"],
      hardwareIdentifiers: ["usb-synthetic"],
      wifiSSID: "Synthetic Wi-Fi",
      ethernetConnected: true,
      ipAddresses: ["2001:db8:42::99"],
      location: .init(latitude: 37.001, longitude: 127.0, radiusMeters: 10)
    )

    let result = evaluator.evaluate(conditions, in: context)

    XCTAssertTrue(result.isMatched)
    XCTAssertEqual(result.items.count, conditions.conditions.count)
    XCTAssertTrue(result.items.allSatisfy(\.isMatched))
  }

  func testAnyModeMatchesWhenOneConditionMatches() {
    let conditions = ProfileConditionSet(
      mode: .any,
      conditions: [
        .init(kind: .ethernetConnected),
        .init(kind: .audioOutputConnected(uid: "present-output")),
      ])
    let context = ConditionContext(audioOutputUIDs: ["present-output"])

    XCTAssertTrue(evaluator.evaluate(conditions, in: context).isMatched)
  }

  func testConditionAndSetInversion() {
    let conditionInversion = ProfileConditionSet(conditions: [
      .init(kind: .ethernetConnected, isInverted: true)
    ])
    let setInversion = ProfileConditionSet(
      mode: .all,
      isInverted: true,
      conditions: [.init(kind: .ethernetConnected)]
    )
    let context = ConditionContext(ethernetConnected: false)

    XCTAssertTrue(evaluator.evaluate(conditionInversion, in: context).isMatched)
    XCTAssertTrue(evaluator.evaluate(setInversion, in: context).isMatched)
  }

  func testEmptyConditionSetHasNoRestriction() {
    XCTAssertTrue(
      evaluator.evaluate(ProfileConditionSet(mode: .all), in: .init()).isMatched
    )
    XCTAssertTrue(
      evaluator.evaluate(ProfileConditionSet(mode: .any), in: .init()).isMatched
    )
  }

  func testUnavailableFactDoesNotBecomeMatchedWhenInverted() {
    let conditions = ProfileConditionSet(conditions: [
      .init(
        kind: .location(.init(latitude: 37, longitude: 127, radiusMeters: 100)),
        isInverted: true
      )
    ])

    let result = evaluator.evaluate(conditions, in: .init(location: nil))

    XCTAssertFalse(result.isMatched)
    XCTAssertFalse(result.items[0].isMatched)
  }

  func testFailedFactSourcesStayUnavailableForEveryConditionKindWhenInverted() {
    let display = DisplayIdentity(vendorID: 100, modelID: 200, serialNumber: 300)
    let cases: [(ProfileConditionKind, ConditionContextSource)] = [
      (.displayConnected(display), .displays),
      (.audioInputConnected(uid: "missing-input"), .audio),
      (.audioOutputConnected(uid: "missing-output"), .audio),
      (.hardwareConnected(identifier: "missing-hardware"), .hardware),
      (.wifiSSID("Synthetic Wi-Fi"), .network),
      (.ethernetConnected, .network),
      (.ipAddressOrCIDR("192.0.2.0/24"), .network),
      (
        .location(.init(latitude: 37, longitude: 127, radiusMeters: 100)),
        .location
      ),
    ]

    for (kind, source) in cases {
      let conditions = ProfileConditionSet(conditions: [
        .init(kind: kind, isInverted: true)
      ])
      let context = ConditionContext(unavailableSources: [source])

      let result = evaluator.evaluate(conditions, in: context)

      XCTAssertFalse(result.isMatched, "Unexpected match for unavailable \(source.rawValue)")
      XCTAssertFalse(result.items[0].isMatched)
      XCTAssertTrue(result.items[0].explanation.contains("unavailable"))
    }
  }

  func testSetInversionDoesNotTurnUnavailableSourceIntoMatch() {
    let conditions = ProfileConditionSet(
      isInverted: true,
      conditions: [
        .init(kind: .ethernetConnected),
        .init(kind: .audioOutputConnected(uid: "missing-output")),
      ]
    )
    let context = ConditionContext(
      ethernetConnected: false,
      unavailableSources: [.audio]
    )

    let result = evaluator.evaluate(conditions, in: context)

    XCTAssertFalse(result.isMatched)
    XCTAssertFalse(result.items[0].isMatched)
  }

  func testConditionContextDecodesLegacyPayloadWithoutAvailabilityMetadata() throws {
    let legacyPayload = """
      {
        "displays": [],
        "audioInputUIDs": [],
        "audioOutputUIDs": [],
        "hardwareIdentifiers": [],
        "ethernetConnected": false,
        "ipAddresses": []
      }
      """

    let decoded = try JSONDecoder().decode(
      ConditionContext.self,
      from: Data(legacyPayload.utf8)
    )

    XCTAssertTrue(decoded.unavailableSources.isEmpty)
  }

  func testConditionContextCodableRoundTripPreservesUnavailableSources() throws {
    let context = ConditionContext(unavailableSources: [.audio, .network])

    let encoded = try JSONEncoder().encode(context)
    let decoded = try JSONDecoder().decode(ConditionContext.self, from: encoded)

    XCTAssertEqual(decoded, context)
  }

  func testAnyModePropagatesUnavailableWhenNothingMatches() {
    let conditions = ProfileConditionSet(
      mode: .any,
      conditions: [
        .init(kind: .wifiSSID("Synthetic Wi-Fi")),
        .init(kind: .ethernetConnected),
      ])

    let result = evaluator.evaluate(
      conditions,
      in: .init(
        wifiSSID: nil,
        ethernetConnected: false
      ))

    XCTAssertFalse(result.isMatched)
  }

  func testAmbiguousDisplayIdentityDoesNotMatch() {
    let desired = DisplayIdentity(vendorID: 100, modelID: 200)
    let first = DisplayIdentity(vendorID: 100, modelID: 200, productName: "A")
    let second = DisplayIdentity(vendorID: 100, modelID: 200, productName: "B")
    let conditions = ProfileConditionSet(conditions: [
      .init(kind: .displayConnected(desired))
    ])

    let result = evaluator.evaluate(
      conditions,
      in: .init(displays: [first, second])
    )

    XCTAssertFalse(result.isMatched)
    XCTAssertTrue(result.items[0].explanation.contains("More than one"))
  }

  func testInvalidCIDRDoesNotMatchEvenWhenInverted() {
    let conditions = ProfileConditionSet(conditions: [
      .init(kind: .ipAddressOrCIDR("192.0.2.1/99"), isInverted: true)
    ])

    XCTAssertFalse(
      evaluator.evaluate(
        conditions,
        in: .init(ipAddresses: ["192.0.2.1"])
      ).isMatched
    )
  }

  func testLocationAccuracyMustFitInsideRequiredRegion() {
    let conditions = ProfileConditionSet(conditions: [
      .init(
        kind: .location(
          .init(
            latitude: 0,
            longitude: 0,
            radiusMeters: 100
          )))
    ])

    let precise = evaluator.evaluate(
      conditions,
      in: .init(location: .init(latitude: 0, longitude: 0, radiusMeters: 10))
    )
    let imprecise = evaluator.evaluate(
      conditions,
      in: .init(location: .init(latitude: 0, longitude: 0, radiusMeters: 150))
    )

    XCTAssertTrue(precise.isMatched)
    XCTAssertFalse(imprecise.isMatched)
  }
}
