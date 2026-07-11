import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupSystem

@Suite("Condition context provider")
struct ConditionContextProviderTests {
  @Test("facts from every injected source compose into core context")
  func composesFacts() async {
    let display = DisplayIdentity(
      uuid: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
      vendorID: 1,
      modelID: 2,
      serialNumber: 3,
      isBuiltIn: false
    )
    let location = LocationRegion(latitude: 37.5, longitude: 127, radiusMeters: 25)
    let readers = FixtureConditionReaders(
      displays: [display],
      audio: .init(inputUIDs: ["input-a"], outputUIDs: ["output-a", "duplex-a"]),
      network: .init(
        wifiSSID: "Desk Wi-Fi",
        ethernetConnected: true,
        ipAddresses: ["192.0.2.10", "2001:db8::10"]
      ),
      hardware: ["usb:1234:5678"],
      location: location
    )

    let result = await makeProvider(readers).discover()

    #expect(result.context.displays == [display])
    #expect(result.context.audioInputUIDs == ["input-a"])
    #expect(result.context.audioOutputUIDs == ["output-a", "duplex-a"])
    #expect(result.context.wifiSSID == "Desk Wi-Fi")
    #expect(result.context.ethernetConnected)
    #expect(result.context.ipAddresses == ["192.0.2.10", "2001:db8::10"])
    #expect(result.context.hardwareIdentifiers == ["usb:1234:5678"])
    #expect(result.context.location == location)
    #expect(result.unavailableSources.isEmpty)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("a source failure erases only that source and diagnostics discard error details")
  func sourceFailureIsIsolatedAndSanitized() async {
    let secretSerial = "PRIVATE-USB-SERIAL"
    let readers = FixtureConditionReaders(
      displays: [DisplayIdentity(vendorID: 10, modelID: 20)],
      audio: .init(inputUIDs: ["input-a"], outputUIDs: ["output-a"]),
      network: .init(
        wifiSSID: "Desk Wi-Fi",
        ethernetConnected: true,
        ipAddresses: ["192.0.2.20"]
      ),
      hardware: ["unused"],
      location: .init(latitude: 1, longitude: 2, radiusMeters: 3),
      failures: [.audio, .hardware],
      failureDetail: secretSerial
    )

    let result = await makeProvider(readers).discover()

    #expect(result.unavailableSources == [.audio, .hardware])
    #expect(result.context.unavailableSources == [.audio, .hardware])
    #expect(result.context.audioInputUIDs.isEmpty)
    #expect(result.context.audioOutputUIDs.isEmpty)
    #expect(result.context.hardwareIdentifiers.isEmpty)
    #expect(result.context.displays == readers.displays)
    #expect(result.context.wifiSSID == "Desk Wi-Fi")
    #expect(result.context.ethernetConnected)
    #expect(result.context.location == readers.location)
    let diagnostics = result.diagnostics.map(\.message).joined(separator: " ")
    #expect(!diagnostics.contains(secretSerial))
    #expect(result.diagnostics.map(\.source) == [.audio, .hardware])
  }

  @Test("reader failures remain unavailable through condition inversion")
  func sourceFailureCannotMatchThroughInversion() async {
    let readers = FixtureConditionReaders(
      failures: [.displays, .audio, .network, .hardware, .location]
    )
    let context = await makeProvider(readers).read()
    let conditions = ProfileConditionSet(
      mode: .any,
      conditions: [
        .init(
          kind: .displayConnected(.init(vendorID: 1, modelID: 2)),
          isInverted: true
        ),
        .init(kind: .audioInputConnected(uid: "missing-input"), isInverted: true),
        .init(kind: .audioOutputConnected(uid: "missing-output"), isInverted: true),
        .init(kind: .hardwareConnected(identifier: "missing-hardware"), isInverted: true),
        .init(kind: .wifiSSID("Synthetic Wi-Fi"), isInverted: true),
        .init(kind: .ethernetConnected, isInverted: true),
        .init(kind: .ipAddressOrCIDR("192.0.2.0/24"), isInverted: true),
        .init(
          kind: .location(.init(latitude: 37, longitude: 127, radiusMeters: 100)),
          isInverted: true
        ),
      ]
    )

    let evaluation = ConditionEvaluator().evaluate(conditions, in: context)

    #expect(context.unavailableSources == Set(ConditionContextSource.allCases))
    #expect(!evaluation.isMatched)
    #expect(evaluation.items.allSatisfy { !$0.isMatched })
    #expect(evaluation.items.allSatisfy { $0.explanation.contains("unavailable") })
  }

  @Test("a network system read failure cannot become a factual inverted match")
  func networkSystemFailureCannotMatchThroughInversion() async {
    let fixtures = FixtureConditionReaders()
    let provider = ConditionContextProvider(
      displayReader: fixtures,
      audioReader: fixtures,
      networkReader: LiveConditionNetworkReader(
        systemAPI: StubNetworkSystemAPI(
          snapshot: .init(),
          failsRead: true
        )
      ),
      hardwareReader: fixtures,
      locationReader: fixtures
    )
    let context = await provider.read()
    let conditions = ProfileConditionSet(
      mode: .any,
      conditions: [
        .init(kind: .ethernetConnected, isInverted: true),
        .init(kind: .ipAddressOrCIDR("192.0.2.0/24"), isInverted: true),
      ]
    )

    let evaluation = ConditionEvaluator().evaluate(conditions, in: context)

    #expect(context.unavailableSources.contains(.network))
    #expect(!evaluation.isMatched)
    #expect(evaluation.items.allSatisfy { !$0.isMatched })
  }

  @Test("permission-hidden SSID and location are unavailable facts, not reader failures")
  func permissionHiddenFactsPreserveUnavailableSemantics() async {
    let context = await makeProvider(FixtureConditionReaders()).read()
    let conditions = ProfileConditionSet(
      mode: .any,
      conditions: [
        .init(kind: .wifiSSID("Synthetic Wi-Fi"), isInverted: true),
        .init(
          kind: .location(.init(latitude: 37, longitude: 127, radiusMeters: 100)),
          isInverted: true
        ),
      ]
    )

    let evaluation = ConditionEvaluator().evaluate(conditions, in: context)

    #expect(!context.unavailableSources.contains(.network))
    #expect(!context.unavailableSources.contains(.location))
    #expect(!evaluation.isMatched)
    #expect(evaluation.items.allSatisfy { !$0.isMatched })
  }

  @Test("display and audio readers return active stable identities and every capable UID")
  func systemReadersMapDisplaysAndAudio() async throws {
    let activeIdentity = DisplayIdentity(
      uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
      vendorID: 100,
      modelID: 200,
      serialNumber: 300
    )
    let inactiveIdentity = DisplayIdentity(vendorID: 400, modelID: 500)
    let displayAPI = StubDisplaySystemAPI(
      displays: [
        makeDisplay(identity: activeIdentity, isActive: true),
        makeDisplay(identity: inactiveIdentity, isActive: false),
      ]
    )
    let audioAPI = StubAudioSystemAPI(
      descriptors: [
        .init(uid: "input", name: "Input", supportsInput: true, supportsOutput: false),
        .init(uid: "output", name: "Output", supportsInput: false, supportsOutput: true),
        .init(uid: "duplex", name: "Duplex", supportsInput: true, supportsOutput: true),
        .init(uid: "neither", name: "Neither", supportsInput: false, supportsOutput: false),
      ]
    )

    let displays = try await LiveConditionDisplayReader(systemAPI: displayAPI)
      .readActiveDisplayIdentities()
    let audio = try await LiveConditionAudioReader(systemAPI: audioAPI).readAudioFacts()

    #expect(displays == [activeIdentity])
    #expect(audio.inputUIDs == ["input", "duplex"])
    #expect(audio.outputUIDs == ["output", "duplex"])
  }

  @Test("network facts include only a readable SSID, linked Ethernet, and local addresses")
  func networkFactsAreConservative() async throws {
    let deniedSnapshot = NetworkSystemSnapshot(
      wifi: .init(
        bsdName: "en0",
        powerOn: true,
        ssid: "Should Not Leak",
        ssidAccess: .permissionDenied
      ),
      interfaces: [
        .init(
          bsdName: "en0",
          kind: .wifi,
          isUp: true,
          isRunning: true,
          addresses: [
            .init(address: "192.0.2.30", family: .ipv4),
            .init(address: "fe80::30%en0", family: .ipv6),
          ]
        ),
        .init(
          bsdName: "en7",
          kind: .ethernet,
          isUp: true,
          isRunning: true,
          addresses: [.init(address: "198.51.100.30", family: .ipv4)]
        ),
        .init(
          bsdName: "en8",
          kind: .ethernet,
          isUp: false,
          isRunning: false,
          addresses: [.init(address: "203.0.113.30", family: .ipv4)]
        ),
        .init(
          bsdName: "lo0",
          kind: .loopback,
          isUp: true,
          isRunning: true,
          addresses: [.init(address: "127.0.0.1", family: .ipv4)]
        ),
      ]
    )

    let deniedFacts = try await LiveConditionNetworkReader(
      systemAPI: StubNetworkSystemAPI(snapshot: deniedSnapshot)
    ).readNetworkFacts()

    #expect(deniedFacts.wifiSSID == nil)
    #expect(deniedFacts.ethernetConnected)
    #expect(
      deniedFacts.ipAddresses == ["192.0.2.30", "fe80::30%en0", "198.51.100.30"]
    )

    var readableSnapshot = deniedSnapshot
    readableSnapshot.wifi?.ssidAccess = .available
    readableSnapshot.wifi?.ssid = "  Desk Wi-Fi  "
    let readableFacts = try await LiveConditionNetworkReader(
      systemAPI: StubNetworkSystemAPI(snapshot: readableSnapshot)
    ).readNetworkFacts()
    #expect(readableFacts.wifiSSID == "Desk Wi-Fi")
  }

