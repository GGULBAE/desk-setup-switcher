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
}
