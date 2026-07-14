import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupPresentation

@Suite("Profile draft validation")
struct ProfileDraftValidationTests {
  @Test("included groups without leaves report stable group fields")
  func noLeafGroups() {
    let settings = ProfileSettings(
      display: .init(value: .init()),
      audio: .init(value: .init()),
      network: .init(value: .init()),
      input: .init(value: .init())
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(!result.isValid)
    #expect(
      result.issues.map(\.fieldID) == [
        .group(.display), .group(.audio), .group(.network), .group(.input),
      ]
    )
    #expect(result.issues.allSatisfy { $0.message == .selectAtLeastOneSetting })
    #expect(result.firstInvalidField == .group(.display))
  }

  @Test("missing and blank audio values identify their exact controls")
  func missingAndBlankAudioValues() {
    let settings = ProfileSettings(
      audio: .init(
        value: .init(
          defaultInputUID: .init(value: nil),
          defaultOutputUID: .init(value: " \t "),
          outputVolume: .init(value: nil),
          outputMuted: .init(value: nil)
        )
      )
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(
      result.issues == [
        issue(.audio(.defaultInputDevice), .audio, .required),
        issue(.audio(.defaultOutputDevice), .audio, .cannotBeBlank),
        issue(.audio(.outputVolume), .audio, .required),
        issue(.audio(.outputMute), .audio, .required),
      ]
    )
  }

  @Test("display mode dimensions refresh rate and rotation are validated")
  func displayModeValidation() {
    let display = DisplayTargetSettings(
      id: displayID,
      identity: .init(productName: "Synthetic display"),
      isPrimary: .init(isIncluded: false, value: true),
      origin: .init(isIncluded: false, value: .init(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        value: .init(
          width: 0,
          height: 100_001,
          pixelWidth: -1,
          pixelHeight: 100_001,
          refreshRate: .infinity
        )
      ),
      rotationDegrees: .init(value: 45),
      isActive: .init(isIncluded: false, value: true)
    )
    let settings = ProfileSettings(
      display: .init(value: .init(displays: [display]))
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(
      result.issues.map(\.fieldID) == [
        .display(displayID, .modeWidth),
        .display(displayID, .modeHeight),
        .display(displayID, .modePixelWidth),
        .display(displayID, .modePixelHeight),
        .display(displayID, .modeRefreshRate),
        .display(displayID, .rotationDegrees),
      ]
    )
    #expect(
      result.issue(for: .display(displayID, .modeWidth))?.message
        == .invalidDisplayDimension
    )
    #expect(
      result.issue(for: .display(displayID, .modeRefreshRate))?.message
        == .outOfRange(minimum: 0, maximum: 1_000)
    )
  }

  @Test("primary display inclusion requires exactly one selected target")
  func primaryDisplayValidation() {
    let first = validDisplay(id: displayID, isPrimary: true)
    let second = validDisplay(
      id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
      isPrimary: true
    )
    let settings = ProfileSettings(
      display: .init(value: .init(displays: [first, second]))
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(result.issue(for: .displayPrimary)?.message == .chooseOnePrimaryDisplay)
  }

  @Test("primary display inclusion is one global option across every target")
  func primaryDisplayRejectsMixedInclusion() {
    var first = validDisplay(id: displayID, isPrimary: true)
    var second = validDisplay(
      id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
      isPrimary: false
    )
    first.isPrimary.isIncluded = true
    second.isPrimary.isIncluded = false
    let settings = ProfileSettings(
      display: .init(value: .init(displays: [first, second]))
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(
      result.issue(for: .displayPrimary)?.message == .repairPrimaryDisplayInclusion
    )
  }

  @Test("volume and input ranges reject non-finite and out-of-range values")
  func numericRanges() {
    let settings = ProfileSettings(
      audio: .init(value: .init(outputVolume: .init(value: 1.01))),
      input: .init(
        value: .init(
          pointerSpeed: .init(value: -.infinity),
          keyRepeatInterval: .init(value: 0),
          initialKeyRepeatDelay: .init(value: 301)
        )
      )
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(
      result.issues == [
        issue(.audio(.outputVolume), .audio, .outOfRange(minimum: 0, maximum: 1)),
        issue(.input(.pointerSpeed), .input, .outOfRange(minimum: -1, maximum: 10)),
        issue(
          .input(.keyRepeatInterval),
          .input,
          .outOfRange(minimum: 1, maximum: 120)
        ),
        issue(
          .input(.initialKeyRepeatDelay),
          .input,
          .outOfRange(minimum: 1, maximum: 300)
        ),
      ]
    )
  }

  @Test("Wi-Fi manual IPv4 DNS and proxy errors have field-specific identifiers")
  func networkFieldValidation() {
    let settings = ProfileSettings(
      network: .init(
        value: .init(
          wifiPower: .init(value: nil),
          wifiSSID: .init(value: "  "),
          ipv4: .init(
            value: .manual(
              address: "999.0.0.1",
              subnetMask: "255.0.255.0",
              router: ""
            )
          ),
          dnsServers: .init(value: ["not-an-address"]),
          webProxy: .init(value: nil),
          secureWebProxy: .init(
            value: .init(enabled: true, host: " \n", port: 65_536)
          )
        )
      )
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(
      result.issues == [
        issue(.network(.wifiPower), .network, .required),
        issue(.network(.wifiSSID), .network, .cannotBeBlank),
        issue(.network(.ipv4Address), .network, .invalidIPv4Address),
        issue(.network(.ipv4SubnetMask), .network, .invalidSubnetMask),
        issue(.network(.ipv4Router), .network, .invalidIPv4Address),
        issue(.dnsServer(at: 0), .network, .invalidIPAddress),
        issue(.network(.webProxy), .network, .required),
        issue(.network(.secureWebProxyHost), .network, .cannotBeBlank),
        issue(
          .network(.secureWebProxyPort),
          .network,
          .outOfRange(minimum: 1, maximum: 65_535)
        ),
      ]
    )
  }

  @Test("Wi-Fi names enforce the adapter's UTF-8 byte limit before save")
  func wifiByteLengthValidation() {
    let settings = ProfileSettings(
      network: .init(
        value: .init(
          wifiSSID: .init(value: String(repeating: "가", count: 11))
        )
      )
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(
      result.issue(for: .network(.wifiSSID))?.message
        == .invalidWiFiNetworkName
    )
  }

  @Test("nil manual network configuration reports the option without hiding proxy errors")
  func missingNetworkConfigurationContinuesValidation() {
    let settings = ProfileSettings(
      network: .init(
        value: .init(
          ipv4: .init(value: nil),
          webProxy: .init(
            value: .init(enabled: true, host: "", port: 0)
          )
        )
      )
    )

    let result = ProfileDraftValidator().validate(settings)

    #expect(
      result.issues == [
        issue(.network(.ipv4), .network, .required),
        issue(.network(.webProxyHost), .network, .cannotBeBlank),
        issue(
          .network(.webProxyPort),
          .network,
          .outOfRange(minimum: 1, maximum: 65_535)
        ),
      ]
    )
  }

  @Test("excluded groups preserve invalid values without blocking save")
  func excludedGroupsAreNotValidated() {
    let settings = ProfileSettings(
      audio: .init(
        isIncluded: false,
        value: .init(outputVolume: .init(value: 2))
      ),
      network: .init(
        isIncluded: false,
        value: .init(wifiSSID: .init(value: ""))
      )
    )

    #expect(ProfileDraftValidator().validate(settings).isValid)
  }

  @Test("valid values pass and disabled proxy values need no host or port")
  func validDraft() {
    let settings = ProfileSettings(
      audio: .init(
        value: .init(
          defaultOutputUID: .init(value: "synthetic-output"),
          outputVolume: .init(value: 0.5),
          outputMuted: .init(value: false)
        )
      ),
      network: .init(
        value: .init(
          wifiPower: .init(value: true),
          wifiSSID: .init(value: "Synthetic Network"),
          ipv4: .init(
            value: .manual(
              address: "192.0.2.10",
              subnetMask: "255.255.255.0",
              router: "192.0.2.1"
            )
          ),
          dnsServers: .init(value: ["2001:db8::1"]),
          webProxy: .init(value: .init(enabled: false, host: "", port: 0)),
          secureWebProxy: .init(
            value: .init(enabled: true, host: "proxy.example", port: 443)
          )
        )
      ),
      input: .init(
        value: .init(
          pointerSpeed: .init(value: 1),
          naturalScrolling: .init(value: true),
          keyRepeatInterval: .init(value: 30),
          initialKeyRepeatDelay: .init(value: 45),
          useStandardFunctionKeys: .init(value: false)
        )
      )
    )

    #expect(ProfileDraftValidator().validate(settings).isValid)
  }

  @Test("field identifiers and message keys are deterministic and localizable")
  func stableIdentifiersAndMessages() {
    let field = DraftFieldIdentifier.display(displayID, .modeRefreshRate)
    let issue = DraftValidationIssue(
      fieldID: field,
      group: .display,
      message: .outOfRange(minimum: 0, maximum: 1_000)
    )

    #expect(
      field.rawValue
        == "settings.display.20000000-0000-0000-0000-000000000001.modeRefreshRate"
    )
    #expect(issue.id == field)
    #expect(issue.localizationKey == "validation.range")
    #expect(issue.defaultMessage == "Enter a value from 0 through 1000.")
  }

  @Test("profile metadata and advanced device values respect storage length limits")
  func editableStringLengthLimits() {
    let tooLong = String(repeating: "a", count: 1_025)
    let profile = DeskProfile(
      name: tooLong,
      profileDescription: tooLong,
      settings: ProfileSettings(
        audio: .init(
          isIncluded: false,
          value: .init(
            defaultInputUID: .init(isIncluded: false, value: tooLong)
          )
        )
      )
    )

    let result = ProfileDraftValidator().validate(profile)

    #expect(
      result.issues.map(\.fieldID) == [
        .profileName,
        .profileDescription,
        .audio(.defaultInputDevice),
      ]
    )
    #expect(
      result.issues.allSatisfy {
        $0.message == .tooLong(maximum: ProfileDraftValidator.maximumStringScalars)
      }
    )
  }

  @Test("validation types satisfy Sendable contracts")
  func sendableContracts() {
    requireSendable(ProfileDraftValidator())
    requireSendable(ProfileDraftValidation(issues: []))
    requireSendable(
      DraftValidationIssue(
        fieldID: .audio(.outputVolume),
        group: .audio,
        message: .required
      )
    )
  }

  private func issue(
    _ fieldID: DraftFieldIdentifier,
    _ group: SettingGroup,
    _ message: DraftValidationMessage
  ) -> DraftValidationIssue {
    DraftValidationIssue(fieldID: fieldID, group: group, message: message)
  }

  private func requireSendable<T: Sendable>(_ value: T) {
    _ = value
  }

  private func validDisplay(id: UUID, isPrimary: Bool) -> DisplayTargetSettings {
    DisplayTargetSettings(
      id: id,
      identity: .init(productName: "Synthetic display"),
      isPrimary: .init(value: isPrimary),
      origin: .init(isIncluded: false, value: .init(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: .init(width: 1_920, height: 1_080, refreshRate: 60)
      ),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
  }

  private var displayID: UUID {
    UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
  }
}