  @Test("USB identifiers are deterministic and never contain a raw serial")
  func hardwareIdentifierIsStableAndOpaque() throws {
    let properties: [String: Any] = [
      "idVendor": NSNumber(value: 0x1234),
      "idProduct": NSNumber(value: 0xabcd),
      "USB Serial Number": " SENSITIVE-SERIAL-123 ",
      "locationID": NSNumber(value: 0x0102_0304),
    ]

    let first = try #require(USBHardwareIdentifier.make(from: properties))
    let second = try #require(USBHardwareIdentifier.make(from: properties))

    #expect(first == second)
    #expect(first.hasPrefix("usb:1234:abcd:serial-sha256:"))
    #expect(!first.contains("SENSITIVE-SERIAL-123"))
    #expect(first.count == "usb:1234:abcd:serial-sha256:".count + 64)
    #expect(
      USBHardwareIdentifier.make(
        from: ["idVendor": NSNumber(value: 0x1234)]
      ) == nil
    )
  }

  @Test("a USB port change does not alter a serial-less hardware identifier")
  func hardwareIdentifierIgnoresLocationID() throws {
    let firstPort: [String: Any] = [
      "idVendor": NSNumber(value: 0x1234),
      "idProduct": NSNumber(value: 0xabcd),
      "locationID": NSNumber(value: 0x0102_0304),
    ]
    var secondPort = firstPort
    secondPort["locationID"] = NSNumber(value: 0x0506_0708)

    let first = try #require(USBHardwareIdentifier.make(from: firstPort))
    let second = try #require(USBHardwareIdentifier.make(from: secondPort))

    #expect(first == "usb:1234:abcd")
    #expect(second == first)
  }

  @Test("an unauthorized or unavailable location remains nil without source failure")
  func unavailableLocationIsNotAFailure() async {
    let readers = FixtureConditionReaders(location: nil)

    let result = await makeProvider(readers).discover()

    #expect(result.context.location == nil)
    #expect(!result.unavailableSources.contains(.location))

    let inverted = ProfileConditionSet(conditions: [
      .init(
        kind: .location(.init(latitude: 37, longitude: 127, radiusMeters: 100)),
        isInverted: true
      )
    ])
    #expect(!ConditionEvaluator().evaluate(inverted, in: result.context).isMatched)
  }

  private func makeProvider(_ readers: FixtureConditionReaders) -> ConditionContextProvider {
    ConditionContextProvider(
      displayReader: readers,
      audioReader: readers,
      networkReader: readers,
      hardwareReader: readers,
      locationReader: readers
    )
  }
}

