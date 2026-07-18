import XCTest

@testable import DeskSetupCore

final class ProfileValidationTests: XCTestCase {
  private let validator = ProfileDocumentValidator()

  func testAcceptsDocumentAtConfiguredLimits() throws {
    let name = String(repeating: "a", count: 1_024)
    let conditions = (0..<100).map { index in
      ProfileCondition(kind: .hardwareConnected(identifier: "device-\(index)"))
    }
    let profile = DeskProfile(
      name: name,
      conditions: ProfileConditionSet(conditions: conditions)
    )
    try validator.validate(ProfileDocument(profiles: [profile], selectedProfileID: profile.id))
  }

  func testRejectsDuplicateProfileIDsAndInvalidSelection() {
    let id = UUID()
    let missingID = UUID()
    let profile = DeskProfile(id: id, name: "Desk")
    let issues = issues(
      in: ProfileDocument(
        profiles: [profile, profile],
        selectedProfileID: missingID
      ))

    XCTAssertTrue(issues.contains(.duplicateProfileID(id)))
    XCTAssertTrue(issues.contains(.invalidSelectedProfileID(missingID)))
  }

  func testRejectsProfileAndConditionLimits() {
    let profiles = (0...500).map { DeskProfile(name: "Desk \($0)") }
    var issues = issues(in: ProfileDocument(profiles: profiles))
    XCTAssertTrue(issues.contains(.tooManyProfiles(actual: 501, maximum: 500)))

    let profileID = UUID()
    let conditions = (0...100).map { index in
      ProfileCondition(kind: .hardwareConnected(identifier: "device-\(index)"))
    }
    let profile = DeskProfile(
      id: profileID,
      name: "Desk",
      conditions: ProfileConditionSet(conditions: conditions)
    )
    issues = self.issues(in: ProfileDocument(profiles: [profile]))
    XCTAssertTrue(
      issues.contains(
        .tooManyConditions(
          profileID: profileID,
          actual: 101,
          maximum: 100
        )))
  }

  func testRejectsStringsByUnicodeScalarCount() {
    let profile = DeskProfile(name: String(repeating: "🙂", count: 1_025))
    let issues = issues(in: ProfileDocument(profiles: [profile]))

    XCTAssertTrue(
      issues.contains { issue in
        guard case .stringTooLong(let path, let scalarCount, let maximum) = issue else {
          return false
        }
        return path.hasSuffix(".name") && scalarCount == 1_025 && maximum == 1_024
      })
  }

  func testRejectsUnsupportedSchema() {
    let issues = issues(in: ProfileDocument(schemaVersion: 2))
    XCTAssertEqual(issues, [.unsupportedSchema(found: 2, expected: 1)])
  }

  func testRejectsBlankProfileNameAndSymbol() {
    let profile = DeskProfile(name: " \n", symbolName: "\t")
    let issues = issues(in: ProfileDocument(profiles: [profile]))

    assertInvalidValue(issues, pathSuffix: ".name", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".symbolName", reason: .blank)
  }

  func testRejectsInvalidDisplayValuesAndDuplicateTargetIDs() {
    let duplicateID = UUID()
    let invalidTarget = displayTarget(
      id: duplicateID,
      origin: .init(value: .init(x: Int.max, y: Int.min)),
      mode: .init(
        value: .init(
          width: 0,
          height: -1,
          pixelWidth: 0,
          pixelHeight: -1,
          refreshRate: .nan
        )),
      rotationDegrees: .init(value: 45)
    )
    let duplicateTarget = displayTarget(
      id: duplicateID,
      mode: .init(value: .init(width: 1_920, height: 1_080, refreshRate: 1_000.01))
    )
    let profile = DeskProfile(
      name: "Invalid display",
      settings: ProfileSettings(
        display: .init(
          value: .init(displays: [invalidTarget, duplicateTarget])
        )
      )
    )
    let issues = issues(in: ProfileDocument(profiles: [profile]))

    assertInvalidValue(issues, pathSuffix: ".displays[0].origin.x", reason: .outOfRange)
    assertInvalidValue(issues, pathSuffix: ".displays[0].origin.y", reason: .outOfRange)
    assertInvalidValue(
      issues,
      pathSuffix: ".displays[0].mode.dimensions",
      reason: .invalidDimensions
    )
    assertInvalidValue(
      issues,
      pathSuffix: ".displays[0].mode.refreshRate",
      reason: .nonFinite
    )
    assertInvalidValue(
      issues,
      pathSuffix: ".displays[0].rotationDegrees",
      reason: .invalidRotation
    )
    assertInvalidValue(
      issues,
      pathSuffix: ".displays[1].id",
      reason: .duplicateIdentifier
    )
    assertInvalidValue(
      issues,
      pathSuffix: ".displays[1].mode.refreshRate",
      reason: .outOfRange
    )
  }

