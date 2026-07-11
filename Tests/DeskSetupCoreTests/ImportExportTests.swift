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
}
