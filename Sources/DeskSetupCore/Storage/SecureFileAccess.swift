import Darwin
import Foundation

/// Reads one immutable-in-name snapshot through a no-follow descriptor.
///
/// The path is used only to open the descriptor. Type, owner, size, and
/// stability checks are performed on that descriptor, so replacing the path
/// after `open(2)` cannot redirect the bytes that are decoded.
struct SecureFileSnapshotReader: Sendable {
  typealias AfterOpen = @Sendable (Int32, URL) throws -> Void

  private let expectedOwnerID: uid_t
  private let afterOpen: AfterOpen

  init(
    expectedOwnerID: uid_t = Darwin.geteuid(),
    afterOpen: @escaping AfterOpen = { _, _ in }
  ) {
    self.expectedOwnerID = expectedOwnerID
    self.afterOpen = afterOpen
  }

  func read(from url: URL, maximumBytes: Int) throws -> Data {
    do {
      return try readSnapshot(from: url, maximumBytes: maximumBytes).data
    } catch let failure as SecureFileSnapshotReadFailure {
      throw failure.storageError
    }
  }

  func readSnapshot(from url: URL, maximumBytes: Int) throws -> SecureFileSnapshot {
    guard url.isFileURL, maximumBytes >= 0 else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    let normalizedURL = url.standardizedFileURL
    try SecureFileAccess.validateAncestorChain(for: normalizedURL)

    let descriptor = try SecureFileAccess.openRegularFileDescriptor(
      at: normalizedURL,
      expectedOwnerID: expectedOwnerID
    )
    defer { _ = Darwin.close(descriptor) }

    let before = try verifiedRegularFileStatus(descriptor)
    guard before.st_uid == expectedOwnerID else {
      throw ProfileStorageError.unexpectedFileOwner
    }
    let identity = SecureFileIdentity(
      device: before.st_dev,
      inode: before.st_ino,
      owner: before.st_uid
    )
    guard before.st_size >= 0 else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    guard before.st_size <= off_t(maximumBytes) else {
      throw SecureFileSnapshotReadFailure(
        storageError: .fileTooLarge(
          actualBytes: clampedInt(before.st_size),
          maximumBytes: maximumBytes
        ),
        identity: identity
      )
    }

    try afterOpen(descriptor, normalizedURL)
    let data: Data
    do {
      data = try readAll(descriptor, maximumBytes: maximumBytes)
    } catch let error as ProfileStorageError where error.canQuarantine {
      throw SecureFileSnapshotReadFailure(
        storageError: error,
        identity: identity
      )
    }
    let after = try verifiedRegularFileStatus(descriptor)
    guard isSameStableFile(before, after) else {
      throw ProfileStorageError.fileChangedDuringRead
    }
    return SecureFileSnapshot(
      data: data,
      identity: identity
    )
  }

  private func verifiedRegularFileStatus(_ descriptor: Int32) throws -> stat {
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0 else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard (status.st_mode & S_IFMT) == S_IFREG else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    return status
  }

  private func readAll(_ descriptor: Int32, maximumBytes: Int) throws -> Data {
    var result = Data()
    result.reserveCapacity(min(maximumBytes, 64 * 1_024))
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)

    while true {
      let readCount = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
      }
      if readCount < 0 {
        if errno == EINTR {
          continue
        }
        throw ProfileStorageError.io(String(cString: strerror(errno)))
      }
      guard readCount > 0 else { break }
      guard result.count <= maximumBytes - readCount else {
        throw ProfileStorageError.fileTooLarge(
          actualBytes: maximumBytes == Int.max ? Int.max : maximumBytes + 1,
          maximumBytes: maximumBytes
        )
      }
      result.append(contentsOf: buffer.prefix(readCount))
    }
    return result
  }

  private func isSameStableFile(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev
      && lhs.st_ino == rhs.st_ino
      && lhs.st_uid == rhs.st_uid
      && lhs.st_mode == rhs.st_mode
      && lhs.st_size == rhs.st_size
      && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
      && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
      && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
      && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
  }

  private func clampedInt(_ value: off_t) -> Int {
    if value > off_t(Int.max) { return Int.max }
    return Int(value)
  }
}

enum SecureManagedPathState: Equatable, Sendable {
  case missing
  case regularFile
  case directory
}

