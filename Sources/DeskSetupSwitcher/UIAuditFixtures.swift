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
  case editor
  case validation
  case permissions
  case diagnostics
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
  let showsMenuBarExtra: Bool

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
        showsMenuBarExtra: environment["DESK_SETUP_UI_AUDIT_MENUBAR"] == "1"
      )
    #else
      return .disabled
    #endif
  }

  static let disabled = Self(
    isEnabled: false,
    variant: .overview,
    displayMode: .standard,
    showsMenuBarExtra: false
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
    private static let readyProfileID = UUID(
      uuidString: "10000000-0000-0000-0000-000000000001")!
    private static let partialProfileID = UUID(
      uuidString: "10000000-0000-0000-0000-000000000002")!
    private static let disabledProfileID = UUID(
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
      let disabled = disabledProfile()

      if variant == .validation {
        ready.name = "Validation Sample"
        ready.settings.display.value.displays[1].isPrimary.value = true
        ready.settings.audio.value.defaultInputUID.value = nil
        ready.settings.network.value.wifiSSID.value = "  "
      }

      let profiles = [ready, partial, disabled]
      let snapshot = syntheticSnapshot(settings: ready.settings)
      let captureSummary: ProfileCaptureSummary? =
        variant == .overview ? partialCaptureSummary() : nil
      let applySummary: ApplyResultSummary? =
        variant == .overview ? partialApplySummary(profile: ready) : nil

      return UIAuditFixtureState(
        profiles: profiles,
        selectedProfileID: ready.id,
        snapshot: snapshot,
        readinessByProfile: [
          ready.id: variant == .validation ? .partial : .ready,
          partial.id: .partial,
          disabled.id: .unavailable,
        ],
        operationCountByProfile: [ready.id: 7],
        availableOperationCountByProfile: [partial.id: 3],
        captureSummary: captureSummary,
        applySummary: applySummary
      )
    }

    private static func readyProfile() -> DeskProfile {
      DeskProfile(
        id: readyProfileID,
        name: "Focus Workspace — Display, Audio, Network & Input",
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

    private static func disabledProfile() -> DeskProfile {
      DeskProfile(
        id: disabledProfileID,
        name: "Archived Synthetic Profile",
        profileDescription: "Disabled profile used to review the Settings sidebar state.",
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

      return ProfileSettings(
        display: .init(
          value: .init(displays: [
            DisplayTargetSettings(
              id: builtInDisplayID,
              identity: builtInIdentity,
              isPrimary: .init(value: true),
              origin: .init(value: .init(x: 0, y: 0)),
              mirroring: .init(value: .extended),
              mode: .init(value: builtInMode),
              rotationDegrees: .init(isIncluded: false, value: 0),
              isActive: .init(isIncluded: false, value: true)
            ),
            DisplayTargetSettings(
              id: externalDisplayID,
              identity: externalIdentity,
              isPrimary: .init(value: false),
              origin: .init(value: .init(x: 1728, y: 0)),
              mirroring: .init(isIncluded: false, value: .extended),
              mode: .init(value: externalMode),
              rotationDegrees: .init(isIncluded: false, value: 0),
              isActive: .init(isIncluded: false, value: true)
            ),
          ])
        ),
        audio: .init(
          value: .init(
            defaultInputUID: .init(value: "synthetic-input"),
            defaultOutputUID: .init(value: "synthetic-output"),
            systemOutputUID: .init(value: "synthetic-output"),
            outputVolume: .init(value: 0.72),
            outputMuted: .init(value: false)
          )
        ),
        network: .init(
          value: .init(
            wifiPower: .init(value: true),
            wifiSSID: .init(value: "Synthetic Studio"),
            ipv4: .init(isIncluded: false, value: .dhcp),
            dnsServers: .init(isIncluded: false, value: ["192.0.2.53"]),
            webProxy: .init(isIncluded: false, value: nil),
            secureWebProxy: .init(isIncluded: false, value: nil)
          )
        ),
        input: .init(
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

    private static func syntheticSnapshot(settings: ProfileSettings) -> SystemSnapshotResult {
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
        displayModeCatalog: displayCatalog
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
      ]
      let audioSnapshot = AdapterSnapshot(
        group: .audio,
        capturedAt: capturedAt,
        payload: .audio(audioSettings),
        items: audioItems
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
        ],
        profileSettings: settings
      )
    }

    private static func partialCaptureSummary() -> ProfileCaptureSummary {
      ProfileCaptureSummary(items: [
        .init(group: .display, key: "display.0.mode", disposition: .savedApplicable),
        .init(group: .display, key: "display.0.rotation", disposition: .savedSnapshotOnly),
        .init(group: .network, key: "wifi.ssid", disposition: .permissionRequired),
        .init(group: .network, key: "network.dns", disposition: .unsupported),
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
          .init(operation: .init(group: .network, key: "wifi.ssid"), status: .notVerified),
          .init(operation: .init(group: .network, key: "network.dns"), status: .unsupported),
        ]
      )
    }
  }
#endif