  func testRejectsMissingIncludedDisplayColorProfile() throws {
    var target = displayTarget()
    target.colorProfile = .init(isIncluded: true, value: nil)
    let profile = DeskProfile(
      name: "Missing ColorSync profile",
      settings: ProfileSettings(
        display: .init(value: .init(displays: [target]))
      )
    )
    let document = ProfileDocument(profiles: [profile])

    let issues = issues(in: document)

    assertInvalidValue(
      issues,
      pathSuffix: ".displays[0].colorProfile",
      reason: .missingIncludedValue
    )

    XCTAssertThrowsError(try ProfileJSONCodec().encode(document)) { error in
      guard let validation = error as? ProfileValidationError else {
        return XCTFail("Expected ProfileValidationError, got \(error)")
      }
      assertInvalidValue(
        validation.issues,
        pathSuffix: ".displays[0].colorProfile",
        reason: .missingIncludedValue
      )
    }

    let unvalidatedEncoder = JSONEncoder()
    unvalidatedEncoder.dateEncodingStrategy = .iso8601
    let importedData = try unvalidatedEncoder.encode(document)
    XCTAssertThrowsError(try ProfileJSONCodec().decode(importedData)) { error in
      guard let validation = error as? ProfileValidationError else {
        return XCTFail("Expected ProfileValidationError, got \(error)")
      }
      assertInvalidValue(
        validation.issues,
        pathSuffix: ".displays[0].colorProfile",
        reason: .missingIncludedValue
      )
    }
  }

  func testRejectsMissingAndInvalidIncludedAudioValues() {
    let profile = DeskProfile(
      name: "Invalid audio",
      settings: ProfileSettings(
        audio: .init(
          value: AudioProfileSettings(
            defaultInputUID: .init(value: nil),
            defaultOutputUID: .init(value: " \t"),
            systemOutputUID: .init(value: nil),
            inputVolume: .init(value: -0.01),
            outputVolume: .init(value: 1.01),
            outputMuted: .init(value: nil)
          )
        )
      )
    )
    let issues = issues(in: ProfileDocument(profiles: [profile]))

    assertInvalidValue(issues, pathSuffix: ".defaultInputUID", reason: .missingIncludedValue)
    assertInvalidValue(issues, pathSuffix: ".defaultOutputUID", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".systemOutputUID", reason: .missingIncludedValue)
    assertInvalidValue(issues, pathSuffix: ".inputVolume", reason: .outOfRange)
    assertInvalidValue(issues, pathSuffix: ".outputVolume", reason: .outOfRange)
    assertInvalidValue(issues, pathSuffix: ".outputMuted", reason: .missingIncludedValue)

    var nonFiniteProfile = profile
    nonFiniteProfile.settings.audio.value.outputVolume.value = .infinity
    let nonFiniteIssues = self.issues(in: ProfileDocument(profiles: [nonFiniteProfile]))
    assertInvalidValue(nonFiniteIssues, pathSuffix: ".outputVolume", reason: .nonFinite)
  }

