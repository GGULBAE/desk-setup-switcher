import Foundation

public enum VisibleSettingKind: String, CaseIterable, Codable, Hashable, Sendable {
  case displayOutputMode
  case displayPrimary
  case displayMode
  case displayColorProfile
  case audioDefaultInput
  case audioDefaultOutput
  case audioInputVolume
  case audioOutputVolume
  case networkServiceIPv4
}

public enum VisibleSettingStage: String, CaseIterable, Codable, Hashable, Sendable {
  case capture
  case edit
  case validate
  case plan
  case apply
  case verify
  case rollback
}

public enum VisibleSettingEditorKind: String, Codable, Hashable, Sendable {
  case segmentedPicker
  case picker
  case sliderAndField
  case ipv4Form
}

public struct VisibleSettingContract: Codable, Hashable, Sendable {
  public var kind: VisibleSettingKind
  public var group: SettingGroup
  public var snapshotKey: String
  public var runtimeCatalogSource: String
  public var validationKey: String
  public var operationKeyPrefix: String
  public var editorKind: VisibleSettingEditorKind
  public var localizationKey: String
  public var accessibilityLabelKey: String
  public var stages: Set<VisibleSettingStage>

  public init(
    kind: VisibleSettingKind,
    group: SettingGroup,
    snapshotKey: String,
    runtimeCatalogSource: String,
    validationKey: String,
    operationKeyPrefix: String,
    editorKind: VisibleSettingEditorKind,
    localizationKey: String,
    accessibilityLabelKey: String,
    stages: Set<VisibleSettingStage> = Set(VisibleSettingStage.allCases)
  ) {
    self.kind = kind
    self.group = group
    self.snapshotKey = snapshotKey
    self.runtimeCatalogSource = runtimeCatalogSource
    self.validationKey = validationKey
    self.operationKeyPrefix = operationKeyPrefix
    self.editorKind = editorKind
    self.localizationKey = localizationKey
    self.accessibilityLabelKey = accessibilityLabelKey
    self.stages = stages
  }
}

public struct VisibleSettingField: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var contract: VisibleSettingContract

  public init(id: String, contract: VisibleSettingContract) {
    self.id = id
    self.contract = contract
  }
}

/// One registry is shared by runtime projection tests and the editor. A field
/// is projected only when its public adapter snapshot exposes the catalog and
/// rollback evidence required by every vertical-slice stage.
public struct VisibleSettingRegistry: Sendable {
  public static let contracts: [VisibleSettingContract] = [
    .init(
      kind: .displayOutputMode,
      group: .display,
      snapshotKey: "display.mirroring",
      runtimeCatalogSource: "displayModeCatalog",
      validationKey: "display.mirroring",
      operationKeyPrefix: "display.atomic-configuration",
      editorKind: .segmentedPicker,
      localizationKey: "editor.display.outputMode",
      accessibilityLabelKey: "editor.display.outputMode.accessibility"
    ),
    .init(
      kind: .displayPrimary,
      group: .display,
      snapshotKey: "display.primary",
      runtimeCatalogSource: "displayModeCatalog",
      validationKey: "display.primary",
      operationKeyPrefix: "display.atomic-configuration",
      editorKind: .picker,
      localizationKey: "editor.display.primary",
      accessibilityLabelKey: "editor.display.primary.accessibility"
    ),
    .init(
      kind: .displayMode,
      group: .display,
      snapshotKey: "display.mode",
      runtimeCatalogSource: "displayModeCatalog",
      validationKey: "display.mode",
      operationKeyPrefix: "display.atomic-configuration",
      editorKind: .picker,
      localizationKey: "editor.display.mode",
      accessibilityLabelKey: "editor.display.mode.accessibility"
    ),
    .init(
      kind: .displayColorProfile,
      group: .display,
      snapshotKey: "display.colorProfile",
      runtimeCatalogSource: "displayColorProfileCatalog",
      validationKey: "display.colorProfile",
      operationKeyPrefix: "display.colorProfile.",
      editorKind: .picker,
      localizationKey: "editor.display.colorProfile",
      accessibilityLabelKey: "editor.display.colorProfile.accessibility"
    ),
    .init(
      kind: .audioDefaultInput,
      group: .audio,
      snapshotKey: "defaultInput",
      runtimeCatalogSource: "audio.device.input",
      validationKey: "defaultInput",
      operationKeyPrefix: "defaultInput",
      editorKind: .picker,
      localizationKey: "editor.audio.defaultInput",
      accessibilityLabelKey: "editor.audio.defaultInput.accessibility"
    ),
    .init(
      kind: .audioDefaultOutput,
      group: .audio,
      snapshotKey: "defaultOutput",
      runtimeCatalogSource: "audio.device.output",
      validationKey: "defaultOutput",
      operationKeyPrefix: "defaultOutput",
      editorKind: .picker,
      localizationKey: "editor.audio.defaultOutput",
      accessibilityLabelKey: "editor.audio.defaultOutput.accessibility"
    ),
    .init(
      kind: .audioInputVolume,
      group: .audio,
      snapshotKey: "inputVolume",
      runtimeCatalogSource: "audio.inputVolume.settable",
      validationKey: "inputVolume",
      operationKeyPrefix: "inputVolume",
      editorKind: .sliderAndField,
      localizationKey: "editor.audio.inputVolume",
      accessibilityLabelKey: "editor.audio.inputVolume.accessibility"
    ),
    .init(
      kind: .audioOutputVolume,
      group: .audio,
      snapshotKey: "outputVolume",
      runtimeCatalogSource: "audio.outputVolume.settable",
      validationKey: "outputVolume",
      operationKeyPrefix: "outputVolume",
      editorKind: .sliderAndField,
      localizationKey: "editor.audio.outputVolume",
      accessibilityLabelKey: "editor.audio.outputVolume.accessibility"
    ),
    .init(
      kind: .networkServiceIPv4,
      group: .network,
      snapshotKey: "network.serviceIPv4",
      runtimeCatalogSource: "networkIPv4RollbackCatalog",
      validationKey: "network.serviceIPv4",
      operationKeyPrefix: "network.serviceIPv4.",
      editorKind: .ipv4Form,
      localizationKey: "editor.network.serviceIPv4",
      accessibilityLabelKey: "editor.network.serviceIPv4.accessibility"
    ),
  ]

