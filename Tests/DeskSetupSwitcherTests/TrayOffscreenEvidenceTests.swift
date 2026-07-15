import AppKit
import SwiftUI
import Testing

@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("Detached tray evidence rendering", .serialized)
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

    @Test("all tray states render offscreen with readable accessibility structure")
    func rendersSyntheticMatrix() throws {
      let fixtures = [
        Fixture(
          name: "01-empty-en-light", variant: .trayEmpty, languageCode: "en", colorScheme: .light,
          largeText: false, reduceTransparency: false, increasedContrast: false),
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

      let outputDirectory = evidenceOutputDirectory
      if let outputDirectory {
        try FileManager.default.createDirectory(
          at: outputDirectory,
          withIntermediateDirectories: true
        )
      }

      for fixture in fixtures {
        setenv("DESK_SETUP_UI_AUDIT_LANGUAGE", fixture.languageCode, 1)
        defer { unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE") }
        let rendered = try render(fixture)

        #expect(rendered.png.count > 10_000)
        #expect(rendered.accessibility.contains("AX"))
        #expect(rendered.accessibility.contains("declared-icon-labels="))
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

    private var evidenceOutputDirectory: URL? {
      guard ProcessInfo.processInfo.environment["DESK_SETUP_WRITE_TRAY_EVIDENCE"] == "1",
        let path = ProcessInfo.processInfo.environment["DESK_SETUP_TRAY_EVIDENCE_DIR"]
      else { return nil }
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func render(_ fixture: Fixture) throws -> (png: Data, accessibility: String) {
      let configuration = UIAuditConfiguration(
        isEnabled: true,
        variant: fixture.variant,
        displayMode: fixture.largeText ? .largeText : .standard,
        showsStatusPopover: false
      )
      let model = UIAuditFixtures.makeModel(configuration: configuration)
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
        profileCount: model.profiles.count
      )
      return (png, accessibility)
    }

    private func accessibilitySnapshot(
      root: NSView,
      fixture: Fixture,
      viewport: CGSize,
      profileCount: Int
    ) -> String {
      var lines = [
        "source=detached NSHostingView read-only accessibility attributes",
        "fixture=\(fixture.name)",
        "language=\(fixture.languageCode)",
        "viewport=\(Int(viewport.width))x\(Int(viewport.height))",
        "profile-count=\(profileCount)",
        "requested-reduce-transparency=\(fixture.reduceTransparency)",
        "applied-reduce-transparency=false",
        "reduce-transparency-limit=SwiftUI exposes this environment value as read-only in a detached host",
        "applied-increased-contrast=\(fixture.increasedContrast)",
        "swiftui-full-surface-background-layers=\(TraySurfaceStylePolicy.swiftUIFullSurfaceBackgroundLayerCount)",
        "declared-icon-labels=Capture Current Settings | Settings | Quit Desk Setup Switcher",
        "detached-ax-limit=virtual SwiftUI children require an onscreen accessibility host and remain pending",
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
  }

  @MainActor
  private final class OffscreenDestinationPresenter: TrayDestinationPresenting {
    func present(_ destination: TrayDestination) async -> TrayDestinationPresentation {
      .failed("Synthetic offscreen host does not present windows.")
    }
  }
#endif
