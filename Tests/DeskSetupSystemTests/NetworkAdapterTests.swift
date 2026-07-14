import CoreLocation
import DeskSetupCore
import Foundation
import Testing

@testable import DeskSetupSystem

@Suite("Network adapter")
struct NetworkAdapterTests {
  private struct ScannedNetwork: Equatable {
    var identifier: String
    var supportedSecurity: Set<String>
  }

  private struct SavedProfile: Equatable {
    var identifier: String
    var security: String
  }

  @Test("saved secure Wi-Fi profiles never select an open evil twin")
  func savedSecureProfileRejectsOpenEvilTwin() throws {
    let openEvilTwin = ScannedNetwork(identifier: "00:00:00:00:00:01", supportedSecurity: ["open"])
    let securedNetwork = ScannedNetwork(
      identifier: "00:00:00:00:00:02",
      supportedSecurity: ["wpa2"]
    )
    let savedSecureProfile = SavedProfile(identifier: "secure", security: "wpa2")

    let selection = try #require(
      compatiblePair(
        networks: [securedNetwork, openEvilTwin],
        profiles: [savedSecureProfile]
      )
    )

    #expect(selection.network == securedNetwork)
    #expect(selection.profile == savedSecureProfile)
  }

  @Test("saved Wi-Fi pairing fails when no scanned security is compatible")
  func savedProfileWithNoCompatibleNetworkReturnsNil() {
    let selection = compatiblePair(
      networks: [ScannedNetwork(identifier: "open", supportedSecurity: ["open"])],
      profiles: [SavedProfile(identifier: "secure", security: "wpa3")]
    )

    #expect(selection == nil)
  }

  @Test("saved open Wi-Fi profiles may select open networks")
  func savedOpenProfileSelectsOpenNetwork() throws {
    let openNetwork = ScannedNetwork(identifier: "open", supportedSecurity: ["open"])
    let openProfile = SavedProfile(identifier: "open", security: "open")

    let selection = try #require(
      compatiblePair(networks: [openNetwork], profiles: [openProfile])
    )

    #expect(selection.network == openNetwork)
    #expect(selection.profile == openProfile)
  }

  @Test("saved Wi-Fi pairing orders both networks and profiles deterministically")
  func savedWiFiPairingIsDeterministic() throws {
    let laterNetwork = ScannedNetwork(identifier: "b", supportedSecurity: ["wpa2", "wpa3"])
    let earlierNetwork = ScannedNetwork(identifier: "a", supportedSecurity: ["wpa2", "wpa3"])
    let laterProfile = SavedProfile(identifier: "b", security: "wpa3")
    let earlierProfile = SavedProfile(identifier: "a", security: "wpa2")

    let selection = try #require(
      compatiblePair(
        networks: [laterNetwork, earlierNetwork],
        profiles: [laterProfile, earlierProfile]
      )
    )

    #expect(selection.network == earlierNetwork)
    #expect(selection.profile == earlierProfile)
  }

  @Test("a powered-on nil SSID is never classified as a restorable disconnection")
  func poweredOnNilSSIDIsAmbiguousEvenWhenAuthorized() {
    #expect(
      LiveNetworkSystemAPI.classifySSIDAccess(
        powerOn: true,
        ssid: nil,
        authorizationStatus: .authorizedAlways
      ) == .unavailable
    )
    #expect(
      LiveNetworkSystemAPI.classifySSIDAccess(
        powerOn: true,
        ssid: nil,
        authorizationStatus: .authorized
      ) == .unavailable
    )
    #expect(
      LiveNetworkSystemAPI.classifySSIDAccess(
        powerOn: false,
        ssid: nil,
        authorizationStatus: .authorizedAlways
      ) == .notAssociated
    )
  }

  @Test("live preflight rejects invalid SSIDs before reading system state")
  func livePreflightRejectsInvalidSSID() async {
    let api = LiveNetworkSystemAPI()

    #expect(
      await api.preflightSavedWiFiAssociation(ssid: "")
        == .unavailable(.invalidSSID)
    )
    #expect(
      await api.preflightSavedWiFiAssociation(ssid: String(repeating: "a", count: 33))
        == .unavailable(.invalidSSID)
    )
  }

  @Test("invalid SSIDs fail validation and never reach preflight")
  func invalidSSIDIsNotPreflighted() async throws {
    let api = MockNetworkSystemAPI(snapshot: .associatedFixture)
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = SettingsPayload.network(
      NetworkProfileSettings(
        wifiPower: .init(value: true),
        wifiSSID: .init(value: String(repeating: "a", count: 33))
      ))

    let issues = await adapter.validate(desired, against: snapshot)
    let plan = try await adapter.plan(desired, from: snapshot, mode: .force)

    #expect(issues.contains(where: { $0.key == "wifi.ssid" && $0.isFatal }))
    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.map(\.key) == ["wifi.ssid"])
    #expect(await api.recordedCalls().isEmpty)
  }

  @Test("location denial degrades only the SSID snapshot item")
  func locationDenialDegradesOnlySSID() async throws {
    let api = MockNetworkSystemAPI(snapshot: .permissionDeniedFixture)
    let adapter = NetworkAdapter(systemAPI: api, now: { Date(timeIntervalSince1970: 1_000) })

    let snapshot = try await adapter.snapshot()

    #expect(snapshot.group == .network)
    #expect(snapshot.items.first(where: { $0.key == "wifi.ssid" })?.state == .permissionRequired)
    #expect(snapshot.items.contains(where: { $0.key == "wifi.power" && $0.state == .storable }))
    #expect(snapshot.items.contains(where: { $0.key == "interface.en0" }))
    #expect(snapshot.items.contains(where: { $0.key == "address.en0.0" }))
    #expect(snapshot.items.contains(where: { $0.key == "address.en0.1" }))
    #expect(snapshot.items.contains(where: { $0.key == "network.ipv4Gateway" }))
    #expect(snapshot.items.contains(where: { $0.key == "network.ipv6Gateway" }))
    #expect(snapshot.items.contains(where: { $0.key == "network.dns" }))
    #expect(
      snapshot.items.first(where: { $0.key == "network.serviceOrder" })?.state
        == .unsupported
    )

    guard case .network(let settings) = snapshot.payload else {
      Issue.record("Expected network settings payload")
      return
    }
    #expect(settings.wifiPower.value == true)
    #expect(settings.wifiSSID.isIncluded == false)
    #expect(settings.ipv4.value == .dhcp)
    #expect(settings.ipv4.isIncluded == false)
    #expect(settings.dnsServers.value == ["192.0.2.53"])
    #expect(settings.dnsServers.isIncluded == false)
    #expect(settings.webProxy.value == .init(enabled: false, host: "", port: 0))
    #expect(settings.webProxy.isIncluded == false)
    #expect(settings.secureWebProxy.value == nil)
    #expect(settings.secureWebProxy.isIncluded == false)
  }

  @Test("an identical full network payload plans no operation or omission")
  func identicalPayloadIsNoOp() async throws {
    let api = MockNetworkSystemAPI(snapshot: .associatedFixture)
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = try #require(snapshot.payload)

    let plan = try await adapter.plan(desired, from: snapshot, mode: .normal)

    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.isEmpty)
    #expect(await api.recordedCalls().isEmpty)
  }

  @Test("planning removes no-ops and omits administrative mutations")
  func planningNoOpsAndUnsupportedMutations() async throws {
    let api = MockNetworkSystemAPI(snapshot: .associatedFixture)
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: "Synthetic Wi-Fi"),
      ipv4: .init(
        value: .manual(
          address: "198.51.100.20",
          subnetMask: "255.255.255.0",
          router: "198.51.100.1"
        )),
      dnsServers: .init(value: ["198.51.100.53"]),
      webProxy: .init(value: .init(enabled: true, host: "proxy.invalid", port: 8080)),
      secureWebProxy: .init(value: nil)
    )

    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .force)

    #expect(plan.operations.isEmpty)
    #expect(
      Set(plan.omissions.map(\.key)) == [
        "network.ipv4", "network.dns", "network.webProxy",
      ])
    #expect(plan.omissions.allSatisfy { $0.status == .unsupported })
  }

  @Test("Wi-Fi power and association plan contains no password")
  func wifiPlanContainsNoPassword() async throws {
    let api = MockNetworkSystemAPI(snapshot: .notAssociatedFixture)
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: "Target Wi-Fi")
    )

    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .normal)

    #expect(plan.operations.map(\.key) == ["wifi.power", "wifi.ssid"])
    #expect(plan.omissions.isEmpty)
    #expect(
      plan.operations.first(where: { $0.key == "wifi.power" })?.preview
        == OperationPreview(previousValue: "Off", desiredValue: "On")
    )
    #expect(
      plan.operations.first(where: { $0.key == "wifi.ssid" })?.preview
        == OperationPreview(previousValue: "Not associated", desiredValue: "Target Wi-Fi")
    )
    #expect(await api.recordedCalls() == [.preflight("Target Wi-Fi")])
    let encodedOperations = plan.operations
      .flatMap { [$0.payload, $0.rollbackPayload ?? Data()] }
      .map { String(decoding: $0, as: UTF8.self).lowercased() }
      .joined(separator: " ")
    #expect(!encodedOperations.contains("password"))
    #expect(!encodedOperations.contains("credential"))
    #expect(encodedOperations.contains("target wi-fi"))
  }

  @Test(
    "an unavailable target saved association is omitted without sensitive details",
    arguments: [
      SavedWiFiAssociationUnavailableReason.invalidSSID,
      .wifiInterfaceUnavailable,
      SavedWiFiAssociationUnavailableReason.savedProfileUnavailable,
      .savedCredentialUnavailable,
      .preflightUnavailable,
    ])
  func unavailableTargetIsOmitted(
    reason: SavedWiFiAssociationUnavailableReason
  ) async throws {
    let targetSSID = "Private Target 8742"
    let api = MockNetworkSystemAPI(
      snapshot: .associatedFixture,
      preflightResults: [targetSSID: .unavailable(reason)]
    )
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: targetSSID)
    )

    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .force)

    #expect(plan.operations.isEmpty)
    let omission = try #require(plan.omissions.first(where: { $0.key == "wifi.ssid" }))
    #expect(omission.status == .skipped)
    #expect(!omission.reason.isEmpty)
    #expect(!omission.reason.contains(targetSSID))
    #expect(!omission.reason.contains("Synthetic Wi-Fi"))
    #expect(!omission.reason.lowercased().contains("password"))
    #expect(await api.recordedCalls() == [.preflight(targetSSID)])
  }

  @Test("failed association preflight leaves an independent power change nonfatal")
  func failedAssociationPreflightLeavesPowerChangeNonfatal() async throws {
    let targetSSID = "Private Target 8742"
    let api = MockNetworkSystemAPI(
      snapshot: .notAssociatedFixture,
      preflightResults: [targetSSID: .unavailable(.savedProfileUnavailable)]
    )
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: targetSSID)
    )

    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .normal)

    #expect(plan.operations.map(\.key) == ["wifi.power"])
    #expect(plan.operations.first?.isFatalOnFailure == false)
    #expect(plan.omissions.map(\.key) == ["wifi.ssid"])
    #expect(await api.recordedCalls() == [.preflight(targetSSID)])
  }

  @Test(
    "an unrestorable current association prevents switching",
    arguments: [
      SavedWiFiAssociationUnavailableReason.invalidSSID,
      .wifiInterfaceUnavailable,
      SavedWiFiAssociationUnavailableReason.savedProfileUnavailable,
      .savedCredentialUnavailable,
      .preflightUnavailable,
    ])
  func unrestorableCurrentAssociationIsOmitted(
    reason: SavedWiFiAssociationUnavailableReason
  ) async throws {
    let targetSSID = "Private Target 8742"
    let currentSSID = "Synthetic Wi-Fi"
    let api = MockNetworkSystemAPI(
      snapshot: .associatedFixture,
      preflightResults: [
        targetSSID: .available,
        currentSSID: .unavailable(reason),
      ]
    )
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: targetSSID)
    )

    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .normal)

    #expect(plan.operations.isEmpty)
    let omission = try #require(plan.omissions.first(where: { $0.key == "wifi.ssid" }))
    #expect(omission.status == .skipped)
    #expect(!omission.reason.isEmpty)
    #expect(!omission.reason.contains(targetSSID))
    #expect(!omission.reason.contains(currentSSID))
    #expect(!omission.reason.lowercased().contains("password"))
    #expect(
      await api.recordedCalls() == [
        .preflight(targetSSID),
        .preflight(currentSSID),
      ])
  }

  @Test("a restorable current association is preflighted and used for rollback")
  func restorableCurrentAssociationIsRollbackTarget() async throws {
    let targetSSID = "Private Target 8742"
    let currentSSID = "Synthetic Wi-Fi"
    let api = MockNetworkSystemAPI(snapshot: .associatedFixture)
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: targetSSID)
    )

    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .normal)
    let association = try #require(plan.operations.first(where: { $0.key == "wifi.ssid" }))
    #expect(plan.omissions.isEmpty)
    #expect(await adapter.apply(association).status == .succeeded)
    #expect(await adapter.rollback(association).status == .rolledBack)
    #expect(
      await api.recordedCalls() == [
        .preflight(targetSSID),
        .preflight(currentSSID),
        .associate(targetSSID),
        .associate(currentSSID),
      ])
  }

  @Test("apply and reverse rollback use only injected host-safe API calls")
  func applyAndRollback() async throws {
    let api = MockNetworkSystemAPI(snapshot: .notAssociatedFixture)
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: "Target Wi-Fi")
    )
    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .normal)

    for operation in plan.operations {
      #expect(await adapter.apply(operation).status == .succeeded)
    }
    for operation in plan.operations.reversed() {
      #expect(await adapter.rollback(operation).status == .rolledBack)
    }

    #expect(
      await api.recordedCalls() == [
        .preflight("Target Wi-Fi"),
        .setPower(true),
        .associate("Target Wi-Fi"),
        .disassociate,
        .setPower(false),
      ])
  }

  @Test("permission-blocked SSID is omitted because rollback state is unknown")
  func permissionBlockedSSIDIsOmitted() async throws {
    let api = MockNetworkSystemAPI(snapshot: .permissionDeniedFixture)
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: "Target Wi-Fi")
    )

    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .force)

    #expect(plan.operations.isEmpty)
    #expect(plan.omissions.map(\.key) == ["wifi.ssid"])
    #expect(await api.recordedCalls().isEmpty)
  }

  @Test("association failure returns a sanitized result")
  func associationFailureIsSanitized() async throws {
    let api = MockNetworkSystemAPI(snapshot: .notAssociatedFixture)
    await api.setAssociationFailure(true)
    let adapter = NetworkAdapter(systemAPI: api)
    let snapshot = try await adapter.snapshot()
    let desired = NetworkProfileSettings(
      wifiPower: .init(value: true),
      wifiSSID: .init(value: "Target Wi-Fi")
    )
    let plan = try await adapter.plan(.network(desired), from: snapshot, mode: .force)
    let association = try #require(plan.operations.first(where: { $0.key == "wifi.ssid" }))

    let result = await adapter.apply(association)

    #expect(result.status == .failed)
    #expect(!result.message.contains("Target Wi-Fi"))
    #expect(!result.message.lowercased().contains("password"))
  }

  private func compatiblePair(
    networks: [ScannedNetwork],
    profiles: [SavedProfile]
  ) -> (network: ScannedNetwork, profile: SavedProfile)? {
    firstCompatibleSavedWiFiPair(
      networks: networks,
      profiles: profiles,
      networkSortKey: \.identifier,
      profileSortKey: \.identifier,
      isCompatible: { network, profile in
        network.supportedSecurity.contains(profile.security)
      }
    )
  }
}

