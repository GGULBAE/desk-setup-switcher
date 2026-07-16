import DeskSetupCore
import DeskSetupPresentation
import Foundation
import Testing

@Suite("Profile presentation")
struct ProfilePresentationTests {
  @Test("group summaries include only applicable groups in stable presentation order")
  func groupSummaryOrderAndInclusion() {
    let profile = DeskProfile(
      name: "Synthetic desk",
      settings: ProfileSettings(
        display: .init(
          value: .init(displays: [displayTarget(name: "Synthetic Panel")])
        ),
        audio: .init(
          value: .init(
            defaultOutputUID: .init(value: "synthetic-output"),
            outputVolume: .init(value: 0.625)
          )
        ),
        network: .init(
          value: .init(
            wifiPower: .init(value: true),
            wifiSSID: .init(isIncluded: false, value: "Excluded Network"),
            serviceIPv4: [
              .init(
                identity: .init(
                  kind: .ethernet,
                  serviceName: "Synthetic Ethernet",
                  interfaceType: "Ethernet"
                ),
                configuration: .init(value: .dhcp)
              )
            ]
          )
        ),
        input: .init(
          value: .init(
            pointerSpeed: .init(value: 1.75),
            naturalScrolling: .init(value: false)
          )
        )
      )
    )

    let summaries = ProfilePresentationBuilder().summaries(for: profile)

    #expect(summaries.map(\.group) == [.display, .audio, .network])
    #expect(summaries[2].items.map(\.kind) == [.networkServiceIPv4])
    #expect(!summaries[2].summaryText.contains("Excluded Network"))
  }

  @Test("display summary favors product details and hides identifiers")
  func displaySummaryHidesIdentifiers() {
    let identifier = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let target = displayTarget(
      identity: .init(
        uuid: identifier,
        vendorID: 101,
        modelID: 202,
        serialNumber: 303,
        productName: "Synthetic Studio Panel",
        isBuiltIn: false
      )
    )
    let settings = ProfileSettings(
      display: .init(value: .init(displays: [target]))
    )

    let summary = ProfilePresentationBuilder().summary(for: .display, in: settings)

    #expect(summary?.items.map(\.kind) == [.display, .displayMode, .displayRole])
    #expect(summary?.summaryText.contains("Synthetic Studio Panel") == true)
    #expect(summary?.summaryText.contains("2560 × 1440 at 60 Hz") == true)
    #expect(summary?.summaryText.contains(identifier.uuidString) == false)
    #expect(summary?.summaryText.contains("303") == false)
    #expect(summary?.technicalDetails.contains { $0.value == identifier.uuidString } == true)
    #expect(summary?.technicalDetails.contains { $0.value == "303" } == true)
  }

