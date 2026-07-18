import Darwin
import Foundation

struct PrivateAtomicFileWriter: Sendable {
  typealias CreatePrivateStagingFile = @Sendable (Data, URL) throws -> Void
  typealias AtomicReplace = @Sendable (URL, URL) throws -> Void

  private let createPrivateStagingFile: CreatePrivateStagingFile
  private let atomicReplace: AtomicReplace

  init(
    createPrivateStagingFile: @escaping CreatePrivateStagingFile = { data, url in
      try PrivateAtomicFileWriter.writePrivateStagingFile(data, to: url)
    },
    atomicReplace: @escaping AtomicReplace = { source, destination in
      try PrivateAtomicFileWriter.replaceAtomically(source, with: destination)
    }
  ) {
    self.createPrivateStagingFile = createPrivateStagingFile
    self.atomicReplace = atomicReplace
  }

  /// Prepares a private staging file completely before one atomic rename commits it.
  /// No fallible permission change occurs after the destination has been replaced.
  func write(_ data: Data, to destination: URL) throws {
    let normalizedDestination = destination.standardizedFileURL
    switch try SecureFileAccess.state(at: normalizedDestination) {
    case .missing, .regularFile:
      break
    case .directory:
      throw ProfileStorageError.unsafeFilesystemObject
    }
    let stagingURL = normalizedDestination.deletingLastPathComponent().appendingPathComponent(
      ".\(normalizedDestination.lastPathComponent).\(UUID().uuidString).tmp",
      isDirectory: false
    )
    defer { try? FileManager.default.removeItem(at: stagingURL) }

    try createPrivateStagingFile(data, stagingURL)
    try atomicReplace(stagingURL, normalizedDestination)
    Self.synchronizeParentDirectoryBestEffort(
      normalizedDestination.deletingLastPathComponent()
    )
  }

  private static func writePrivateStagingFile(_ data: Data, to url: URL) throws {
    let descriptor = url.path.withCString { path in
      Darwin.open(
        path,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
        mode_t(0o600)
      )
    }
    guard descriptor >= 0 else {
      throw posixError(errno)
    }

    var isOpen = true
    defer {
      if isOpen {
        _ = Darwin.close(descriptor)
      }
    }

    guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
      throw posixError(errno)
    }

    try data.withUnsafeBytes { bytes in
      guard !bytes.isEmpty else { return }
      guard let baseAddress = bytes.baseAddress else {
        throw posixError(EIO)
      }

      var offset = 0
      while offset < bytes.count {
        let written = Darwin.write(
          descriptor,
          baseAddress.advanced(by: offset),
          bytes.count - offset
        )
        if written < 0 {
          let code = errno
          if code == EINTR {
            continue
          }
          throw posixError(code)
        }
        guard written > 0 else {
          throw posixError(EIO)
        }
        offset += written
      }
    }

    // Flush staged bytes before the atomic rename publishes this inode. APFS
    // supports F_FULLFSYNC; fall back to fsync for other mounted filesystems.
    if Darwin.fcntl(descriptor, F_FULLFSYNC) == -1,
      Darwin.fsync(descriptor) != 0
    {
      throw posixError(errno)
    }

    let closeResult = Darwin.close(descriptor)
    let closeError = errno
    isOpen = false
    guard closeResult == 0 else {
      throw posixError(closeError)
    }
  }

  private static func replaceAtomically(_ sourceURL: URL, with destinationURL: URL) throws {
    let result = sourceURL.path.withCString { source in
      destinationURL.path.withCString { target in
        Darwin.rename(source, target)
      }
    }
    let renameError = errno
    guard result == 0 else {
      throw posixError(renameError)
    }
  }

  /// The committed rename cannot be rolled back safely if directory syncing
  /// fails, so this is a best-effort durability step after atomic visibility.
  private static func synchronizeParentDirectoryBestEffort(_ directoryURL: URL) {
    let descriptor = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else { return }
    _ = Darwin.fsync(descriptor)
    _ = Darwin.close(descriptor)
  }

  private static func posixError(_ code: Int32) -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
  }
}

