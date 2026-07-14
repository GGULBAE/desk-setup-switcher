import Foundation
import XCTest

@testable import DeskSetupCore

final class ImportExportTests: XCTestCase {
  func testISO8601CodecRoundTripsDocument() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000.125)
    let profile = DeskProfile(name: "Desk", createdAt: date, updatedAt: date)
    let document = ProfileDocument(
      profiles: [profile],
      selectedProfileID: profile.id,
      updatedAt: date
    )

    let data = try ProfileJSONCodec().encode(document)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(json.contains("2023-11-14T22:13:20.125000000Z"))
    XCTAssertEqual(try ProfileJSONCodec().decode(data).document, document)
  }

  func testCodecDecodesLegacyWholeSecondISO8601Dates() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let document = ProfileDocument(updatedAt: date)
    let encoded = try ProfileJSONCodec().encode(document)
    let currentJSON = try XCTUnwrap(String(data: encoded, encoding: .utf8))
    let legacyJSON = currentJSON.replacingOccurrences(of: ".000000000Z", with: "Z")

    XCTAssertEqual(
      try ProfileJSONCodec().decode(Data(legacyJSON.utf8)).document,
      document
    )
  }

  func testExportThenValidatedImport() throws {
    let directory = try makeTemporaryDirectory()
    let destination = directory.appendingPathComponent("desk-profile.json")
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let profile = DeskProfile(name: "Office", createdAt: date, updatedAt: date)
    let document = ProfileDocument(
      profiles: [profile],
      selectedProfileID: profile.id,
      updatedAt: date
    )
    let service = ProfileImportExport()

    try service.export(document, to: destination)
    let imported = try service.importDocument(from: destination)

    XCTAssertEqual(imported.document, document)
    XCTAssertEqual(imported.sourceURL, destination.standardizedFileURL)
    XCTAssertEqual(imported.originalSchemaVersion, ProfileDocument.currentSchemaVersion)
  }

  func testLegacyImportNormalizesUnsupportedLeavesWithoutLosingValues() throws {
    let directory = try makeTemporaryDirectory()
    let source = directory.appendingPathComponent("legacy-profile.json")
    let document = unsupportedNetworkDocument()
    let codec = ProfileJSONCodec()
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: codec.encode(document)) as? [String: Any]
    )
    object["schemaVersion"] = 0
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: source)

    let imported = try ProfileImportExport().importDocument(from: source)
    let network = try XCTUnwrap(imported.document.profiles.first?.settings.network)

    XCTAssertEqual(imported.originalSchemaVersion, 0)
    XCTAssertTrue(imported.wasNormalized)
    XCTAssertEqual(imported.document.schemaVersion, ProfileDocument.currentSchemaVersion)
    XCTAssertFalse(network.isIncluded)
    XCTAssertEqual(network.value.ipv4.value, .dhcp)
    XCTAssertFalse(network.value.ipv4.isIncluded)
    XCTAssertEqual(network.value.dnsServers.value, ["192.0.2.53"])
    XCTAssertFalse(network.value.dnsServers.isIncluded)
    XCTAssertEqual(
      network.value.webProxy.value,
      .init(enabled: true, host: "proxy.invalid", port: 8_080)
    )
    XCTAssertFalse(network.value.webProxy.isIncluded)
  }

  func testDirectExportWritesNormalizedApplicabilityFlags() throws {
    let directory = try makeTemporaryDirectory()
    let destination = directory.appendingPathComponent("normalized-profile.json")
    let codec = ProfileJSONCodec()

    try ProfileImportExport().export(unsupportedNetworkDocument(), to: destination)
    let decoded = try codec.decode(contentsOf: destination)

    XCTAssertFalse(decoded.wasNormalized)
    let network = try XCTUnwrap(decoded.document.profiles.first?.settings.network)
    XCTAssertFalse(network.isIncluded)
    XCTAssertEqual(network.value.dnsServers.value, ["192.0.2.53"])
  }

  func testImportNormalizesMixedPrimaryDisplayInclusionToDormant() throws {
    let first = displayTarget(name: "Synthetic Panel A", isIncluded: true, value: false)
    let second = displayTarget(name: "Synthetic Panel B", isIncluded: false, value: true)
    var settings = ProfileSettings()
    settings.display = .init(
      isIncluded: true,
      value: DisplayProfileSettings(displays: [first, second])
    )
    let profile = DeskProfile(name: "Synthetic", settings: settings)
    let data = try ProfileJSONCodec().encode(
      ProfileDocument(profiles: [profile], selectedProfileID: profile.id)
    )

    let decoded = try ProfileJSONCodec().decode(data)
    let display = try XCTUnwrap(decoded.document.profiles.first?.settings.display)

    XCTAssertTrue(decoded.wasNormalized)
    XCTAssertFalse(display.isIncluded)
    XCTAssertEqual(display.value.displays.map(\.isPrimary.isIncluded), [false, false])
    XCTAssertEqual(display.value.displays.map(\.isPrimary.value), [false, true])
  }

  func testExportNeverOverwritesImportSource() throws {
    let directory = try makeTemporaryDirectory()
    let source = directory.appendingPathComponent("source.json")
    let document = ProfileDocument(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let originalData = try ProfileJSONCodec().encode(document)
    try originalData.write(to: source)
    let service = ProfileImportExport()
    let imported = try service.importDocument(from: source)

    XCTAssertThrowsError(try service.export(imported, to: source)) { error in
      XCTAssertEqual(error as? ProfileStorageError, .importSourceOverwrite(source))
    }
    XCTAssertEqual(try Data(contentsOf: source), originalData)
  }

  func testExportRefusesAnyExistingDestination() throws {
    let directory = try makeTemporaryDirectory()
    let destination = directory.appendingPathComponent("existing.json")
    let sentinel = Data("do-not-replace".utf8)
    try sentinel.write(to: destination)

    XCTAssertThrowsError(
      try ProfileImportExport().export(ProfileDocument(), to: destination)
    ) { error in
      XCTAssertEqual(error as? ProfileStorageError, .destinationExists(destination))
    }
    XCTAssertEqual(try Data(contentsOf: destination), sentinel)
  }

  func testImportRejectsInvalidSelection() throws {
    let directory = try makeTemporaryDirectory()
    let source = directory.appendingPathComponent("invalid.json")
    let validData = try ProfileJSONCodec().encode(ProfileDocument())
    var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: validData) as? [String: Any])
    object["selectedProfileID"] = UUID().uuidString
    try JSONSerialization.data(withJSONObject: object).write(to: source)

    XCTAssertThrowsError(try ProfileImportExport().importDocument(from: source)) { error in
      guard let validation = error as? ProfileValidationError else {
        return XCTFail("Expected ProfileValidationError, got \(error)")
      }
      XCTAssertTrue(
        validation.issues.contains { issue in
          if case .invalidSelectedProfileID = issue { return true }
          return false
        })
    }
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("DeskSetupCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func unsupportedNetworkDocument() -> ProfileDocument {
    var settings = ProfileSettings()
    settings.network = .init(
      isIncluded: true,
      value: .init(
        ipv4: .init(value: .dhcp),
        dnsServers: .init(value: ["192.0.2.53"]),
        webProxy: .init(value: .init(enabled: true, host: "proxy.invalid", port: 8_080))
      )
    )
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let profile = DeskProfile(
      name: "Synthetic",
      settings: settings,
      createdAt: timestamp,
      updatedAt: timestamp
    )
    return ProfileDocument(
      profiles: [profile],
      selectedProfileID: profile.id,
      updatedAt: timestamp
    )
  }

  private func displayTarget(
    name: String,
    isIncluded: Bool,
    value: Bool
  ) -> DisplayTargetSettings {
    DisplayTargetSettings(
      identity: DisplayIdentity(productName: name),
      isPrimary: .init(isIncluded: isIncluded, value: value),
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
