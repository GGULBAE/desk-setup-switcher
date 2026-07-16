import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif
#if canImport(DeskSetupSystem)
  import DeskSetupSystem
#endif

enum UIAuditVariant: String {
  case overview
  case menuPolish = "menu-polish"
  case trayEmpty = "tray-empty"
  case traySingle = "tray-single"
  case trayOverflow = "tray-overflow"
  case trayDelete = "tray-delete"
  case trayCapturePermission = "tray-capture-permission"
  case trayCaptureSuccess = "tray-capture-success"
  case trayCaptureFailure = "tray-capture-failure"
  case trayApplyResult = "tray-apply-result"
  case editor
  case editorPolish = "editor-polish"
  case editorDisplay = "editor-display"
  case editorDisplayColor = "editor-display-color"
  case editorAudio = "editor-audio"
  case editorAudioUnsupported = "editor-audio-unsupported"
  case editorNetwork = "editor-network"
  case editorNetworkEthernetDHCP = "editor-network-ethernet-dhcp"
  case editorNetworkEthernetManual = "editor-network-ethernet-manual"
  case editorNetworkWiFiDHCP = "editor-network-wifi-dhcp"
  case editorNetworkWiFiManual = "editor-network-wifi-manual"
  case validation
  case permissions
  case diagnostics

  var isTraySurface: Bool {
    switch self {
    case .overview, .menuPolish, .trayEmpty, .traySingle, .trayOverflow, .trayDelete,
      .trayCapturePermission, .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult:
      true
    case .editor, .editorPolish, .editorDisplay, .editorDisplayColor, .editorAudio,
      .editorAudioUnsupported,
      .editorNetwork, .editorNetworkEthernetDHCP, .editorNetworkEthernetManual,
      .editorNetworkWiFiDHCP, .editorNetworkWiFiManual, .validation, .permissions,
      .diagnostics:
      false
    }
  }
}

enum UIAuditDisplayMode: String {
  case standard
  case minimum
  case largeText = "large-text"
}

struct UIAuditConfiguration {
  let isEnabled: Bool
  let variant: UIAuditVariant
  let displayMode: UIAuditDisplayMode
  let showsStatusPopover: Bool

  static var current: Self {
    #if DEBUG
      let environment = ProcessInfo.processInfo.environment
      guard environment["DESK_SETUP_UI_AUDIT"] == "1" else {
        return .disabled
      }
      return Self(
        isEnabled: true,
        variant: UIAuditVariant(rawValue: environment["DESK_SETUP_UI_AUDIT_STATE"] ?? "")
          ?? .overview,
        displayMode: UIAuditDisplayMode(
          rawValue: environment["DESK_SETUP_UI_AUDIT_DISPLAY"] ?? "") ?? .standard,
        showsStatusPopover: environment["DESK_SETUP_UI_AUDIT_MENUBAR"] == "1"
      )
    #else
      return .disabled
    #endif
  }

  static let disabled = Self(
    isEnabled: false,
    variant: .overview,
    displayMode: .standard,
    showsStatusPopover: false
  )
}

private struct UIAuditConfigurationEnvironmentKey: EnvironmentKey {
  static let defaultValue = UIAuditConfiguration.disabled
}

extension EnvironmentValues {
  var uiAuditConfiguration: UIAuditConfiguration {
    get { self[UIAuditConfigurationEnvironmentKey.self] }
    set { self[UIAuditConfigurationEnvironmentKey.self] = newValue }
  }
}

private struct UIAuditEnvironmentModifier: ViewModifier {
  let configuration: UIAuditConfiguration

  @ViewBuilder
  func body(content: Content) -> some View {
    #if DEBUG
      switch configuration.displayMode {
      case .standard, .minimum:
        content.environment(\.uiAuditConfiguration, configuration)
      case .largeText:
        content
          .environment(\.uiAuditConfiguration, configuration)
          .dynamicTypeSize(.accessibility3)
      }
    #else
      content
    #endif
  }
}

extension View {
  func uiAuditEnvironment(_ configuration: UIAuditConfiguration) -> some View {
    modifier(UIAuditEnvironmentModifier(configuration: configuration))
  }
}

