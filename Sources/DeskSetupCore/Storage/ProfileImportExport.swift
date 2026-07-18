import Darwin
import Foundation

public struct ImportedProfileDocument: Equatable, Sendable {
  public let document: ProfileDocument
  public let sourceURL: URL
  public let originalSchemaVersion: Int
  public let wasNormalized: Bool

  public init(
    document: ProfileDocument,
    sourceURL: URL,
    originalSchemaVersion: Int,
    wasNormalized: Bool = false
  ) {
    self.document = document
    self.sourceURL = sourceURL
    self.originalSchemaVersion = originalSchemaVersion
    self.wasNormalized = wasNormalized
  }
}

public struct ProfileImportExport: Sendable {
  private let codec: ProfileJSONCodec
  private let normalizer: ProfileApplicabilityNormalizer

  public init(
    codec: ProfileJSONCodec = .init(),
    normalizer: ProfileApplicabilityNormalizer = .init()
  ) {
    self.codec = codec
    self.normalizer = normalizer
  }

  public func importDocument(from sourceURL: URL) throws -> ImportedProfileDocument {
    let decoded = try codec.decode(contentsOf: sourceURL)
    return ImportedProfileDocument(
      document: decoded.document,
      sourceURL: sourceURL.standardizedFileURL,
      originalSchemaVersion: decoded.originalSchemaVersion,
      wasNormalized: decoded.wasNormalized
    )
  }

  public func export(_ document: ProfileDocument, to destinationURL: URL) throws {
    try write(document, to: destinationURL)
  }

  public func export(_ imported: ImportedProfileDocument, to destinationURL: URL) throws {
    let source = imported.sourceURL.resolvingSymlinksInPath().standardizedFileURL
    let destination = destinationURL.resolvingSymlinksInPath().standardizedFileURL
    guard source != destination else {
      throw ProfileStorageError.importSourceOverwrite(imported.sourceURL)
    }
    try write(imported.document, to: destinationURL)
  }

  private func write(_ document: ProfileDocument, to destinationURL: URL) throws {
    let data = try codec.encode(normalizer.normalize(document))
    guard destinationURL.isFileURL else {
      throw ProfileStorageError.unsafeFilesystemObject
    }
    let normalizedDestinationURL = destinationURL.standardizedFileURL
    let descriptor = normalizedDestinationURL.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else { return -1 }
      return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else {
      if errno == EEXIST {
        throw ProfileStorageError.destinationExists(destinationURL)
      }
      throw ProfileStorageError.io(String(cString: strerror(errno)))
    }

    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try handle.close()
    } catch {
      try? handle.close()
      try? FileManager.default.removeItem(at: normalizedDestinationURL)
      throw ProfileStorageError.io(String(describing: error))
    }
  }
}