private struct FixtureConditionReaders: ConditionDisplayReading, ConditionAudioReading,
  ConditionNetworkReading, ConditionHardwareReading, ConditionLocationReading
{
  var displays: Set<DisplayIdentity> = []
  var audio = ConditionAudioFacts()
  var network = ConditionNetworkFacts()
  var hardware: Set<String> = []
  var location: LocationRegion?
  var failures: Set<ConditionContextSource> = []
  var failureDetail = "synthetic failure"

  func readActiveDisplayIdentities() async throws -> Set<DisplayIdentity> {
    try require(.displays)
    return displays
  }

  func readAudioFacts() async throws -> ConditionAudioFacts {
    try require(.audio)
    return audio
  }

  func readNetworkFacts() async throws -> ConditionNetworkFacts {
    try require(.network)
    return network
  }

  func readHardwareIdentifiers() async throws -> Set<String> {
    try require(.hardware)
    return hardware
  }

  func readAuthorizedLocation() async throws -> LocationRegion? {
    try require(.location)
    return location
  }

  private func require(_ source: ConditionContextSource) throws {
    if failures.contains(source) {
      throw FixtureReaderError.failed(failureDetail)
    }
  }
}

private enum FixtureReaderError: Error, Hashable, Sendable {
  case failed(String)
}

