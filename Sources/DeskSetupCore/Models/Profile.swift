import Foundation

public enum ProfileReadiness: String, Codable, CaseIterable, Hashable, Sendable {
  case ready
  case partial
  case unavailable
  case applying
  case applied
  case failed
}

public enum ApplicationItemStatus: String, Codable, Hashable, Sendable {
  case succeeded
  case failed
  case skipped
  case unsupported
  case rolledBack
  case rollbackFailed
}

public struct ApplicationItemSummary: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var group: SettingGroup
  public var key: String
  public var status: ApplicationItemStatus
  public var message: String

  public init(
    id: UUID = UUID(),
    group: SettingGroup,
    key: String,
    status: ApplicationItemStatus,
    message: String
  ) {
    self.id = id
    self.group = group
    self.key = key
    self.status = status
    self.message = message
  }
}

public struct ApplicationSummary: Codable, Hashable, Sendable {
  public var appliedAt: Date
  public var status: ProfileReadiness
  public var items: [ApplicationItemSummary]

  public init(appliedAt: Date, status: ProfileReadiness, items: [ApplicationItemSummary]) {
    self.appliedAt = appliedAt
    self.status = status
    self.items = items
  }
}

public struct DeskProfile: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  public var profileDescription: String
  public var symbolName: String
  public var isEnabled: Bool
  public var settings: ProfileSettings
  public var conditions: ProfileConditionSet
  public var createdAt: Date
  public var updatedAt: Date
  public var lastApplication: ApplicationSummary?

  public init(
    id: UUID = UUID(),
    name: String,
    profileDescription: String = "",
    symbolName: String = "display.2",
    isEnabled: Bool = true,
    settings: ProfileSettings = .init(),
    conditions: ProfileConditionSet = .init(),
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastApplication: ApplicationSummary? = nil
  ) {
    self.id = id
    self.name = name
    self.profileDescription = profileDescription
    self.symbolName = symbolName
    self.isEnabled = isEnabled
    self.settings = settings
    self.conditions = conditions
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastApplication = lastApplication
  }
}

public struct ProfileDocument: Codable, Hashable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var profiles: [DeskProfile]
  public var selectedProfileID: UUID?
  public var updatedAt: Date

  public init(
    schemaVersion: Int = ProfileDocument.currentSchemaVersion,
    profiles: [DeskProfile] = [],
    selectedProfileID: UUID? = nil,
    updatedAt: Date = Date()
  ) {
    self.schemaVersion = schemaVersion
    self.profiles = profiles
    self.selectedProfileID = selectedProfileID
    self.updatedAt = updatedAt
  }
}
