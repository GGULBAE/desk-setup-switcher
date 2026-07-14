import Foundation
import XCTest

@testable import DeskSetupCore

final class MigrationTests: XCTestCase {
  func testSequentialMigrationFromSchemaZero() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let original = ProfileDocument(
      profiles: [DeskProfile(name: "Desk", createdAt: date, updatedAt: date)],
      updatedAt: date
    )
    let schemaZeroData = try dataByChangingSchema(in: ProfileJSONCodec().encode(original), to: 0)

    let decoded = try ProfileJSONCodec().decode(schemaZeroData)

    XCTAssertEqual(decoded.originalSchemaVersion, 0)
    XCTAssertTrue(decoded.wasMigrated)
    XCTAssertEqual(decoded.document, original)
  }

  func testMissingSchemaVersionUsesSchemaZeroMigration() throws {
    let original = ProfileDocument(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let currentData = try ProfileJSONCodec().encode(original)
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: currentData) as? [String: Any])
    object.removeValue(forKey: "schemaVersion")

    let decoded = try ProfileJSONCodec().decode(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )

    XCTAssertEqual(decoded.originalSchemaVersion, 0)
    XCTAssertEqual(decoded.document.schemaVersion, ProfileDocument.currentSchemaVersion)
  }

  func testCurrentSchemaDoesNotMigrate() throws {
    let document = ProfileDocument(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let decoded = try ProfileJSONCodec().decode(ProfileJSONCodec().encode(document))
    XCTAssertFalse(decoded.wasMigrated)
    XCTAssertEqual(decoded.document, document)
  }

  func testCurrentSchemaApplicabilityNormalizationPreservesValuesAndIsIdempotent() throws {
    let document = unsupportedSnapshotDocument()
    let codec = ProfileJSONCodec()

    let decoded = try codec.decode(codec.encode(document))
    let profile = try XCTUnwrap(decoded.document.profiles.first)
    let display = try XCTUnwrap(profile.settings.display.value.displays.first)

    XCTAssertFalse(decoded.wasMigrated)
    XCTAssertTrue(decoded.wasNormalized)
    XCTAssertTrue(decoded.requiresPersistence)
    XCTAssertEqual(display.rotationDegrees.value, 180)
    XCTAssertFalse(display.rotationDegrees.isIncluded)
    XCTAssertFalse(display.isActive.value)
    XCTAssertFalse(display.isActive.isIncluded)
    XCTAssertEqual(profile.settings.network.value.ipv4.value, .dhcp)
    XCTAssertFalse(profile.settings.network.value.ipv4.isIncluded)
    XCTAssertEqual(profile.settings.network.value.dnsServers.value, ["192.0.2.53"])
    XCTAssertFalse(profile.settings.network.value.dnsServers.isIncluded)
    XCTAssertFalse(profile.settings.display.isIncluded)
    XCTAssertFalse(profile.settings.network.isIncluded)

    let decodedAgain = try codec.decode(codec.encode(decoded.document))
    XCTAssertFalse(decodedAgain.wasNormalized)
    XCTAssertFalse(decodedAgain.requiresPersistence)
    XCTAssertEqual(decodedAgain.document, decoded.document)
  }

  func testNormalizationDoesNotBypassImportedValueValidation() throws {
    let codec = ProfileJSONCodec()
    let data = try codec.encode(unsupportedSnapshotDocument())
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    let invalidJSON = json.replacingOccurrences(
      of: "192.0.2.53",
      with: "not-an-address"
    )
    XCTAssertNotEqual(invalidJSON, json)

    XCTAssertThrowsError(try codec.decode(Data(invalidJSON.utf8))) { error in
      guard let validation = error as? ProfileValidationError else {
        return XCTFail("Expected ProfileValidationError, got \(error)")
      }
      XCTAssertTrue(
        validation.issues.contains { issue in
          guard case .invalidValue(let path, let reason) = issue else { return false }
          return path.hasSuffix(".dnsServers[0]") && reason == .malformedIPAddress
        }
      )
    }
  }

  func testFutureSchemaIsRejectedWithoutMigration() throws {
    let data = try dataByChangingSchema(
      in: ProfileJSONCodec().encode(ProfileDocument()),
      to: ProfileDocument.currentSchemaVersion + 1
    )

    XCTAssertThrowsError(try ProfileJSONCodec().decode(data)) { error in
      XCTAssertEqual(
        error as? ProfileStorageError,
        .unsupportedSchema(found: 2, current: 1)
      )
    }
  }

  func testMissingSequentialStepFailsExplicitly() throws {
    let data = try dataByChangingSchema(
      in: ProfileJSONCodec().encode(ProfileDocument()),
      to: 0
    )
    let migrator = ProfileDocumentMigrator(steps: [])

    XCTAssertThrowsError(try migrator.migrate(data)) { error in
      XCTAssertEqual(error as? ProfileStorageError, .missingMigration(fromVersion: 0))
    }
  }

  private func dataByChangingSchema(in data: Data, to version: Int) throws -> Data {
    var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["schemaVersion"] = version
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private func unsupportedSnapshotDocument() -> ProfileDocument {
    let display = DisplayTargetSettings(
      identity: DisplayIdentity(productName: "Synthetic Panel"),
      isPrimary: .init(isIncluded: false, value: false),
      origin: .init(isIncluded: false, value: DisplayPoint(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(
        isIncluded: false,
        value: DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)
      ),
      rotationDegrees: .init(value: 180),
      isActive: .init(value: false)
    )
    var settings = ProfileSettings()
    settings.display = .init(isIncluded: true, value: .init(displays: [display]))
    settings.network = .init(
      isIncluded: true,
      value: .init(
        ipv4: .init(value: .dhcp),
        dnsServers: .init(value: ["192.0.2.53"]),
        webProxy: .init(value: .init(enabled: true, host: "proxy.invalid", port: 8_080))
      )
    )
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    return ProfileDocument(
      profiles: [
        DeskProfile(
          name: "Synthetic",
          settings: settings,
          createdAt: timestamp,
          updatedAt: timestamp
        )
      ],
      updatedAt: timestamp
    )
  }
}
