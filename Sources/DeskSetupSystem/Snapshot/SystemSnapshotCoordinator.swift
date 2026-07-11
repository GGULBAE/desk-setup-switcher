import Foundation

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif

public enum SystemSnapshotFailureStage: String, Hashable, Sendable {
  case duplicateAdapter
  case capabilityContract
  case snapshot
  case snapshotContract
  case payloadContract
}

public struct SystemSnapshotGroupFailure: Hashable, Sendable {
  public let stage: SystemSnapshotFailureStage
  public let message: String

  public init(stage: SystemSnapshotFailureStage, message: String) {
    self.stage = stage
    self.message = message
  }
}

public struct SystemSnapshotGroupResult: Equatable, Sendable {
  public let group: SettingGroup
  public let capability: AdapterCapability
  public let snapshot: AdapterSnapshot?
  public let items: [SnapshotItem]
  public let failures: [SystemSnapshotGroupFailure]

  public init(
    group: SettingGroup,
    capability: AdapterCapability,
    snapshot: AdapterSnapshot?,
    items: [SnapshotItem],
    failures: [SystemSnapshotGroupFailure]
  ) {
    self.group = group
    self.capability = capability
    self.snapshot = snapshot
    self.items = items
    self.failures = failures
  }

  public var detectedItems: [SnapshotItem] {
    items.filter { $0.state == .detected }
  }

  public var storableItems: [SnapshotItem] {
    items.filter { $0.state == .storable }
  }

  public var unreadableItems: [SnapshotItem] {
    items.filter { $0.state == .unreadable }
  }

  public var permissionRequiredItems: [SnapshotItem] {
    items.filter { $0.state == .permissionRequired }
  }

  public var unsupportedItems: [SnapshotItem] {
    items.filter { $0.state == .unsupported }
  }
}

public struct SystemSnapshotResult: Equatable, Sendable {
  public let capturedAt: Date
  public let groups: [SystemSnapshotGroupResult]
  public let profileSettings: ProfileSettings

  public var settings: ProfileSettings { profileSettings }

  public init(
    capturedAt: Date,
    groups: [SystemSnapshotGroupResult],
    profileSettings: ProfileSettings
  ) {
    self.capturedAt = capturedAt
    self.groups = groups
    self.profileSettings = profileSettings
  }

  public func result(for group: SettingGroup) -> SystemSnapshotGroupResult? {
    groups.first { $0.group == group }
  }
}

/// Aggregates read-only adapter snapshots. This type deliberately has no path to
/// adapter validation, planning, application, or rollback methods.
public struct SystemSnapshotCoordinator: Sendable {
  private let adaptersByGroup: [SettingGroup: any SystemSettingsAdapter]
  private let duplicateGroups: Set<SettingGroup>
  private let now: @Sendable () -> Date

  public init(
    adapters: [any SystemSettingsAdapter] = LiveAdapterFactory.makeAdapters(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    var indexed: [SettingGroup: any SystemSettingsAdapter] = [:]
    var duplicates = Set<SettingGroup>()
    for adapter in adapters {
      if indexed[adapter.group] == nil {
        indexed[adapter.group] = adapter
      } else {
        duplicates.insert(adapter.group)
      }
    }
    adaptersByGroup = indexed
    duplicateGroups = duplicates
    self.now = now
  }

  public func capture() async -> SystemSnapshotResult {
    var groupResults: [SystemSnapshotGroupResult] = []
    var settings = ProfileSettings()

    for group in SettingGroup.allCases {
      guard let adapter = adaptersByGroup[group] else { continue }

      let capability = await adapter.capability()
      var failures: [SystemSnapshotGroupFailure] = []
      if duplicateGroups.contains(group) {
        failures.append(
          SystemSnapshotGroupFailure(
            stage: .duplicateAdapter,
            message: "Only the first adapter registered for this group was queried."
          )
        )
      }
      if capability.group != group {
        failures.append(
          SystemSnapshotGroupFailure(
            stage: .capabilityContract,
            message: "The adapter returned capability data for another settings group."
          )
        )
      }

      let snapshot: AdapterSnapshot
      do {
        snapshot = try await adapter.snapshot()
      } catch {
        let unreadable = SnapshotItem(
          key: "snapshot",
          label: "\(group.rawValue.capitalized) snapshot",
          state: .unreadable,
          detail: "This settings group could not be read."
        )
        failures.append(
          SystemSnapshotGroupFailure(
            stage: .snapshot,
            message: "The read-only snapshot failed."
          )
        )
        groupResults.append(
          SystemSnapshotGroupResult(
            group: group,
            capability: capability,
            snapshot: nil,
            items: [unreadable],
            failures: failures
          )
        )
        continue
      }

      guard snapshot.group == group else {
        failures.append(
          SystemSnapshotGroupFailure(
            stage: .snapshotContract,
            message: "The adapter returned a snapshot for another settings group."
          )
        )
        let unreadable = SnapshotItem(
          key: "snapshot",
          label: "\(group.rawValue.capitalized) snapshot",
          state: .unreadable,
          detail: "The snapshot could not be attributed safely."
        )
        groupResults.append(
          SystemSnapshotGroupResult(
            group: group,
            capability: capability,
            snapshot: nil,
            items: [unreadable],
            failures: failures
          )
        )
        continue
      }

      let matchingPayload = snapshot.payload?.group == group
      if snapshot.payload != nil, !matchingPayload {
        failures.append(
          SystemSnapshotGroupFailure(
            stage: .payloadContract,
            message: "The snapshot payload belongs to another settings group."
          )
        )
      }
      if matchingPayload, snapshot.items.contains(where: { $0.state == .storable }) {
        include(snapshot.payload, in: &settings)
      }

      groupResults.append(
        SystemSnapshotGroupResult(
          group: group,
          capability: capability,
          snapshot: snapshot,
          items: snapshot.items,
          failures: failures
        )
      )
    }

    return SystemSnapshotResult(
      capturedAt: now(),
      groups: groupResults,
      profileSettings: settings
    )
  }

  private func include(_ payload: SettingsPayload?, in settings: inout ProfileSettings) {
    switch payload {
    case .display(let value):
      settings.display = SettingGroupConfiguration(isIncluded: true, value: value)
    case .audio(let value):
      settings.audio = SettingGroupConfiguration(isIncluded: true, value: value)
    case .network(let value):
      settings.network = SettingGroupConfiguration(isIncluded: true, value: value)
    case .input(let value):
      settings.input = SettingGroupConfiguration(isIncluded: true, value: value)
    case nil:
      break
    }
  }
}
