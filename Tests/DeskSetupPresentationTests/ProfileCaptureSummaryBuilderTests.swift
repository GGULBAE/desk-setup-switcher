import DeskSetupCore
import DeskSetupPresentation
import Foundation
import Testing

@Suite("Profile capture summary builder")
struct ProfileCaptureSummaryBuilderTests {
  @Test("hidden Wi-Fi permission evidence does not degrade visible capture")
  func hiddenPermissionEvidenceIsDormant() {
    let display = DisplayTargetSettings(
      identity: DisplayIdentity(isBuiltIn: true),
      isPrimary: .init(value: true),
      origin: .init(value: DisplayPoint(x: 0, y: 0)),
      mirroring: .init(value: .extended),
      mode: .init(value: DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)),
      colorProfile: .init(
        value: .init(
          registeredProfileID: "synthetic-legacy",
          fileSHA256: String(repeating: "a", count: 64),
          displayName: "Synthetic Legacy ICC"
        )),
      rotationDegrees: .init(isIncluded: false, value: 90),
      isActive: .init(isIncluded: false, value: true)
    )
    let settings = ProfileSettings(
      display: .init(value: .init(displays: [display])),
      network: .init(
        value: .init(
          wifiPower: .init(value: true),
          wifiSSID: .init(isIncluded: false, value: nil),
          dnsServers: .init(isIncluded: false, value: ["192.0.2.53"])
        )
      )
    )
    let evidence = [
      CaptureSnapshotEvidence(
        group: .network,
        key: "wifi.ssid",
        state: .permissionRequired
      )
    ]

    let summary = ProfileCaptureSummaryBuilder().summary(
      settings: settings,
      evidence: evidence
    )

    #expect(summary.status == .complete)
    #expect(!summary.items.contains { $0.group == .network })
    #expect(summary.applicableCount == 2)
    #expect(!summary.items.contains { $0.key.contains("colorProfile") })
    #expect(summary.excludedCount == 0)
    #expect(summary.unreadableCount == 0)
    #expect(summary.permissionRequiredCount == 0)
    #expect(summary.unsupportedCount == 0)
    #expect(!summary.wifiNetworkWasNotCaptured)
  }

  @Test("snapshot-only values are omitted from the user-facing capture result")
  func snapshotOnlyCaptureIsUnusable() {
    let settings = ProfileSettings(
      network: .init(
        isIncluded: false,
        value: .init(dnsServers: .init(isIncluded: false, value: ["198.51.100.53"]))
      )
    )

    let summary = ProfileCaptureSummaryBuilder().summary(
      settings: settings,
      evidence: []
    )

    #expect(summary.status == .failure)
    #expect(summary.items.isEmpty)
    #expect(summary.excludedCount == 0)
    #expect(!summary.canCreateProfile)
  }

  @Test("readable output mute can be captured as an applicable setting", arguments: [true, false])
  func capturedOutputMuteIsApplicable(value: Bool) {
    let settings = ProfileSettings(
      audio: .init(
        value: .init(outputMuted: .init(value: value))
      )
    )

    let summary = ProfileCaptureSummaryBuilder().summary(
      settings: settings,
      evidence: []
    )

    #expect(summary.status == .complete)
    #expect(summary.items.map(\.key) == ["outputMute"])
    #expect(summary.applicableCount == 1)
    #expect(summary.canCreateProfile)
  }

  @Test("keyboard capture reports exactly the three supported settings")
  func keyboardCaptureIsApplicable() {
    let settings = ProfileSettings(
      input: .init(
        value: .init(
          pointerSpeed: .init(value: 4.5),
          naturalScrolling: .init(value: true),
          keyRepeatInterval: .init(value: 30),
          initialKeyRepeatDelay: .init(value: 90),
          keyboardBrightness: .init(value: 0.7),
          useStandardFunctionKeys: .init(value: false)
        )
      )
    )

    let summary = ProfileCaptureSummaryBuilder().summary(
      settings: settings,
      evidence: []
    )

    #expect(summary.status == .complete)
    #expect(summary.applicableCount == 3)
    #expect(summary.canCreateProfile)
    #expect(
      summary.items == [
        .init(group: .input, key: "KeyRepeat", disposition: .savedApplicable),
        .init(group: .input, key: "InitialKeyRepeat", disposition: .savedApplicable),
        .init(group: .input, key: "KeyboardBrightness", disposition: .savedApplicable),
      ]
    )
  }

  @Test("unavailable visible keyboard controls make capture explicitly partial")
  func keyboardCaptureOmissionsRemainVisible() {
    let settings = ProfileSettings(
      input: .init(value: .init(keyRepeatInterval: .init(value: 30)))
    )
    let summary = ProfileCaptureSummaryBuilder().summary(
      settings: settings,
      evidence: [
        .init(group: .input, key: "InitialKeyRepeat", state: .unreadable),
        .init(group: .input, key: "KeyboardBrightness", state: .permissionRequired),
        .init(group: .input, key: "retired-input-key", state: .unsupported),
      ]
    )

    #expect(summary.status == .partial)
    #expect(summary.applicableCount == 1)
    #expect(summary.unreadableCount == 1)
    #expect(summary.permissionRequiredCount == 1)
    #expect(summary.unsupportedCount == 0)
    #expect(
      summary.permissionRequirements == [.inputMonitoringForKeyboardBrightness]
    )
    #expect(
      summary.items.contains {
        $0.group == .input
          && $0.key == "KeyboardBrightness"
          && $0.disposition == .permissionRequired
      }
    )
  }

  @Test("unreadable and unsupported evidence is omitted from the user-facing result")
  func nonActionableEvidenceIsOmitted() {
    let duplicate = CaptureSnapshotEvidence(
      group: .display,
      key: "snapshot",
      state: .unreadable
    )

    let summary = ProfileCaptureSummaryBuilder().summary(
      settings: ProfileSettings(),
      evidence: [
        duplicate,
        duplicate,
        .init(group: .network, key: "network.serviceOrder", state: .unsupported),
      ]
    )

    #expect(summary.status == .failure)
    #expect(summary.items.isEmpty)
    #expect(summary.unreadableCount == 0)
    #expect(summary.savedCount == 0)
    #expect(summary.permissionRequiredCount == 0)
    #expect(summary.unsupportedCount == 0)
  }

  @Test("ignored device evidence keeps no runtime identifier")
  func incompleteDeviceEvidenceIsSanitized() {
    let runtimeID = "6A1C2DD1-5FB0-4D83-A4FA-2FA127EDC978"
    let summary = ProfileCaptureSummaryBuilder().summary(
      settings: ProfileSettings(),
      evidence: [
        .init(
          group: .display,
          key: "display.\(runtimeID)",
          state: .unreadable
        )
      ]
    )

    #expect(summary.items.isEmpty)
    #expect(!summary.items.contains { $0.key.contains(runtimeID) })
  }
}
