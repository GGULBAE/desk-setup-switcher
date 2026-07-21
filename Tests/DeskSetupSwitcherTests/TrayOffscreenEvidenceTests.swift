import AppKit
import SwiftUI
import Testing

@testable import DeskSetupCore
@testable import DeskSetupPresentation
@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("Attached offscreen UI evidence rendering", .serialized)
  @MainActor
  struct TrayOffscreenEvidenceTests {
    struct Fixture {
      let name: String
      let variant: UIAuditVariant
      let languageCode: String
      let colorScheme: ColorScheme
      let largeText: Bool
      let reduceTransparency: Bool
      let increasedContrast: Bool
    }

    struct TrayActionCopy {
      let captureLabel: String
      let captureHelp: String
      let settingsLabel: String
      let quitLabel: String
    }

    struct SettingsFixture {
      enum State: String {
        case standard
        case dirtyDraft = "dirty-draft"
        case storageError = "storage-error"
      }

      let name: String
      let variant: UIAuditVariant
      let languageCode: String
      let colorScheme: ColorScheme
      let displayMode: UIAuditDisplayMode
      let size: CGSize
      let state: State

      init(
        name: String,
        variant: UIAuditVariant,
        languageCode: String,
        colorScheme: ColorScheme,
        displayMode: UIAuditDisplayMode,
        size: CGSize,
        state: State = .standard
      ) {
        self.name = name
        self.variant = variant
        self.languageCode = languageCode
        self.colorScheme = colorScheme
        self.displayMode = displayMode
        self.size = size
        self.state = state
      }
    }

    struct SettingsRenderEvidence {
      let png: Data
      let accessibility: String
      let sidebarActionGeometry: SidebarActionGeometry?
      let footerDarkPixelCount: Int
      let storageErrorAccentPixelCount: Int
      let nearBlackSampleRatio: Double
      let brightSampleRatio: Double
    }

    struct SidebarActionGeometry {
      let logicalYFromTop: CGFloat
      let runs: [ClosedRange<CGFloat>]
    }

    struct ApplyPreviewFixture {
      let name: String
      let languageCode: String
      let reviewReason: ApplyPreviewReviewReason
      let mode: ApplyMode
      let size: CGSize
      let largeText: Bool
    }

    @Test("all tray states render offscreen with readable accessibility structure")
    func rendersSyntheticMatrix() throws {
      let allFixtures = [
        Fixture(
          name: "01-empty-en-light", variant: .trayEmpty, languageCode: "en", colorScheme: .light,
          largeText: false, reduceTransparency: false, increasedContrast: false),
        Fixture(
          name: "01b-empty-ko-light", variant: .trayEmpty, languageCode: "ko",
          colorScheme: .light, largeText: false, reduceTransparency: false,
          increasedContrast: false),
        Fixture(
          name: "01c-empty-ko-accessibility3", variant: .trayEmpty, languageCode: "ko",
          colorScheme: .light, largeText: true, reduceTransparency: false,
          increasedContrast: false),
        Fixture(
          name: "01d-empty-en-dark", variant: .trayEmpty, languageCode: "en",
          colorScheme: .dark, largeText: false, reduceTransparency: false,
          increasedContrast: false),
        Fixture(
          name: "02-single-en-light", variant: .traySingle, languageCode: "en", colorScheme: .light,
          largeText: false, reduceTransparency: false, increasedContrast: false),
        Fixture(
          name: "03-three-en-light", variant: .overview, languageCode: "en", colorScheme: .light,
          largeText: false, reduceTransparency: false, increasedContrast: false),
        Fixture(
          name: "04-overflow-en-light", variant: .trayOverflow, languageCode: "en",
          colorScheme: .light, largeText: false, reduceTransparency: false, increasedContrast: false
        ),
        Fixture(
          name: "05-delete-en-light", variant: .trayDelete, languageCode: "en", colorScheme: .light,
          largeText: false, reduceTransparency: false, increasedContrast: false),
        Fixture(
          name: "06-capture-permission-en-light", variant: .trayCapturePermission,
          languageCode: "en", colorScheme: .light, largeText: false, reduceTransparency: false,
          increasedContrast: false),
        Fixture(
          name: "07-capture-success-en-dark", variant: .trayCaptureSuccess, languageCode: "en",
          colorScheme: .dark, largeText: false, reduceTransparency: false, increasedContrast: false),
        Fixture(
          name: "08-capture-failure-en-light", variant: .trayCaptureFailure, languageCode: "en",
          colorScheme: .light, largeText: false, reduceTransparency: false, increasedContrast: true),
        Fixture(
          name: "09-apply-result-en-dark", variant: .trayApplyResult, languageCode: "en",
          colorScheme: .dark, largeText: false, reduceTransparency: true, increasedContrast: false),
        Fixture(
          name: "10-overflow-ko-light", variant: .trayOverflow, languageCode: "ko",
          colorScheme: .light, largeText: false, reduceTransparency: false, increasedContrast: false
        ),
        Fixture(
          name: "11-delete-ko-dark", variant: .trayDelete, languageCode: "ko", colorScheme: .dark,
          largeText: false, reduceTransparency: false, increasedContrast: false),
        Fixture(
          name: "12-overflow-ko-large-text", variant: .trayOverflow, languageCode: "ko",
          colorScheme: .light, largeText: true, reduceTransparency: true, increasedContrast: false),
      ]
      let selectedFixture = ProcessInfo.processInfo.environment[
        "DESK_SETUP_TRAY_EVIDENCE_FIXTURE"
      ]
      let fixtures =
        selectedFixture.map { selected in
          allFixtures.filter { $0.name == selected }
        } ?? allFixtures
      #expect(selectedFixture == nil || fixtures.count == 1)

      let outputDirectory = evidenceOutputDirectory
      if let outputDirectory {
        try FileManager.default.createDirectory(
          at: outputDirectory,
          withIntermediateDirectories: true
        )
      }

      for fixture in fixtures {
        let actionCopy = TrayActionCopy(
          captureLabel: appLocalizedRuntime(
            TrayAccessibilityCopy.captureLabel,
            languageCode: fixture.languageCode
          ),
          captureHelp: appLocalizedRuntime(
            TrayAccessibilityCopy.captureHelp,
            languageCode: fixture.languageCode
          ),
          settingsLabel: appLocalizedRuntime(
            TrayAccessibilityCopy.settingsLabel,
            languageCode: fixture.languageCode
          ),
          quitLabel: appLocalizedRuntime(
            TrayAccessibilityCopy.quitLabel,
            languageCode: fixture.languageCode
          )
        )
        setenv("DESK_SETUP_UI_AUDIT_LANGUAGE", fixture.languageCode, 1)
        defer { unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE") }
        let rendered = try render(fixture, actionCopy: actionCopy)

        #expect(rendered.png.count > 10_000)
        #expect(rendered.accessibility.contains("AX"))
        #expect(rendered.accessibility.contains("declared-icon-labels="))
        if fixture.variant == .trayEmpty {
          #expect(rendered.accessibility.contains("capture-affordance=empty-state-primary"))
          #expect(rendered.accessibility.contains("capture-visible-action-count=1"))
          #expect(rendered.accessibility.contains("capture-default-key=return"))
          #expect(
            rendered.accessibility.contains(
              "declared-primary-action=" + actionCopy.captureLabel
            )
          )
        } else {
          #expect(rendered.accessibility.contains("capture-affordance=compact-header"))
          #expect(rendered.accessibility.contains("capture-visible-action-count=1"))
          #expect(rendered.accessibility.contains("capture-default-key=none"))
          #expect(rendered.accessibility.contains("declared-primary-action=none"))
        }
        #expect(!rendered.accessibility.contains("/Users/"))
        #expect(!rendered.accessibility.localizedCaseInsensitiveContains("password"))

        if let outputDirectory {
          try rendered.png.write(
            to: outputDirectory.appendingPathComponent("\(fixture.name).png"),
            options: .atomic
          )
          try rendered.accessibility.write(
            to: outputDirectory.appendingPathComponent("\(fixture.name).ax.txt"),
            atomically: true,
            encoding: .utf8
          )
        }
        unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE")
      }
    }

    @Test("simplified profile sections render offscreen in English and Korean")
    func rendersSimplifiedProfileSections() throws {
      let allFixtures = [
        SettingsFixture(
          name: "13-display-en-light",
          variant: .editorDisplay,
          languageCode: "en",
          colorScheme: .light,
          displayMode: .standard,
          size: CGSize(width: 900, height: 568)
        ),
        SettingsFixture(
          name: "14-audio-ko-light",
          variant: .editorAudio,
          languageCode: "ko",
          colorScheme: .light,
          displayMode: .standard,
          size: CGSize(width: 900, height: 568)
        ),
        SettingsFixture(
          name: "15-network-en-dark",
          variant: .editorNetworkEthernetManual,
          languageCode: "en",
          colorScheme: .dark,
          displayMode: .standard,
          size: CGSize(width: 900, height: 568)
        ),
        SettingsFixture(
          name: "16-profile-ko-minimum",
          variant: .editorDisplay,
          languageCode: "ko",
          colorScheme: .light,
          displayMode: .minimum,
          size: CGSize(width: 680, height: 480)
        ),
        SettingsFixture(
          name: "16b-profile-ko-minimum-large-text",
          variant: .editorDisplay,
          languageCode: "ko",
          colorScheme: .light,
          displayMode: .largeText,
          size: CGSize(width: 680, height: 480)
        ),
        SettingsFixture(
          name: "16c-profile-dirty-export-ko-minimum-large-text",
          variant: .editorDisplay,
          languageCode: "ko",
          colorScheme: .light,
          displayMode: .largeText,
          size: CGSize(width: 680, height: 480),
          state: .dirtyDraft
        ),
        SettingsFixture(
          name: "16d-profile-storage-error-ko-minimum-large-text",
          variant: .editorDisplay,
          languageCode: "ko",
          colorScheme: .light,
          displayMode: .largeText,
          size: CGSize(width: 680, height: 480),
          state: .storageError
        ),
        SettingsFixture(
          name: "17-audio-en-large-text",
          variant: .editorAudio,
          languageCode: "en",
          colorScheme: .light,
          displayMode: .largeText,
          size: CGSize(width: 900, height: 568)
        ),
        SettingsFixture(
          name: "18-display-color-en-dark",
          variant: .editorDisplayColor,
          languageCode: "en",
          colorScheme: .dark,
          displayMode: .standard,
          size: CGSize(width: 900, height: 568)
        ),
        SettingsFixture(
          name: "19-audio-unsupported-en-light",
          variant: .editorAudioUnsupported,
          languageCode: "en",
          colorScheme: .light,
          displayMode: .standard,
          size: CGSize(width: 900, height: 568)
        ),
        SettingsFixture(
          name: "20-ethernet-dhcp-en-light",
          variant: .editorNetworkEthernetDHCP,
          languageCode: "en",
          colorScheme: .light,
          displayMode: .standard,
          size: CGSize(width: 900, height: 568)
        ),
        SettingsFixture(
          name: "21-wifi-dhcp-ko-light",
          variant: .editorNetworkWiFiDHCP,
          languageCode: "ko",
          colorScheme: .light,
          displayMode: .standard,
          size: CGSize(width: 900, height: 568)
        ),
        SettingsFixture(
          name: "22-wifi-manual-en-dark",
          variant: .editorNetworkWiFiManual,
          languageCode: "en",
          colorScheme: .dark,
          displayMode: .standard,
          size: CGSize(width: 900, height: 568)
        ),
      ]
      let selectedFixture = ProcessInfo.processInfo.environment[
        "DESK_SETUP_REFINEMENT_EVIDENCE_FIXTURE"
      ]
      let footerComparisonFixtureNames: Set<String> = [
        "16b-profile-ko-minimum-large-text",
        "16c-profile-dirty-export-ko-minimum-large-text",
      ]
      let selectedFixtureNames = selectedFixture.map { selected in
        footerComparisonFixtureNames.contains(selected)
          ? footerComparisonFixtureNames : Set([selected])
      }
      let fixtures =
        selectedFixtureNames.map { names in
          allFixtures.filter { names.contains($0.name) }
        } ?? allFixtures
      if let selectedFixtureNames {
        #expect(fixtures.count == selectedFixtureNames.count)
      }
      let outputDirectory = refinementEvidenceOutputDirectory
      if let outputDirectory {
        try FileManager.default.createDirectory(
          at: outputDirectory,
          withIntermediateDirectories: true
        )
      }

      var renderedEvidenceByFixtureName: [String: SettingsRenderEvidence] = [:]
      for fixture in fixtures {
        setenv("DESK_SETUP_UI_AUDIT_LANGUAGE", fixture.languageCode, 1)
        let rendered = try renderSettings(fixture)
        unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE")

        #expect(rendered.png.count > 10_000)
        #expect(rendered.accessibility.contains("synthetic-settings-host=true"))
        #expect(!rendered.accessibility.contains("/Users/"))
        #expect(!rendered.accessibility.localizedCaseInsensitiveContains("password"))
        if fixture.colorScheme == .light {
          #expect(rendered.nearBlackSampleRatio < 0.01)
          #expect(rendered.brightSampleRatio > 0.80)
        }
        if fixture.size == CGSize(width: 680, height: 480),
          fixture.displayMode == .largeText
        {
          if fixture.state != .storageError {
            let geometry = try #require(rendered.sidebarActionGeometry)
            #expect(geometry.runs.count == 2)
            #expect(geometry.runs[0].upperBound + 20 < geometry.runs[1].lowerBound)
            #expect(geometry.runs[0].upperBound - geometry.runs[0].lowerBound > 90)
            #expect(geometry.runs[1].upperBound - geometry.runs[1].lowerBound > 40)
          }
          #expect(rendered.accessibility.contains("dynamic-type=accessibility3"))
          #expect(rendered.accessibility.contains("inclusion-header-layout=stacked"))
          #expect(rendered.accessibility.contains("inclusion-state-cues=text,symbol,switch"))
          #expect(rendered.accessibility.contains("sidebar-primary-action="))
          #expect(rendered.accessibility.contains("sidebar-secondary-menu="))
        }
        switch fixture.state {
        case .standard:
          break
        case .dirtyDraft:
          let notice = appLocalizedRuntime(
            ProfileExportScopePolicy.unsavedDraftNotice,
            languageCode: fixture.languageCode
          )
          #expect(rendered.accessibility.contains("declared-dirty-export-notice=\(notice)"))
          #expect(rendered.accessibility.contains("export-source=persisted-document-only"))
        case .storageError:
          #expect(rendered.accessibility.contains("storage-error-card-visible=true"))
          #expect(rendered.accessibility.contains("storage-error-action-count=1"))
          #expect(rendered.accessibility.contains("profile-workspace-disabled=true"))
          #expect(rendered.accessibility.contains("storage-error-focus-target=heading"))
          #expect(
            rendered.accessibility.contains(
              "storage-error-action="
                + appLocalizedRuntime("Dismiss Error", languageCode: fixture.languageCode)
            )
          )
          #expect(rendered.storageErrorAccentPixelCount > 500)
        }
        if let outputDirectory {
          try rendered.png.write(
            to: outputDirectory.appendingPathComponent("\(fixture.name).png"),
            options: .atomic
          )
          try rendered.accessibility.write(
            to: outputDirectory.appendingPathComponent("\(fixture.name).ax.txt"),
            atomically: true,
            encoding: .utf8
          )
        }
        renderedEvidenceByFixtureName[fixture.name] = rendered
      }

      if let standard = renderedEvidenceByFixtureName[
        "16b-profile-ko-minimum-large-text"
      ],
        let dirty = renderedEvidenceByFixtureName[
          "16c-profile-dirty-export-ko-minimum-large-text"
        ]
      {
        let differenceCount = try pixelDifferenceCount(
          baseline: standard.png,
          comparison: dirty.png,
          viewport: CGSize(width: 680, height: 480),
          logicalRegion: CGRect(x: 20, y: 425, width: 640, height: 55),
          minimumChannelDelta: 0.08
        )
        // The footer notice is text-only at this viewport. Keep the threshold
        // above incidental antialiasing noise without assuming a large filled
        // surface changes between the standard and dirty-draft states.
        #expect(differenceCount > 750)
        #expect(standard.accessibility.contains("state=standard"))
        #expect(dirty.accessibility.contains("state=dirty-draft"))
        #expect(dirty.accessibility.contains("declared-dirty-export-notice="))
        #expect(!dirty.accessibility.contains("declared-dirty-export-notice=none"))

        if let outputDirectory {
          let comparisonNotes =
            [
              "source=paired opaque profile settings evidence",
              "baseline-fixture=16b-profile-ko-minimum-large-text",
              "comparison-fixture=16c-profile-dirty-export-ko-minimum-large-text",
              "viewport=680x480",
              "image-has-alpha=false",
              "logical-region-from-top=x20,y425,width640,height55",
              "minimum-channel-delta=0.08",
              "footer-pairwise-pixel-difference-count=\(differenceCount)",
              "comparison-state=dirty-draft",
              "declared-dirty-export-notice="
                + appLocalizedRuntime(
                  ProfileExportScopePolicy.unsavedDraftNotice,
                  languageCode: "ko"
                ),
            ].joined(separator: "\n") + "\n"
          try comparisonNotes.write(
            to: outputDirectory.appendingPathComponent(
              "16b-16c-profile-footer-comparison.ax.txt"
            ),
            atomically: true,
            encoding: .utf8
          )
        }
      }
    }

    @Test("apply previews render from the top at default and minimum large-text canvases")
    func rendersApplyPreviewStates() throws {
      let fixtures = [
        ApplyPreviewFixture(
          name: "23-apply-preview-en-initial",
          languageCode: "en",
          reviewReason: .initial,
          mode: .normal,
          size: CGSize(width: 620, height: 500),
          largeText: false
        ),
        ApplyPreviewFixture(
          name: "24-apply-preview-ko-refreshed",
          languageCode: "ko",
          reviewReason: .refreshedSystemState,
          mode: .normal,
          size: CGSize(width: 620, height: 500),
          largeText: false
        ),
        ApplyPreviewFixture(
          name: "25-apply-preview-ko-minimum-large-text",
          languageCode: "ko",
          reviewReason: .refreshedSystemState,
          mode: .force,
          size: CGSize(width: 520, height: 360),
          largeText: true
        ),
      ]
      let outputDirectory = workflowEvidenceOutputDirectory
      let bottomOutputDirectory = workflowBottomEvidenceOutputDirectory
      if let outputDirectory {
        try FileManager.default.createDirectory(
          at: outputDirectory,
          withIntermediateDirectories: true
        )
      }
      if let bottomOutputDirectory {
        try FileManager.default.createDirectory(
          at: bottomOutputDirectory,
          withIntermediateDirectories: true
        )
      }

      for fixture in fixtures {
        setenv("DESK_SETUP_UI_AUDIT_LANGUAGE", fixture.languageCode, 1)
        let rendered = try renderApplyPreview(fixture)
        let withoutHardwareStatus =
          fixture.name == "23-apply-preview-en-initial"
          ? try renderApplyPreview(fixture, showsHardwareVerificationStatus: false)
          : nil
        let bottomRendered =
          fixture.largeText
          ? try renderApplyPreview(fixture, initialScrollAnchor: .bottom)
          : nil
        unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE")

        #expect(rendered.png.count > 10_000)
        if let withoutHardwareStatus {
          #expect(rendered.png != withoutHardwareStatus.png)
        }
        if let bottomRendered {
          #expect(bottomRendered.png.count > 10_000)
          #expect(rendered.png != bottomRendered.png)
          #expect(bottomRendered.accessibility.contains("initial-scroll-anchor=bottom"))
          let bottomRepresentation = try #require(
            NSBitmapImageRep(data: bottomRendered.png)
          )
          let cancelActionInkCount = pixelCount(
            in: bottomRepresentation,
            viewport: fixture.size,
            logicalRegion: CGRect(
              x: 15,
              y: fixture.size.height - 95,
              width: 130,
              height: 75
            )
          ) { perceivedBrightness($0) < 0.75 }
          let applyActionInkCount = pixelCount(
            in: bottomRepresentation,
            viewport: fixture.size,
            logicalRegion: CGRect(
              x: fixture.size.width - 190,
              y: fixture.size.height - 65,
              width: 175,
              height: 50
            )
          ) { perceivedBrightness($0) < 0.75 }
          #expect(cancelActionInkCount > 50)
          #expect(applyActionInkCount > 200)
          if let bottomOutputDirectory {
            try bottomRendered.png.write(
              to: bottomOutputDirectory.appendingPathComponent(
                "\(fixture.name)-bottom.png"
              ),
              options: .atomic
            )
            try bottomRendered.accessibility.write(
              to: bottomOutputDirectory.appendingPathComponent(
                "\(fixture.name)-bottom.ax.txt"
              ),
              atomically: true,
              encoding: .utf8
            )
          }
        }
        #expect(rendered.accessibility.contains("synthetic-apply-preview=true"))
        #expect(
          rendered.accessibility.contains(
            "declared-beta-hardware-verification-status="
              + ApplyPreviewActionCopy.hardwareVerificationNotice(
                languageCode: fixture.languageCode
              )
          )
        )
        #expect(
          rendered.accessibility.contains(
            "declared-beta-hardware-verification-accessibility-label="
              + ApplyPreviewActionCopy.hardwareVerificationAccessibilityLabel(
                languageCode: fixture.languageCode
              )
          )
        )
        #expect(
          rendered.accessibility.contains(
            "declared-beta-hardware-verification-cues=text,exclamationmark.shield"
          )
        )
        #expect(rendered.accessibility.contains("hardware-verification-status-visible=true"))
        #expect(!rendered.accessibility.contains("/Users/"))
        #expect(!rendered.accessibility.localizedCaseInsensitiveContains("password"))
        if let outputDirectory {
          try rendered.png.write(
            to: outputDirectory.appendingPathComponent("\(fixture.name).png"),
            options: .atomic
          )
          try rendered.accessibility.write(
            to: outputDirectory.appendingPathComponent("\(fixture.name).ax.txt"),
            atomically: true,
            encoding: .utf8
          )
        }
      }
    }

    @Test("filtered asymmetric safe area matches zero-inset empty rendering")
    func emptyContentIgnoresAsymmetricNativeSafeArea() throws {
      let configuration = UIAuditConfiguration(
        isEnabled: true,
        variant: .trayEmpty,
        displayMode: .standard,
        showsStatusPopover: false
      )
      let model = UIAuditFixtures.makeModel(configuration: configuration)
      let permission = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .denied
      )
      let editor = ProfileEditorModel()
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: permission,
        profileEditor: editor
      )
      let router = TrayActionRouter(
        executor: presentation,
        destinationPresenter: OffscreenDestinationPresenter(),
        terminateApplication: {}
      )
      let viewport = CGSize(width: TrayGeometry.width, height: TrayGeometry.compactHeight)
      presentation.trayDidOpen(sessionGeneration: 1, viewport: viewport)
      presentation.trayContentDidAttach(sessionGeneration: 1)
      let root = TrayRootView(presentation: presentation, router: router)
        .environmentObject(model)
        .environmentObject(permission)
        .environmentObject(editor)
        .frame(width: viewport.width, height: viewport.height)
        .background(Color.white)
      let baseline = try renderTraySafeAreaFixture(
        root: root,
        viewport: viewport,
        nativeSafeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
      )
      let asymmetric = try renderTraySafeAreaFixture(
        root: root,
        viewport: viewport,
        nativeSafeAreaInsets: NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 0)
      )
      let unfilteredControl = try renderTraySafeAreaFixture(
        root: root,
        viewport: viewport,
        nativeSafeAreaInsets: NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 0),
        filtersHorizontalSafeArea: false
      )

      #expect(asymmetric.hostingSafeAreaInsets.top == 0)
      #expect(asymmetric.hostingSafeAreaInsets.left == 0)
      #expect(asymmetric.hostingSafeAreaInsets.bottom == 0)
      #expect(asymmetric.hostingSafeAreaInsets.right == 0)

      let baselineInkCenter = try #require(
        horizontalEmptyStateInkCenter(in: baseline.representation)
      )
      let asymmetricInkCenter = try #require(
        horizontalEmptyStateInkCenter(in: asymmetric.representation)
      )
      let unfilteredInkCenter = try #require(
        horizontalEmptyStateInkCenter(in: unfilteredControl.representation)
      )
      #expect(abs(asymmetricInkCenter - baselineInkCenter) <= 4)
      #expect(abs(unfilteredInkCenter - baselineInkCenter) > 4)
    }

    private func renderTraySafeAreaFixture<Content: View>(
      root: Content,
      viewport: CGSize,
      nativeSafeAreaInsets: NSEdgeInsets,
      filtersHorizontalSafeArea: Bool = true
    ) throws -> (representation: NSBitmapImageRep, hostingSafeAreaInsets: NSEdgeInsets) {
      let hostingController = NSHostingController(rootView: root)
      hostingController.sizingOptions = []
      let contentController: NSViewController =
        filtersHorizontalSafeArea
        ? TrayPopoverContentController(hostedController: hostingController)
        : hostingController
      let host = hostingController.view
      host.frame = NSRect(origin: .zero, size: viewport)
      // The ink classifier assumes the fixture's white background. Do not let
      // the system's automatic dark appearance render white foreground on it.
      host.appearance = NSAppearance(named: .aqua)
      let boundaryView = contentController.view
      boundaryView.frame = NSRect(origin: .zero, size: viewport)
      let nativeContainer = AsymmetricSafeAreaContainerView(
        frame: NSRect(origin: .zero, size: viewport),
        injectedSafeAreaInsets: nativeSafeAreaInsets
      )
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: viewport),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )
      window.contentView = nativeContainer
      boundaryView.autoresizingMask = [.width, .height]
      nativeContainer.addSubview(boundaryView)
      nativeContainer.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
      nativeContainer.layoutSubtreeIfNeeded()
      host.needsLayout = true
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()

      let hostingSafeAreaInsets = host.safeAreaInsets
      let representation = try #require(
        host.bitmapImageRepForCachingDisplay(in: host.bounds)
      )
      host.cacheDisplay(in: host.bounds, to: representation)
      withExtendedLifetime((window, contentController, hostingController)) {}
      return (representation, hostingSafeAreaInsets)
    }

    private var evidenceOutputDirectory: URL? {
      guard ProcessInfo.processInfo.environment["DESK_SETUP_WRITE_TRAY_EVIDENCE"] == "1",
        let path = ProcessInfo.processInfo.environment["DESK_SETUP_TRAY_EVIDENCE_DIR"]
      else { return nil }
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    private var refinementEvidenceOutputDirectory: URL? {
      guard ProcessInfo.processInfo.environment["DESK_SETUP_WRITE_REFINEMENT_EVIDENCE"] == "1",
        let path = ProcessInfo.processInfo.environment["DESK_SETUP_REFINEMENT_EVIDENCE_DIR"]
      else { return nil }
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    private var workflowEvidenceOutputDirectory: URL? {
      guard ProcessInfo.processInfo.environment["DESK_SETUP_WRITE_WORKFLOW_EVIDENCE"] == "1",
        let path = ProcessInfo.processInfo.environment["DESK_SETUP_WORKFLOW_EVIDENCE_DIR"]
      else { return nil }
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    private var workflowBottomEvidenceOutputDirectory: URL? {
      guard
        ProcessInfo.processInfo.environment[
          "DESK_SETUP_WRITE_WORKFLOW_BOTTOM_EVIDENCE"
        ] == "1",
        let path = ProcessInfo.processInfo.environment[
          "DESK_SETUP_WORKFLOW_BOTTOM_EVIDENCE_DIR"
        ]
      else { return nil }
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func renderApplyPreview(
      _ fixture: ApplyPreviewFixture,
      showsHardwareVerificationStatus: Bool = true,
      initialScrollAnchor: UnitPoint = .top
    ) throws -> (png: Data, accessibility: String) {
      let configuration = UIAuditConfiguration(
        isEnabled: true,
        variant: .editorDisplay,
        displayMode: fixture.largeText ? .largeText : .standard,
        showsStatusPopover: false
      )
      let model = UIAuditFixtures.makeModel(configuration: configuration)
      let profile = try #require(model.profiles.first)
      let operations = [
        PlannedOperation(
          group: .audio,
          key: "inputVolume",
          summary: "Change input volume",
          risk: .low,
          preview: OperationPreview(previousValue: "50%", desiredValue: "5%")
        ),
        PlannedOperation(
          group: .audio,
          key: "outputVolume",
          summary: "Change output volume",
          risk: .low,
          preview: OperationPreview(previousValue: "68%", desiredValue: "4%")
        ),
        PlannedOperation(
          group: .display,
          key: "displayConfiguration",
          summary: "Apply the complete display configuration",
          risk: .high,
          preview: OperationPreview(
            previousValue: "Built-in Display · 1512×982 @ 120 Hz",
            desiredValue: "Built-in Display · 3024×1964 @ 48 Hz"
          )
        ),
      ]
      let preparation = ApplyPreparation(
        profileID: profile.id,
        mode: fixture.mode,
        preparedAt: Date(timeIntervalSince1970: 1_700_000_000),
        includedGroups: [.display, .audio],
        capabilities: [],
        snapshots: [],
        validationIssues: [],
        operations: operations,
        omissions: [],
        readiness: ReadinessEvaluation(
          status: .ready,
          applicableGroups: [.display, .audio],
          unavailableGroups: [],
          reasons: []
        ),
        rejectionReasons: []
      )
      let request = PendingApplyRequest(
        profile: profile,
        preparation: preparation,
        reviewReason: fixture.reviewReason
      )
      let size = fixture.size
      let root = ApplyPreviewView(
        request: request,
        showsHardwareVerificationStatus: showsHardwareVerificationStatus,
        initialScrollAnchor: initialScrollAnchor,
        onConfirm: {}
      )
      .environmentObject(model)
      .environment(\.locale, Locale(identifier: fixture.languageCode))
      .dynamicTypeSize(fixture.largeText ? .accessibility3 : .large)
      .uiAuditEnvironment(configuration)
      .frame(width: size.width, height: size.height)
      .background(Color.white)
      let host = NSHostingView(rootView: root)
      host.frame = NSRect(origin: .zero, size: size)
      host.appearance = NSAppearance(named: .aqua)
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )
      window.contentView = host
      window.setContentSize(size)
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
      host.needsLayout = true
      host.needsDisplay = true
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()

      let representation = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: representation)
      let png = try #require(representation.representation(using: .png, properties: [:]))
      let hardwareStatus = ApplyPreviewHardwareVerificationStatus.localized()
      var lines = [
        "source=ApplyPreviewView in attached offscreen NSWindow",
        "synthetic-apply-preview=true",
        "fixture=\(fixture.name)",
        "language=\(fixture.languageCode)",
        "viewport=\(Int(size.width))x\(Int(size.height))",
        "review-reason=\(String(describing: fixture.reviewReason))",
        "mode=\(String(describing: fixture.mode))",
        "large-text=\(fixture.largeText)",
        "initial-scroll-anchor=\(initialScrollAnchor == .bottom ? "bottom" : "top")",
        "live-display-audio-network-mutations=false",
        "declared-beta-hardware-verification-status=" + hardwareStatus.text,
        "declared-beta-hardware-verification-accessibility-label="
          + hardwareStatus.accessibilityLabel,
        "declared-beta-hardware-verification-cues=text,\(hardwareStatus.systemImage)",
        "hardware-verification-status-visible=\(showsHardwareVerificationStatus)",
        "offscreen-ax-limit=SwiftUI descendants may remain collapsed into AXGroup without ordering the window front",
      ]
      var visited: Set<ObjectIdentifier> = []
      appendAccessibility(host, depth: 0, lines: &lines, visited: &visited)
      return (png, lines.joined(separator: "\n") + "\n")
    }

    private func renderSettings(
      _ fixture: SettingsFixture
    ) throws -> SettingsRenderEvidence {
      let configuration = UIAuditConfiguration(
        isEnabled: true,
        variant: fixture.variant,
        displayMode: fixture.displayMode,
        showsStatusPopover: false
      )
      let model = UIAuditFixtures.makeModel(configuration: configuration)
      let locationPermission = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .denied
      )
      let editor = ProfileEditorModel()
      switch fixture.state {
      case .standard:
        break
      case .dirtyDraft:
        let selectedProfile = try #require(
          model.profiles.first(where: { $0.id == model.selectedProfileID })
            ?? model.profiles.first
        )
        editor.initialize(profiles: model.profiles, preferredProfileID: selectedProfile.id)
        #expect(
          editor.updateDraft {
            $0.name = "저장하지 않은 변경사항이 있는 프로필"
          }
        )
      case .storageError:
        model.configureProfileStorageFailureForUIAudit()
      }
      let size = fixture.size
      let navigation = SettingsNavigationModel(selectedTab: .profiles)
      navigation.beginPresentation()
      let root = ZStack {
        (fixture.colorScheme == .dark ? Color.black : Color.white)
          .ignoresSafeArea()
        RuntimeSettingsRoot(
          navigation: navigation,
          uiAuditConfiguration: configuration
        )
        .environmentObject(model)
        .environmentObject(locationPermission)
        .environmentObject(editor)
      }
      .environment(\.locale, Locale(identifier: fixture.languageCode))
      .uiAuditEnvironment(configuration)
      .preferredColorScheme(fixture.colorScheme)
      .frame(width: size.width, height: size.height)

      let host = NSHostingView(rootView: root)
      host.frame = NSRect(origin: .zero, size: size)
      host.autoresizingMask = [.width, .height]
      host.appearance = NSAppearance(
        named: fixture.colorScheme == .dark ? .darkAqua : .aqua
      )
      let opaqueBackground = fixture.colorScheme == .dark ? NSColor.black : NSColor.white
      let container = NSView(frame: NSRect(origin: .zero, size: size))
      container.wantsLayer = true
      container.layer?.backgroundColor = opaqueBackground.cgColor
      container.addSubview(host)
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )
      window.contentView = container
      window.setContentSize(size)
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      // Profile initialization and locale propagation publish once from
      // onAppear. Drain that offscreen-host update before caching pixels.
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
      host.needsLayout = true
      host.needsDisplay = true
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()

      let sourceRepresentation = try #require(
        container.bitmapImageRepForCachingDisplay(in: container.bounds)
      )
      container.cacheDisplay(in: container.bounds, to: sourceRepresentation)
      let representation = try opaqueRepresentation(
        from: sourceRepresentation,
        background: opaqueBackground
      )
      #expect(!representation.hasAlpha)
      let png = try #require(
        representation.representation(using: .png, properties: [:])
      )
      let evidenceRepresentation = try #require(NSBitmapImageRep(data: png))
      #expect(!evidenceRepresentation.hasAlpha)
      let imageStatistics = sampledImageStatistics(in: evidenceRepresentation)
      let sidebarActionGeometry = sidebarActionGeometry(
        in: evidenceRepresentation,
        viewport: size
      )
      // This cached representation indexes y from the rendered top. Inspect
      // only the bottom 100-point footer band; the top contains the synthetic
      // selected-tab shape and must never satisfy the dirty-notice check.
      let footerDarkPixelCount = pixelCount(
        in: evidenceRepresentation,
        viewport: size,
        logicalRegion: CGRect(x: 20, y: size.height - 100, width: 640, height: 100)
      ) { color in
        perceivedBrightness(color) < 0.63
      }
      let storageErrorAccentPixelCount = pixelCount(
        in: evidenceRepresentation,
        viewport: size,
        logicalRegion: CGRect(origin: .zero, size: size)
      ) { color in
        color.redComponent > 0.55
          && color.redComponent - color.greenComponent > 0.08
          && color.redComponent - color.blueComponent > 0.08
      }
      let inclusionLayout =
        fixture.displayMode == .largeText ? "stacked" : "inline"
      let sidebarRuns =
        sidebarActionGeometry?.runs.map {
          String(format: "%.1f...%.1f", $0.lowerBound, $0.upperBound)
        }.joined(separator: "|") ?? "unavailable"
      var lines = [
        "source=full RuntimeSettingsRoot in attached offscreen NSWindow with synthetic profile and snapshot",
        "synthetic-settings-host=true",
        "fixture=\(fixture.name)",
        "language=\(fixture.languageCode)",
        "viewport=\(Int(size.width))x\(Int(size.height))",
        "variant=\(fixture.variant.rawValue)",
        "display-mode=\(fixture.displayMode.rawValue)",
        "state=\(fixture.state.rawValue)",
        "image-format=png",
        "image-has-alpha=false",
        "near-black-sample-ratio=\(imageStatistics.nearBlackRatio)",
        "bright-sample-ratio=\(imageStatistics.brightRatio)",
        "dynamic-type=\(fixture.displayMode == .largeText ? "accessibility3" : "system")",
        "sidebar-primary-action=\(appLocalizedRuntime("New Profile"))",
        "sidebar-secondary-menu=\(appLocalizedRuntime("More Profile Actions"))",
        "sidebar-action-background-runs=\(sidebarRuns)",
        "inclusion-header-layout=\(inclusionLayout)",
        "inclusion-minimum-available-width=\(Int(ProfileSettingInclusionLayoutPolicy.minimumAvailableHeaderWidth))",
        "inclusion-expected-control-width-limit=\(Int(ProfileSettingInclusionLayoutPolicy.maximumExpectedControlWidth))",
        "inclusion-state-cues=text,symbol,switch",
        "declared-dirty-export-notice=\(fixture.state == .dirtyDraft ? appLocalizedRuntime(ProfileExportScopePolicy.unsavedDraftNotice) : "none")",
        "export-source=persisted-document-only",
        "storage-error-card-visible=\(fixture.state == .storageError)",
        "storage-error-action-count=\(fixture.state == .storageError ? 1 : 0)",
        "storage-error-action=\(fixture.state == .storageError ? appLocalizedRuntime("Dismiss Error") : "none")",
        "profile-workspace-disabled=\(fixture.state == .storageError)",
        "storage-error-focus-target=\(fixture.state == .storageError ? "heading" : "none")",
        "footer-dark-pixel-threshold=0.63",
        "footer-dark-pixel-count=\(footerDarkPixelCount)",
        "storage-error-accent-pixel-count=\(storageErrorAccentPixelCount)",
        "live-display-audio-network-mutations=false",
        "offscreen-ax-limit=virtual SwiftUI children require an onscreen accessibility host",
      ]
      var visited: Set<ObjectIdentifier> = []
      appendAccessibility(host, depth: 0, lines: &lines, visited: &visited)
      withExtendedLifetime((window, container, host)) {}
      return SettingsRenderEvidence(
        png: png,
        accessibility: lines.joined(separator: "\n") + "\n",
        sidebarActionGeometry: sidebarActionGeometry,
        footerDarkPixelCount: footerDarkPixelCount,
        storageErrorAccentPixelCount: storageErrorAccentPixelCount,
        nearBlackSampleRatio: imageStatistics.nearBlackRatio,
        brightSampleRatio: imageStatistics.brightRatio
      )
    }

    private func sampledImageStatistics(
      in representation: NSBitmapImageRep
    ) -> (nearBlackRatio: Double, brightRatio: Double) {
      var nearBlackCount = 0
      var brightCount = 0
      var sampleCount = 0
      for y in stride(from: 0, to: representation.pixelsHigh, by: 4) {
        for x in stride(from: 0, to: representation.pixelsWide, by: 4) {
          guard
            let color = representation.colorAt(x: x, y: y)?
              .usingColorSpace(.deviceRGB)
          else { continue }
          sampleCount += 1
          if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.06 {
            nearBlackCount += 1
          }
          if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.94 {
            brightCount += 1
          }
        }
      }
      guard sampleCount > 0 else { return (0, 0) }
      return (
        Double(nearBlackCount) / Double(sampleCount),
        Double(brightCount) / Double(sampleCount)
      )
    }

    private func opaqueRepresentation(
      from source: NSBitmapImageRep,
      background: NSColor
    ) throws -> NSBitmapImageRep {
      let width = source.pixelsWide
      let height = source.pixelsHigh
      let opaque = try #require(
        NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: width,
          pixelsHigh: height,
          bitsPerSample: 8,
          samplesPerPixel: 3,
          hasAlpha: false,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: width * 3,
          bitsPerPixel: 24
        )
      )
      let destination = try #require(opaque.bitmapData)
      let backgroundRGB = try #require(background.usingColorSpace(.deviceRGB))
      for y in 0..<height {
        autoreleasepool {
          for x in 0..<width {
            let sourceColor =
              source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .clear
            let alpha = sourceColor.alphaComponent
            let destinationOffset = y * opaque.bytesPerRow + x * 3
            destination[destinationOffset] = byte(
              sourceColor.redComponent * alpha
                + backgroundRGB.redComponent * (1 - alpha)
            )
            destination[destinationOffset + 1] = byte(
              sourceColor.greenComponent * alpha
                + backgroundRGB.greenComponent * (1 - alpha)
            )
            destination[destinationOffset + 2] = byte(
              sourceColor.blueComponent * alpha
                + backgroundRGB.blueComponent * (1 - alpha)
            )
          }
        }
      }
      opaque.size = source.size
      return opaque
    }

    private func byte(_ component: CGFloat) -> UInt8 {
      UInt8(max(0, min(255, Int((component * 255).rounded()))))
    }

    private func pixelDifferenceCount(
      baseline baselineData: Data,
      comparison comparisonData: Data,
      viewport: CGSize,
      logicalRegion: CGRect,
      minimumChannelDelta: CGFloat
    ) throws -> Int {
      let baseline = try #require(NSBitmapImageRep(data: baselineData))
      let comparison = try #require(NSBitmapImageRep(data: comparisonData))
      #expect(!baseline.hasAlpha)
      #expect(!comparison.hasAlpha)
      #expect(baseline.pixelsWide == comparison.pixelsWide)
      #expect(baseline.pixelsHigh == comparison.pixelsHigh)

      let scaleX = CGFloat(baseline.pixelsWide) / viewport.width
      let scaleY = CGFloat(baseline.pixelsHigh) / viewport.height
      let lowerX = max(0, Int((logicalRegion.minX * scaleX).rounded(.down)))
      let upperX = min(
        baseline.pixelsWide,
        Int((logicalRegion.maxX * scaleX).rounded(.up))
      )
      let lowerY = max(0, Int((logicalRegion.minY * scaleY).rounded(.down)))
      let upperY = min(
        baseline.pixelsHigh,
        Int((logicalRegion.maxY * scaleY).rounded(.up))
      )

      var differenceCount = 0
      for y in lowerY..<upperY {
        for x in lowerX..<upperX {
          guard
            let baselineColor = baseline.colorAt(x: x, y: y)?
              .usingColorSpace(.deviceRGB),
            let comparisonColor = comparison.colorAt(x: x, y: y)?
              .usingColorSpace(.deviceRGB)
          else { continue }
          let maximumChannelDelta = max(
            abs(baselineColor.redComponent - comparisonColor.redComponent),
            abs(baselineColor.greenComponent - comparisonColor.greenComponent),
            abs(baselineColor.blueComponent - comparisonColor.blueComponent)
          )
          if maximumChannelDelta > minimumChannelDelta {
            differenceCount += 1
          }
        }
      }
      return differenceCount
    }

    private func render(
      _ fixture: Fixture,
      actionCopy: TrayActionCopy
    ) throws -> (png: Data, accessibility: String) {
      let configuration = UIAuditConfiguration(
        isEnabled: true,
        variant: fixture.variant,
        displayMode: fixture.largeText ? .largeText : .standard,
        showsStatusPopover: false
      )
      let model = UIAuditFixtures.makeModel(configuration: configuration)
      if fixture.variant == .trayCaptureFailure {
        let state = UIAuditFixtures.fixture(.trayCaptureFailure)
        model.configureForUIAudit(
          UIAuditFixtureState(
            profiles: state.profiles,
            selectedProfileID: state.selectedProfileID,
            snapshot: state.snapshot,
            readinessByProfile: state.readinessByProfile,
            operationCountByProfile: state.operationCountByProfile,
            availableOperationCountByProfile: state.availableOperationCountByProfile,
            captureSummary: ProfileCaptureSummary(items: [
              .init(group: .display, key: "display", disposition: .unreadable)
            ]),
            applySummary: state.applySummary
          )
        )
      }
      let locationPermission = LocationPermissionController(
        allowsSystemRequests: false,
        syntheticAuthorizationStatus: .denied
      )
      let profileEditor = ProfileEditorModel()
      let presentation = TrayPresentationModel(
        model: model,
        locationPermission: locationPermission,
        profileEditor: profileEditor,
        initialDeletionProfileID: fixture.variant == .trayDelete
          ? UIAuditFixtures.readyProfileID
          : nil
      )
      switch fixture.variant {
      case .trayCaptureSuccess:
        presentation.configureForUIAudit(
          capturePhase: .success(
            appLocalized("Captured current settings without changing the Mac."))
        )
      case .trayCaptureFailure:
        presentation.configureForUIAudit(
          capturePhase: .failure(
            appLocalized("No settings could be added safely from this snapshot."))
        )
      default:
        break
      }

      let destinationPresenter = OffscreenDestinationPresenter()
      let router = TrayActionRouter(
        executor: presentation,
        destinationPresenter: destinationPresenter,
        terminateApplication: {}
      )
      let viewport = TrayGeometry().viewport(
        for: presentation.geometryContext,
        on: TrayScreenMetrics(
          visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
          backingScaleFactor: 2
        )
      )
      presentation.trayDidOpen(sessionGeneration: 1, viewport: viewport)
      presentation.trayContentDidAttach(sessionGeneration: 1)

      let root = TrayRootView(presentation: presentation, router: router)
        .environmentObject(model)
        .environmentObject(locationPermission)
        .environmentObject(profileEditor)
        .environment(\.locale, Locale(identifier: fixture.languageCode))
        .dynamicTypeSize(fixture.largeText ? .accessibility3 : .large)
        .preferredColorScheme(fixture.colorScheme)
        .frame(width: viewport.width, height: viewport.height)
        .background(fixture.colorScheme == .dark ? Color.black : Color.white)

      let host = NSHostingView(rootView: root)
      host.frame = NSRect(origin: .zero, size: viewport)
      let appearanceName: NSAppearance.Name =
        if fixture.increasedContrast {
          fixture.colorScheme == .dark
            ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
        } else {
          fixture.colorScheme == .dark ? .darkAqua : .aqua
        }
      host.appearance = NSAppearance(named: appearanceName)
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: viewport),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )
      window.contentView = host
      window.setContentSize(viewport)
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      // Allow localized text and SF Symbol providers to settle once, then
      // capture a stable frame from the same synthetic host.
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
      host.needsLayout = true
      host.needsDisplay = true
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()

      let representation = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: representation)
      let png = try #require(
        representation.representation(
          using: NSBitmapImageRep.FileType.png,
          properties: [:]
        )
      )
      let accessibility = accessibilitySnapshot(
        root: host,
        fixture: fixture,
        viewport: viewport,
        profileCount: model.profiles.count,
        actionCopy: actionCopy,
        captureAffordancePlacement: TrayCaptureAffordancePolicy.placement(
          profileCount: model.profiles.count,
          capturePhase: presentation.capturePhase,
          hasCaptureSummary: model.lastCaptureSummary != nil,
          hasApplySummary: model.lastApplySummary != nil,
          hasHandoffError: presentation.handoffError != nil
        )
      )
      return (png, accessibility)
    }

    private func accessibilitySnapshot(
      root: NSView,
      fixture: Fixture,
      viewport: CGSize,
      profileCount: Int,
      actionCopy: TrayActionCopy,
      captureAffordancePlacement: TrayCaptureAffordancePlacement
    ) -> String {
      let primaryAction =
        captureAffordancePlacement.showsEmptyStatePrimary ? actionCopy.captureLabel : "none"
      let iconLabels = [
        captureAffordancePlacement.showsCompactHeader ? actionCopy.captureLabel : nil,
        actionCopy.settingsLabel,
        actionCopy.quitLabel,
      ].compactMap { $0 }.joined(separator: " | ")
      var lines = [
        "source=TrayRootView in attached offscreen NSWindow read-only accessibility attributes",
        "fixture=\(fixture.name)",
        "language=\(fixture.languageCode)",
        "viewport=\(Int(viewport.width))x\(Int(viewport.height))",
        "profile-count=\(profileCount)",
        "requested-reduce-transparency=\(fixture.reduceTransparency)",
        "applied-reduce-transparency=false",
        "reduce-transparency-limit=SwiftUI exposes this environment value as read-only in an offscreen host",
        "applied-increased-contrast=\(fixture.increasedContrast)",
        "swiftui-full-surface-background-layers=\(TraySurfaceStylePolicy.swiftUIFullSurfaceBackgroundLayerCount)",
        "capture-affordance=\(captureAffordancePlacement.rawValue)",
        "capture-visible-action-count=\(captureAffordancePlacement.visibleActionCount)",
        "capture-default-key=\(captureAffordancePlacement.showsEmptyStatePrimary ? "return" : "none")",
        "declared-capture-label=\(actionCopy.captureLabel)",
        "declared-capture-help=\(actionCopy.captureHelp)",
        "declared-primary-action=\(primaryAction)",
        "declared-icon-labels=\(iconLabels)",
        "offscreen-ax-limit=virtual SwiftUI children may remain pending without ordering the window front",
      ]
      var visited: Set<ObjectIdentifier> = []
      appendAccessibility(root, depth: 0, lines: &lines, visited: &visited)
      return lines.joined(separator: "\n") + "\n"
    }

    private func appendAccessibility(
      _ object: AnyObject,
      depth: Int,
      lines: inout [String],
      visited: inout Set<ObjectIdentifier>
    ) {
      guard depth < 20 else { return }
      let identifier = ObjectIdentifier(object)
      guard visited.insert(identifier).inserted else { return }

      let role: String
      let label: String?
      let help: String?
      let children: [Any]
      if let view = object as? NSView {
        role = view.accessibilityRole()?.rawValue ?? "AXUnknown"
        label = view.accessibilityLabel()
        help = view.accessibilityHelp()
        children = view.accessibilityChildren() ?? view.subviews
      } else if let element = object as? NSAccessibilityElement {
        role = element.accessibilityRole()?.rawValue ?? "AXUnknown"
        label = element.accessibilityLabel()
        help = element.accessibilityHelp()
        children = element.accessibilityChildren() ?? []
      } else {
        return
      }

      let indentation = String(repeating: "  ", count: depth)
      let values = [
        "role=\(role)",
        label.map { "label=\($0)" },
        help.map { "help=\($0)" },
      ].compactMap { $0 }
      lines.append(indentation + values.joined(separator: " "))
      for child in children {
        appendAccessibility(child as AnyObject, depth: depth + 1, lines: &lines, visited: &visited)
      }
    }

    private func sidebarActionGeometry(
      in representation: NSBitmapImageRep,
      viewport: CGSize
    ) -> SidebarActionGeometry? {
      let scaleX = CGFloat(representation.pixelsWide) / viewport.width
      let scaleY = CGFloat(representation.pixelsHigh) / viewport.height
      guard scaleX > 0, scaleY > 0 else { return nil }

      var best: SidebarActionGeometry?
      var bestWidth: CGFloat = 0
      for logicalY in stride(from: CGFloat(20), through: viewport.height - 20, by: 1) {
        let pixelY = min(
          representation.pixelsHigh - 1,
          max(0, Int((logicalY * scaleY).rounded()))
        )
        var pixelRuns: [ClosedRange<Int>] = []
        var runStart: Int?
        let lowerX = max(0, Int((15 * scaleX).rounded()))
        let upperX = min(
          representation.pixelsWide,
          Int(((ProfileWorkspaceLayoutPolicy.sidebarWidth + 25) * scaleX).rounded())
        )

        for pixelX in lowerX..<upperX {
          let color = representation.colorAt(x: pixelX, y: pixelY)?
            .usingColorSpace(.deviceRGB)
          let isControlBackground = color.map { perceivedBrightness($0) < 0.94 } ?? false
          if isControlBackground, runStart == nil {
            runStart = pixelX
          } else if !isControlBackground, let start = runStart {
            if pixelX - start >= Int((40 * scaleX).rounded()) {
              pixelRuns.append(start...(pixelX - 1))
            }
            runStart = nil
          }
        }
        if let start = runStart, upperX - start >= Int((40 * scaleX).rounded()) {
          pixelRuns.append(start...(upperX - 1))
        }
        guard pixelRuns.count == 2 else { continue }

        let logicalRuns = pixelRuns.map {
          CGFloat($0.lowerBound) / scaleX...CGFloat($0.upperBound) / scaleX
        }
        let totalWidth = logicalRuns.reduce(CGFloat.zero) {
          $0 + $1.upperBound - $1.lowerBound
        }
        let gap = logicalRuns[1].lowerBound - logicalRuns[0].upperBound
        guard gap > 20, totalWidth > bestWidth else { continue }
        bestWidth = totalWidth
        best = SidebarActionGeometry(
          logicalYFromTop: logicalY,
          runs: logicalRuns
        )
      }
      return best
    }

    private func pixelCount(
      in representation: NSBitmapImageRep,
      viewport: CGSize,
      logicalRegion: CGRect,
      matching predicate: (NSColor) -> Bool
    ) -> Int {
      let scaleX = CGFloat(representation.pixelsWide) / viewport.width
      let scaleY = CGFloat(representation.pixelsHigh) / viewport.height
      let lowerX = max(0, Int((logicalRegion.minX * scaleX).rounded(.down)))
      let upperX = min(
        representation.pixelsWide,
        Int((logicalRegion.maxX * scaleX).rounded(.up))
      )
      let lowerY = max(0, Int((logicalRegion.minY * scaleY).rounded(.down)))
      let upperY = min(
        representation.pixelsHigh,
        Int((logicalRegion.maxY * scaleY).rounded(.up))
      )
      var count = 0
      for y in lowerY..<upperY {
        for x in lowerX..<upperX {
          guard
            let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
            predicate(color)
          else { continue }
          count += 1
        }
      }
      return count
    }

    private func perceivedBrightness(_ color: NSColor) -> CGFloat {
      0.2126 * color.redComponent
        + 0.7152 * color.greenComponent
        + 0.0722 * color.blueComponent
    }

    private func horizontalEmptyStateInkCenter(
      in representation: NSBitmapImageRep
    ) -> CGFloat? {
      let lowerY = Int(CGFloat(representation.pixelsHigh) * 0.10)
      let upperY = Int(CGFloat(representation.pixelsHigh) * 0.50)
      var minimumX = representation.pixelsWide
      var maximumX = -1
      for y in lowerY..<upperY {
        for x in 0..<representation.pixelsWide {
          guard
            let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
            color.alphaComponent > 0.5
          else { continue }
          let brightness =
            0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
          if brightness < 0.82 {
            minimumX = min(minimumX, x)
            maximumX = max(maximumX, x)
          }
        }
      }
      guard maximumX >= minimumX else { return nil }
      return CGFloat(minimumX + maximumX) / 2
    }
  }

  @MainActor
  private final class AsymmetricSafeAreaContainerView: NSView {
    private let injectedSafeAreaInsets: NSEdgeInsets

    init(frame: NSRect, injectedSafeAreaInsets: NSEdgeInsets) {
      self.injectedSafeAreaInsets = injectedSafeAreaInsets
      super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    override var safeAreaInsets: NSEdgeInsets {
      injectedSafeAreaInsets
    }
  }

  @MainActor
  private final class OffscreenDestinationPresenter: TrayDestinationPresenting {
    func present(_ destination: TrayDestination) async -> TrayDestinationPresentation {
      .failed("Synthetic offscreen host does not present windows.")
    }
  }
#endif
