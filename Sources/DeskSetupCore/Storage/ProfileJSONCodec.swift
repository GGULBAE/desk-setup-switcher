import Foundation

public struct DecodedProfileDocument: Equatable, Sendable {
  public let document: ProfileDocument
  public let originalSchemaVersion: Int
  public let wasNormalized: Bool

  public var wasMigrated: Bool {
    originalSchemaVersion != document.schemaVersion
  }

  public var requiresPersistence: Bool {
    wasMigrated || wasNormalized
  }
}

public struct ProfileJSONCodec: Sendable {
  public let limits: ProfileValidationLimits
  private let validator: ProfileDocumentValidator
  private let migrator: ProfileDocumentMigrator
  private let normalizer: ProfileApplicabilityNormalizer
  private let snapshotReader: SecureFileSnapshotReader

  public init(
    limits: ProfileValidationLimits = .standard,
    migrator: ProfileDocumentMigrator = .init(),
    normalizer: ProfileApplicabilityNormalizer = .init()
  ) {
    self.limits = limits
    self.validator = ProfileDocumentValidator(limits: limits)
    self.migrator = migrator
    self.normalizer = normalizer
    self.snapshotReader = SecureFileSnapshotReader()
  }

  init(
    limits: ProfileValidationLimits = .standard,
    migrator: ProfileDocumentMigrator = .init(),
    normalizer: ProfileApplicabilityNormalizer = .init(),
    snapshotReader: SecureFileSnapshotReader
  ) {
    self.limits = limits
    self.validator = ProfileDocumentValidator(limits: limits)
    self.migrator = migrator
    self.normalizer = normalizer
    self.snapshotReader = snapshotReader
  }

  public func encode(_ document: ProfileDocument) throws -> Data {
    try validator.validate(document)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(Self.iso8601String(from: date))
    }
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data: Data
    do {
      data = try encoder.encode(document)
    } catch {
      throw ProfileStorageError.invalidJSON(String(describing: error))
    }
    try validateSize(data.count)
    return data
  }

  public func decode(_ data: Data) throws -> DecodedProfileDocument {
    try validateSize(data.count)
    let migration = try migrator.migrate(data)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      guard let date = Self.date(fromISO8601: value) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Expected an ISO-8601 timestamp"
        )
      }
      return date
    }
    let decodedDocument: ProfileDocument
    do {
      decodedDocument = try decoder.decode(ProfileDocument.self, from: migration.data)
    } catch {
      throw ProfileStorageError.invalidJSON(String(describing: error))
    }
    try validator.validate(decodedDocument)
    let document = normalizer.normalize(decodedDocument)
    try validator.validate(document)
    return DecodedProfileDocument(
      document: document,
      originalSchemaVersion: migration.originalVersion,
      wasNormalized: document != decodedDocument
    )
  }

  public func decode(contentsOf url: URL) throws -> DecodedProfileDocument {
    do {
      return try decode(readSnapshot(contentsOf: url).data)
    } catch let failure as SecureFileSnapshotReadFailure {
      throw failure.storageError
    } catch let error as ProfileStorageError {
      throw error
    } catch let error as ProfileValidationError {
      throw error
    } catch {
      throw ProfileStorageError.io(String(describing: error))
    }
  }

  func readSnapshot(contentsOf url: URL) throws -> SecureFileSnapshot {
    try snapshotReader.readSnapshot(
      from: url,
      maximumBytes: limits.maximumDocumentBytes
    )
  }

  private func validateSize(_ count: Int) throws {
    guard count <= limits.maximumDocumentBytes else {
      throw ProfileStorageError.fileTooLarge(
        actualBytes: count,
        maximumBytes: limits.maximumDocumentBytes
      )
    }
  }

  private static func iso8601String(from date: Date) -> String {
    var wholeSeconds = floor(date.timeIntervalSince1970)
    var nanoseconds = Int64(
      ((date.timeIntervalSince1970 - wholeSeconds) * 1_000_000_000).rounded()
    )
    if nanoseconds == 1_000_000_000 {
      wholeSeconds += 1
      nanoseconds = 0
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let whole = formatter.string(from: Date(timeIntervalSince1970: wholeSeconds))
    let fraction = String(format: "%09lld", nanoseconds)
    guard whole.hasSuffix("Z") else {
      return whole
    }
    return "\(whole.dropLast()).\(fraction)Z"
  }

  private static func date(fromISO8601 value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: value) {
      return date
    }

    guard let decimalIndex = value.firstIndex(of: "."),
      let zoneIndex = value[decimalIndex...].firstIndex(where: {
        $0 == "Z" || $0 == "+" || $0 == "-"
      })
    else {
      return nil
    }
    let digits = value[value.index(after: decimalIndex)..<zoneIndex]
    guard !digits.isEmpty,
      digits.count <= 9,
      digits.allSatisfy(\.isNumber)
    else {
      return nil
    }

    let wholeValue = String(value[..<decimalIndex]) + String(value[zoneIndex...])
    guard let wholeDate = formatter.date(from: wholeValue),
      let fractionalValue = Int64(digits)
    else {
      return nil
    }
    let scale = pow(10.0, Double(digits.count))
    return wholeDate.addingTimeInterval(Double(fractionalValue) / scale)
  }
}