  @Test("audio summary uses names when available and roles otherwise")
  func audioSummaryUsesFriendlyNames() {
    let settings = ProfileSettings(
      audio: .init(
        value: .init(
          defaultInputUID: .init(value: "synthetic-input-uid"),
          defaultOutputUID: .init(value: "synthetic-output-uid"),
          outputVolume: .init(value: 0.7),
          outputMuted: .init(value: false)
        )
      )
    )
    let builder = ProfilePresentationBuilder(
      audioDeviceNamesByUID: ["synthetic-output-uid": "Synthetic Speakers"]
    )

    let summary = builder.summary(for: .audio, in: settings)

    #expect(
      summary?.items.map(\.kind) == [
        .defaultInput, .defaultOutput, .outputVolume,
      ]
    )
    #expect(summary?.summaryText.contains("Synthetic Speakers") == true)
    #expect(summary?.summaryText.contains("Selected input device") == true)
    #expect(summary?.summaryText.contains("70%") == true)
    #expect(summary?.summaryText.contains("synthetic-output-uid") == false)
    #expect(summary?.summaryText.contains("synthetic-input-uid") == false)
    #expect(
      summary?.technicalDetails.map(\.value) == [
        "synthetic-input-uid", "synthetic-output-uid",
      ]
    )
  }

  @Test("multiple unnamed displays receive stable role-based names")
  func multipleUnnamedDisplaysHaveStableNames() {
    let first = displayTarget(
      identity: .init(
        uuid: UUID(uuidString: "10000000-0000-0000-0000-000000000001"),
        isBuiltIn: false
      )
    )
    let second = displayTarget(
      identity: .init(
        uuid: UUID(uuidString: "20000000-0000-0000-0000-000000000002"),
        isBuiltIn: false
      )
    )
    let settings = ProfileSettings(
      display: .init(value: .init(displays: [first, second]))
    )

    let summary = ProfilePresentationBuilder().summary(for: .display, in: settings)

    #expect(summary?.items[0].label == "Display 1")
    #expect(summary?.items[0].value.primaryText == "External display 1")
    let secondDisplay = summary?.items.first { $0.label == "Display 2" }
    #expect(secondDisplay?.value.primaryText == "External display 2")
  }

  @Test("included unavailable values remain visible without invented values")
  func unavailableValuesAreExplicit() {
    let settings = ProfileSettings(
      audio: .init(
        value: .init(
          defaultOutputUID: .init(value: nil),
          outputVolume: .init(value: nil)
        )
      ),
      network: .init(
        value: .init(
          serviceIPv4: [
            .init(
              identity: .init(
                kind: .wifi,
                serviceName: "Synthetic Wi-Fi",
                interfaceType: "IEEE80211"
              ),
              configuration: .init(value: nil)
            )
          ]
        )
      )
    )
    let builder = ProfilePresentationBuilder()

    let audio = builder.summary(for: .audio, in: settings)
    let network = builder.summary(for: .network, in: settings)

    #expect(audio?.items.map(\.value.primaryText) == ["No device saved", "Value unavailable"])
    #expect(network?.items.map(\.value.primaryText) == ["Value unavailable"])
  }

  @Test("service IPv4 values format deterministically while input remains dormant")
  func serviceIPv4Formatting() {
    let settings = ProfileSettings(
      network: .init(
        value: .init(
          wifiPower: .init(value: true),
          wifiSSID: .init(value: "Synthetic Network"),
          serviceIPv4: [
            .init(
              identity: .init(
                kind: .ethernet,
                serviceName: "Synthetic Ethernet",
                interfaceType: "Ethernet"
              ),
              configuration: .init(
                value: .manual(
                  address: "192.0.2.20",
                  subnetMask: "255.255.255.0",
                  router: "192.0.2.1"
                )
              )
            )
          ],
          ipv4: .init(value: .dhcp),
          dnsServers: .init(value: ["192.0.2.53", "198.51.100.53"]),
          webProxy: .init(value: .init(enabled: false, host: "proxy.invalid", port: 8080))
        )
      ),
      input: .init(
        value: .init(
          pointerSpeed: .init(value: 1.5),
          naturalScrolling: .init(value: true),
          keyRepeatInterval: .init(value: 0.125),
          useStandardFunctionKeys: .init(value: true)
        )
      )
    )
    let builder = ProfilePresentationBuilder()

    let network = builder.summary(for: .network, in: settings)
    let input = builder.summary(for: .input, in: settings)

    #expect(network?.items.map(\.kind) == [.networkServiceIPv4])
    #expect(network?.items[0].value.primaryText == "Manual — 192.0.2.20")
    #expect(network?.items[0].value.secondaryText?.contains("255.255.255.0") == true)
    #expect(input == nil)
  }

  @Test("legacy Wi-Fi formatter preserves target whitespace but its summary is dormant")
  func wifiSummariesPreserveExactTargetName() {
    let target = "  Synthetic Target Wi-Fi  "
    #expect(FriendlyValueFormatter.wifiNetworkName(target) == target)
    #expect(FriendlyValueFormatter.wifiNetworkName(" \t\n ") == nil)
    #expect(FriendlyValueFormatter.wifiNetworkName(nil) == nil)

    let settings = ProfileSettings(
      network: .init(value: .init(wifiSSID: .init(value: target)))
    )
    #expect(ProfilePresentationBuilder().summary(for: .network, in: settings) == nil)
  }

  @Test("operation preview keeps audio names visible and UIDs disclosed separately")
  func audioOperationPreviewHidesUIDs() {
    let operation = PlannedOperation(
      group: .audio,
      key: "defaultOutput",
      summary: "Change the synthetic output device",
      preview: .init(
        previousValue: "Synthetic Internal Speakers [synthetic-current-output]",
        desiredValue: "synthetic-target-output"
      )
    )
    let builder = ProfilePresentationBuilder(
      audioDeviceNamesByUID: ["synthetic-target-output": "Synthetic Dock Speakers"]
    )

    let preview = builder.operationPreview(for: operation)

    #expect(preview?.previousValue.primaryText == "Synthetic Internal Speakers")
    #expect(preview?.desiredValue.primaryText == "Synthetic Dock Speakers")
    #expect(preview?.previousValue.compactText.contains("synthetic-current-output") == false)
    #expect(preview?.desiredValue.compactText.contains("synthetic-target-output") == false)
    #expect(
      preview?.previousValue.technicalDetails == [
        .init(label: "Audio device UID", value: "synthetic-current-output")
      ]
    )
    #expect(
      preview?.desiredValue.technicalDetails == [
        .init(label: "Audio device UID", value: "synthetic-target-output")
      ]
    )
  }

  @Test("operation preview does not reinterpret bracketed display or network data")
  func operationPreviewPreservesNonAudioData() {
    let display = PlannedOperation(
      group: .display,
      key: "display.atomic-configuration",
      summary: "Synthetic display change",
      preview: .init(
        previousValue: "Prototype Panel [A] • 1920×1080",
        desiredValue: "Prototype Panel [B] • 2560×1440"
      )
    )
    let network = PlannedOperation(
      group: .network,
      key: "wifi.ssid",
      summary: "Synthetic Wi-Fi change",
      preview: .init(
        previousValue: "Synthetic Network [Guest]",
        desiredValue: "Synthetic Network [Desk]"
      )
    )
    let builder = ProfilePresentationBuilder()

    let displayPreview = builder.operationPreview(for: display)
    let networkPreview = builder.operationPreview(for: network)

    #expect(displayPreview?.previousValue.primaryText == "Prototype Panel [A] • 1920×1080")
    #expect(displayPreview?.desiredValue.primaryText == "Prototype Panel [B] • 2560×1440")
    #expect(displayPreview?.previousValue.technicalDetails.isEmpty == true)
    #expect(networkPreview?.previousValue.primaryText == "Synthetic Network [Guest]")
    #expect(networkPreview?.desiredValue.primaryText == "Synthetic Network [Desk]")
    #expect(networkPreview?.desiredValue.technicalDetails.isEmpty == true)
  }

  @Test("unnamed display identifiers are disclosed only as technical details")
  func unnamedDisplayPreviewHidesIdentifiers() {
    let operation = PlannedOperation(
      group: .display,
      key: "display.atomic-configuration",
      summary: "Synthetic display change",
      preview: .init(
        previousValue:
          "🖥 A1B2C3D4 • 1920×1080 (1920×1080 px) @ 60.0 Hz • x:0 y:0 → 🖥 1234:5678",
        desiredValue:
          "🖥 1234:5678 • 2560×1440 (2560×1440 px) @ 60.0 Hz • x:0 y:0"
      )
    )

    let preview = ProfilePresentationBuilder().operationPreview(for: operation)

    #expect(preview?.previousValue.primaryText.contains("A1B2C3D4") == false)
    #expect(preview?.previousValue.primaryText.contains("1234:5678") == false)
    #expect(preview?.previousValue.primaryText.contains("External display") == true)
    #expect(preview?.previousValue.primaryText.contains("Another display") == true)
    #expect(
      preview?.previousValue.technicalDetails == [
        .init(label: "Display 1 identifier", value: "A1B2C3D4"),
        .init(label: "Display 1 mirror identifier", value: "1234:5678"),
      ]
    )
    #expect(preview?.desiredValue.primaryText.contains("1234:5678") == false)
    #expect(
      preview?.desiredValue.technicalDetails == [
        .init(label: "Display 1 identifier", value: "1234:5678")
      ]
    )
  }

  @Test("operation without a preview remains absent")
  func operationWithoutPreview() {
    let operation = PlannedOperation(
      group: .input,
      key: "synthetic.input",
      summary: "Synthetic input change"
    )

    #expect(ProfilePresentationBuilder().operationPreview(for: operation) == nil)
  }

  @Test("ready profile exposes the primary apply action")
  func readyMenuAction() {
    let state = menuState(readiness: .ready, normalApplyAvailable: true)

    #expect(state.apply == .init(isEnabled: true))
    #expect(state.review.isEnabled)
    #expect(state.forceApply.disabledReason == .forceApplyNotNeeded)
  }

  @Test("partial profile explains unavailable normal apply and permits available items")
  func partialMenuAction() {
    let state = menuState(readiness: .partial, forceApplyAvailable: true)

    #expect(state.apply.disabledReason == .unavailableSettings)
    #expect(state.forceApply.isEnabled)
  }

  @Test("menu action reasons ignore legacy activation while preserving other lock states")
  func menuDisabledReasons() {
    let unavailable = menuState(readiness: .unavailable)
    let applying = menuState(readiness: .applying, isTransactionLocked: true)
    let noOp = menuState(
      readiness: .ready,
      rejectionReasons: [.noOperations]
    )
    let disabled = MenuProfileActionState(
      profile: profileWithSetting(isEnabled: false),
      readiness: .ready,
      normalApplyAvailable: true,
      forceApplyAvailable: false
    )
    let locked = menuState(readiness: .ready, isTransactionLocked: true)

    #expect(unavailable.apply.disabledReason == .noAvailableOperations)
    #expect(applying.apply.disabledReason == .applying)
    #expect(applying.review.disabledReason == .applying)
    #expect(noOp.apply.disabledReason == .noChanges)
    #expect(disabled.apply.isEnabled)
    #expect(disabled.review.isEnabled)
    #expect(locked.apply.disabledReason == .transactionInProgress)
    #expect(locked.review.disabledReason == .transactionInProgress)
  }

  @Test("condition and protected-change rejections have specific explanations")
  func explicitRejectionReasons() {
    let condition = menuState(
      readiness: .partial,
      rejectionReasons: [.conditionsUnsatisfied]
    )
    let displayConfirmation = menuState(
      readiness: .ready,
      rejectionReasons: [.safetyConfirmationCapacityReached]
    )
    let refreshing = menuState(readiness: .ready, isRefreshing: true)

    #expect(condition.apply.disabledReason == .conditionsUnsatisfied)
    #expect(displayConfirmation.apply.disabledReason == .pendingSafetyConfirmation)
    #expect(refreshing.apply.disabledReason == .readinessRefreshing)
    #expect(refreshing.review.disabledReason == .readinessRefreshing)
  }

  @Test("normal and available-items actions can explain different blockers")
  func separateNormalAndForceRejectionReasons() {
    let state = MenuProfileActionState(
      profile: profileWithSetting(),
      readiness: .partial,
      normalApplyAvailable: false,
      forceApplyAvailable: false,
      rejectionReasons: [.unavailableItems],
      forceRejectionReasons: [.conditionsUnsatisfied]
    )

    #expect(state.apply.disabledReason == .unavailableSettings)
    #expect(state.forceApply.disabledReason == .conditionsUnsatisfied)
  }

  @Test("presentation values and states satisfy Sendable contracts")
  func sendableContracts() {
    requireSendable(FriendlyDisplayValue(primaryText: "Synthetic"))
    requireSendable(ProfilePresentationBuilder())
    requireSendable(menuState(readiness: .ready))
  }

  @Test("same-name choices receive stable non-sensitive ordinals")
  func friendlyNameDisambiguation() {
    let labels = FriendlyNameDisambiguator().labels(
      for: [
        (id: "first", name: "Synthetic Display"),
        (id: "unique", name: "Built-in Display"),
        (id: "second", name: "Synthetic Display"),
      ]
    )

    #expect(labels["first"] == "Synthetic Display 1")
    #expect(labels["second"] == "Synthetic Display 2")
    #expect(labels["unique"] == "Built-in Display")
    #expect(!labels.values.contains { $0.contains("uid") })
  }

  private func menuState(
    readiness: ProfileReadiness,
    normalApplyAvailable: Bool = false,
    forceApplyAvailable: Bool = false,
    isRefreshing: Bool = false,
    isTransactionLocked: Bool = false,
    rejectionReasons: [ApplyRejectionReason] = []
  ) -> MenuProfileActionState {
    MenuProfileActionState(
      profile: profileWithSetting(),
      readiness: readiness,
      normalApplyAvailable: normalApplyAvailable,
      forceApplyAvailable: forceApplyAvailable,
      isRefreshing: isRefreshing,
      isTransactionLocked: isTransactionLocked,
      rejectionReasons: rejectionReasons
    )
  }

  private func profileWithSetting(isEnabled: Bool = true) -> DeskProfile {
    DeskProfile(
      name: "Synthetic desk",
      isEnabled: isEnabled,
      settings: ProfileSettings(
        audio: .init(
          value: .init(outputVolume: .init(value: 0.5))
        )
      )
    )
  }

  private func displayTarget(
    name: String,
    isPrimary: Bool = true
  ) -> DisplayTargetSettings {
    displayTarget(
      identity: .init(productName: name),
      isPrimary: isPrimary
    )
  }

  private func displayTarget(
    identity: DisplayIdentity,
    isPrimary: Bool = true
  ) -> DisplayTargetSettings {
    DisplayTargetSettings(
      identity: identity,
      isPrimary: .init(value: isPrimary),
      origin: .init(isIncluded: false, value: .init(x: 0, y: 0)),
      mirroring: .init(isIncluded: false, value: .extended),
      mode: .init(value: .init(width: 2560, height: 1440, refreshRate: 60)),
      rotationDegrees: .init(isIncluded: false, value: 0),
      isActive: .init(isIncluded: false, value: true)
    )
  }

  private func requireSendable<Value: Sendable>(_ value: Value) {
    _ = value
  }
}
