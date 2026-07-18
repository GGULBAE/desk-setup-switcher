import Foundation

public enum ProfileStorageError: Error, Equatable, Sendable {
  case fileTooLarge(actualBytes: Int, maximumBytes: Int)
  case invalidJSON
  case unsupportedSchema(found: Int, current: Int)
  case missingMigration(fromVersion: Int)
  case invalidMigration(fromVersion: Int, toVersion: Int)
  case profileNotFound(UUID)
  case profileAlreadyExists(UUID)
  case invalidReorderIndex(Int)
  case invalidStoreFileName
  case unsafeFilesystemObject
  case unexpectedFileOwner
  case fileChangedDuringRead
  case destinationExists(URL)
  case importSourceOverwrite(URL)
  case io

  /// Converts parser details to a non-sensitive typed error without retaining them.
  public static func invalidJSON(_: String) -> Self {
    .invalidJSON
  }

  /// Converts I/O details to a non-sensitive typed error without retaining them.
  public static func io(_: String) -> Self {
    .io
  }

  var canQuarantine: Bool {
    switch self {
    case .fileTooLarge, .invalidJSON, .invalidMigration:
      true
    case .unsupportedSchema,
      .missingMigration,
      .profileNotFound,
      .profileAlreadyExists,
      .invalidReorderIndex,
      .invalidStoreFileName,
      .unsafeFilesystemObject,
      .unexpectedFileOwner,
      .fileChangedDuringRead,
      .destinationExists,
      .importSourceOverwrite,
      .io:
      false
    }
  }
}

extension ProfileStorageError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .fileTooLarge(let actualBytes, let maximumBytes):
      "The profile document is \(actualBytes) bytes; the limit is \(maximumBytes) bytes."
    case .invalidJSON:
      "The profile document is invalid."
    case .unsupportedSchema(let found, let current):
      "Profile schema \(found) is not supported by this app (current: \(current))."
    case .missingMigration(let fromVersion):
      "No migration is registered for profile schema \(fromVersion)."
    case .invalidMigration(let fromVersion, let toVersion):
      "The migration from schema \(fromVersion) did not produce schema \(toVersion)."
    case .profileNotFound(let id):
      "No profile exists with identifier \(id.uuidString)."
    case .profileAlreadyExists(let id):
      "A profile already exists with identifier \(id.uuidString)."
    case .invalidReorderIndex(let index):
      "Profile reorder index \(index) is out of bounds."
    case .invalidStoreFileName:
      "The profile store file name must be one non-reserved file name."
    case .unsafeFilesystemObject:
      "The selected profile path is not a safe regular file or managed directory."
    case .unexpectedFileOwner:
      "The profile path is not owned by the current user."
    case .fileChangedDuringRead:
      "The profile document changed while it was being read."
    case .destinationExists(let url):
      "Export destination already exists: \(url.lastPathComponent)."
    case .importSourceOverwrite(let url):
      "Export would overwrite the imported source: \(url.lastPathComponent)."
    case .io:
      "Profile storage failed."
    }
  }
}

extension ProfileStorageError: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    errorDescription ?? "Profile storage failed."
  }

  public var debugDescription: String {
    description
  }
}

public enum ProfileInvalidValueReason: String, Equatable, Sendable {
  case blank
  case missingIncludedValue
  case nonFinite
  case outOfRange
  case invalidDimensions
  case invalidRotation
  case duplicateIdentifier
  case malformedIPv4Address
  case malformedSubnetMask
  case malformedIPAddress
  case malformedCIDR
}

public enum ProfileValidationIssue: Equatable, Sendable {
  case unsupportedSchema(found: Int, expected: Int)
  case tooManyProfiles(actual: Int, maximum: Int)
  case duplicateProfileID(UUID)
  case invalidSelectedProfileID(UUID)
  case tooManyConditions(profileID: UUID, actual: Int, maximum: Int)
  case duplicateConditionID(profileID: UUID, conditionID: UUID)
  case stringTooLong(path: String, scalarCount: Int, maximum: Int)
  case invalidValue(path: String, reason: ProfileInvalidValueReason)
}

public struct ProfileValidationError: Error, Equatable, Sendable {
  public let issues: [ProfileValidationIssue]

  public init(issues: [ProfileValidationIssue]) {
    self.issues = issues
  }
}

extension ProfileValidationError: LocalizedError {
  public var errorDescription: String? {
    guard let first = issues.first else {
      return "The profile document is invalid."
    }
    let prefix =
      issues.count == 1
      ? "Profile validation failed" : "Profile validation found \(issues.count) problems"
    return "\(prefix). \(first.safeDescription)"
  }
}

extension ProfileValidationIssue {
  fileprivate var safeDescription: String {
    switch self {
    case .unsupportedSchema(let found, let expected):
      "Schema \(found) is unsupported; this app expects schema \(expected)."
    case .tooManyProfiles(let actual, let maximum):
      "The document contains \(actual) profiles; the limit is \(maximum)."
    case .duplicateProfileID:
      "The document contains a duplicate profile identifier."
    case .invalidSelectedProfileID:
      "The selected profile identifier does not exist in the document."
    case .tooManyConditions(_, let actual, let maximum):
      "A profile contains \(actual) conditions; the limit is \(maximum)."
    case .duplicateConditionID:
      "A profile contains a duplicate condition identifier."
    case .stringTooLong(let path, let scalarCount, let maximum):
      "\(path) contains \(scalarCount) characters; the limit is \(maximum)."
    case .invalidValue(let path, let reason):
      "\(path) has an invalid value (\(reason.safeDescription))."
    }
  }
}

extension ProfileInvalidValueReason {
  fileprivate var safeDescription: String {
    switch self {
    case .blank: "blank"
    case .missingIncludedValue: "an included value is missing"
    case .nonFinite: "the number is not finite"
    case .outOfRange: "outside the supported range"
    case .invalidDimensions: "invalid dimensions"
    case .invalidRotation: "invalid rotation"
    case .duplicateIdentifier: "duplicate identifier"
    case .malformedIPv4Address: "malformed IPv4 address"
    case .malformedSubnetMask: "malformed subnet mask"
    case .malformedIPAddress: "malformed IP address"
    case .malformedCIDR: "malformed address or CIDR"
    }
  }
}
