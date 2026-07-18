import Darwin
import Foundation
import XCTest

@testable import DeskSetupCore

final class ImportExportTests: XCTestCase {
  func testImportRejectsSymlinkAndNonRegularSources() throws {
    let directory = try makeTemporaryDirectory()
    let regular = directory.appendingPathComponent("regular.json")
    let symlink = directory.appendingPathComponent("linked.json")
    let nonRegular = directory.appendingPathComponent("directory.json", isDirectory: true)
    try ProfileJSONCodec().encode(ProfileDocument()).write(to: regular)
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: regular)
    try FileManager.default.createDirectory(at: nonRegular, withIntermediateDirectories: false)

    for source in [symlink, nonRegular] {
      XCTAssertThrowsError(try ProfileImportExport().importDocument(from: source)) { error in
        XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
      }
    }
  }

  func testImportRejectsNonFileURLWithoutNetworkAccess() throws {
    let remoteURL = try XCTUnwrap(URL(string: "https://profiles.invalid/document.json"))

    XCTAssertThrowsError(try ProfileImportExport().importDocument(from: remoteURL)) { error in
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }
  }

  func testOversizedImportPreservesTypedSizeError() throws {
    let directory = try makeTemporaryDirectory()
    let source = directory.appendingPathComponent("oversized.json")
    try Data(repeating: 0x78, count: 33).write(to: source)
    let service = ProfileImportExport(
      codec: ProfileJSONCodec(
        limits: ProfileValidationLimits(maximumDocumentBytes: 32)
      )
    )

    XCTAssertThrowsError(try service.importDocument(from: source)) { error in
      XCTAssertEqual(
        error as? ProfileStorageError,
        .fileTooLarge(actualBytes: 33, maximumBytes: 32)
      )
    }
  }

  func testImportRejectsNamedPipeWithoutBlocking() throws {
    let directory = try makeTemporaryDirectory()
    let pipe = directory.appendingPathComponent("profile-pipe.json")
    let result = pipe.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.mkfifo(path, mode_t(0o600))
    }
    XCTAssertEqual(result, 0)

    XCTAssertThrowsError(try ProfileImportExport().importDocument(from: pipe)) { error in
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }
  }

  func testImportRejectsUserOwnedAncestorSymlink() throws {
    let directory = try makeTemporaryDirectory()
    let target = directory.appendingPathComponent("target", isDirectory: true)
    let linkedParent = directory.appendingPathComponent("linked-parent", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    let source = target.appendingPathComponent("profiles.json")
    try ProfileJSONCodec().encode(ProfileDocument()).write(to: source)
    try FileManager.default.createSymbolicLink(
      at: linkedParent,
      withDestinationURL: target
    )

    XCTAssertThrowsError(
      try ProfileImportExport().importDocument(
        from: linkedParent.appendingPathComponent("profiles.json")
      )
    ) { error in
      XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
    }
  }

  func testImportAllowsMacOSRootOwnedTemporaryDirectoryCompatibilityLink() throws {
    let source = URL(
      fileURLWithPath: "/tmp/DeskSetupCoreTests-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: source) }
    let document = ProfileDocument(
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try ProfileJSONCodec().encode(document).write(to: source)
    XCTAssertNoThrow(try SecureFileAccess.validateAncestorChain(for: source))
    let descriptor = try SecureFileAccess.openRegularFileDescriptor(
      at: source,
      expectedOwnerID: Darwin.geteuid()
    )
    XCTAssertGreaterThanOrEqual(descriptor, 0)
    _ = Darwin.close(descriptor)

    let imported = try ProfileImportExport().importDocument(from: source)

    XCTAssertEqual(imported.document, document)
  }

  func testImportRejectsNonDirectoryAncestorAndSymlinkLoopAsUnsafe() throws {
    let directory = try makeTemporaryDirectory()
    let regularAncestor = directory.appendingPathComponent("not-a-directory")
    try Data("sentinel".utf8).write(to: regularAncestor)
    let loop = directory.appendingPathComponent("loop", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: loop)

    let unsafeSources = [
      regularAncestor.appendingPathComponent("profiles.json"),
      loop.appendingPathComponent("nested/profiles.json"),
    ]
    for source in unsafeSources {
      XCTAssertThrowsError(try ProfileImportExport().importDocument(from: source)) { error in
        XCTAssertEqual(error as? ProfileStorageError, .unsafeFilesystemObject)
      }
    }
  }

  func testImportRejectsSourcePathReplacementDuringDescriptorRead() throws {
    let directory = try makeTemporaryDirectory()
    let source = directory.appendingPathComponent("source.json")
    let displaced = directory.appendingPathComponent("opened-source.json")
    let replacement = directory.appendingPathComponent("replacement.json")
    let original = ProfileDocument(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let other = ProfileDocument(updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    let baselineCodec = ProfileJSONCodec()
    try baselineCodec.encode(original).write(to: source)
    try baselineCodec.encode(other).write(to: replacement)
    let codec = ProfileJSONCodec(
      snapshotReader: SecureFileSnapshotReader(afterOpen: { _, _ in
        try FileManager.default.moveItem(at: source, to: displaced)
        try FileManager.default.moveItem(at: replacement, to: source)
      })
    )

    XCTAssertThrowsError(try ProfileImportExport(codec: codec).importDocument(from: source)) {
      error in
      XCTAssertEqual(error as? ProfileStorageError, .fileChangedDuringRead)
    }
    XCTAssertEqual(try baselineCodec.decode(contentsOf: source).document, other)
  }

  func testImportRejectsInPlaceMutationDuringDescriptorRead() throws {
    let directory = try makeTemporaryDirectory()
    let source = directory.appendingPathComponent("source.json")
    let baselineCodec = ProfileJSONCodec()
    let original = ProfileDocument(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let replacement = ProfileDocument(
      profiles: [DeskProfile(name: "Changed during read")],
      updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    try baselineCodec.encode(original).write(to: source)
    let replacementData = try baselineCodec.encode(replacement)
    let codec = ProfileJSONCodec(
      snapshotReader: SecureFileSnapshotReader(afterOpen: { _, url in
        try overwriteInPlace(replacementData, at: url)
      })
    )

    XCTAssertThrowsError(try ProfileImportExport(codec: codec).importDocument(from: source)) {
      error in
      XCTAssertEqual(error as? ProfileStorageError, .fileChangedDuringRead)
    }
  }

  func testImportRejectsSameSizeRewriteWithRestoredModificationTime() throws {
    let directory = try makeTemporaryDirectory()
    let source = directory.appendingPathComponent("source.json")
    let baselineCodec = ProfileJSONCodec()
    let data = try baselineCodec.encode(
      ProfileDocument(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    )
    try data.write(to: source)
    let codec = ProfileJSONCodec(
      snapshotReader: SecureFileSnapshotReader(afterOpen: { _, url in
        try overwriteInPlacePreservingModificationTime(data, at: url)
      })
    )

    XCTAssertThrowsError(try ProfileImportExport(codec: codec).importDocument(from: source)) {
      error in
      XCTAssertEqual(error as? ProfileStorageError, .fileChangedDuringRead)
    }
  }

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

private func overwriteInPlace(_ data: Data, at url: URL) throws {
  let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
    guard let path else { return -1 }
    return Darwin.open(path, O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW)
  }
  guard descriptor >= 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
  defer { _ = Darwin.close(descriptor) }

  try data.withUnsafeBytes { bytes in
    guard let baseAddress = bytes.baseAddress else { return }
    var offset = 0
    while offset < bytes.count {
      let count = Darwin.write(
        descriptor,
        baseAddress.advanced(by: offset),
        bytes.count - offset
      )
      if count < 0, errno == EINTR {
        continue
      }
      guard count > 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      offset += count
    }
  }
}

private func overwriteInPlacePreservingModificationTime(_ data: Data, at url: URL) throws {
  let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
    guard let path else { return -1 }
    return Darwin.open(path, O_WRONLY | O_CLOEXEC | O_NOFOLLOW)
  }
  guard descriptor >= 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
  defer { _ = Darwin.close(descriptor) }

  var before = stat()
  guard Darwin.fstat(descriptor, &before) == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
  try data.withUnsafeBytes { bytes in
    guard let baseAddress = bytes.baseAddress else { return }
    var offset = 0
    while offset < bytes.count {
      let count = Darwin.pwrite(
        descriptor,
        baseAddress.advanced(by: offset),
        bytes.count - offset,
        off_t(offset)
      )
      if count < 0, errno == EINTR {
        continue
      }
      guard count > 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      offset += count
    }
  }
  var times = [before.st_atimespec, before.st_mtimespec]
  guard Darwin.futimens(descriptor, &times) == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