struct ProfileStoreFileOperations: Sendable {
  typealias PrivateFileWriter = @Sendable (Data, URL) throws -> Void
  typealias SetPrivatePermissions = @Sendable (URL, SecureFileIdentity?) throws -> Void
  typealias MoveItem = @Sendable (URL, URL, SecureFileIdentity) throws -> Void
  typealias BeforeQuarantine = @Sendable (URL) throws -> Void

  let privateFileWriter: PrivateFileWriter
  let setPrivatePermissions: SetPrivatePermissions
  let moveItem: MoveItem
  let beforeQuarantine: BeforeQuarantine

  init(
    privateFileWriter: @escaping PrivateFileWriter = { data, url in
      try PrivateAtomicFileWriter().write(data, to: url)
    },
    setPrivatePermissions: @escaping SetPrivatePermissions = { url, expectedIdentity in
      try SecureFileAccess.setPrivateFilePermissions(
        url,
        expectedIdentity: expectedIdentity
      )
    },
    moveItem: @escaping MoveItem = { source, destination, expectedIdentity in
      try SecureFileAccess.moveRegularFileWithoutFollowing(
        source,
        to: destination,
        expectedIdentity: expectedIdentity
      )
    },
    beforeQuarantine: @escaping BeforeQuarantine = { _ in }
  ) {
    self.privateFileWriter = privateFileWriter
    self.setPrivatePermissions = setPrivatePermissions
    self.moveItem = moveItem
    self.beforeQuarantine = beforeQuarantine
  }
}

public struct ProfileStoreLocations: Equatable, Sendable {
  public let directoryURL: URL
  public let fileName: String
  public let primaryURL: URL
  public let backupURL: URL
  public let quarantineDirectoryURL: URL

  public init(directoryURL: URL, fileName: String = "profiles.json") {
    let normalizedDirectoryURL =
      directoryURL.isFileURL ? directoryURL.standardizedFileURL : directoryURL
    self.directoryURL = normalizedDirectoryURL
    self.fileName = fileName
    self.primaryURL = normalizedDirectoryURL.appendingPathComponent(
      fileName,
      isDirectory: false
    )
    self.backupURL = normalizedDirectoryURL.appendingPathComponent(
      "profiles.backup.json",
      isDirectory: false
    )
    self.quarantineDirectoryURL = normalizedDirectoryURL.appendingPathComponent(
      "Quarantine", isDirectory: true)
  }
}

public enum ProfileLoadStatus: Equatable, Sendable {
  case loaded
  case createdEmpty
  case migrated(fromVersion: Int)
  case recoveredFromBackup(quarantinedURLs: [URL])
  case resetAfterCorruption(quarantinedURLs: [URL])
}

public struct ProfileLoadResult: Equatable, Sendable {
  public let document: ProfileDocument
  public let status: ProfileLoadStatus
}

