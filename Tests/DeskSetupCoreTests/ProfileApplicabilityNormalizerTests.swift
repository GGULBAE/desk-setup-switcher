import Foundation
import Testing

@testable import DeskSetupCore

@Suite("Profile applicability normalization")
struct ProfileApplicabilityNormalizerTests {
  private let normalizer = ProfileApplicabilityNormalizer()

  @Test("unsupported snapshot values are preserved, excluded, and idempotent")
  func unsupportedValuesArePreservedAndNormalizationIsIdempotent() throws {
    let displayID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
    let profileID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    let display = DisplayTargetSettings(
      id: displayID,
      identity: DisplayIdentity(productName: "Synthetic Panel"),
      isPrimary: .init(value: true),
      origin: .init(isIncluded: false, value: DisplayPoint(x: 40, y: 20)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)
      ),
      rotationDegrees: .init(value: 270),
      isActive: .init(value: false)
    )
    let ipv4 = IPv4Configuration.manual(
      address: "192.0.2.20",
      subnetMask: "255.255.255.0",
      router: "192.0.2.1"
    )
    let webProxy = ProxyConfiguration(enabled: true, host: "proxy.invalid", port: 8_080)
    let secureProxy = ProxyConfiguration(enabled: false, host: "", port: 0)
    let conditions = ProfileConditionSet(
      mode: .any,
      isInverted: true,
      conditions: [.init(kind: .ethernetConnected)]
    )
    var settings = ProfileSettings()
    settings.display = .init(
      isIncluded: true,
      value: DisplayProfileSettings(displays: [display])
    )
    settings.network = .init(
      isIncluded: true,
      value: NetworkProfileSettings(
        wifiPower: .init(value: true),
        wifiSSID: .init(isIncluded: false, value: "Synthetic Wi-Fi"),
        ipv4: .init(value: ipv4),
        dnsServers: .init(value: ["192.0.2.53", "2001:db8::53"]),
        webProxy: .init(value: webProxy),
        secureWebProxy: .init(value: secureProxy)
      )
    )
    let profile = DeskProfile(
      id: profileID,
      name: "Synthetic",
      profileDescription: "Preserved metadata",
      settings: settings,
      conditions: conditions
    )

    let normalized = normalizer.normalize(profile)
    let normalizedAgain = normalizer.normalize(normalized)
    let normalizedDisplay = try #require(normalized.settings.display.value.displays.first)

    #expect(normalized == normalizedAgain)
    #expect(normalized.id == profileID)
    #expect(normalized.name == profile.name)
    #expect(normalized.profileDescription == profile.profileDescription)
    #expect(normalized.conditions == conditions)
    #expect(normalizedDisplay.id == displayID)
    #expect(normalizedDisplay.rotationDegrees.value == 270)
    #expect(!normalizedDisplay.rotationDegrees.isIncluded)
    #expect(normalizedDisplay.isActive.value == false)
    #expect(!normalizedDisplay.isActive.isIncluded)
    #expect(normalized.settings.display.isIncluded)
    #expect(normalized.settings.network.value.ipv4.value == ipv4)
    #expect(!normalized.settings.network.value.ipv4.isIncluded)
    #expect(normalized.settings.network.value.dnsServers.value == ["192.0.2.53", "2001:db8::53"])
    #expect(!normalized.settings.network.value.dnsServers.isIncluded)
    #expect(normalized.settings.network.value.webProxy.value == webProxy)
    #expect(!normalized.settings.network.value.webProxy.isIncluded)
    #expect(normalized.settings.network.value.secureWebProxy.value == secureProxy)
    #expect(!normalized.settings.network.value.secureWebProxy.isIncluded)
    #expect(normalized.settings.network.isIncluded)
  }

  @Test("groups with no applicable leaves are disabled without deleting values")
  func emptyApplicableGroupsAreDisabled() {
    let display = DisplayTargetSettings(
      identity: DisplayIdentity(productName: "Snapshot-only Panel"),
      isPrimary: .init(isIncluded: false, value: false),
      origin: .init(isIncluded: false, value: DisplayPoint(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: DisplayMode(width: 1_280, height: 720, refreshRate: 60)
      ),
      rotationDegrees: .init(value: 90),
      isActive: .init(value: true)
    )
    var settings = ProfileSettings()
    settings.display = .init(isIncluded: true, value: .init(displays: [display]))
    settings.audio.isIncluded = true
    settings.network = .init(
      isIncluded: true,
      value: .init(dnsServers: .init(value: ["192.0.2.53"]))
    )
    settings.input.isIncluded = true

    let normalized = normalizer.normalize(settings)

    #expect(!normalized.display.isIncluded)
    #expect(!normalized.audio.isIncluded)
    #expect(!normalized.network.isIncluded)
    #expect(!normalized.input.isIncluded)
    #expect(normalized.display.value.displays[0].rotationDegrees.value == 90)
    #expect(normalized.display.value.displays[0].isActive.value)
    #expect(normalized.network.value.dnsServers.value == ["192.0.2.53"])
    for group in SettingGroup.allCases {
      #expect(normalized.payload(for: group) == nil)
    }
  }

  @Test("mixed primary-display inclusion fails closed without changing saved values")
  func mixedPrimaryDisplayInclusionFailsClosed() {
    let first = DisplayTargetSettings(
      identity: DisplayIdentity(productName: "Synthetic Panel A"),
      isPrimary: .init(isIncluded: true, value: false),
      origin: .init(isIncluded: false, value: DisplayPoint(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)
      ),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
    let second = DisplayTargetSettings(
      identity: DisplayIdentity(productName: "Synthetic Panel B"),
      isPrimary: .init(isIncluded: false, value: true),
      origin: .init(isIncluded: false, value: DisplayPoint(x: 1_920, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: DisplayMode(width: 2_560, height: 1_440, refreshRate: 60)
      ),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
    var settings = ProfileSettings()
    settings.display = .init(
      isIncluded: true,
      value: DisplayProfileSettings(displays: [first, second])
    )

    let normalized = normalizer.normalize(settings)
    let normalizedAgain = normalizer.normalize(normalized)

    #expect(normalized == normalizedAgain)
    #expect(!normalized.display.isIncluded)
    #expect(normalized.display.value.displays.map(\.isPrimary.isIncluded) == [false, false])
    #expect(normalized.display.value.displays.map(\.isPrimary.value) == [false, true])
    #expect(normalized.payload(for: .display) == nil)
  }

  @Test("ambiguous enabled primary selection also fails closed")
  func ambiguousEnabledPrimarySelectionFailsClosed() {
    let displays = [
      displayTarget(name: "Synthetic Panel A", isPrimary: true),
      displayTarget(name: "Synthetic Panel B", isPrimary: true),
    ]
    var settings = ProfileSettings()
    settings.display = .init(
      isIncluded: true,
      value: DisplayProfileSettings(displays: displays)
    )

    let normalized = normalizer.normalize(settings)

    #expect(!normalized.display.isIncluded)
    #expect(normalized.display.value.displays.map(\.isPrimary.isIncluded) == [false, false])
    #expect(normalized.display.value.displays.map(\.isPrimary.value) == [true, true])
  }

  private func displayTarget(name: String, isPrimary: Bool) -> DisplayTargetSettings {
    DisplayTargetSettings(
      identity: DisplayIdentity(productName: name),
      isPrimary: .init(value: isPrimary),
      origin: .init(isIncluded: false, value: DisplayPoint(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)
      ),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
  }
}
