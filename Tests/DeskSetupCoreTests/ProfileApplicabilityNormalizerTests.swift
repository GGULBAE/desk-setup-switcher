import Foundation
import Testing

@testable import DeskSetupCore

@Suite("Profile applicability normalization")
struct ProfileApplicabilityNormalizerTests {
  private let normalizer = ProfileApplicabilityNormalizer()

  @Test("explicit sound exclusions survive normalization and JSON round trips")
  func registeredAudioValuesParticipateAcrossJSONRoundTrip() throws {
    var settings = ProfileSettings()
    settings.audio.value = .init(
      defaultInputUID: .init(isIncluded: false, value: "synthetic-input"),
      defaultOutputUID: .init(isIncluded: false, value: "synthetic-output"),
      systemOutputUID: .init(value: "synthetic-alert"),
      inputVolume: .init(isIncluded: false, value: 0),
      outputVolume: .init(isIncluded: false, value: 1),
      outputMuted: .init(value: true)
    )
    let profile = DeskProfile(
      name: "Registered values", settings: settings,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let normalized = normalizer.normalize(profile)
    let audio = normalized.settings.audio.value
    #expect(normalized.settings.audio.isIncluded)
    #expect(audio.defaultInputUID == .init(isIncluded: false, value: "synthetic-input"))
    #expect(audio.defaultOutputUID == .init(isIncluded: false, value: "synthetic-output"))
    #expect(audio.inputVolume == .init(isIncluded: false, value: 0))
    #expect(audio.outputVolume == .init(isIncluded: false, value: 1))
    #expect(!audio.systemOutputUID.isIncluded)
    #expect(audio.outputMuted.isIncluded)
    #expect(!profile.settings.audio.value.defaultInputUID.isIncluded)
    let codec = ProfileJSONCodec()
    let decoded = try codec.decode(codec.encode(.init(profiles: [profile])))
    #expect(decoded.document.profiles == [normalized])
    #expect(decoded.wasNormalized)
    let roundTrip = try codec.decode(codec.encode(decoded.document))
    #expect(roundTrip.document == decoded.document)
    #expect(!roundTrip.requiresPersistence)
  }

  @Test("missing values stay absent and invalid requested values are not silently repaired")
  func missingAndInvalidValuesAreNotInvented() throws {
    var settings = ProfileSettings()
    #expect(!normalizer.normalize(settings).audio.isIncluded)
    settings.audio.value.defaultOutputUID = .init(value: "synthetic-output")
    settings.audio.value.inputVolume = .init(value: nil)
    settings.audio.value.outputVolume = .init(isIncluded: false, value: 2)
    let normalized = normalizer.normalize(settings)
    #expect(normalized.audio.value.defaultInputUID == .init(isIncluded: false, value: nil))
    #expect(normalized.audio.value.inputVolume == .init(value: nil))
    #expect(normalized.audio.value.outputVolume == .init(isIncluded: false, value: 2))
    #expect(throws: (any Error).self) {
      try ProfileJSONCodec().encode(
        .init(profiles: [
          DeskProfile(name: "Invalid volume", settings: normalized)
        ]))
    }
  }

  @Test("unsupported snapshot values are preserved, excluded, and idempotent")
  func unsupportedValuesArePreservedAndNormalizationIsIdempotent() throws {
    let displayID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
    let profileID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    let display = DisplayTargetSettings(
      id: displayID,
      identity: DisplayIdentity(productName: "Synthetic Panel"),
      isPrimary: .init(value: true),
      origin: .init(value: DisplayPoint(x: 40, y: 20)),
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
        serviceIPv4: [
          .init(
            identity: .init(
              kind: .ethernet,
              serviceName: "Synthetic Ethernet",
              interfaceType: "Ethernet"
            ),
            configuration: .init(value: ipv4)
          )
        ],
        ipv4: .init(value: ipv4),
        dnsServers: .init(value: ["192.0.2.53", "2001:db8::53"]),
        webProxy: .init(value: webProxy),
        secureWebProxy: .init(value: secureProxy)
      )
    )
    settings.audio = .init(
      isIncluded: true,
      value: .init(
        defaultInputUID: .init(value: "synthetic-input"),
        systemOutputUID: .init(value: "synthetic-system-output"),
        outputMuted: .init(value: true)
      )
    )
    settings.input = .init(
      isIncluded: true,
      value: .init(pointerSpeed: .init(value: 4.5))
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
    #expect(!normalizedDisplay.isPrimary.isIncluded)
    #expect(normalizedDisplay.isPrimary.value)
    #expect(normalizedDisplay.origin.value == DisplayPoint(x: 40, y: 20))
    #expect(!normalizedDisplay.origin.isIncluded)
    #expect(!normalizedDisplay.mode.isIncluded)
    #expect(normalizedDisplay.rotationDegrees.value == 270)
    #expect(!normalizedDisplay.rotationDegrees.isIncluded)
    #expect(normalizedDisplay.isActive.value == false)
    #expect(!normalizedDisplay.isActive.isIncluded)
    #expect(!normalized.settings.display.isIncluded)
    #expect(normalized.settings.audio.isIncluded)
    #expect(normalized.settings.audio.value.defaultInputUID.isIncluded)
    #expect(!normalized.settings.audio.value.systemOutputUID.isIncluded)
    #expect(normalized.settings.audio.value.outputMuted.isIncluded)
    #expect(normalized.settings.audio.value.outputMuted.value == true)
    #expect(normalized.settings.network.value.serviceIPv4[0].configuration.value == ipv4)
    #expect(!normalized.settings.network.value.serviceIPv4[0].configuration.isIncluded)
    #expect(normalized.settings.network.value.ipv4.value == ipv4)
    #expect(!normalized.settings.network.value.ipv4.isIncluded)
    #expect(normalized.settings.network.value.dnsServers.value == ["192.0.2.53", "2001:db8::53"])
    #expect(!normalized.settings.network.value.dnsServers.isIncluded)
    #expect(normalized.settings.network.value.webProxy.value == webProxy)
    #expect(!normalized.settings.network.value.webProxy.isIncluded)
    #expect(normalized.settings.network.value.secureWebProxy.value == secureProxy)
    #expect(!normalized.settings.network.value.secureWebProxy.isIncluded)
    #expect(!normalized.settings.network.isIncluded)
    #expect(!normalized.settings.input.isIncluded)
    #expect(normalized.settings.input.value.pointerSpeed.value == 4.5)
    #expect(!normalized.settings.input.value.pointerSpeed.isIncluded)
  }

