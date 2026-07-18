import Darwin
import Foundation
import XCTest

@testable import DeskSetupCore

final class ProfileStoreTests: XCTestCase {
  func testCustomFileNameAcceptsOneNonReservedLeaf() async throws {
    let directory = try makeTemporaryDirectory()
    let store = ProfileStore(directoryURL: directory, fileName: "workstation-profiles.json")

    let result = try await store.load()

    XCTAssertEqual(result.status, .createdEmpty)
    XCTAssertEqual(store.locations.fileName, "workstation-profiles.json")
    XCTAssertEqual(store.locations.primaryURL.lastPathComponent, "workstation-profiles.json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.locations.primaryURL.path))
  }

  func testCustomFileNameRejectsTraversalAndReservedManagedNamesBeforeIO() async throws {
    let parent = try makeTemporaryDirectory()
    let outside = parent.appendingPathComponent("escape.json")
    let sentinel = Data("unchanged".utf8)
    try sentinel.write(to: outside)
    let invalidNames = [
      "",
      ".",
      "..",
      "../escape.json",
      "nested/profiles.json",
      "/tmp/profiles.json",
      "profiles.backup.json",
      "PROFILES.BACKUP.JSON",
      "Quarantine",
      "quarantine",
    ]

    for (index, fileName) in invalidNames.enumerated() {
      let directory = parent.appendingPathComponent("store-\(index)", isDirectory: true)
      let store = ProfileStore(directoryURL: directory, fileName: fileName)

      do {
        _ = try await store.load()
        XCTFail("Expected invalid store file name: \(fileName)")
      } catch {
        XCTAssertEqual(error as? ProfileStorageError, .invalidStoreFileName)
      }
      XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    XCTAssertEqual(try Data(contentsOf: outside), sentinel)
  }

  func testProfileStoreRejectsNonFileDirectoryURL() async throws {
    let remoteURL = try XCTUnwrap(URL(string: "https://profiles.invalid/store"))

    do {
      _ = try await ProfileStore(directoryURL: remoteURL).load()
      XCTFail("Expected non-file profile directory rejection")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }
  }

  func testProfileStoreNormalizesDotComponentsBeforeDerivingManagedPaths() async throws {
    let parent = try makeTemporaryDirectory()
    let rawDirectory = URL(
      fileURLWithPath: parent.path + "/unused/../normalized-store",
      isDirectory: true
    )
    let expectedDirectory = parent.appendingPathComponent(
      "normalized-store",
      isDirectory: true
    )
    let store = ProfileStore(directoryURL: rawDirectory)

    _ = try await store.load()

    XCTAssertEqual(store.locations.directoryURL, expectedDirectory.standardizedFileURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.locations.primaryURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: parent.appendingPathComponent("unused", isDirectory: true).path
      )
    )
  }

  func testManagedDirectorySymlinkIsRejectedWithoutWritingThroughIt() async throws {
    let parent = try makeTemporaryDirectory()
    let target = parent.appendingPathComponent("target", isDirectory: true)
    let link = parent.appendingPathComponent("store-link", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    let targetPermissions = try permissions(at: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    do {
      _ = try await ProfileStore(directoryURL: link).load()
      XCTFail("Expected managed directory symlink rejection")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }

    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    XCTAssertEqual(try permissions(at: target), targetPermissions)
  }

  func testUserOwnedAncestorSymlinkIsRejectedWithoutCreatingManagedDirectory() async throws {
    let parent = try makeTemporaryDirectory()
    let target = parent.appendingPathComponent("redirect-target", isDirectory: true)
    let link = parent.appendingPathComponent("redirect-parent", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let redirectedStore = link.appendingPathComponent("Store", isDirectory: true)

    do {
      _ = try await ProfileStore(directoryURL: redirectedStore).load()
      XCTFail("Expected user-owned ancestor symlink rejection")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }

    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
  }

  func testManagedPrimarySymlinkIsRejectedWithoutQuarantineOrTargetMutation() async throws {
    let directory = try makeTemporaryDirectory()
    let outside = directory.deletingLastPathComponent().appendingPathComponent(
      "ProfileStoreOutside-\(UUID().uuidString).json"
    )
    addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
    let sentinel = Data("outside-sentinel".utf8)
    try sentinel.write(to: outside)
    let outsidePermissions = try permissions(at: outside)
    let locations = ProfileStoreLocations(directoryURL: directory)
    try FileManager.default.createSymbolicLink(
      at: locations.primaryURL,
      withDestinationURL: outside
    )

    do {
      _ = try await ProfileStore(directoryURL: directory).load()
      XCTFail("Expected managed primary symlink rejection")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }

    XCTAssertEqual(try Data(contentsOf: outside), sentinel)
    XCTAssertEqual(try permissions(at: outside), outsidePermissions)
    XCTAssertFalse(FileManager.default.fileExists(atPath: locations.backupURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: locations.quarantineDirectoryURL.path))
  }

  func testManagedBackupSymlinkIsRejectedWithoutReadingItsTarget() async throws {
    let directory = try makeTemporaryDirectory()
    let outside = directory.deletingLastPathComponent().appendingPathComponent(
      "ProfileStoreBackupOutside-\(UUID().uuidString).json"
    )
    addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
    let sentinel = Data("not-a-profile".utf8)
    try sentinel.write(to: outside)
    let locations = ProfileStoreLocations(directoryURL: directory)
    try FileManager.default.createSymbolicLink(
      at: locations.backupURL,
      withDestinationURL: outside
    )

    do {
      _ = try await ProfileStore(directoryURL: directory).load()
      XCTFail("Expected managed backup symlink rejection")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }

    XCTAssertEqual(try Data(contentsOf: outside), sentinel)
    XCTAssertFalse(FileManager.default.fileExists(atPath: locations.primaryURL.path))
  }

  func testManagedQuarantineDirectorySymlinkIsRejectedBeforeCorruptFileMove() async throws {
    let directory = try makeTemporaryDirectory()
    let outside = directory.deletingLastPathComponent().appendingPathComponent(
      "ProfileStoreQuarantineOutside-\(UUID().uuidString)",
      isDirectory: true
    )
    addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    let locations = ProfileStoreLocations(directoryURL: directory)
    let corrupt = Data("not-json".utf8)
    try corrupt.write(to: locations.primaryURL)
    try FileManager.default.createSymbolicLink(
      at: locations.quarantineDirectoryURL,
      withDestinationURL: outside
    )

    do {
      _ = try await ProfileStore(directoryURL: directory).load()
      XCTFail("Expected managed quarantine symlink rejection")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }

    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), corrupt)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
  }

  func testManagedNonRegularPrimaryIsRejectedWithoutRecoverySideEffects() async throws {
    let directory = try makeTemporaryDirectory()
    let locations = ProfileStoreLocations(directoryURL: directory)
    try FileManager.default.createDirectory(
      at: locations.primaryURL,
      withIntermediateDirectories: false
    )

    do {
      _ = try await ProfileStore(directoryURL: directory).load()
      XCTFail("Expected non-regular managed primary rejection")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: locations.backupURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: locations.quarantineDirectoryURL.path))
  }

  func testSecureManagedAccessRejectsUnexpectedOwnerDeterministically() throws {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent("profile.json")
    try Data("{}".utf8).write(to: file)
    let anotherOwner = Darwin.geteuid() == uid_t.max ? Darwin.geteuid() - 1 : Darwin.geteuid() + 1
    let directoryPermissions = try permissions(at: directory)

    XCTAssertThrowsError(
      try SecureFileAccess.preparePrivateDirectory(
        directory,
        expectedOwnerID: anotherOwner
      )
    ) { error in
      XCTAssertEqual(error as? ProfileStorageError, .unexpectedFileOwner)
    }
    XCTAssertThrowsError(
      try SecureFileAccess.state(at: file, expectedOwnerID: anotherOwner)
    ) { error in
      XCTAssertEqual(error as? ProfileStorageError, .unexpectedFileOwner)
    }
    XCTAssertThrowsError(
      try SecureFileSnapshotReader(expectedOwnerID: anotherOwner).read(
        from: file,
        maximumBytes: 1_024
      )
    ) { error in
      XCTAssertEqual(error as? ProfileStorageError, .unexpectedFileOwner)
    }
    XCTAssertEqual(try permissions(at: directory), directoryPermissions)
  }

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

  func testLoadRejectsPrimaryReplacedBeforeIdentityBoundPermissionRepair() async throws {
    let directory = try makeTemporaryDirectory()
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let locations = ProfileStoreLocations(directoryURL: directory)
    let displacedPrimary = directory.appendingPathComponent("displaced-primary.json")
    let replacement = directory.appendingPathComponent("replacement.json")
    let codec = ProfileJSONCodec()
    let originalProfile = DeskProfile(
      name: "Snapshot A",
      createdAt: timestamp,
      updatedAt: timestamp
    )
    let originalDocument = ProfileDocument(
      profiles: [originalProfile],
      selectedProfileID: originalProfile.id,
      updatedAt: timestamp
    )
    let replacementProfile = DeskProfile(
      name: "Replacement B",
      createdAt: timestamp,
      updatedAt: timestamp
    )
    let replacementDocument = ProfileDocument(
      profiles: [replacementProfile],
      selectedProfileID: replacementProfile.id,
      updatedAt: timestamp
    )
    let originalData = try codec.encode(originalDocument)
    let replacementData = try codec.encode(replacementDocument)
    try originalData.write(to: locations.primaryURL)
    try replacementData.write(to: replacement)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o640],
      ofItemAtPath: replacement.path
    )
    let operations = ProfileStoreFileOperations(
      setPrivatePermissions: { source, expectedIdentity in
        guard let expectedIdentity else {
          try SecureFileAccess.setPrivateFilePermissions(source)
          return
        }
        try FileManager.default.moveItem(at: source, to: displacedPrimary)
        try FileManager.default.moveItem(at: replacement, to: source)
        try SecureFileAccess.setPrivateFilePermissions(
          source,
          expectedIdentity: expectedIdentity
        )
      }
    )
    let store = ProfileStore(
      directoryURL: directory,
      now: { timestamp },
      fileOperations: operations
    )

