import AppKit
import SwiftUI
import Testing

@testable import DeskSetupCore
@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("Launch gallery synthetic evidence", .serialized)
  @MainActor
  struct LaunchGalleryEvidenceTests {
    private let viewport = CGSize(width: 620, height: 440)

    @Test("launch review uses current scope and remains side-effect free")
    func rendersCurrentScopeReview() throws {
      let configuration = UIAuditConfiguration(
        isEnabled: true,
        variant: .editorAudio,
        displayMode: .standard,
        showsStatusPopover: false
      )
      let model = UIAuditFixtures.makeModel(configuration: configuration)
      var profile = try #require(model.profiles.first)
      profile.name = "Studio Desk"

      let operations = [
        PlannedOperation(
          group: .audio,
          key: "outputMute",
          summary: "Change output mute",
          risk: .low,
          preview: OperationPreview(previousValue: "Off", desiredValue: "On")
        ),
        PlannedOperation(
          group: .audio,
          key: "outputVolume",
          summary: "Change output volume",
          risk: .low,
          preview: OperationPreview(previousValue: "42%", desiredValue: "68%")
        ),
      ]
      let preparation = ApplyPreparation(
        profileID: profile.id,
        mode: .normal,
        preparedAt: Date(timeIntervalSince1970: 1_700_000_000),
        includedGroups: [.audio],
        capabilities: [],
        snapshots: [],
        validationIssues: [],
        operations: operations,
        omissions: [],
        readiness: ReadinessEvaluation(
          status: .ready,
          applicableGroups: [.audio],
          unavailableGroups: [],
          reasons: []
        ),
        rejectionReasons: []
      )
      let request = PendingApplyRequest(
        profile: profile,
        preparation: preparation,
        reviewReason: .initial
      )

      setenv("DESK_SETUP_UI_AUDIT_LANGUAGE", "en", 1)
      defer { unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE") }

      let root = ApplyPreviewView(
        request: request,
        onConfirm: {
          Issue.record("The launch evidence renderer must never invoke Apply.")
        }
      )
      .environmentObject(model)
      .environment(\.locale, Locale(identifier: "en"))
      .dynamicTypeSize(.large)
      .uiAuditEnvironment(configuration)
      .frame(width: viewport.width, height: viewport.height)
      .preferredColorScheme(.light)
      .background(Color.white)

      let rendered = try render(root)
      #expect(rendered.png.count > 10_000)
      #expect(!rendered.accessibility.contains("Display, Audio & Network"))
      #expect(!rendered.accessibility.contains("Display and network changes"))
      #expect(rendered.accessibility.contains("declared-profile=Studio Desk"))
      #expect(rendered.accessibility.contains("declared-change-count=2"))
      #expect(rendered.accessibility.contains("live-system-mutations=false"))

      guard
        ProcessInfo.processInfo.environment[
          "DESK_SETUP_WRITE_LAUNCH_GALLERY_EVIDENCE"
        ] == "1",
        let outputPath = ProcessInfo.processInfo.environment[
          "DESK_SETUP_LAUNCH_GALLERY_EVIDENCE_DIR"
        ]
      else { return }

      let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
      try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
      )
      try rendered.png.write(
        to: outputDirectory.appendingPathComponent("27-launch-review-en-light.png"),
        options: .atomic
      )
      try rendered.accessibility.write(
        to: outputDirectory.appendingPathComponent("27-launch-review-en-light.ax.txt"),
        atomically: true,
        encoding: .utf8
      )
    }

    private func render<Content: View>(
      _ content: Content
    ) throws -> (png: Data, accessibility: String) {
      let host = NSHostingView(rootView: content)
      host.frame = NSRect(origin: .zero, size: viewport)
      host.appearance = NSAppearance(named: .aqua)
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
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
      host.needsLayout = true
      host.needsDisplay = true
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()

      let source = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: source)
      let representation = try opaqueRepresentation(from: source, background: .white)
      #expect(!representation.hasAlpha)
      let png = try #require(
        representation.representation(using: .png, properties: [:])
      )

      var lines = [
        "source=ApplyPreviewView in attached offscreen NSWindow",
        "synthetic-launch-gallery=true",
        "fixture=27-launch-review-en-light",
        "language=en",
        "viewport=620x440",
        "declared-profile=Studio Desk",
        "declared-groups=audio",
        "declared-change-count=2",
        "confirmation-closure=records-test-failure-only",
        "live-system-mutations=false",
        "window-ordered-front=false",
        "offscreen-ax-limit=SwiftUI descendants may remain collapsed into AXGroup",
      ]
      var visited: Set<ObjectIdentifier> = []
      appendAccessibility(host, depth: 0, lines: &lines, visited: &visited)
      withExtendedLifetime(window) {}
      return (png, lines.joined(separator: "\n") + "\n")
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
            let offset = y * opaque.bytesPerRow + x * 3
            destination[offset] = byte(
              sourceColor.redComponent * alpha
                + backgroundRGB.redComponent * (1 - alpha)
            )
            destination[offset + 1] = byte(
              sourceColor.greenComponent * alpha
                + backgroundRGB.greenComponent * (1 - alpha)
            )
            destination[offset + 2] = byte(
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
        appendAccessibility(
          child as AnyObject,
          depth: depth + 1,
          lines: &lines,
          visited: &visited
        )
      }
    }
  }
#endif
