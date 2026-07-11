import Foundation

public struct ProfileMigrationStep: Sendable {
  public let fromVersion: Int
  public let toVersion: Int
  private let transform: @Sendable (Data) throws -> Data

  public init(
    fromVersion: Int,
    toVersion: Int,
    transform: @escaping @Sendable (Data) throws -> Data
  ) {
    self.fromVersion = fromVersion
    self.toVersion = toVersion
    self.transform = transform
  }

  func apply(to data: Data) throws -> Data {
    try transform(data)
  }
}

public struct ProfileMigrationResult: Equatable, Sendable {
  public let data: Data
  public let originalVersion: Int
  public let finalVersion: Int

  public var didMigrate: Bool {
    originalVersion != finalVersion
  }
}

public struct ProfileDocumentMigrator: Sendable {
  private let stepsByVersion: [Int: ProfileMigrationStep]

  public init(steps: [ProfileMigrationStep] = Self.defaultSteps) {
    self.stepsByVersion = steps.reduce(into: [:]) { result, step in
      result[step.fromVersion] = step
    }
  }

  public func migrate(_ data: Data) throws -> ProfileMigrationResult {
    let originalVersion = try schemaVersion(in: data)
    guard originalVersion <= ProfileDocument.currentSchemaVersion else {
      throw ProfileStorageError.unsupportedSchema(
        found: originalVersion,
        current: ProfileDocument.currentSchemaVersion
      )
    }
    guard originalVersion >= 0 else {
      throw ProfileStorageError.invalidJSON("schemaVersion must not be negative")
    }

    var version = originalVersion
    var migratedData = data
    while version < ProfileDocument.currentSchemaVersion {
      guard let step = stepsByVersion[version] else {
        throw ProfileStorageError.missingMigration(fromVersion: version)
      }
      guard step.toVersion == version + 1 else {
        throw ProfileStorageError.invalidMigration(
          fromVersion: version,
          toVersion: step.toVersion
        )
      }
      migratedData = try step.apply(to: migratedData)
      let emittedVersion = try schemaVersion(in: migratedData)
      guard emittedVersion == step.toVersion else {
        throw ProfileStorageError.invalidMigration(
          fromVersion: version,
          toVersion: step.toVersion
        )
      }
      version = emittedVersion
    }

    return ProfileMigrationResult(
      data: migratedData,
      originalVersion: originalVersion,
      finalVersion: version
    )
  }

  private func schemaVersion(in data: Data) throws -> Int {
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ProfileStorageError.invalidJSON("top-level value must be an object")
      }
      guard let value = object["schemaVersion"] else {
        return 0
      }
      guard let version = value as? Int else {
        throw ProfileStorageError.invalidJSON("schemaVersion must be an integer")
      }
      return version
    } catch let error as ProfileStorageError {
      throw error
    } catch {
      throw ProfileStorageError.invalidJSON(String(describing: error))
    }
  }

  public static let defaultSteps: [ProfileMigrationStep] = [
    ProfileMigrationStep(fromVersion: 0, toVersion: 1) { data in
      do {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          throw ProfileStorageError.invalidJSON("schema 0 top-level value must be an object")
        }
        object["schemaVersion"] = 1
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      } catch let error as ProfileStorageError {
        throw error
      } catch {
        throw ProfileStorageError.invalidJSON(String(describing: error))
      }
    }
  ]
}