    do {
      _ = try await store.load()
      XCTFail("Expected replacement to invalidate the decoded snapshot")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .fileChangedDuringRead)
    }

    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), replacementData)
    XCTAssertEqual(try permissions(at: locations.primaryURL), 0o640)
    XCTAssertEqual(try Data(contentsOf: displacedPrimary), originalData)
    let inMemoryDocument = await store.currentDocument()
    XCTAssertTrue(inMemoryDocument.profiles.isEmpty)
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

  func testQuarantineRefusesPrimaryReplacedAfterCorruptSnapshot() async throws {
    let directory = try makeTemporaryDirectory()
    let locations = ProfileStoreLocations(directoryURL: directory)
    let displacedCorrupt = directory.appendingPathComponent("displaced-corrupt.json")
    let replacement = directory.appendingPathComponent("replacement.json")
    let corruptData = Data("not-json".utf8)
    let validDocument = ProfileDocument(
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let validData = try ProfileJSONCodec().encode(validDocument)
    try corruptData.write(to: locations.primaryURL)
    try validData.write(to: replacement)
    let operations = ProfileStoreFileOperations(
      beforeQuarantine: { source in
        try FileManager.default.moveItem(at: source, to: displacedCorrupt)
        try FileManager.default.moveItem(at: replacement, to: source)
      }
    )
    let store = ProfileStore(
      directoryURL: directory,
      fileOperations: operations
    )

    do {
      _ = try await store.load()
      XCTFail("Expected replaced corrupt snapshot to abort quarantine")
    } catch {
      XCTAssertEqual(error as? ProfileStorageError, .fileChangedDuringRead)
    }

    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), validData)
    XCTAssertEqual(try Data(contentsOf: displacedCorrupt), corruptData)
    XCTAssertFalse(FileManager.default.fileExists(atPath: locations.quarantineDirectoryURL.path))
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

  func testOversizedPrimaryRecoversValidBackupUsingReadFailureIdentity() async throws {
    let directory = try makeTemporaryDirectory()
    let codec = constrainedCodec(maximumDocumentBytes: 1_024)
    let locations = ProfileStoreLocations(directoryURL: directory)
    let document = ProfileDocument(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let validData = try codec.encode(document)
    try Data(repeating: 0x78, count: 1_025).write(to: locations.primaryURL)
    try validData.write(to: locations.backupURL)

    let result = try await ProfileStore(directoryURL: directory, codec: codec).load()

    XCTAssertEqual(result.document, document)
    guard case .recoveredFromBackup(let quarantinedURLs) = result.status else {
      return XCTFail("Expected oversized-primary recovery, got \(result.status)")
    }
    XCTAssertEqual(quarantinedURLs.count, 1)
    XCTAssertEqual(try Data(contentsOf: locations.primaryURL), validData)
  }

  func testCorruptPrimaryAndOversizedBackupAreBothQuarantinedBeforeReset() async throws {
    let directory = try makeTemporaryDirectory()
    let codec = constrainedCodec(maximumDocumentBytes: 1_024)
    let locations = ProfileStoreLocations(directoryURL: directory)
    try Data("not-json".utf8).write(to: locations.primaryURL)
    try Data(repeating: 0x78, count: 1_025).write(to: locations.backupURL)

    let result = try await ProfileStore(directoryURL: directory, codec: codec).load()

    XCTAssertTrue(result.document.profiles.isEmpty)
    guard case .resetAfterCorruption(let quarantinedURLs) = result.status else {
      return XCTFail("Expected oversized-backup reset, got \(result.status)")
    }
    XCTAssertEqual(quarantinedURLs.count, 2)
    XCTAssertTrue(quarantinedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    XCTAssertNoThrow(try codec.decode(contentsOf: locations.primaryURL))
    XCTAssertNoThrow(try codec.decode(contentsOf: locations.backupURL))
  }

  func testPersistQuarantinesOversizedCurrentPrimaryBeforeCandidateCommit() async throws {
    let directory = try makeTemporaryDirectory()
    let codec = constrainedCodec(maximumDocumentBytes: 4_096)
    let store = ProfileStore(directoryURL: directory, codec: codec)
    _ = try await store.load()
    try Data(repeating: 0x78, count: 4_097).write(
      to: store.locations.primaryURL,
      options: [.atomic]
    )

    let profile = try await store.createProfile(DeskProfile(name: "Recovered Candidate"))

    let reloaded = try await ProfileStore(directoryURL: directory, codec: codec).load()
    XCTAssertEqual(reloaded.document.profiles.map(\.id), [profile.id])
    let quarantined = try FileManager.default.contentsOfDirectory(
      at: store.locations.quarantineDirectoryURL,
      includingPropertiesForKeys: nil
    )
    XCTAssertEqual(quarantined.count, 1)
    XCTAssertEqual(try Data(contentsOf: quarantined[0]).count, 4_097)
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

  func testAtomicReplaceDoesNotFollowDestinationSymlinkInsertedAfterPreflight() throws {
    let directory = try makeTemporaryDirectory()
    let destination = directory.appendingPathComponent("profiles.json")
    let outside = directory.appendingPathComponent("outside.json")
    let sentinel = Data("outside-sentinel".utf8)
    let replacement = Data("replacement".utf8)
    try sentinel.write(to: outside)
    let writer = PrivateAtomicFileWriter(
      atomicReplace: { stagingURL, destinationURL in
        try FileManager.default.createSymbolicLink(
          at: destinationURL,
          withDestinationURL: outside
        )
        let result = stagingURL.path.withCString { stagingPath in
          destinationURL.path.withCString { destinationPath in
            Darwin.rename(stagingPath, destinationPath)
          }
        }
        guard result == 0 else {
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
      }
    )

    try writer.write(replacement, to: destination)

    XCTAssertEqual(try Data(contentsOf: destination), replacement)
    XCTAssertEqual(try Data(contentsOf: outside), sentinel)
    let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
    XCTAssertEqual(values.isSymbolicLink, false)
  }

  func testSecureMoveRestoresSourceLeafSwappedBetweenOpenAndRename() throws {
    let directory = try makeTemporaryDirectory()
    let quarantine = directory.appendingPathComponent("Quarantine", isDirectory: true)
    try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: false)
    let source = directory.appendingPathComponent("profiles.json")
    let displaced = directory.appendingPathComponent("opened-profiles.json")
    let replacement = directory.appendingPathComponent("replacement.json")
    let destination = quarantine.appendingPathComponent("corrupt.json")
    let originalData = Data("original-corrupt".utf8)
    let replacementData = Data("new-valid-file".utf8)
    try originalData.write(to: source)
    try replacementData.write(to: replacement)
    let expectedIdentity = try SecureFileAccess.regularFileIdentity(at: source)

    XCTAssertThrowsError(
      try SecureFileAccess.moveRegularFileWithoutFollowing(
        source,
        to: destination,
        expectedIdentity: expectedIdentity,
        beforeRename: { source, _ in
          try FileManager.default.moveItem(at: source, to: displaced)
          try FileManager.default.moveItem(at: replacement, to: source)
        }
      )
    ) { error in
      XCTAssertEqual(error as? ProfileStorageError, .fileChangedDuringRead)
    }

    XCTAssertEqual(try Data(contentsOf: source), replacementData)
    XCTAssertEqual(try Data(contentsOf: displaced), originalData)
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  func testSecureMoveRestoresSourceAfterPostRenameVerificationFailure() throws {
    let directory = try makeTemporaryDirectory()
    let quarantine = directory.appendingPathComponent("Quarantine", isDirectory: true)
    try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: false)
    let source = directory.appendingPathComponent("profiles.json")
    let destination = quarantine.appendingPathComponent("corrupt.json")
    let data = Data("recoverable-corrupt-data".utf8)
    try data.write(to: source)
    let expectedIdentity = try SecureFileAccess.regularFileIdentity(at: source)

    XCTAssertThrowsError(
      try SecureFileAccess.moveRegularFileWithoutFollowing(
        source,
        to: destination,
        expectedIdentity: expectedIdentity,
        afterRename: { _, _ in
          throw InjectedFileOperationError.postRenameVerificationFailure
        }
      )
    ) { error in
      XCTAssertEqual(
        error as? InjectedFileOperationError,
        .postRenameVerificationFailure
      )
    }

    XCTAssertEqual(try Data(contentsOf: source), data)
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
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
      setPrivatePermissions: { _, _ in
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
      setPrivatePermissions: { _, _ in
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

  private func constrainedCodec(maximumDocumentBytes: Int) -> ProfileJSONCodec {
    ProfileJSONCodec(
      limits: ProfileValidationLimits(
        maximumDocumentBytes: maximumDocumentBytes
      )
    )
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
  case postRenameVerificationFailure
}