private struct StubDisplaySystemAPI: DisplaySystemAPI {
  var displays: [DisplaySystemDisplay]

  func activeDisplays() async throws -> [DisplaySystemDisplay] {
    displays
  }

  func apply(
    _ configuration: DisplayAtomicConfiguration,
    commitScope: DisplayConfigurationCommitScope
  ) async throws {}
}

private func makeDisplay(
  identity: DisplayIdentity,
  isActive: Bool
) -> DisplaySystemDisplay {
  DisplaySystemDisplay(
    sessionID: isActive ? 1 : 2,
    identity: identity,
    bounds: .init(x: 0, y: 0, width: 1920, height: 1080),
    isMain: isActive,
    rotationDegrees: 0,
    isActive: isActive,
    currentMode: nil,
    supportedModes: []
  )
}

private struct StubAudioSystemAPI: AudioSystemAPI {
  var descriptors: [AudioDeviceDescriptor]

  func devices() throws -> [AudioDeviceDescriptor] {
    descriptors
  }

  func defaultDeviceUID(for role: AudioDefaultDeviceRole) throws -> String? {
    nil
  }

  func outputVolume(forDeviceUID uid: String) throws -> AudioControlState<Double> {
    .unsupported
  }

  func outputMute(forDeviceUID uid: String) throws -> AudioControlState<Bool> {
    .unsupported
  }

  func setDefaultDeviceUID(_ uid: String, for role: AudioDefaultDeviceRole) throws {}

  func setOutputVolume(_ value: Double, forDeviceUID uid: String) throws {}

  func setOutputMute(_ value: Bool, forDeviceUID uid: String) throws {}
}

private struct StubNetworkSystemAPI: NetworkSystemAPI {
  var snapshot: NetworkSystemSnapshot
  var failsRead = false

  func readSnapshot() async throws -> NetworkSystemSnapshot {
    if failsRead {
      throw NetworkSystemAPIError.interfaceEnumerationFailed
    }
    return snapshot
  }

  func setWiFiPower(_ enabled: Bool) async throws {}

  func associateToSavedWiFi(ssid: String) async throws {}

  func disassociateWiFi() async throws {}
}