  func testRejectsInvalidIncludedNetworkValues() {
    let privateAddress = "private-address-value"
    let network = NetworkProfileSettings(
      wifiPower: .init(value: nil),
      wifiSSID: .init(value: " \n"),
      serviceIPv4: [
        .init(
          identity: .init(
            kind: .ethernet,
            serviceName: "Synthetic Ethernet",
            interfaceType: "Ethernet"
          ),
          configuration: .init(
            value: .manual(
              address: privateAddress,
              subnetMask: "255.0.255.0",
              router: "not-a-router"
            )
          )
        )
      ],
      ipv4: .init(
        value: .manual(
          address: privateAddress,
          subnetMask: "255.0.255.0",
          router: "not-a-router"
        )
      ),
      dnsServers: .init(
        value: ["8.8.8.8", "not-a-dns-server", "1.1.1.1\0private-suffix"]
      ),
      webProxy: .init(value: .init(enabled: true, host: " \t", port: 0)),
      secureWebProxy: .init(
        value: .init(enabled: true, host: "proxy.example", port: 65_536)
      )
    )
    let profile = DeskProfile(
      name: "Invalid network",
      settings: ProfileSettings(network: .init(value: network))
    )
    let missingProfile = DeskProfile(
      name: "Missing network",
      settings: ProfileSettings(
        network: .init(
          value: .init(
            ipv4: .init(value: nil),
            webProxy: .init(value: nil)
          )
        )
      )
    )
    let issues = issues(in: ProfileDocument(profiles: [profile, missingProfile]))

    assertInvalidValue(issues, pathSuffix: ".wifiPower", reason: .missingIncludedValue)
    assertInvalidValue(issues, pathSuffix: ".wifiSSID", reason: .blank)
    assertInvalidValue(
      issues,
      pathSuffix: ".serviceIPv4[0].address",
      reason: .malformedIPv4Address
    )
    assertInvalidValue(
      issues,
      pathSuffix: ".serviceIPv4[0].subnetMask",
      reason: .malformedSubnetMask
    )
    assertInvalidValue(
      issues,
      pathSuffix: ".serviceIPv4[0].router",
      reason: .malformedIPv4Address
    )
    assertInvalidValue(issues, pathSuffix: ".ipv4.address", reason: .malformedIPv4Address)
    assertInvalidValue(issues, pathSuffix: ".ipv4.subnetMask", reason: .malformedSubnetMask)
    assertInvalidValue(issues, pathSuffix: ".ipv4.router", reason: .malformedIPv4Address)
    assertInvalidValue(issues, pathSuffix: ".dnsServers[1]", reason: .malformedIPAddress)
    assertInvalidValue(issues, pathSuffix: ".dnsServers[2]", reason: .malformedIPAddress)
    assertInvalidValue(issues, pathSuffix: ".webProxy.host", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".webProxy.port", reason: .outOfRange)
    assertInvalidValue(issues, pathSuffix: ".secureWebProxy.port", reason: .outOfRange)
    assertInvalidValue(issues, pathSuffix: ".ipv4", reason: .missingIncludedValue)
    assertInvalidValue(issues, pathSuffix: ".webProxy", reason: .missingIncludedValue)

    let description = String(describing: ProfileValidationError(issues: issues))
    XCTAssertFalse(description.contains(privateAddress))
    XCTAssertFalse(description.contains("not-a-dns-server"))
    XCTAssertFalse(description.contains("private-suffix"))
  }

  func testRejectsMissingNonFiniteAndOutOfRangeIncludedInputValues() {
    let input = InputProfileSettings(
      pointerSpeed: .init(value: 10.01),
      naturalScrolling: .init(value: nil),
      keyRepeatInterval: .init(value: nil),
      initialKeyRepeatDelay: .init(value: .infinity),
      useStandardFunctionKeys: .init(value: nil)
    )
    let profile = DeskProfile(
      name: "Invalid input",
      settings: ProfileSettings(input: .init(value: input))
    )
    let issues = issues(in: ProfileDocument(profiles: [profile]))

    assertInvalidValue(issues, pathSuffix: ".pointerSpeed", reason: .outOfRange)
    assertInvalidValue(issues, pathSuffix: ".naturalScrolling", reason: .missingIncludedValue)
    assertInvalidValue(issues, pathSuffix: ".keyRepeatInterval", reason: .missingIncludedValue)
    assertInvalidValue(issues, pathSuffix: ".initialKeyRepeatDelay", reason: .nonFinite)
    assertInvalidValue(
      issues,
      pathSuffix: ".useStandardFunctionKeys",
      reason: .missingIncludedValue
    )
  }