enum SecureManagedLeafState: Equatable, Sendable {
  case missing
  case regularFile(SecureFileIdentity)
}

enum SecureDirectoryEntryState: Equatable, Sendable {
  case missing
  case present(SecureDirectoryEntryIdentity)
}

enum SecureExtendedACLState: Equatable, Sendable {
  case absent
  case denyOnly
  case containsAllow
}

struct SecureDirectoryEntryIdentity: Equatable, Sendable {
  let device: dev_t
  let inode: ino_t
  let owner: uid_t
  let fileType: mode_t
}

struct SecureFileIdentity: Equatable, Sendable {
  let device: dev_t
  let inode: ino_t
  let owner: uid_t
}

struct SecureFileSnapshot: Equatable, Sendable {
  let data: Data
  let identity: SecureFileIdentity
}

struct SecureFileSnapshotReadFailure: Error, Equatable, Sendable {
  let storageError: ProfileStorageError
  let identity: SecureFileIdentity
}

enum SecureFileAccess {
  /// Rejects user-controlled symlink redirection above a managed or imported
  /// leaf. Root-owned compatibility links such as macOS `/var` are allowed;
  /// an unprivileged process cannot create or retarget those links.
  static func validateAncestorChain(for url: URL) throws {
    guard url.isFileURL else {
      throw ProfileStorageError.unsafeFilesystemObject
    }

    var ancestor = url.standardizedFileURL.deletingLastPathComponent()
    while ancestor.path != "/" {
      var status = stat()
      let result = ancestor.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else { return -1 }
        return Darwin.lstat(path, &status)
      }
      if result != 0 {
        if errno == ENOENT {
          ancestor.deleteLastPathComponent()
          continue
        }
        if errno == ELOOP || errno == ENOTDIR {
          throw ProfileStorageError.unsafeFilesystemObject
        }
        throw ProfileStorageError.io(String(cString: strerror(errno)))
      }

      switch status.st_mode & S_IFMT {
      case S_IFDIR:
        break
      case S_IFLNK where status.st_uid == 0:
        break
      default:
        throw ProfileStorageError.unsafeFilesystemObject
      }
      ancestor.deleteLastPathComponent()
    }
  }

  static func state(
    at url: URL,
    expectedOwnerID: uid_t = Darwin.geteuid()
  ) throws -> SecureManagedPathState {
    guard url.isFileURL else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    let normalizedURL = url.standardizedFileURL
    try validateAncestorChain(for: normalizedURL)
    var status = stat()
    let result = normalizedURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.lstat(path, &status)
    }
    if result != 0 {
      if errno == ENOENT {
        return .missing
      }
      if errno == ELOOP || errno == ENOTDIR {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard status.st_uid == expectedOwnerID else {
      throw ProfileStorageError.unexpectedFileOwner
    }
    switch status.st_mode & S_IFMT {
    case S_IFREG:
      return .regularFile
    case S_IFDIR:
      return .directory
    default:
      throw ProfileStorageError.unsafeFilesystemObject
    }
  }

  static func preparePrivateDirectory(
    _ url: URL,
    expectedOwnerID: uid_t = Darwin.geteuid()
  ) throws {
    guard url.isFileURL else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    let normalizedURL = url.standardizedFileURL

    switch try state(at: normalizedURL, expectedOwnerID: expectedOwnerID) {
    case .missing:
      do {
        try FileManager.default.createDirectory(
          at: normalizedURL,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        throw ProfileStorageError.io(String(describing: error))
      }
    case .directory:
      break
    case .regularFile:
      throw ProfileStorageError.unsafeFilesystemObject
    }

    // `createDirectory(withIntermediateDirectories:)` is path-based. Recheck
    // the chain before opening the managed leaf so a newly inserted
    // user-owned ancestor symlink is rejected.
    try validateAncestorChain(for: normalizedURL)

    let descriptor = try openVerifiedDirectory(
      normalizedURL,
      expectedOwnerID: expectedOwnerID
    )
    defer { _ = Darwin.close(descriptor) }
    try enforcePrivatePermissions(descriptor: descriptor, mode: mode_t(0o700))
  }

  static func setPrivateFilePermissions(
    _ url: URL,
    expectedIdentity: SecureFileIdentity? = nil,
    expectedOwnerID: uid_t = Darwin.geteuid()
  ) throws {
    let normalizedURL = url.standardizedFileURL
    let descriptor = try openRegularFileDescriptor(
      at: normalizedURL,
      expectedOwnerID: expectedOwnerID
    )
    defer { _ = Darwin.close(descriptor) }
    let openedIdentity = try regularFileIdentity(
      descriptor: descriptor,
      expectedOwnerID: expectedOwnerID
    )
    if let expectedIdentity, openedIdentity != expectedIdentity {
      throw ProfileStorageError.fileChangedDuringRead
    }
    try enforcePrivatePermissions(descriptor: descriptor, mode: mode_t(0o600))
  }

  static func regularFileIdentity(
    at url: URL,
    expectedOwnerID: uid_t = Darwin.geteuid()
  ) throws -> SecureFileIdentity {
    let normalizedURL = url.standardizedFileURL
    let descriptor = try openRegularFileDescriptor(
      at: normalizedURL,
      expectedOwnerID: expectedOwnerID
    )
    defer { _ = Darwin.close(descriptor) }

    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0 else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard (status.st_mode & S_IFMT) == S_IFREG else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    guard status.st_uid == expectedOwnerID else {
      throw ProfileStorageError.unexpectedFileOwner
    }
    return SecureFileIdentity(
      device: status.st_dev,
      inode: status.st_ino,
      owner: status.st_uid
    )
  }

  /// Moves one regular file between already-managed directories. Directory
  /// descriptors anchor both sides, and the opened source identity is checked
  /// after `renameat(2)` so a leaf swapped during the operation is rejected.
  static func moveRegularFileWithoutFollowing(
    _ source: URL,
    to destination: URL,
    expectedIdentity: SecureFileIdentity,
    expectedOwnerID: uid_t = Darwin.geteuid(),
    beforeRename: @escaping @Sendable (URL, URL) throws -> Void = { _, _ in },
    afterRename: @escaping @Sendable (URL, URL) throws -> Void = { _, _ in }
  ) throws {
    let normalizedSource = source.standardizedFileURL
    let normalizedDestination = destination.standardizedFileURL
    let sourceName = try validatedLeafName(normalizedSource)
    let destinationName = try validatedLeafName(normalizedDestination)
    let sourceDirectory = try openOwnedDirectory(
      normalizedSource.deletingLastPathComponent(),
      expectedOwnerID: expectedOwnerID
    )
    defer { _ = Darwin.close(sourceDirectory) }
    let destinationDirectory = try openOwnedDirectory(
      normalizedDestination.deletingLastPathComponent(),
      expectedOwnerID: expectedOwnerID
    )
    defer { _ = Darwin.close(destinationDirectory) }

    let sourceDescriptor = sourceName.withCString { name in
      Darwin.openat(
        sourceDirectory,
        name,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
      )
    }
    guard sourceDescriptor >= 0 else {
      if errno == ELOOP || errno == EISDIR || errno == ENXIO {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    defer { _ = Darwin.close(sourceDescriptor) }
    let openedIdentity = try regularFileIdentity(
      descriptor: sourceDescriptor,
      expectedOwnerID: expectedOwnerID
    )
    guard openedIdentity == expectedIdentity else {
      throw ProfileStorageError.fileChangedDuringRead
    }
    try beforeRename(normalizedSource, normalizedDestination)

    let renameResult = sourceName.withCString { sourcePath in
      destinationName.withCString { destinationPath in
        Darwin.renameatx_np(
          sourceDirectory,
          sourcePath,
          destinationDirectory,
          destinationPath,
          UInt32(RENAME_EXCL)
        )
      }
    }
    guard renameResult == 0 else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }

    do {
      try afterRename(normalizedSource, normalizedDestination)
      let movedDescriptor = destinationName.withCString { name in
        Darwin.openat(
          destinationDirectory,
          name,
          O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
      }
      guard movedDescriptor >= 0 else {
        throw ProfileStorageError.fileChangedDuringRead
      }
      defer { _ = Darwin.close(movedDescriptor) }
      let movedIdentity = try regularFileIdentity(
        descriptor: movedDescriptor,
        expectedOwnerID: expectedOwnerID
      )
      guard movedIdentity == openedIdentity else {
        throw ProfileStorageError.fileChangedDuringRead
      }
    } catch {
      // A source leaf swapped after `openat` may have been renamed. Restore it
      // only if the source name is still absent; otherwise leave both entries
      // intact and surface the failure rather than deleting either file.
      _ = destinationName.withCString { destinationPath in
        sourceName.withCString { sourcePath in
          Darwin.renameatx_np(
            destinationDirectory,
            destinationPath,
            sourceDirectory,
            sourcePath,
            UInt32(RENAME_EXCL)
          )
        }
      }
      throw error
    }
  }

  static func openOwnedDirectory(
    _ url: URL,
    expectedOwnerID: uid_t
  ) throws -> Int32 {
    try openVerifiedDirectory(url, expectedOwnerID: expectedOwnerID)
  }

  /// Opens a stable export directory whose ownership and sticky-bit policy
  /// prevents another non-root UID from removing a private staging leaf.
  ///
  /// User-owned directories must either deny shared POSIX writes or be sticky.
  /// A root-owned compatibility directory such as `/private/tmp` must be sticky.
  static func openExportDirectory(
    _ url: URL,
    expectedOwnerID: uid_t
  ) throws -> Int32 {
    let descriptor = try openVerifiedDirectory(url, expectedOwnerID: nil)
    do {
      var status = stat()
      guard Darwin.fstat(descriptor, &status) == 0 else {
        throw ProfileStorageError.io(String(cString: strerror(errno)))
      }
      guard (status.st_mode & S_IFMT) == S_IFDIR else {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      guard status.st_uid == expectedOwnerID || status.st_uid == 0 else {
        throw ProfileStorageError.unexpectedFileOwner
      }
      guard
        isTrustedExportDirectory(
          ownerID: status.st_uid,
          mode: status.st_mode,
          expectedOwnerID: expectedOwnerID
        )
      else {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      guard try extendedACLState(descriptor: descriptor) != .containsAllow else {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      return descriptor
    } catch {
      _ = Darwin.close(descriptor)
      throw error
    }
  }

  static func isTrustedExportDirectory(
    ownerID: uid_t,
    mode: mode_t,
    expectedOwnerID: uid_t
  ) -> Bool {
    let isSticky = mode & mode_t(S_ISVTX) != 0
    let isSharedWritable = mode & (mode_t(S_IWGRP) | mode_t(S_IWOTH)) != 0

    if ownerID == expectedOwnerID {
      return !isSharedWritable || isSticky
    }
    return ownerID == 0 && isSticky
  }

  static func enforcePrivatePermissions(
    descriptor: Int32,
    mode: mode_t
  ) throws {
    guard mode == mode_t(0o600) || mode == mode_t(0o700) else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    try removeExtendedACL(descriptor: descriptor)
    guard Darwin.fchmod(descriptor, mode) == 0 else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }

    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0 else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard status.st_mode & mode_t(0o777) == mode,
      try extendedACLState(descriptor: descriptor) == .absent
    else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
  }

  static func extendedACLState(descriptor: Int32) throws -> SecureExtendedACLState {
    errno = 0
    guard let acl = Darwin.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
      let code = errno
      if code == ENOENT {
        return .absent
      }
      throw ProfileStorageError.io(String(cString: strerror(code)))
    }
    defer { _ = Darwin.acl_free(UnsafeMutableRawPointer(acl)) }

    var entry: acl_entry_t?
    var selector = Int32(ACL_FIRST_ENTRY.rawValue)
    var foundDeny = false
    while true {
      errno = 0
      let result = Darwin.acl_get_entry(acl, selector, &entry)
      guard result == 0 else {
        let code = errno
        if code == EINVAL {
          return foundDeny ? .denyOnly : .absent
        }
        throw ProfileStorageError.io(String(cString: strerror(code)))
      }
      guard let entry else {
        throw ProfileStorageError.unsafeFilesystemObject
      }

      var tag = ACL_UNDEFINED_TAG
      guard Darwin.acl_get_tag_type(entry, &tag) == 0 else {
        throw ProfileStorageError.io(String(cString: strerror(errno)))
      }
      switch tag {
      case ACL_EXTENDED_ALLOW:
        return .containsAllow
      case ACL_EXTENDED_DENY:
        foundDeny = true
      default:
        throw ProfileStorageError.unsafeFilesystemObject
      }
      selector = Int32(ACL_NEXT_ENTRY.rawValue)
    }
  }

  private static func removeExtendedACL(descriptor: Int32) throws {
    guard try extendedACLState(descriptor: descriptor) != .absent else {
      return
    }
    guard let emptyACL = Darwin.acl_init(0) else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    defer { _ = Darwin.acl_free(UnsafeMutableRawPointer(emptyACL)) }
    guard Darwin.acl_set_fd_np(descriptor, emptyACL, ACL_TYPE_EXTENDED) == 0 else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard try extendedACLState(descriptor: descriptor) == .absent else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
  }

  static func directoryIdentity(
    descriptor: Int32,
    expectedOwnerID: uid_t?
  ) throws -> SecureFileIdentity {
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0 else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard (status.st_mode & S_IFMT) == S_IFDIR else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    if let expectedOwnerID, status.st_uid != expectedOwnerID {
      throw ProfileStorageError.unexpectedFileOwner
    }
    return SecureFileIdentity(
      device: status.st_dev,
      inode: status.st_ino,
      owner: status.st_uid
    )
  }

  static func verifyDirectoryPathIdentity(
    _ url: URL,
    equals expectedIdentity: SecureFileIdentity,
    expectedOwnerID: uid_t?
  ) throws {
    let descriptor = try openVerifiedDirectory(url, expectedOwnerID: expectedOwnerID)
    defer { _ = Darwin.close(descriptor) }
    guard
      try directoryIdentity(
        descriptor: descriptor,
        expectedOwnerID: expectedOwnerID
      ) == expectedIdentity
    else {
      throw ProfileStorageError.fileChangedDuringRead
    }
  }

  static func managedRegularFileState(
    in directoryDescriptor: Int32,
    named name: String,
    expectedOwnerID: uid_t
  ) throws -> SecureManagedLeafState {
    switch try directoryEntryState(
      in: directoryDescriptor,
      named: name,
      expectedOwnerID: expectedOwnerID
    ) {
    case .missing:
      return .missing
    case .present(let identity):
      guard identity.fileType == S_IFREG else {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      return .regularFile(
        SecureFileIdentity(
          device: identity.device,
          inode: identity.inode,
          owner: identity.owner
        )
      )
    }
  }

  static func directoryEntryState(
    in directoryDescriptor: Int32,
    named name: String,
    expectedOwnerID: uid_t?
  ) throws -> SecureDirectoryEntryState {
    guard isValidLeafName(name) else {
      throw ProfileStorageError.unsafeFilesystemObject
    }

    var status = stat()
    let result = name.withCString { leaf in
      Darwin.fstatat(directoryDescriptor, leaf, &status, AT_SYMLINK_NOFOLLOW)
    }
    guard result == 0 else {
      if errno == ENOENT {
        return .missing
      }
      if errno == ELOOP || errno == EISDIR || errno == ENXIO || errno == ENOTDIR {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    if let expectedOwnerID, status.st_uid != expectedOwnerID {
      throw ProfileStorageError.unexpectedFileOwner
    }
    return .present(
      SecureDirectoryEntryIdentity(
        device: status.st_dev,
        inode: status.st_ino,
        owner: status.st_uid,
        fileType: status.st_mode & S_IFMT
      )
    )
  }

  static func openRegularFileDescriptor(
    at url: URL,
    expectedOwnerID: uid_t
  ) throws -> Int32 {
    guard url.isFileURL else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    let normalizedURL = url.standardizedFileURL
    let name = try validatedLeafName(normalizedURL)
    let parentDescriptor = try openVerifiedDirectory(
      normalizedURL.deletingLastPathComponent(),
      expectedOwnerID: nil
    )
    defer { _ = Darwin.close(parentDescriptor) }

    var before = stat()
    let preflightResult = name.withCString { leaf in
      Darwin.fstatat(parentDescriptor, leaf, &before, AT_SYMLINK_NOFOLLOW)
    }
    guard preflightResult == 0 else {
      if errno == ELOOP || errno == EISDIR || errno == ENXIO || errno == ENOTDIR {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard (before.st_mode & S_IFMT) == S_IFREG else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    guard before.st_uid == expectedOwnerID else {
      throw ProfileStorageError.unexpectedFileOwner
    }

    let descriptor = name.withCString { leaf in
      Darwin.openat(
        parentDescriptor,
        leaf,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
      )
    }
    guard descriptor >= 0 else {
      if errno == ELOOP || errno == EISDIR || errno == ENXIO || errno == ENOTDIR {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }

    do {
      let openedIdentity = try regularFileIdentity(
        descriptor: descriptor,
        expectedOwnerID: expectedOwnerID
      )
      guard openedIdentity.device == before.st_dev,
        openedIdentity.inode == before.st_ino,
        openedIdentity.owner == before.st_uid
      else {
        throw ProfileStorageError.fileChangedDuringRead
      }
      return descriptor
    } catch {
      _ = Darwin.close(descriptor)
      throw error
    }
  }

  private static func openVerifiedDirectory(
    _ url: URL,
    expectedOwnerID: uid_t?
  ) throws -> Int32 {
    guard url.isFileURL else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    let normalizedURL = url.standardizedFileURL
    try validateAncestorChain(for: normalizedURL)

    var before = stat()
    var effectiveURL = normalizedURL
    var lstatResult = effectiveURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.lstat(path, &before)
    }
    if lstatResult == 0,
      (before.st_mode & S_IFMT) == S_IFLNK,
      before.st_uid == 0
    {
      effectiveURL = try resolvedExistingDirectoryURL(normalizedURL)
      try validateAncestorChain(for: effectiveURL)
      lstatResult = effectiveURL.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else { return -1 }
        return Darwin.lstat(path, &before)
      }
    }
    guard lstatResult == 0 else {
      if errno == ELOOP || errno == ENOTDIR {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard (before.st_mode & S_IFMT) == S_IFDIR else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    if let expectedOwnerID, before.st_uid != expectedOwnerID {
      throw ProfileStorageError.unexpectedFileOwner
    }

    let descriptor = effectiveURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    }
    guard descriptor >= 0 else {
      if errno == ELOOP || errno == ENOTDIR {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }

    var after = stat()
    guard Darwin.fstat(descriptor, &after) == 0 else {
      let code = errno
      _ = Darwin.close(descriptor)
      throw ProfileStorageError.io(String(cString: strerror(code)))
    }
    guard (after.st_mode & S_IFMT) == S_IFDIR,
      before.st_dev == after.st_dev,
      before.st_ino == after.st_ino,
      before.st_uid == after.st_uid
    else {
      _ = Darwin.close(descriptor)
      throw ProfileStorageError.fileChangedDuringRead
    }
    if let expectedOwnerID, after.st_uid != expectedOwnerID {
      _ = Darwin.close(descriptor)
      throw ProfileStorageError.unexpectedFileOwner
    }
    do {
      try validateAncestorChain(for: effectiveURL)
    } catch {
      _ = Darwin.close(descriptor)
      throw error
    }
    return descriptor
  }

  private static func resolvedExistingDirectoryURL(_ url: URL) throws -> URL {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let resolvedPath: String? = buffer.withUnsafeMutableBufferPointer { bytes in
      url.withUnsafeFileSystemRepresentation { path in
        guard let path, let baseAddress = bytes.baseAddress,
          let resolved = Darwin.realpath(path, baseAddress)
        else {
          return nil
        }
        return String(cString: resolved)
      }
    }
    guard let resolvedPath else {
      if errno == ELOOP || errno == ENOTDIR {
        throw ProfileStorageError.unsafeFilesystemObject
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    // Keep the raw realpath. Foundation canonicalizes `/private/tmp` back to
    // the `/tmp` compatibility symlink when `standardizedFileURL` is applied.
    return URL(fileURLWithPath: resolvedPath, isDirectory: true)
  }

  static func validatedLeafName(_ url: URL) throws -> String {
    let name = url.lastPathComponent
    guard isValidLeafName(name),
      url.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        == url.standardizedFileURL
    else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    return name
  }

  private static func isValidLeafName(_ name: String) -> Bool {
    !name.isEmpty
      && name != "."
      && name != ".."
      && !name.utf8.contains(0)
      && !name.contains("/")
  }

  static func regularFileIdentity(
    descriptor: Int32,
    expectedOwnerID: uid_t
  ) throws -> SecureFileIdentity {
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0 else {
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }
    guard (status.st_mode & S_IFMT) == S_IFREG else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    guard status.st_uid == expectedOwnerID else {
      throw ProfileStorageError.unexpectedFileOwner
    }
    return SecureFileIdentity(
      device: status.st_dev,
      inode: status.st_ino,
      owner: status.st_uid
    )
  }
}
