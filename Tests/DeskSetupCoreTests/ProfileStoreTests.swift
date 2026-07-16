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

  func testPermissionFailureBeforeAtomicCommitPreservesDestination() throws {
    let directory = try makeTemporaryDirectory()
    let destination = directory.appendingPathComponent("profiles.json")
    let original = Data("original".utf8)
    try original.write(to: destination)
    let writer = PrivateAtomicFileWriter(
      createPrivateStagingFile: { _, stagingURL in
        try Data("partial".utf8).write(to: stagingURL, options: [.withoutOverwriting])
        throw CocoaError(.fileWriteNoPermission)
      }
    )

    XCTAssertThrowsError(try writer.write(Data("replacement".utf8), to: destination))

    XCTAssertEqual(try Data(contentsOf: destination), original)
    XCTAssertFalse(
      try FileManager.default.contentsOfDirectory(atPath: directory.path).contains {
        $0.hasPrefix(".profiles.json.") && $0.hasSuffix(".tmp")
      }
    )
  }

  func testRenameFailurePreservesDestinationAndCleansPrivateStagingFile() throws {
    let directory = try makeTemporaryDirectory()
    let destination = directory.appendingPathComponent("profiles.json")
    let original = Data("original".utf8)
    try original.write(to: destination)
    let writer = PrivateAtomicFileWriter(
      atomicReplace: { stagingURL, _ in
        let attributes = try FileManager.default.attributesOfItem(atPath: stagingURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        guard permissions == 0o600 else {
          throw InjectedFileOperationError.unexpectedStagingPermissions
        }
        throw InjectedFileOperationError.renameFailure
      }
    )

    XCTAssertThrowsError(
      try writer.write(Data("replacement".utf8), to: destination)
    ) { error in
      XCTAssertEqual(error as? InjectedFileOperationError, .renameFailure)
    }

    XCTAssertEqual(try Data(contentsOf: destination), original)
    XCTAssertFalse(
      try FileManager.default.contentsOfDirectory(atPath: directory.path).contains {
        $0.hasPrefix(".profiles.json.") && $0.hasSuffix(".tmp")
      }
    )
  }

  func testBackupOnlyRecoveryRewritesBackupPrivatelyBeforePrimary() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let codec = ProfileJSONCodec()
    let locations = ProfileStoreLocations(directoryURL: directory)
    let profile = DeskProfile(name: "Backup", createdAt: timestamp, updatedAt: timestamp)
    let document = ProfileDocument(
      profiles: [profile],
      selectedProfileID: profile.id,
      updatedAt: timestamp
    )
    let canonical = try codec.encode(document)
    try canonical.write(to: locations.backupURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: locations.backupURL.path
    )

    let store = ProfileStore(directoryURL: directory, now: { timestamp })
    let result = try await store.load()

    XCTAssertEqual(result.status, .recoveredFromBackup(quarantinedURLs: []))
    XCTAssertEqual(result.document, document)
    XCTAssertEqual(try Data(contentsOf: locations.backupURL), canonical)
    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), canonical)
    XCTAssertEqual(try permissions(at: locations.backupURL), 0o600)
    XCTAssertEqual(try permissions(at: locations.primaryURL), 0o600)
  }

  func testMigratedBackupPrimaryCommitFailureLeavesPrimaryUnchanged() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let codec = ProfileJSONCodec()
    let locations = ProfileStoreLocations(directoryURL: directory)
    let profile = DeskProfile(name: "Migrated", createdAt: timestamp, updatedAt: timestamp)
    let document = ProfileDocument(
      profiles: [profile],
      selectedProfileID: profile.id,
      updatedAt: timestamp
    )
    let migratedData = try dataByChangingSchema(in: codec.encode(document), to: 0)
    try migratedData.write(to: locations.backupURL)
    let liveWriter = PrivateAtomicFileWriter()
    let operations = ProfileStoreFileOperations(
      privateFileWriter: { data, destination in
        if destination == locations.primaryURL {
          throw CocoaError(.fileWriteNoPermission)
        }
        try liveWriter.write(data, to: destination)
      }
    )
    let store = ProfileStore(
      directoryURL: directory,
      now: { timestamp },
      fileOperations: operations
    )

    do {
      _ = try await store.load()
      XCTFail("Expected primary commit failure")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .io)
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: locations.primaryURL.path))
    let canonicalBackup = try codec.decode(contentsOf: locations.backupURL)
    XCTAssertEqual(canonicalBackup.originalSchemaVersion, ProfileDocument.currentSchemaVersion)
    XCTAssertEqual(canonicalBackup.document, document)
    XCTAssertEqual(try permissions(at: locations.backupURL), 0o600)
    let documentAfterFailure = await store.currentDocument()
    XCTAssertTrue(documentAfterFailure.profiles.isEmpty)
  }

  func testNormalizedLoadDoesNotRunPermissionMutationAfterPersistence() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let codec = ProfileJSONCodec()
    let locations = ProfileStoreLocations(directoryURL: directory)
    let document = unsupportedNetworkDocument(timestamp: timestamp)
    let expected = ProfileApplicabilityNormalizer().normalize(document)
    try codec.encode(document).write(to: locations.primaryURL)
    let operations = ProfileStoreFileOperations(
      setPrivatePermissions: { _ in
        throw CocoaError(.fileWriteNoPermission)
      }
    )
    let store = ProfileStore(
      directoryURL: directory,
      now: { timestamp },
      fileOperations: operations
    )

    let result = try await store.load()

    XCTAssertEqual(result.status, .loaded)
    XCTAssertEqual(result.document, expected)
    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), try codec.encode(expected))
    XCTAssertEqual(try permissions(at: locations.primaryURL), 0o600)
  }

  func testQuarantinePermissionFailureLeavesCorruptPrimaryInPlace() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let locations = ProfileStoreLocations(directoryURL: directory)
    let corruptData = Data("not-json".utf8)
    try corruptData.write(to: locations.primaryURL)
    let operations = ProfileStoreFileOperations(
      setPrivatePermissions: { _ in
        throw CocoaError(.fileWriteNoPermission)
      }
    )
    let store = ProfileStore(
      directoryURL: directory,
      now: { timestamp },
      fileOperations: operations
    )

    do {
      _ = try await store.load()
      XCTFail("Expected quarantine permission failure")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .io)
    }

    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), corruptData)
    XCTAssertTrue(
      try FileManager.default.contentsOfDirectory(
        atPath: locations.quarantineDirectoryURL.path
      ).isEmpty
    )
  }

  func testBackupWriterFailureIsTypedAndPreservesMemoryAndDisk() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let setupStore = ProfileStore(directoryURL: directory, now: { timestamp })
    _ = try await setupStore.load()
    let profile = try await setupStore.createProfile(DeskProfile(name: "Before"))
    let locations = setupStore.locations
    let primaryBefore = try Data(contentsOf: locations.primaryURL)
    try PrivateAtomicFileWriter().write(primaryBefore, to: locations.backupURL)
    let backupBefore = try Data(contentsOf: locations.backupURL)
    let liveWriter = PrivateAtomicFileWriter()
    let operations = ProfileStoreFileOperations(
      privateFileWriter: { data, destination in
        if destination == locations.backupURL {
          throw CocoaError(.fileWriteNoPermission)
        }
        try liveWriter.write(data, to: destination)
      }
    )
    let store = ProfileStore(
      directoryURL: directory,
      now: { timestamp },
      fileOperations: operations
    )
    _ = try await store.load()
    let documentBefore = await store.currentDocument()
    var update = profile
    update.name = "After"

    do {
      _ = try await store.updateProfile(update)
      XCTFail("Expected backup writer failure")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .io)
    }

    let documentAfterFailure = await store.currentDocument()
    XCTAssertEqual(documentAfterFailure, documentBefore)
    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), primaryBefore)
    XCTAssertEqual(try Data(contentsOf: locations.backupURL), backupBefore)
  }

  func testPrimaryWriterFailureIsTypedAndPreservesMemoryAndDisk() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let setupStore = ProfileStore(directoryURL: directory, now: { timestamp })
    _ = try await setupStore.load()
    let profile = try await setupStore.createProfile(DeskProfile(name: "Before"))
    let locations = setupStore.locations
    let primaryBefore = try Data(contentsOf: locations.primaryURL)
    try PrivateAtomicFileWriter().write(primaryBefore, to: locations.backupURL)
    let backupBefore = try Data(contentsOf: locations.backupURL)
    let liveWriter = PrivateAtomicFileWriter()
    let operations = ProfileStoreFileOperations(
      privateFileWriter: { data, destination in
        if destination == locations.primaryURL {
          throw CocoaError(.fileWriteNoPermission)
        }
        try liveWriter.write(data, to: destination)
      }
    )
    let store = ProfileStore(
      directoryURL: directory,
      now: { timestamp },
      fileOperations: operations
    )
    _ = try await store.load()
    let documentBefore = await store.currentDocument()
    var update = profile
    update.name = "After"

    do {
      _ = try await store.updateProfile(update)
      XCTFail("Expected primary writer failure")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .io)
    }

    let documentAfterFailure = await store.currentDocument()
    XCTAssertEqual(documentAfterFailure, documentBefore)
    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), primaryBefore)
    XCTAssertEqual(try Data(contentsOf: locations.backupURL), backupBefore)
  }

  func testLoadNormalizesExistingProfileAndPersistsCanonicalDocument() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let codec = ProfileJSONCodec()
    let locations = ProfileStoreLocations(directoryURL: directory)
    let document = unsupportedNetworkDocument(timestamp: timestamp)
    let expected = ProfileApplicabilityNormalizer().normalize(document)
    try codec.encode(document).write(to: locations.primaryURL, options: [.atomic])

    let store = ProfileStore(directoryURL: directory, now: { timestamp })
    let result = try await store.load()

    XCTAssertEqual(result.status, .loaded)
    XCTAssertEqual(result.document, expected)
    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), try codec.encode(expected))
    XCTAssertEqual(try Data(contentsOf: locations.backupURL), try codec.encode(expected))

    let reloaded = try await ProfileStore(directoryURL: directory).load()
    XCTAssertEqual(reloaded.document, expected)
    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), try codec.encode(expected))
  }

  func testCreateAndReplaceAllNormalizeProfilesBeforePersistence() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let store = ProfileStore(directoryURL: directory, now: { timestamp })
    _ = try await store.load()
    let source = try XCTUnwrap(unsupportedNetworkDocument(timestamp: timestamp).profiles.first)

    let created = try await store.createProfile(source)

    XCTAssertFalse(created.settings.network.isIncluded)
    XCTAssertEqual(created.settings.network.value.dnsServers.value, ["192.0.2.53"])
    XCTAssertFalse(created.settings.network.value.dnsServers.isIncluded)

    var replacement = unsupportedNetworkDocument(timestamp: timestamp)
    replacement.profiles[0].id = UUID()
    replacement.selectedProfileID = replacement.profiles[0].id
    try await store.replaceAll(with: replacement)
    let stored = await store.currentDocument()

    XCTAssertFalse(try XCTUnwrap(stored.profiles.first).settings.network.isIncluded)
    XCTAssertFalse(
      try XCTUnwrap(stored.profiles.first).settings.network.value.dnsServers.isIncluded
    )
    XCTAssertEqual(
      try XCTUnwrap(stored.profiles.first).settings.network.value.dnsServers.value,
      ["192.0.2.53"]
    )
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

  private func dataByChangingSchema(in data: Data, to version: Int) throws -> Data {
    var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["schemaVersion"] = version
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private func unsupportedNetworkDocument(timestamp: Date) -> ProfileDocument {
    var settings = ProfileSettings()
    settings.network = .init(
      isIncluded: true,
      value: .init(
        ipv4: .init(value: .dhcp),
        dnsServers: .init(value: ["192.0.2.53"]),
        secureWebProxy: .init(
          value: .init(enabled: true, host: "secure-proxy.invalid", port: 8443)
        )
      )
    )
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
}

private enum InjectedFileOperationError: Error, Equatable, Sendable {
  case unexpectedStagingPermissions
  case renameFailure
}