public actor ProfileStore {
  public nonisolated let locations: ProfileStoreLocations

  private let codec: ProfileJSONCodec
  private let normalizer: ProfileApplicabilityNormalizer
  private let fileOperations: ProfileStoreFileOperations
  private let now: @Sendable () -> Date
  private var document: ProfileDocument
  private var hasLoaded = false

  public static var defaultDirectoryURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Desk Setup Switcher", isDirectory: true)
  }

  public init(
    directoryURL: URL = ProfileStore.defaultDirectoryURL,
    fileName: String = "profiles.json",
    codec: ProfileJSONCodec = .init(),
    normalizer: ProfileApplicabilityNormalizer = .init(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.locations = ProfileStoreLocations(directoryURL: directoryURL, fileName: fileName)
    self.codec = codec
    self.normalizer = normalizer
    self.fileOperations = ProfileStoreFileOperations()
    self.now = now
    self.document = ProfileDocument(updatedAt: now())
  }

  init(
    directoryURL: URL,
    fileName: String = "profiles.json",
    codec: ProfileJSONCodec = .init(),
    normalizer: ProfileApplicabilityNormalizer = .init(),
    now: @escaping @Sendable () -> Date = { Date() },
    fileOperations: ProfileStoreFileOperations
  ) {
    self.locations = ProfileStoreLocations(directoryURL: directoryURL, fileName: fileName)
    self.codec = codec
    self.normalizer = normalizer
    self.fileOperations = fileOperations
    self.now = now
    self.document = ProfileDocument(updatedAt: now())
  }

  public func load() throws -> ProfileLoadResult {
    try validateLocations()
    try createDirectoryIfNeeded(locations.directoryURL)

    guard try regularFileExists(at: locations.primaryURL) else {
      if try regularFileExists(at: locations.backupURL) {
        return try recoverFromBackup(quarantinedURLs: [])
      }
      let empty = ProfileDocument(updatedAt: now())
      try persist(empty)
      document = empty
      hasLoaded = true
      return ProfileLoadResult(document: empty, status: .createdEmpty)
    }

    let primarySnapshot: SecureFileSnapshot
    do {
      primarySnapshot = try codec.readSnapshot(contentsOf: locations.primaryURL)
    } catch let failure as SecureFileSnapshotReadFailure
      where failure.storageError.canQuarantine
    {
      return try recoverAfterCorruption(
        cause: failure.storageError,
        expectedIdentity: failure.identity
      )
    } catch let failure as SecureFileSnapshotReadFailure {
      throw failure.storageError
    }
    do {
      let decoded = try codec.decode(primarySnapshot.data)
      if decoded.requiresPersistence {
        try ensureCurrentIdentity(
          of: locations.primaryURL,
          equals: primarySnapshot.identity
        )
        try persist(decoded.document)
      } else {
        try setPrivateFilePermissions(
          locations.primaryURL,
          expectedIdentity: primarySnapshot.identity
        )
        if try regularFileExists(at: locations.backupURL) {
          try setPrivateFilePermissions(locations.backupURL)
        }
      }
      document = decoded.document
      hasLoaded = true
      if decoded.wasMigrated {
        return ProfileLoadResult(
          document: decoded.document,
          status: .migrated(fromVersion: decoded.originalSchemaVersion)
        )
      }
      return ProfileLoadResult(document: decoded.document, status: .loaded)
    } catch let error as ProfileValidationError {
      return try recoverAfterCorruption(
        cause: error,
        expectedIdentity: primarySnapshot.identity
      )
    } catch let error as ProfileStorageError where error.canQuarantine {
      return try recoverAfterCorruption(
        cause: error,
        expectedIdentity: primarySnapshot.identity
      )
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }

  public func currentDocument() -> ProfileDocument {
    document
  }

  @discardableResult
  public func createProfile(
    _ profile: DeskProfile,
    selecting: Bool = false
  ) throws -> DeskProfile {
    try ensureLoaded()
    guard !document.profiles.contains(where: { $0.id == profile.id }) else {
      throw ProfileStorageError.profileAlreadyExists(profile.id)
    }
    let timestamp = now()
    var created = normalizer.normalize(profile)
    created.createdAt = timestamp
    created.updatedAt = timestamp

    var candidate = document
    candidate.profiles.append(created)
    if selecting || candidate.selectedProfileID == nil {
      candidate.selectedProfileID = created.id
    }
    candidate.updatedAt = timestamp
    try replaceCurrent(with: candidate)
    return created
  }

  @discardableResult
  public func updateProfile(_ profile: DeskProfile) throws -> DeskProfile {
    try ensureLoaded()
    guard let index = document.profiles.firstIndex(where: { $0.id == profile.id }) else {
      throw ProfileStorageError.profileNotFound(profile.id)
    }
    let timestamp = now()
    var updated = normalizer.normalize(profile)
    updated.createdAt = document.profiles[index].createdAt
    updated.updatedAt = timestamp

    var candidate = document
    candidate.profiles[index] = updated
    candidate.updatedAt = timestamp
    try replaceCurrent(with: candidate)
    return updated
  }

  @discardableResult
  public func duplicateProfile(
    id: UUID,
    newID: UUID = UUID(),
    name: String? = nil
  ) throws -> DeskProfile {
    try ensureLoaded()
    guard let index = document.profiles.firstIndex(where: { $0.id == id }) else {
      throw ProfileStorageError.profileNotFound(id)
    }
    guard !document.profiles.contains(where: { $0.id == newID }) else {
      throw ProfileStorageError.profileAlreadyExists(newID)
    }
    let timestamp = now()
    var duplicate = normalizer.normalize(document.profiles[index])
    duplicate.id = newID
    duplicate.name = name ?? "\(duplicate.name) Copy"
    duplicate.createdAt = timestamp
    duplicate.updatedAt = timestamp
    duplicate.lastApplication = nil

    var candidate = document
    candidate.profiles.insert(duplicate, at: index + 1)
    candidate.updatedAt = timestamp
    try replaceCurrent(with: candidate)
    return duplicate
  }

  public func deleteProfile(id: UUID) throws {
    try ensureLoaded()
    guard let index = document.profiles.firstIndex(where: { $0.id == id }) else {
      throw ProfileStorageError.profileNotFound(id)
    }
    let wasSelected = document.selectedProfileID == id
    var candidate = document
    candidate.profiles.remove(at: index)
    if wasSelected {
      if candidate.profiles.isEmpty {
        candidate.selectedProfileID = nil
      } else {
        candidate.selectedProfileID =
          candidate.profiles[min(index, candidate.profiles.count - 1)].id
      }
    }
    candidate.updatedAt = now()
    try replaceCurrent(with: candidate)
  }

  public func moveProfile(id: UUID, toIndex: Int) throws {
    try ensureLoaded()
    guard let sourceIndex = document.profiles.firstIndex(where: { $0.id == id }) else {
      throw ProfileStorageError.profileNotFound(id)
    }
    guard document.profiles.indices.contains(toIndex) else {
      throw ProfileStorageError.invalidReorderIndex(toIndex)
    }
    guard sourceIndex != toIndex else { return }

    var candidate = document
    let profile = candidate.profiles.remove(at: sourceIndex)
    candidate.profiles.insert(profile, at: toIndex)
    candidate.updatedAt = now()
    try replaceCurrent(with: candidate)
  }

  public func selectProfile(id: UUID?) throws {
    try ensureLoaded()
    if let id, !document.profiles.contains(where: { $0.id == id }) {
      throw ProfileStorageError.profileNotFound(id)
    }
    var candidate = document
    candidate.selectedProfileID = id
    candidate.updatedAt = now()
    try replaceCurrent(with: candidate)
  }

  public func replaceAll(with importedDocument: ProfileDocument) throws {
    try ensureLoaded()
    var candidate = importedDocument
    candidate.updatedAt = now()
    try replaceCurrent(with: candidate)
  }

  private func replaceCurrent(with candidate: ProfileDocument) throws {
    let normalized = normalizer.normalize(candidate)
    try persist(normalized)
    document = normalized
  }

  private func persist(_ candidate: ProfileDocument) throws {
    let data = try codec.encode(candidate)
    try createDirectoryIfNeeded(locations.directoryURL)
    var hasUsableBackup = try regularFileExists(at: locations.backupURL)

    if try regularFileExists(at: locations.primaryURL) {
      do {
        let primarySnapshot = try codec.readSnapshot(contentsOf: locations.primaryURL)
        do {
          let previous = try codec.decode(primarySnapshot.data).document
          let previousData = try codec.encode(previous)
          try writePrivateFileAtomically(previousData, to: locations.backupURL)
          hasUsableBackup = true
        } catch let error as ProfileValidationError {
          _ = try quarantine(
            locations.primaryURL,
            expectedIdentity: primarySnapshot.identity
          )
          _ = error
        } catch let error as ProfileStorageError where error.canQuarantine {
          _ = try quarantine(
            locations.primaryURL,
            expectedIdentity: primarySnapshot.identity
          )
        }
      } catch let failure as SecureFileSnapshotReadFailure
        where failure.storageError.canQuarantine
      {
        _ = try quarantine(
          locations.primaryURL,
          expectedIdentity: failure.identity
        )
      } catch let failure as SecureFileSnapshotReadFailure {
        throw failure.storageError
      }
    }

    do {
      if !hasUsableBackup {
        try writePrivateFileAtomically(data, to: locations.backupURL)
      }
      try writePrivateFileAtomically(data, to: locations.primaryURL)
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }

  private func recoverAfterCorruption(
    cause: Error,
    expectedIdentity: SecureFileIdentity
  ) throws -> ProfileLoadResult {
    let quarantinedPrimary = try quarantine(
      locations.primaryURL,
      expectedIdentity: expectedIdentity
    )
    _ = cause
    if try regularFileExists(at: locations.backupURL) {
      return try recoverFromBackup(quarantinedURLs: [quarantinedPrimary])
    }
    return try resetAfterCorruption(quarantinedURLs: [quarantinedPrimary])
  }

  private func recoverFromBackup(quarantinedURLs: [URL]) throws -> ProfileLoadResult {
    let backupSnapshot: SecureFileSnapshot
    do {
      backupSnapshot = try codec.readSnapshot(contentsOf: locations.backupURL)
    } catch let failure as SecureFileSnapshotReadFailure
      where failure.storageError.canQuarantine
    {
      let quarantinedBackup = try quarantine(
        locations.backupURL,
        expectedIdentity: failure.identity
      )
      return try resetAfterCorruption(
        quarantinedURLs: quarantinedURLs + [quarantinedBackup]
      )
    } catch let failure as SecureFileSnapshotReadFailure {
      throw failure.storageError
    }
    do {
      let decoded = try codec.decode(backupSnapshot.data)
      let canonical = try codec.encode(decoded.document)
      try ensureCurrentIdentity(
        of: locations.backupURL,
        equals: backupSnapshot.identity
      )
      try writePrivateFileAtomically(canonical, to: locations.backupURL)
      try writePrivateFileAtomically(canonical, to: locations.primaryURL)
      document = decoded.document
      hasLoaded = true
      return ProfileLoadResult(
        document: decoded.document,
        status: .recoveredFromBackup(quarantinedURLs: quarantinedURLs)
      )
    } catch let error as ProfileValidationError {
      let quarantinedBackup = try quarantine(
        locations.backupURL,
        expectedIdentity: backupSnapshot.identity
      )
      _ = error
      return try resetAfterCorruption(quarantinedURLs: quarantinedURLs + [quarantinedBackup])
    } catch let error as ProfileStorageError where error.canQuarantine {
      let quarantinedBackup = try quarantine(
        locations.backupURL,
        expectedIdentity: backupSnapshot.identity
      )
      return try resetAfterCorruption(quarantinedURLs: quarantinedURLs + [quarantinedBackup])
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }

  private func resetAfterCorruption(quarantinedURLs: [URL]) throws -> ProfileLoadResult {
    let empty = ProfileDocument(updatedAt: now())
    try persist(empty)
    document = empty
    hasLoaded = true
    return ProfileLoadResult(
      document: empty,
      status: .resetAfterCorruption(quarantinedURLs: quarantinedURLs)
    )
  }

  private func quarantine(
    _ url: URL,
    expectedIdentity: SecureFileIdentity
  ) throws -> URL {
    try fileOperations.beforeQuarantine(url)
    guard try regularFileExists(at: url) else {
      throw ProfileStorageError.io("managed file disappeared before quarantine")
    }
    guard try SecureFileAccess.regularFileIdentity(at: url) == expectedIdentity else {
      throw ProfileStorageError.fileChangedDuringRead
    }
    try createDirectoryIfNeeded(locations.quarantineDirectoryURL)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: now()).replacingOccurrences(of: ":", with: "-")
    let name =
      "\(url.deletingPathExtension().lastPathComponent)-corrupt-\(timestamp)-\(UUID().uuidString).json"
    let destination = locations.quarantineDirectoryURL.appendingPathComponent(name)
    try setPrivateFilePermissions(url, expectedIdentity: expectedIdentity)
    guard try SecureFileAccess.regularFileIdentity(at: url) == expectedIdentity else {
      throw ProfileStorageError.fileChangedDuringRead
    }
    try moveItem(url, to: destination, expectedIdentity: expectedIdentity)
    guard try SecureFileAccess.regularFileIdentity(at: destination) == expectedIdentity else {
      throw ProfileStorageError.fileChangedDuringRead
    }
    return destination
  }

  private func createDirectoryIfNeeded(_ url: URL) throws {
    do {
      try SecureFileAccess.preparePrivateDirectory(url)
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }

  private func setPrivateFilePermissions(
    _ url: URL,
    expectedIdentity: SecureFileIdentity? = nil
  ) throws {
    do {
      try fileOperations.setPrivatePermissions(url, expectedIdentity)
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }

  private func ensureCurrentIdentity(
    of url: URL,
    equals expectedIdentity: SecureFileIdentity
  ) throws {
    guard try SecureFileAccess.regularFileIdentity(at: url) == expectedIdentity else {
      throw ProfileStorageError.fileChangedDuringRead
    }
  }

  private func writePrivateFileAtomically(_ data: Data, to url: URL) throws {
    do {
      try fileOperations.privateFileWriter(data, url)
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }

  private func moveItem(
    _ source: URL,
    to destination: URL,
    expectedIdentity: SecureFileIdentity
  ) throws {
    do {
      try fileOperations.moveItem(source, destination, expectedIdentity)
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }

  private func ensureLoaded() throws {
    if !hasLoaded {
      _ = try load()
    }
  }

  private func validateLocations() throws {
    guard locations.directoryURL.isFileURL else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    guard Self.isValidStoreFileName(locations.fileName) else {
      throw ProfileStorageError.invalidStoreFileName
    }

    let directory = locations.directoryURL.standardizedFileURL
    guard locations.primaryURL.deletingLastPathComponent().standardizedFileURL == directory,
      locations.backupURL.deletingLastPathComponent().standardizedFileURL == directory,
      locations.quarantineDirectoryURL.deletingLastPathComponent().standardizedFileURL
        == directory
    else {
      throw ProfileStorageError.invalidStoreFileName
    }
  }

  private static func isValidStoreFileName(_ fileName: String) -> Bool {
    guard !fileName.isEmpty,
      fileName != ".",
      fileName != "..",
      !fileName.utf8.contains(0),
      !fileName.contains("/"),
      (fileName as NSString).lastPathComponent == fileName
    else {
      return false
    }

    let reservedNames = ["profiles.backup.json", "Quarantine"]
    return !reservedNames.contains { reserved in
      fileName.compare(
        reserved,
        options: [.caseInsensitive, .diacriticInsensitive]
      ) == .orderedSame
    }
  }

  private func regularFileExists(at url: URL) throws -> Bool {
    switch try SecureFileAccess.state(at: url) {
    case .missing:
      return false
    case .regularFile:
      return true
    case .directory:
      throw ProfileStorageError.unsafeFilesystemObject
    }
  }
}
