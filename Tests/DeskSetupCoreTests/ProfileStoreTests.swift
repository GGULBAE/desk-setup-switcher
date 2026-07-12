import Foundation
import XCTest

@testable import DeskSetupCore

final class ProfileStoreTests: XCTestCase {
  func testCRUDReorderSelectionAndReload() async throws {
    let directory = try makeTemporaryDirectory()
    let store = ProfileStore(
      directoryURL: directory,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    let initial = try await store.load()
    XCTAssertEqual(initial.status, .createdEmpty)

    let first = try await store.createProfile(DeskProfile(id: UUID(), name: "Home"))
    let second = try await store.createProfile(
      DeskProfile(id: UUID(), name: "Office"),
      selecting: true
    )
    let selectedAfterAtomicCreation = await store.currentDocument().selectedProfileID
    XCTAssertEqual(selectedAfterAtomicCreation, second.id)
    let copyID = UUID()
    let copy = try await store.duplicateProfile(id: first.id, newID: copyID, name: "Home Alt")
    try await store.moveProfile(id: copy.id, toIndex: 0)
    try await store.selectProfile(id: second.id)

    var changedSecond = second
    changedSecond.name = "Office Updated"
    _ = try await store.updateProfile(changedSecond)
    try await store.deleteProfile(id: first.id)

    let reloadedStore = ProfileStore(directoryURL: directory)
    let reloaded = try await reloadedStore.load().document
    XCTAssertEqual(reloaded.profiles.map(\.id), [copyID, second.id])
    XCTAssertEqual(reloaded.profiles.map(\.name), ["Home Alt", "Office Updated"])
    XCTAssertEqual(reloaded.selectedProfileID, second.id)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: reloadedStore.locations.backupURL.path
      ))
  }

  func testCorruptPrimaryRecoversLastKnownGoodBackupAndQuarantinesSource() async throws {
    let directory = try makeTemporaryDirectory()
    let store = ProfileStore(
      directoryURL: directory,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    _ = try await store.load()
    let first = try await store.createProfile(DeskProfile(name: "First"))
    _ = try await store.createProfile(DeskProfile(name: "Second"))
    try Data("not-json".utf8).write(to: store.locations.primaryURL, options: [.atomic])

    let recoveredStore = ProfileStore(
      directoryURL: directory,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    let result = try await recoveredStore.load()

    XCTAssertEqual(result.document.profiles.map(\.id), [first.id])
    guard case .recoveredFromBackup(let quarantinedURLs) = result.status else {
      return XCTFail("Expected backup recovery, got \(result.status)")
    }
    XCTAssertEqual(quarantinedURLs.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedURLs[0].path))
  }

  func testCorruptPrimaryAndBackupAreQuarantinedBeforeEmptyReset() async throws {
    let directory = try makeTemporaryDirectory()
    let store = ProfileStore(
      directoryURL: directory,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    _ = try await store.load()
    try Data("bad-primary".utf8).write(to: store.locations.primaryURL, options: [.atomic])
    try Data("bad-backup".utf8).write(to: store.locations.backupURL, options: [.atomic])

    let recoveredStore = ProfileStore(
      directoryURL: directory,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    let result = try await recoveredStore.load()

    XCTAssertTrue(result.document.profiles.isEmpty)
    guard case .resetAfterCorruption(let quarantinedURLs) = result.status else {
      return XCTFail("Expected corruption reset, got \(result.status)")
    }
    XCTAssertEqual(quarantinedURLs.count, 2)
    XCTAssertTrue(
      quarantinedURLs.allSatisfy {
        FileManager.default.fileExists(atPath: $0.path)
      })
    XCTAssertNoThrow(try ProfileJSONCodec().decode(contentsOf: recoveredStore.locations.primaryURL))
  }

  func testFailedUpdateDoesNotChangePersistedOrInMemoryDocument() async throws {
    let directory = try makeTemporaryDirectory()
    let store = ProfileStore(
      directoryURL: directory,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    _ = try await store.load()
    var profile = try await store.createProfile(DeskProfile(name: "Valid"))
    let before = await store.currentDocument()
    profile.name = String(repeating: "x", count: 1_025)

    do {
      _ = try await store.updateProfile(profile)
      XCTFail("Expected validation failure")
    } catch is ProfileValidationError {
      // Expected.
    }

    let after = await store.currentDocument()
    XCTAssertEqual(after, before)
    let reloaded = try await ProfileStore(directoryURL: directory).load().document
    XCTAssertEqual(reloaded, before)
  }

  func testProfileDirectoryAndFilesUsePrivatePermissions() async throws {
    let directory = try makeTemporaryDirectory()
    let store = ProfileStore(directoryURL: directory)
    _ = try await store.load()

    XCTAssertEqual(try permissions(at: directory), 0o700)
    XCTAssertEqual(try permissions(at: store.locations.primaryURL), 0o600)
    XCTAssertEqual(try permissions(at: store.locations.backupURL), 0o600)
  }

  private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ProfileStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}