  func testRejectsBlankMalformedAndInvalidConditionValuesWithoutEchoingThem() {
    let privateMalformedCIDR = "198.51.100.7/private-prefix"
    let conditions = ProfileConditionSet(
      conditions: [
        ProfileCondition(kind: .displayConnected(.init())),
        ProfileCondition(kind: .displayConnected(.init(productName: " \t"))),
        ProfileCondition(kind: .audioInputConnected(uid: " \n")),
        ProfileCondition(kind: .audioOutputConnected(uid: "\t")),
        ProfileCondition(kind: .hardwareConnected(identifier: " ")),
        ProfileCondition(kind: .wifiSSID("\n")),
        ProfileCondition(kind: .ipAddressOrCIDR("not-an-ip-address")),
        ProfileCondition(kind: .ipAddressOrCIDR(privateMalformedCIDR)),
        ProfileCondition(kind: .ipAddressOrCIDR("192.0.2.1\0/24")),
        ProfileCondition(
          kind: .location(
            .init(latitude: .nan, longitude: 181, radiusMeters: -1)
          )
        ),
        ProfileCondition(
          kind: .location(
            .init(latitude: 0, longitude: 0, radiusMeters: .infinity)
          )
        ),
      ]
    )
    let profile = DeskProfile(name: "Invalid conditions", conditions: conditions)
    let issues = issues(in: ProfileDocument(profiles: [profile]))

    assertInvalidValue(issues, pathSuffix: ".conditions[0].display", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".conditions[1].display.productName", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".conditions[2].audioUID", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".conditions[3].audioUID", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".conditions[4].hardwareIdentifier", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".conditions[5].wifiSSID", reason: .blank)
    assertInvalidValue(issues, pathSuffix: ".conditions[6].ipAddressOrCIDR", reason: .malformedCIDR)
    assertInvalidValue(issues, pathSuffix: ".conditions[7].ipAddressOrCIDR", reason: .malformedCIDR)
    assertInvalidValue(issues, pathSuffix: ".conditions[8].ipAddressOrCIDR", reason: .malformedCIDR)
    assertInvalidValue(issues, pathSuffix: ".conditions[9].location.latitude", reason: .nonFinite)
    assertInvalidValue(issues, pathSuffix: ".conditions[9].location.longitude", reason: .outOfRange)
    assertInvalidValue(
      issues, pathSuffix: ".conditions[9].location.radiusMeters", reason: .outOfRange)
    assertInvalidValue(
      issues, pathSuffix: ".conditions[10].location.radiusMeters", reason: .nonFinite)

    let description = String(describing: ProfileValidationError(issues: issues))
    XCTAssertFalse(description.contains(privateMalformedCIDR))
    XCTAssertFalse(description.contains("not-an-ip-address"))
  }

  func testAcceptsExcludedNilValuesAndValidBoundaryValues() throws {
    let display = displayTarget(
      origin: .init(value: .init(x: Int(Int32.min), y: Int(Int32.max))),
      mode: .init(value: .init(width: 1, height: 1, refreshRate: 0)),
      rotationDegrees: .init(value: 270)
    )
    let settings = ProfileSettings(
      display: .init(value: .init(displays: [display])),
      audio: .init(
        value: .init(
          defaultInputUID: .init(value: "input-device"),
          defaultOutputUID: .init(value: "output-device"),
          systemOutputUID: .init(value: "system-device"),
          outputVolume: .init(value: 1),
          outputMuted: .init(value: true)
        )
      ),
      network: .init(
        value: .init(
          wifiPower: .init(value: true),
          wifiSSID: .init(value: "Office"),
          ipv4: .init(
            value: .manual(
              address: "192.168.1.20",
              subnetMask: "255.255.255.0",
              router: nil
            )
          ),
          dnsServers: .init(value: ["8.8.8.8", "2001:4860:4860::8888"]),
          webProxy: .init(value: .init(enabled: false, host: "", port: 0)),
          secureWebProxy: .init(
            value: .init(enabled: true, host: "proxy.example", port: 65_535)
          )
        )
      ),
      input: .init(
        value: .init(
          pointerSpeed: .init(value: -1),
          naturalScrolling: .init(value: true),
          keyRepeatInterval: .init(value: 120),
          initialKeyRepeatDelay: .init(value: 300),
          useStandardFunctionKeys: .init(value: false)
        )
      )
    )
    let conditions = ProfileConditionSet(
      conditions: [
        .init(kind: .ipAddressOrCIDR("192.168.1.20")),
        .init(kind: .ipAddressOrCIDR("2001:db8::/32")),
        .init(kind: .location(.init(latitude: -90, longitude: 180, radiusMeters: 0))),
        .init(
          kind: .location(
            .init(latitude: 90, longitude: -180, radiusMeters: 40_000_000)
          )
        ),
      ]
    )
    let boundaryProfile = DeskProfile(
      name: "Boundary values",
      settings: settings,
      conditions: conditions
    )
    let optionExcludedProfile = DeskProfile(
      name: "Excluded options",
      settings: ProfileSettings(
        audio: .init(value: .init()),
        network: .init(value: .init()),
        input: .init(value: .init())
      )
    )
    let groupExcludedProfile = DeskProfile(
      name: "Excluded groups",
      settings: ProfileSettings(
        display: .init(
          isIncluded: false,
          value: .init(
            displays: [
              displayTarget(
                origin: .init(value: .init(x: Int.max, y: Int.min)),
                mode: .init(value: .init(width: 0, height: 0, refreshRate: -1)),
                rotationDegrees: .init(value: 1)
              )
            ]
          )
        ),
        audio: .init(
          isIncluded: false,
          value: .init(defaultInputUID: .init(value: nil), outputVolume: .init(value: 2))
        ),
        network: .init(
          isIncluded: false,
          value: .init(
            wifiSSID: .init(value: nil),
            ipv4: .init(value: nil),
            webProxy: .init(value: nil)
          )
        ),
        input: .init(
          isIncluded: false,
          value: .init(pointerSpeed: .init(value: nil))
        )
      )
    )

    try validator.validate(
      ProfileDocument(
        profiles: [boundaryProfile, optionExcludedProfile, groupExcludedProfile]
      )
    )
  }