  public init() {}

  public func fields(snapshots: [AdapterSnapshot]) -> [VisibleSettingField] {
    let contractByKind = Dictionary(
      uniqueKeysWithValues: Self.contracts.map { ($0.kind, $0) }
    )
    var fields: [VisibleSettingField] = []

    if let display = snapshots.first(where: { $0.group == .display }) {
      let modes = display.displayModeCatalog ?? []
      if !modes.isEmpty, let contract = contractByKind[.displayPrimary] {
        fields.append(.init(id: contract.kind.rawValue, contract: contract))
      }
      if modes.count >= 2, let contract = contractByKind[.displayOutputMode] {
        fields.append(.init(id: contract.kind.rawValue, contract: contract))
      }
      if let contract = contractByKind[.displayMode] {
        for index in modes.indices where !modes[index].modes.isEmpty {
          fields.append(.init(id: "\(contract.kind.rawValue).\(index)", contract: contract))
        }
      }
      if let contract = contractByKind[.displayColorProfile] {
        for (index, entry) in (display.displayColorProfileCatalog ?? []).enumerated()
        where entry.canApply && !entry.profiles.isEmpty {
          fields.append(.init(id: "\(contract.kind.rawValue).\(index)", contract: contract))
        }
      }
    }

    if let audio = snapshots.first(where: { $0.group == .audio }) {
      let devices = audio.audioDeviceCatalog ?? []
      if devices.contains(where: \.supportsInput),
        let contract = contractByKind[.audioDefaultInput]
      {
        fields.append(.init(id: contract.kind.rawValue, contract: contract))
      }
      if devices.contains(where: \.supportsOutput),
        let contract = contractByKind[.audioDefaultOutput]
      {
        fields.append(.init(id: contract.kind.rawValue, contract: contract))
      }
      for (kind, role) in [
        (VisibleSettingKind.audioInputVolume, AudioVolumeCatalogRole.input),
        (.audioOutputVolume, .output),
      ]
      where (audio.audioVolumeControlCatalog ?? []).contains(where: {
        $0.role == role && $0.canApply && $0.currentValue != nil && $0.deviceUID != nil
      }) {
        if let contract = contractByKind[kind] {
          fields.append(.init(id: contract.kind.rawValue, contract: contract))
        }
      }
    }

    if let network = snapshots.first(where: { $0.group == .network }),
      let contract = contractByKind[.networkServiceIPv4]
    {
      let catalog = network.networkIPv4RollbackCatalog ?? []
      let counts = Dictionary(grouping: catalog, by: \.identity).mapValues(\.count)
      for index in catalog.indices where counts[catalog[index].identity] == 1 {
        fields.append(.init(id: "\(contract.kind.rawValue).\(index)", contract: contract))
      }
    }

    return fields
  }
}