private actor MockNetworkSystemAPI: NetworkSystemAPI {
  enum Call: Equatable, Sendable {
    case preflight(String)
    case setPower(Bool)
    case associate(String)
    case disassociate
  }

  private var snapshotValue: NetworkSystemSnapshot
  private var calls: [Call] = []
  private var associationFails = false
  private var preflightResults: [String: SavedWiFiAssociationPreflight]

  init(
    snapshot: NetworkSystemSnapshot,
    preflightResults: [String: SavedWiFiAssociationPreflight] = [:]
  ) {
    snapshotValue = snapshot
    self.preflightResults = preflightResults
  }

  func readSnapshot() async throws -> NetworkSystemSnapshot {
    snapshotValue
  }

  func preflightSavedWiFiAssociation(ssid: String) async -> SavedWiFiAssociationPreflight {
    calls.append(.preflight(ssid))
    return preflightResults[ssid] ?? .available
  }

  func setWiFiPower(_ enabled: Bool) async throws {
    calls.append(.setPower(enabled))
  }

  func associateToSavedWiFi(ssid: String) async throws {
    calls.append(.associate(ssid))
    if associationFails {
      throw NetworkSystemAPIError.operationFailed
    }
  }

  func disassociateWiFi() async throws {
    calls.append(.disassociate)
  }

  func setAssociationFailure(_ enabled: Bool) {
    associationFails = enabled
  }

  func recordedCalls() -> [Call] {
    calls
  }
}