  func testStorageErrorsDiscardAndDoNotEchoUnderlyingValues() throws {
    let privateValue = "private-network-name-and-address"
    let errors: [ProfileStorageError] = [
      .invalidJSON(privateValue),
      .io(privateValue),
    ]

    for error in errors {
      XCTAssertFalse(error.localizedDescription.contains(privateValue))
      XCTAssertFalse(String(describing: error).contains(privateValue))
      XCTAssertFalse(String(reflecting: error).contains(privateValue))
    }

    let codec = ProfileJSONCodec()
    let encoded = try codec.encode(
      ProfileDocument(
        profiles: [
          DeskProfile(
            name: "Desk",
            conditions: .init(conditions: [.init(kind: .ethernetConnected)])
          )
        ]
      )
    )
    let validJSON = try XCTUnwrap(String(data: encoded, encoding: .utf8))
    let invalidJSON = validJSON.replacingOccurrences(
      of: #""mode" : "all""#,
      with: #""mode" : "private-network-name-and-address""#
    )
    XCTAssertNotEqual(invalidJSON, validJSON)

    XCTAssertThrowsError(try codec.decode(Data(invalidJSON.utf8))) { error in
      XCTAssertEqual(error as? ProfileStorageError, .invalidJSON)
      XCTAssertFalse(error.localizedDescription.contains(privateValue))
      XCTAssertFalse(String(describing: error).contains(privateValue))
      XCTAssertFalse(String(reflecting: error).contains(privateValue))
    }
  }

  func testCodecRejectsMoreThanFiveMiBBeforeParsing() {
    let data = Data(repeating: 0x20, count: 5 * 1_024 * 1_024 + 1)
    XCTAssertThrowsError(try ProfileJSONCodec().decode(data)) { error in
      XCTAssertEqual(
        error as? ProfileStorageError,
        .fileTooLarge(actualBytes: data.count, maximumBytes: 5 * 1_024 * 1_024)
      )
    }
  }

  private func issues(in document: ProfileDocument) -> [ProfileValidationIssue] {
    do {
      try validator.validate(document)
      XCTFail("Expected validation to fail")
      return []
    } catch let error as ProfileValidationError {
      return error.issues
    } catch {
      XCTFail("Unexpected error: \(error)")
      return []
    }
  }

  private func assertInvalidValue(
    _ issues: [ProfileValidationIssue],
    pathSuffix: String,
    reason: ProfileInvalidValueReason,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(
      issues.contains { issue in
        guard case .invalidValue(let path, let actualReason) = issue else { return false }
        return path.hasSuffix(pathSuffix) && actualReason == reason
      },
      "Expected invalid value at path ending in \(pathSuffix) with reason \(reason)",
      file: file,
      line: line
    )
  }

  private func displayTarget(
    id: UUID = UUID(),
    origin: SettingOption<DisplayPoint> = .init(value: .init(x: 0, y: 0)),
    mode: SettingOption<DisplayMode> = .init(
      value: .init(width: 1_920, height: 1_080, refreshRate: 60)
    ),
    rotationDegrees: SettingOption<Int> = .init(value: 0)
  ) -> DisplayTargetSettings {
    DisplayTargetSettings(
      id: id,
      identity: .init(),
      isPrimary: .init(value: false),
      origin: origin,
      mirroring: .init(value: .extended),
      mode: mode,
      rotationDegrees: rotationDegrees,
      isActive: .init(value: true)
    )
  }
}
