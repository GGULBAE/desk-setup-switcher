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
  typealias ExportWriter = @Sendable (Data, URL) throws -> Void

  private let codec: ProfileJSONCodec
  private let normalizer: ProfileApplicabilityNormalizer
  private let exportWriter: ExportWriter

  public init(
    codec: ProfileJSONCodec = .init(),
    normalizer: ProfileApplicabilityNormalizer = .init()
  ) {
    self.codec = codec
    self.normalizer = normalizer
    self.exportWriter = { data, destination in
      try PrivateAtomicFileWriter().writeNew(data, to: destination)
    }
  }

  init(
    codec: ProfileJSONCodec = .init(),
    normalizer: ProfileApplicabilityNormalizer = .init(),
    exportWriter: @escaping ExportWriter
  ) {
    self.codec = codec
    self.normalizer = normalizer
    self.exportWriter = exportWriter
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
    do {
      try exportWriter(data, normalizedDestinationURL)
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }
}