extension NetworkSystemSnapshot {
  fileprivate static var permissionDeniedFixture: NetworkSystemSnapshot {
    fixture(ssid: nil, ssidAccess: .permissionDenied, powerOn: true)
  }

  fileprivate static var associatedFixture: NetworkSystemSnapshot {
    fixture(ssid: "Synthetic Wi-Fi", ssidAccess: .available, powerOn: true)
  }

  fileprivate static var notAssociatedFixture: NetworkSystemSnapshot {
    fixture(ssid: nil, ssidAccess: .notAssociated, powerOn: false)
  }

  private static func fixture(
    ssid: String?,
    ssidAccess: WiFiSSIDAccess,
    powerOn: Bool
  ) -> NetworkSystemSnapshot {
    NetworkSystemSnapshot(
      wifi: .init(
        bsdName: "en0",
        powerOn: powerOn,
        ssid: ssid,
        ssidAccess: ssidAccess
      ),
      interfaces: [
        .init(
          bsdName: "en0",
          kind: .wifi,
          isUp: true,
          isRunning: true,
          addresses: [
            .init(
              address: "192.0.2.20",
              family: .ipv4,
              prefixLength: 24,
              subnetMask: "255.255.255.0"
            ),
            .init(
              address: "2001:db8:1::20",
              family: .ipv6,
              prefixLength: 64,
              subnetMask: "ffff:ffff:ffff:ffff::"
            ),
          ]
        ),
        .init(
          bsdName: "en7",
          kind: .ethernet,
          isUp: true,
          isRunning: false
        ),
      ],
      primaryInterfaceName: "en0",
      primaryServiceID: "service-wifi",
      ipv4Gateway: "192.0.2.1",
      ipv6Gateway: "2001:db8:1::1",
      dnsServers: ["192.0.2.53"],
      serviceOrder: ["service-wifi", "service-ethernet"],
      services: [
        .init(
          serviceID: "service-wifi",
          bsdName: "en0",
          enabled: true,
          ipv4: .dhcp,
          dnsServers: ["192.0.2.53"],
          webProxy: .init(enabled: false, host: "", port: 0)
        )
      ]
    )
  }
}