  @Test("legacy color profiles stay dormant after normalization and JSON import")
  func legacyColorProfileIsExcludedWithoutDeletingItsValue() throws {
    let color = ColorSyncProfileTarget(
      registeredProfileID: "synthetic-legacy",
      fileSHA256: String(repeating: "a", count: 64),
      displayName: "Synthetic Legacy ICC"
    )
    let display = DisplayTargetSettings(
      identity: DisplayIdentity(productName: "Synthetic Panel"),
      isPrimary: .init(isIncluded: false, value: true),
      origin: .init(isIncluded: false, value: .init(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(isIncluded: false, value: .init(width: 1_920, height: 1_080, refreshRate: 60)),
      colorProfile: .init(value: color),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
    let profile = DeskProfile(
      name: "Synthetic legacy color",
      settings: .init(display: .init(value: .init(displays: [display]))),
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let normalized = normalizer.normalize(profile)
    #expect(!normalized.settings.display.isIncluded)
    #expect(!normalized.settings.display.value.displays[0].colorProfile.isIncluded)
    #expect(normalized.settings.display.value.displays[0].colorProfile.value == color)
    #expect(normalizer.normalize(normalized) == normalized)
    let codec = ProfileJSONCodec()
    let imported = try codec.decode(codec.encode(ProfileDocument(profiles: [profile])))
    #expect(imported.wasNormalized)
    #expect(imported.document.profiles[0] == normalized)
    let roundTrip = try codec.decode(codec.encode(imported.document))
    #expect(!roundTrip.wasNormalized)
    #expect(roundTrip.document == imported.document)
  }

  @Test(
    "excluded mute and unmute values remain dormant across JSON round trips",
    arguments: [true, false])
  func outputMuteRemainsApplicable(value: Bool) throws {
    var settings = ProfileSettings()
    settings.audio.value.outputMuted = .init(isIncluded: false, value: value)

    let normalized = normalizer.normalize(settings)

    #expect(!normalized.audio.isIncluded)
    #expect(normalized.audio.value.outputMuted == .init(isIncluded: false, value: value))
    #expect(normalized.payload(for: .audio) == nil)
    #expect(normalizer.normalize(normalized) == normalized)
    let codec = ProfileJSONCodec()
    let imported = try codec.decode(
      codec.encode(
        .init(profiles: [
          DeskProfile(name: "Synthetic mute", settings: settings)
        ])))
    #expect(imported.document.profiles[0].settings == normalized)
    #expect(!normalizer.normalize(ProfileSettings()).audio.value.outputMuted.isIncluded)
    #expect(normalizer.normalize(ProfileSettings()).audio.value.outputMuted.value == nil)
  }

  @Test("repeat settings preserve applicability while legacy keyboard values stay dormant")
  func keyboardApplicabilityPreservesOnlyRegisteredControls() {
    var settings = ProfileSettings()
    settings.input = .init(
      isIncluded: false,
      value: .init(
        pointerSpeed: .init(value: 4),
        naturalScrolling: .init(value: true),
        keyRepeatInterval: .init(isIncluded: false, value: 2),
        initialKeyRepeatDelay: .init(isIncluded: true, value: 15),
        keyboardBrightness: .init(isIncluded: true, value: 0.5),
        useStandardFunctionKeys: .init(value: false)
      )
    )

    let normalized = normalizer.normalize(settings)

    #expect(normalized.input.isIncluded)
    #expect(!normalized.input.value.pointerSpeed.isIncluded)
    #expect(!normalized.input.value.naturalScrolling.isIncluded)
    #expect(!normalized.input.value.useStandardFunctionKeys.isIncluded)
    #expect(normalized.input.value.keyRepeatInterval == .init(isIncluded: false, value: 2))
    #expect(normalized.input.value.initialKeyRepeatDelay == .init(value: 15))
    #expect(
      normalized.input.value.keyboardBrightness
        == .init(isIncluded: false, value: 0.5)
    )
    #expect(normalizer.normalize(normalized) == normalized)
  }

  @Test("legacy keyboard brightness alone cannot activate the input group")
  func brightnessOnlyInputStaysDormant() {
    var settings = ProfileSettings()
    settings.input = .init(
      isIncluded: true,
      value: .init(keyboardBrightness: .init(isIncluded: true, value: 0.65))
    )

    let normalized = normalizer.normalize(settings)

    #expect(!normalized.input.isIncluded)
    #expect(!normalized.input.value.keyboardBrightness.isIncluded)
    #expect(normalized.input.value.keyboardBrightness.value == 0.65)
    #expect(normalized.payload(for: .input) == nil)
    #expect(normalizer.normalize(normalized) == normalized)
  }

  @Test("legacy display values stay dormant while preserving their stored values")
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
    #expect(!normalized.display.value.displays[0].rotationDegrees.isIncluded)
    #expect(normalized.display.value.displays[0].isActive.value)
    #expect(!normalized.display.value.displays[0].isActive.isIncluded)
    #expect(!normalized.display.value.displays[0].isPrimary.isIncluded)
    #expect(!normalized.display.value.displays[0].mode.isIncluded)
    #expect(normalized.network.value.dnsServers.value == ["192.0.2.53"])
    for group in SettingGroup.allCases {
      #expect(normalized.payload(for: group) == nil)
    }
  }

  @Test("mixed legacy primary flags remain stored but cannot reactivate display")
  func mixedPrimaryDisplayInclusionStaysDormant() {
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
    #expect(normalized.display.value.displays.allSatisfy { !$0.mode.isIncluded })
  }

  @Test("ambiguous legacy primary selection also stays dormant")
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
    #expect(normalized.display.value.displays.allSatisfy { !$0.mode.isIncluded })
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

@Suite("Selective profile settings")
struct SelectiveProfileSettingsTests {
  private func capturedSettings() -> ProfileSettings {
    .init(
      audio: .init(
        value: .init(
          defaultInputUID: .init(value: "synthetic-input"),
          defaultOutputUID: .init(value: "synthetic-output"),
          inputVolume: .init(value: 0.3), outputVolume: .init(value: 0.7),
          outputMuted: .init(value: false))),
      input: .init(
        value: .init(
          keyRepeatInterval: .init(value: 2), initialKeyRepeatDelay: .init(value: 15))))
  }

  @Test("all section combinations survive persistence without losing values", arguments: 0..<8)
  func sectionSelectionsRoundTrip(mask: Int) throws {
    var settings = capturedSettings()
    for (index, section) in ProfileSettingSection.allCases.enumerated() {
      settings.setIncluded(mask & (1 << index) != 0, for: section)
    }
    let normalized = ProfileApplicabilityNormalizer().normalize(settings)
    #expect(normalized == settings)
    let profile = DeskProfile(name: "Synthetic", settings: settings)
    let codec = ProfileJSONCodec()
    let decoded = try codec.decode(codec.encode(.init(profiles: [profile])))
    #expect(decoded.document.profiles[0].settings == settings)
    #expect(settings.audio.value.defaultOutputUID.value == "synthetic-output")
    #expect(settings.audio.value.inputVolume.value == 0.3)
    #expect(settings.input.value.keyRepeatInterval.value == 2)
    for (index, section) in ProfileSettingSection.allCases.enumerated() {
      #expect(settings.isIncluded(section) == (mask & (1 << index) != 0))
    }
    if mask == 0 {
      #expect(settings.payload(for: .audio) == nil)
      #expect(settings.payload(for: .input) == nil)
    }
    for section in ProfileSettingSection.allCases { settings.setIncluded(true, for: section) }
    #expect(settings == ProfileApplicabilityNormalizer().normalize(capturedSettings()))
  }

  @Test(
    "recapture retains every inclusion flag including an all-off profile", arguments: [true, false])
  func recapturePreservesSelections(allOff: Bool) {
    var saved = capturedSettings()
    saved.audio.value.outputVolume.isIncluded = false
    if allOff {
      for section in ProfileSettingSection.allCases { saved.setIncluded(false, for: section) }
    }
    var fresh = capturedSettings()
    fresh.audio.value.outputVolume.value = 0.9
    fresh.input.value.keyRepeatInterval.value = 3
    let refreshed = saved.refreshingValues(from: fresh)
    #expect(!refreshed.audio.value.outputVolume.isIncluded)
    #expect(refreshed.audio.value.outputVolume.value == 0.9)
    #expect(refreshed.input.value.keyRepeatInterval.isIncluded == !allOff)
    #expect(refreshed.input.value.keyRepeatInterval.value == 3)
    #expect(ProfileSettings().refreshingValues(from: fresh) == fresh)
  }
}
