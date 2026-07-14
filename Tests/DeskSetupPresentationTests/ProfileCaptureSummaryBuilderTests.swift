import DeskSetupCore
import DeskSetupPresentation
import Foundation
import Testing

@Suite("Profile capture summary builder")
struct ProfileCaptureSummaryBuilderTests {
  @Test("permission-hidden Wi-Fi and snapshot-only values create a sanitized partial result")
  func partialCaptureClassification() {
    let display = DisplayTargetSettings(
      identity: DisplayIdentity(isBuiltIn: true),
      isPrimary: .init(value: true),
      origin: .init(value: DisplayPoint(x: 0, y: 0)),
      mirroring: .init(value: .extended),
      mode: .init(value: DisplayMode(width: 1_920, height: 1_080, refreshRate: 60)),
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

    #expect(summary.status == .partial)
    #expect(
      summary.items.contains(
        .init(group: .network, key: "wifi.ssid", disposition: .permissionRequired)
      )
    )
    #expect(summary.applicableCount == 5)
    #expect(summary.excludedCount == 3)
    #expect(summary.permissionRequiredCount == 1)
    #expect(summary.wifiNetworkWasNotCaptured)
  }

  @Test("snapshot-only values alone cannot create a profile")
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
    #expect(summary.excludedCount == 1)
    #expect(!summary.canCreateProfile)
  }

  @Test("duplicate snapshot failure evidence is counted once")
  func duplicateSnapshotFailureEvidenceIsDeduplicated() {
    let duplicate = CaptureSnapshotEvidence(
      group: .display,
      key: "snapshot",
      state: .unreadable
    )

    let summary = ProfileCaptureSummaryBuilder().summary(
      settings: ProfileSettings(),
      evidence: [duplicate, duplicate]
    )

    #expect(summary.status == .failure)
    #expect(summary.unreadableCount == 1)
    #expect(
      summary.items.filter { $0.disposition == .unreadable }
        == [.init(group: .display, key: "snapshot", disposition: .unreadable)]
    )
    #expect(summary.savedCount == 0)
    #expect(summary.permissionRequiredCount == 0)
    #expect(summary.unsupportedCount == 0)
  }

  @Test("incomplete device evidence keeps no runtime identifier")
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

    #expect(
      summary.items == [
        .init(group: .display, key: "display.settings", disposition: .unreadable)
      ]
    )
    #expect(!summary.items.contains { $0.key.contains(runtimeID) })
  }
}