#if DEBUG
  struct UIAuditFixtureState {
    let profiles: [DeskProfile]
    let selectedProfileID: UUID?
    let snapshot: SystemSnapshotResult
    let readinessByProfile: [UUID: ProfileReadiness]
    let operationCountByProfile: [UUID: Int]
    let availableOperationCountByProfile: [UUID: Int]
    let captureSummary: ProfileCaptureSummary?
    let applySummary: ApplyResultSummary?
  }

  @MainActor
  enum UIAuditFixtures {
    static let readyProfileID = UUID(
      uuidString: "10000000-0000-0000-0000-000000000001")!
    private static let partialProfileID = UUID(
      uuidString: "10000000-0000-0000-0000-000000000002")!
    private static let legacyProfileID = UUID(
      uuidString: "10000000-0000-0000-0000-000000000003")!
    private static let builtInDisplayID = UUID(
      uuidString: "20000000-0000-0000-0000-000000000001")!
    private static let externalDisplayID = UUID(
      uuidString: "20000000-0000-0000-0000-000000000002")!
    private static let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func makeModel(configuration: UIAuditConfiguration) -> ApplicationModel {
      let isolatedStoreURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "DeskSetupSwitcher-UIAudit-\(ProcessInfo.processInfo.processIdentifier)",
          isDirectory: true
        )
      let model = ApplicationModel(
        profileStore: ProfileStore(directoryURL: isolatedStoreURL),
        snapshotCoordinator: SystemSnapshotCoordinator(adapters: []),
        applyEngine: ApplyEngine(registry: AdapterRegistry()),
        diagnosticLog: nil
      )
      model.configureForUIAudit(fixture(configuration.variant))
      return model
    }

    static func fixture(_ variant: UIAuditVariant) -> UIAuditFixtureState {
      var ready = readyProfile()
      let partial = partialProfile()
      let legacy = legacyProfile()

      if variant == .validation {
        ready.name = "Validation Sample"
        ready.settings.display.value.displays[1].isPrimary.value = true
        ready.settings.audio.value.defaultInputUID.value = nil
        ready.settings.network.value.wifiSSID.value = "  "
      }

      configureNetworkEvidence(variant, profile: &ready)

      let profiles: [DeskProfile]
      switch variant {
      case .trayEmpty:
        profiles = []
      case .traySingle:
        profiles = [ready]
      case .trayOverflow:
        profiles = (0..<10).map { index in
          var profile = ready
          profile.id = UUID(
            uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 10)
          )!
          profile.name = "Synthetic Workspace \(index + 1) — Long Profile Name"
          return profile
        }
      case .overview, .menuPolish, .trayDelete, .trayCapturePermission,
        .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult,
        .editor, .editorPolish, .editorDisplay, .editorDisplayColor, .editorAudio,
        .editorAudioUnsupported,
        .editorNetwork, .editorNetworkEthernetDHCP, .editorNetworkEthernetManual,
        .editorNetworkWiFiDHCP, .editorNetworkWiFiManual, .validation, .permissions,
        .diagnostics:
        profiles = [ready, partial, legacy]
      }
      let snapshot = syntheticSnapshot(
        settings: ready.settings,
        supportsDisplayModes: variant != .editorDisplayColor,
        supportsAudioVolume: variant != .editorAudioUnsupported
      )
      let captureSummary: ProfileCaptureSummary? =
        variant == .overview || variant == .menuPolish || variant == .trayCapturePermission
        ? partialCaptureSummary() : nil
      let applySummary: ApplyResultSummary? =
        variant == .overview || variant == .trayApplyResult
        ? partialApplySummary(profile: ready) : nil

      let readiness = Dictionary(
        uniqueKeysWithValues: profiles.map { profile in
          if profile.id == partial.id { return (profile.id, ProfileReadiness.partial) }
          return (
            profile.id,
            variant == .validation ? ProfileReadiness.partial : ProfileReadiness.ready
          )
        }
      )
      let operations = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, 7) })

      return UIAuditFixtureState(
        profiles: profiles,
        selectedProfileID: profiles.first?.id,
        snapshot: snapshot,
        readinessByProfile: readiness,
        operationCountByProfile: operations,
        availableOperationCountByProfile: [partial.id: 3],
        captureSummary: captureSummary,
        applySummary: applySummary
      )
    }

    private static func readyProfile() -> DeskProfile {
      DeskProfile(
        id: readyProfileID,
        name: "Focus Workspace — Display, Audio & Network",
        profileDescription:
          "A long synthetic profile used only to review layout, wrapping, controls, and accessibility metadata.",
        symbolName: "display.2",
        settings: comprehensiveSettings(),
        createdAt: capturedAt,
        updatedAt: capturedAt,
        lastApplication: ApplicationSummary(
          appliedAt: capturedAt,
          status: .partial,
          items: [
            ApplicationItemSummary(
              group: .audio,
              key: "outputVolume",
              status: .succeeded,
              message: "The saved target was applied."
            ),
            ApplicationItemSummary(
              group: .network,
              key: "wifi.ssid",
              status: .skipped,
              message: "Read-back was unavailable."
            ),
          ]
        )
      )
    }

    private static func partialProfile() -> DeskProfile {
      var settings = comprehensiveSettings()
      settings.display.isIncluded = false
      settings.input.isIncluded = false
      return DeskProfile(
        id: partialProfileID,
        name: "Portable Desk — Available Settings Only",
        profileDescription: "Synthetic partial state with an unavailable target.",
        symbolName: "laptopcomputer.and.iphone",
        settings: settings,
        createdAt: capturedAt,
        updatedAt: capturedAt
      )
    }

    private static func legacyProfile() -> DeskProfile {
      DeskProfile(
        id: legacyProfileID,
        name: "Legacy Synthetic Profile",
        profileDescription: "Legacy false activation value retained only for migration review.",
        symbolName: "archivebox",
        isEnabled: false,
        settings: comprehensiveSettings(),
        createdAt: capturedAt,
        updatedAt: capturedAt
      )
    }

    private static func comprehensiveSettings() -> ProfileSettings {
      let builtInIdentity = DisplayIdentity(
        uuid: builtInDisplayID,
        productName: "Built-in Retina Display",
        isBuiltIn: true
      )
      let externalIdentity = DisplayIdentity(
        uuid: externalDisplayID,
        productName: "Synthetic Wide Display"
      )
      let builtInMode = DisplayMode(
        width: 1728,
        height: 1117,
        pixelWidth: 3456,
        pixelHeight: 2234,
        refreshRate: 60
      )
      let externalMode = DisplayMode(width: 2560, height: 1440, refreshRate: 60)
      let colorProfile = ColorSyncProfileTarget(
        registeredProfileID: "synthetic-srgb",
        fileSHA256: String(repeating: "a", count: 64),
        displayName: "Synthetic sRGB ICC"
      )

      return ProfileSettings(
        display: .init(
          value: .init(displays: [
            DisplayTargetSettings(
              id: builtInDisplayID,
              identity: builtInIdentity,
              isPrimary: .init(value: true),
              origin: .init(isIncluded: false, value: .init(x: 0, y: 0)),
              mirroring: .init(value: .extended),
              mode: .init(value: builtInMode),
              colorProfile: .init(value: colorProfile),
              rotationDegrees: .init(isIncluded: false, value: 0),
              isActive: .init(isIncluded: false, value: true)
            ),
            DisplayTargetSettings(
              id: externalDisplayID,
              identity: externalIdentity,
              isPrimary: .init(value: false),
              origin: .init(isIncluded: false, value: .init(x: 1728, y: 0)),
              mirroring: .init(value: .extended),
              mode: .init(value: externalMode),
              colorProfile: .init(value: colorProfile),
              rotationDegrees: .init(isIncluded: false, value: 0),
              isActive: .init(isIncluded: false, value: true)
            ),
          ])
        ),
        audio: .init(
          value: .init(
            defaultInputUID: .init(value: "synthetic-input"),
            defaultOutputUID: .init(value: "synthetic-output"),
            systemOutputUID: .init(isIncluded: false, value: "synthetic-output"),
            inputVolume: .init(value: 0.44),
            outputVolume: .init(value: 0.72),
            outputMuted: .init(isIncluded: false, value: false)
          )
        ),
        network: .init(
          value: .init(
            wifiPower: .init(isIncluded: false, value: true),
            wifiSSID: .init(isIncluded: false, value: "Synthetic Studio"),
            serviceIPv4: [
              .init(
                identity: .init(
                  kind: .ethernet,
                  serviceName: "Synthetic Ethernet",
                  interfaceType: "Ethernet"
                ),
                configuration: .init(
                  value: .manual(
                    address: "192.0.2.40",
                    subnetMask: "255.255.255.0",
                    router: "192.0.2.1"
                  )
                )
              ),
              .init(
                identity: .init(
                  kind: .wifi,
                  serviceName: "Synthetic Wi-Fi",
                  interfaceType: "IEEE80211"
                ),
                configuration: .init(value: .dhcp)
              ),
            ],
            ipv4: .init(isIncluded: false, value: .dhcp),
            dnsServers: .init(isIncluded: false, value: ["192.0.2.53"]),
            webProxy: .init(isIncluded: false, value: nil),
            secureWebProxy: .init(isIncluded: false, value: nil)
          )
        ),
        input: .init(
          isIncluded: false,
          value: .init(
            pointerSpeed: .init(value: 4.5),
            naturalScrolling: .init(value: true),
            keyRepeatInterval: .init(value: 60),
            initialKeyRepeatDelay: .init(value: 150),
            useStandardFunctionKeys: .init(value: false)
          )
        )
      )
    }

    private static func syntheticSnapshot(
      settings: ProfileSettings,
      supportsDisplayModes: Bool = true,
      supportsAudioVolume: Bool = true
    ) -> SystemSnapshotResult {
      let displaySettings = settings.display.value
      let audioSettings = settings.audio.value
      let displayCatalog = displaySettings.displays.map { display in
        DisplayModeCatalogEntry(
          identity: display.identity,
          modes: [
            display.mode.value,
            DisplayMode(width: 1920, height: 1080, refreshRate: 60),
          ]
        )
      }
      let displaySnapshot = AdapterSnapshot(
        group: .display,
        capturedAt: capturedAt,
        payload: .display(displaySettings),
        items: [],
        displayModeCatalog: supportsDisplayModes ? displayCatalog : [],
        displayColorProfileCatalog: displaySettings.displays.compactMap { display in
          guard let profile = display.colorProfile.value else { return nil }
          return DisplayColorProfileCatalogEntry(
            identity: display.identity,
            profiles: [profile],
            canApply: true
          )
        }
      )
      let audioItems = [
        SnapshotItem(
          key: "device:synthetic-input",
          label: "Synthetic Microphone",
          state: .detected,
          detail: "Input"
        ),
        SnapshotItem(
          key: "device:synthetic-output",
          label: "Synthetic Speakers",
          state: .detected,
          detail: "Output"
        ),
        SnapshotItem(
          key: "inputVolume",
          label: "Input volume",
          state: .storable,
          detail: "Readable and writable"
        ),
        SnapshotItem(
          key: "outputVolume",
          label: "Output volume",
          state: .storable,
          detail: "Readable and writable"
        ),
      ]
      let audioSnapshot = AdapterSnapshot(
        group: .audio,
        capturedAt: capturedAt,
        payload: .audio(audioSettings),
        items: audioItems,
        audioDeviceCatalog: [
          .init(
            uid: "synthetic-input",
            name: "Synthetic Microphone",
            supportsInput: true,
            supportsOutput: false
          ),
          .init(
            uid: "synthetic-output",
            name: "Synthetic Speakers",
            supportsInput: false,
            supportsOutput: true
          ),
        ],
        audioVolumeControlCatalog: [
          .init(
            role: .input,
            deviceUID: "synthetic-input",
            currentValue: audioSettings.inputVolume.value,
            canApply: supportsAudioVolume
          ),
          .init(
            role: .output,
            deviceUID: "synthetic-output",
            currentValue: audioSettings.outputVolume.value,
            canApply: supportsAudioVolume
          ),
        ]
      )
      let networkRollbackCatalog = settings.network.value.serviceIPv4.map { service in
        NetworkIPv4RollbackCatalogEntry(
          identity: service.identity,
          configurationData: Data("synthetic-\(service.identity.kind.rawValue)".utf8),
          currentConfiguration: service.configuration.value
        )
      }
      let networkSnapshot = AdapterSnapshot(
        group: .network,
        capturedAt: capturedAt,
        payload: .network(settings.network.value),
        items: [],
        networkIPv4RollbackCatalog: networkRollbackCatalog,
        savedWiFiNetworkNames: ["Synthetic Saved Wi-Fi"]
      )
      return SystemSnapshotResult(
        capturedAt: capturedAt,
        groups: [
          SystemSnapshotGroupResult(
            group: .display,
            capability: .init(group: .display, state: .supported, reason: ""),
            snapshot: displaySnapshot,
            items: [],
            failures: []
          ),
          SystemSnapshotGroupResult(
            group: .audio,
            capability: .init(group: .audio, state: .supported, reason: ""),
            snapshot: audioSnapshot,
            items: audioItems,
            failures: []
          ),
          SystemSnapshotGroupResult(
            group: .network,
            capability: .init(group: .network, state: .supported, reason: ""),
            snapshot: networkSnapshot,
            items: [],
            failures: []
          ),
        ],
        profileSettings: settings
      )
    }

    private static func configureNetworkEvidence(
      _ variant: UIAuditVariant,
      profile: inout DeskProfile
    ) {
      let selection: (NetworkServiceKind, IPv4Configuration)? =
        switch variant {
        case .editorNetworkEthernetDHCP:
          (.ethernet, .dhcp)
        case .editorNetworkEthernetManual:
          (
            .ethernet,
            .manual(
              address: "192.0.2.40",
              subnetMask: "255.255.255.0",
              router: "192.0.2.1"
            )
          )
        case .editorNetworkWiFiDHCP:
          (.wifi, .dhcp)
        case .editorNetworkWiFiManual:
          (
            .wifi,
            .manual(
              address: "198.51.100.40",
              subnetMask: "255.255.255.0",
              router: "198.51.100.1"
            )
          )
        case .overview, .menuPolish, .trayEmpty, .traySingle, .trayOverflow, .trayDelete,
          .trayCapturePermission, .trayCaptureSuccess, .trayCaptureFailure, .trayApplyResult,
          .editor, .editorPolish, .editorDisplay, .editorDisplayColor, .editorAudio,
          .editorAudioUnsupported,
          .editorNetwork, .validation, .permissions, .diagnostics:
          nil
        }
      guard let selection,
        var service = profile.settings.network.value.serviceIPv4.first(where: {
          $0.identity.kind == selection.0
        })
      else { return }
      service.configuration = .init(value: selection.1)
      profile.settings.network.value.serviceIPv4 = [service]
    }

    private static func partialCaptureSummary() -> ProfileCaptureSummary {
      ProfileCaptureSummary(items: [
        .init(group: .display, key: "display.0.primary", disposition: .savedApplicable),
        .init(group: .display, key: "display.0.origin", disposition: .savedApplicable),
        .init(group: .display, key: "display.0.mirroring", disposition: .savedApplicable),
        .init(group: .display, key: "display.0.mode", disposition: .savedApplicable),
        .init(group: .display, key: "display.0.colorProfile", disposition: .savedApplicable),
        .init(group: .audio, key: "defaultInput", disposition: .savedApplicable),
        .init(group: .audio, key: "defaultOutput", disposition: .savedApplicable),
        .init(group: .audio, key: "inputVolume", disposition: .savedApplicable),
        .init(group: .audio, key: "outputVolume", disposition: .savedApplicable),
        .init(
          group: .network, key: "network.serviceIPv4.ethernet.0", disposition: .savedApplicable),
        .init(group: .network, key: "network.serviceIPv4.wifi.1", disposition: .savedApplicable),
      ])
    }

    private static func partialApplySummary(profile: DeskProfile) -> ApplyResultSummary {
      ApplyResultSummary(
        profileID: profile.id,
        profileName: profile.name,
        appliedAt: capturedAt,
        items: [
          .init(
            operation: .init(group: .display, key: "display.atomic-configuration"),
            status: .succeeded
          ),
          .init(operation: .init(group: .audio, key: "outputVolume"), status: .succeeded),
          .init(
            operation: .init(group: .network, key: "network.serviceIPv4.ethernet.0"),
            status: .notVerified
          ),
        ]
      )
    }
  }
#endif
