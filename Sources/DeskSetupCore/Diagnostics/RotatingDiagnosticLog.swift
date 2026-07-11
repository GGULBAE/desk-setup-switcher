import Foundation

public protocol DiagnosticLogClock: Sendable {
  func now() -> Date
}

public struct SystemDiagnosticLogClock: DiagnosticLogClock {
  public init() {}

  public func now() -> Date {
    Date()
  }
}

public protocol DiagnosticLogStoring: Sendable {
  func append(_ entry: DiagnosticEntry) async throws
  func entries() async throws -> [DiagnosticEntry]
  func removeAll() async throws
}

public enum RotatingDiagnosticLogError: Error, Equatable, Sendable {
  case invalidConfiguration
  case entryTooLarge(actualBytes: Int, maximumBytes: Int)
}

/// A local-only, actor-serialized JSON-lines store.
///
/// Entries are redacted and encoded completely in memory before any write.
/// The active file is replaced atomically for each append; rotation uses a
/// same-directory rename. A truncated or malformed line is ignored on read so
/// one damaged record does not make the remaining diagnostics unavailable.
public actor RotatingDiagnosticLogStore: DiagnosticLogStoring {
  public let directoryURL: URL
  public let baseFileName: String
  public let maximumFileSizeBytes: Int
  public let maximumFileCount: Int

  private let redactor: SensitiveDataRedactor
  private let clock: any DiagnosticLogClock
  private let fileManager: FileManager
  private var rotationSequence: UInt64 = 0

  public init(
    directoryURL: URL,
    baseFileName: String = "diagnostics",
    maximumFileSizeBytes: Int = 512 * 1_024,
    maximumFileCount: Int = 4,
    redactor: SensitiveDataRedactor = .init(),
    clock: any DiagnosticLogClock = SystemDiagnosticLogClock(),
    fileManager: FileManager = .default
  ) throws {
    guard
      directoryURL.isFileURL,
      !baseFileName.isEmpty,
      baseFileName != ".",
      baseFileName != "..",
      !baseFileName.contains("/"),
      !baseFileName.contains("\\"),
      maximumFileSizeBytes > 0,
      maximumFileCount > 0
    else {
      throw RotatingDiagnosticLogError.invalidConfiguration
    }

    self.directoryURL = directoryURL.standardizedFileURL
    self.baseFileName = baseFileName
    self.maximumFileSizeBytes = maximumFileSizeBytes
    self.maximumFileCount = maximumFileCount
    self.redactor = redactor
    self.clock = clock
    self.fileManager = fileManager
  }

  public func append(_ entry: DiagnosticEntry) async throws {
    let safeEntry = redactor.redact(entry)
    var line = try encoder().encode(safeEntry)
    line.append(0x0A)

    guard line.count <= maximumFileSizeBytes else {
      throw RotatingDiagnosticLogError.entryTooLarge(
        actualBytes: line.count,
        maximumBytes: maximumFileSizeBytes
      )
    }

    try ensureDirectory()
    var activeData = (try? Data(contentsOf: activeFileURL)) ?? Data()
    if !activeData.isEmpty,
      activeData.count + line.count > maximumFileSizeBytes
    {
      try rotateActiveFile()
      activeData = Data()
    }

    activeData.append(line)
    try activeData.write(to: activeFileURL, options: .atomic)
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: activeFileURL.path
    )
    try pruneArchives()
  }

  public func entries() async throws -> [DiagnosticEntry] {
    guard fileManager.fileExists(atPath: directoryURL.path) else {
      return []
    }

    var urls = try archiveFileURLs()
    if fileManager.fileExists(atPath: activeFileURL.path) {
      urls.append(activeFileURL)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var result: [DiagnosticEntry] = []
    for url in urls {
      let data = try Data(contentsOf: url)
      for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
        if let entry = try? decoder.decode(DiagnosticEntry.self, from: Data(line)) {
          result.append(entry)
        }
      }
    }
    return result
  }

  public func removeAll() async throws {
    guard fileManager.fileExists(atPath: directoryURL.path) else {
      return
    }

    if fileManager.fileExists(atPath: activeFileURL.path) {
      try fileManager.removeItem(at: activeFileURL)
    }
    for url in try archiveFileURLs() {
      try fileManager.removeItem(at: url)
    }
  }

  private var activeFileURL: URL {
    directoryURL.appendingPathComponent("\(baseFileName).jsonl", isDirectory: false)
  }

  private func ensureDirectory() throws {
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directoryURL.path
    )
  }

  private func rotateActiveFile() throws {
    guard fileManager.fileExists(atPath: activeFileURL.path) else {
      return
    }

    let timestamp = max(0, Int64((clock.now().timeIntervalSince1970 * 1_000).rounded(.down)))
    var archiveURL: URL
    repeat {
      rotationSequence += 1
      let fileName = String(
        format: "%@-%013lld-%06llu.jsonl",
        baseFileName,
        timestamp,
        rotationSequence
      )
      archiveURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
    } while fileManager.fileExists(atPath: archiveURL.path)

    try fileManager.moveItem(at: activeFileURL, to: archiveURL)
  }

  private func pruneArchives() throws {
    let allowedArchiveCount = max(0, maximumFileCount - 1)
    let archives = try archiveFileURLs()
    let excessCount = max(0, archives.count - allowedArchiveCount)
    for archive in archives.prefix(excessCount) {
      try fileManager.removeItem(at: archive)
    }
  }

  private func archiveFileURLs() throws -> [URL] {
    guard fileManager.fileExists(atPath: directoryURL.path) else {
      return []
    }

    let prefix = "\(baseFileName)-"
    return try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter {
      $0.pathExtension == "jsonl"
        && $0.deletingPathExtension().lastPathComponent.hasPrefix(prefix)
    }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}
