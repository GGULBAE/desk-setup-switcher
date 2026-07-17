import AppKit
import SwiftUI
import Testing

@testable import DeskSetupSwitcher

#if DEBUG
  @Suite("Responsive workflow layout", .serialized)
  @MainActor
  struct WorkflowResponsiveLayoutTests {
    private enum FixtureState: String {
      case permissionDenied = "permission-denied"
      case dirtyApply = "dirty-apply"
    }

    private struct Fixture {
      let name: String
      let state: FixtureState
    }

    private struct RGBSample {
      let red: CGFloat
      let green: CGFloat
      let blue: CGFloat

      var minimumComponent: CGFloat {
        min(red, green, blue)
      }
    }

    private struct PixelStatistics {
      let brightSampleRatio: Double
      let darkSampleRatio: Double
      let backgroundSamples: [RGBSample]
    }

    @Test("accessibility text selects the stacked workflow action layout")
    func accessibilityTextSelectsStackedActions() {
      #expect(!WorkflowActionBarLayoutPolicy.requiresStackedLayout(for: .large))
      #expect(WorkflowActionBarLayoutPolicy.requiresStackedLayout(for: .accessibility1))
      #expect(WorkflowActionBarLayoutPolicy.requiresStackedLayout(for: .accessibility3))
      #expect(WorkflowActionBarLayoutPolicy.requiresStackedLayout(for: .accessibility5))
    }

    @Test("workflow action bars focus only an enabled safe cancellation action")
    func actionBarsFocusEnabledCancellationAction() {
      #expect(
        WorkflowKeyboardFocusPolicy.initialActionID(
          cancelActionID: "cancel",
          isCancelActionDisabled: false
        ) == "cancel"
      )
      #expect(
        WorkflowKeyboardFocusPolicy.initialActionID(
          cancelActionID: "revert",
          isCancelActionDisabled: true
        ) == nil
      )
    }

    @Test("workflow action layout keeps wide and stacked button frames inside the footer")
    func actionLayoutKeepsButtonsInsideFooter() {
      let bounds = CGRect(x: 0, y: 0, width: 472, height: 200)
      let horizontalSizes = [
        CGSize(width: 80, height: 30),
        CGSize(width: 130, height: 30),
        CGSize(width: 170, height: 30),
      ]
      #expect(
        !WorkflowActionBarLayoutPolicy.requiresStackedLayout(
          forceStacked: false,
          availableWidth: bounds.width,
          idealItemWidths: horizontalSizes.map(\.width)
        )
      )
      let horizontalFrames = WorkflowActionBarLayoutPolicy.frames(
        in: bounds,
        itemSizes: horizontalSizes,
        isStacked: false
      )
      #expect(horizontalFrames.first?.minX == bounds.minX)
      #expect(horizontalFrames.last?.maxX == bounds.maxX)
      #expect(horizontalFrames.allSatisfy { bounds.contains($0) })
      #expect(!horizontalFrames[0].intersects(horizontalFrames[1]))
      #expect(!horizontalFrames[1].intersects(horizontalFrames[2]))

      let longIdealWidths: [CGFloat] = [80, 650, 520]
      #expect(
        WorkflowActionBarLayoutPolicy.requiresStackedLayout(
          forceStacked: false,
          availableWidth: bounds.width,
          idealItemWidths: longIdealWidths
        )
      )
      let stackedFrames = WorkflowActionBarLayoutPolicy.frames(
        in: bounds,
        itemSizes: [
          CGSize(width: 80, height: 30),
          CGSize(width: 440, height: 54),
          CGSize(width: 430, height: 54),
        ],
        isStacked: true
      )
      #expect(stackedFrames.allSatisfy { bounds.contains($0) })
      #expect(stackedFrames[0].minX == bounds.minX)
      #expect(stackedFrames[1].maxX == bounds.maxX)
      #expect(stackedFrames[2].maxX == bounds.maxX)
      #expect(stackedFrames[0].maxY < stackedFrames[1].minY)
      #expect(stackedFrames[1].maxY < stackedFrames[2].minY)
    }

    @Test("Korean permission and dirty-draft workflows render at minimum size with large text")
    func rendersMinimumLargeTextWorkflowStates() throws {
      let allFixtures = [
        Fixture(name: "26-permission-ko-minimum-large-text", state: .permissionDenied),
        Fixture(name: "27-dirty-apply-ko-minimum-large-text", state: .dirtyApply),
      ]
      let selectedFixture = ProcessInfo.processInfo.environment[
        "DESK_SETUP_WORKFLOW_RESPONSIVE_FIXTURE"
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
        setenv("DESK_SETUP_UI_AUDIT_LANGUAGE", "ko", 1)
        defer { unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE") }
        let rendered = try render(fixture)

        #expect(rendered.image.count > 10_000)
        #expect(rendered.notes.contains("synthetic-workflow-root=true"))
        #expect(rendered.notes.contains("expected-action-layout=stacked"))
        #expect(rendered.notes.contains("live-display-audio-network-mutations=false"))
        #expect(!rendered.notes.contains("/Users/"))
        #expect(!rendered.notes.localizedCaseInsensitiveContains("password"))
        let decodedImage = try #require(NSBitmapImageRep(data: rendered.image))
        #expect(!decodedImage.hasAlpha)
        let pixelStatistics = try pixelStatistics(for: decodedImage)
        #expect(pixelStatistics.brightSampleRatio > 0.85)
        #expect(pixelStatistics.darkSampleRatio < 0.01)
        #expect(
          pixelStatistics.backgroundSamples.allSatisfy { sample in
            sample.minimumComponent > 0.94
          })

        if let outputDirectory {
          try rendered.image.write(
            to: outputDirectory.appendingPathComponent("\(fixture.name).jpg"),
            options: .atomic
          )
          try rendered.notes.write(
            to: outputDirectory.appendingPathComponent("\(fixture.name).ax.txt"),
            atomically: true,
            encoding: .utf8
          )
        }
        unsetenv("DESK_SETUP_UI_AUDIT_LANGUAGE")
      }
    }

    private var evidenceOutputDirectory: URL? {
      guard
        ProcessInfo.processInfo.environment["DESK_SETUP_WRITE_WORKFLOW_RESPONSIVE_EVIDENCE"]
          == "1",
        let path = ProcessInfo.processInfo.environment[
          "DESK_SETUP_WORKFLOW_RESPONSIVE_EVIDENCE_DIR"]
      else { return nil }
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func render(_ fixture: Fixture) throws -> (image: Data, notes: String) {
      let configuration = UIAuditConfiguration(
        isEnabled: true,
        variant: .editorDisplay,
        displayMode: .largeText,
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

      switch fixture.state {
      case .permissionDenied:
        presentation.setWorkflowDestination(.permission(.captureDenied))
      case .dirtyApply:
        let openProfile = try #require(model.profiles.first)
        let targetProfile = try #require(model.profiles.dropFirst().first)
        editor.initialize(profiles: model.profiles, preferredProfileID: openProfile.id)
        #expect(
          editor.updateDraft { draft in
            draft.name = "집중 업무용 디스플레이와 오디오 및 네트워크를 포함하는 매우 긴 프로필 이름"
          })
        presentation.setWorkflowDestination(.applyPreview(targetProfile.id, .normal))
        presentation.beginApplyWorkflow(profileID: targetProfile.id, mode: .normal)
        let prompt = try #require(presentation.applyDraftPrompt)
        #expect(prompt.targetProfileName == targetProfile.name)
        #expect(presentation.applyDraftMessage.contains(targetProfile.name))
      }

      let size = CGSize(width: 520, height: 360)
      let root = ZStack {
        Color.white
          .ignoresSafeArea()
        TrayWorkflowRootView(presentation: presentation, onClose: {})
          .environmentObject(model)
          .environmentObject(permission)
      }
      .environment(\.locale, Locale(identifier: "ko"))
      .environment(\.colorScheme, .light)
      .dynamicTypeSize(.accessibility3)
      .preferredColorScheme(.light)
      .uiAuditEnvironment(configuration)
      .frame(width: size.width, height: size.height)

      let host = NSHostingView(rootView: root)
      host.frame = NSRect(origin: .zero, size: size)
      host.appearance = NSAppearance(named: .aqua)
      host.autoresizingMask = [.width, .height]
      let container = NSView(frame: NSRect(origin: .zero, size: size))
      container.wantsLayer = true
      container.layer?.backgroundColor = NSColor.white.cgColor
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
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
      host.needsLayout = true
      host.needsDisplay = true
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()

      let representation = try #require(
        container.bitmapImageRepForCachingDisplay(in: container.bounds)
      )
      container.cacheDisplay(in: container.bounds, to: representation)
      let image = try opaqueJPEG(from: representation)
      #expect(representation.pixelsWide >= Int(size.width))
      #expect(representation.pixelsHigh >= Int(size.height))

      var lines = [
        "source=TrayWorkflowRootView in attached offscreen NSWindow",
        "synthetic-workflow-root=true",
        "fixture=\(fixture.name)",
        "state=\(fixture.state.rawValue)",
        "language=ko",
        "viewport=520x360",
        "dynamic-type=accessibility3",
        "expected-action-layout=stacked",
        "image-format=jpeg",
        "image-has-alpha=false",
        "opaque-background-pixel-assertion=true",
        "live-display-audio-network-mutations=false",
        "offscreen-ax-limit=virtual SwiftUI children require an onscreen accessibility host",
      ]
      var visited: Set<ObjectIdentifier> = []
      appendAccessibility(host, depth: 0, lines: &lines, visited: &visited)
      return (image, lines.joined(separator: "\n") + "\n")
    }

    private func opaqueJPEG(from source: NSBitmapImageRep) throws -> Data {
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
      let opaqueData = try #require(opaque.bitmapData)
      for y in 0..<height {
        autoreleasepool {
          for x in 0..<width {
            let color = source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .clear
            let alpha = color.alphaComponent
            let whiteContribution = 1 - alpha
            let rgbOffset = y * opaque.bytesPerRow + x * 3
            opaqueData[rgbOffset] = UInt8(
              max(0, min(255, Int((color.redComponent * alpha + whiteContribution) * 255))))
            opaqueData[rgbOffset + 1] = UInt8(
              max(0, min(255, Int((color.greenComponent * alpha + whiteContribution) * 255))))
            opaqueData[rgbOffset + 2] = UInt8(
              max(0, min(255, Int((color.blueComponent * alpha + whiteContribution) * 255))))
          }
        }
      }
      opaque.size = source.size
      #expect(!opaque.hasAlpha)
      return try #require(
        opaque.representation(
          using: .jpeg,
          properties: [.compressionFactor: NSNumber(value: 0.98)]
        )
      )
    }

    private func pixelStatistics(for image: NSBitmapImageRep) throws -> PixelStatistics {
      let width = image.pixelsWide
      let height = image.pixelsHigh
      #expect(width > 0)
      #expect(height > 0)

      var brightSampleCount = 0
      var darkSampleCount = 0
      var sampledPixelCount = 0
      for y in stride(from: 0, to: height, by: 4) {
        for x in stride(from: 0, to: width, by: 4) {
          guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            continue
          }
          sampledPixelCount += 1
          if min(color.redComponent, color.greenComponent, color.blueComponent) >= 0.94 {
            brightSampleCount += 1
          }
          if max(color.redComponent, color.greenComponent, color.blueComponent) <= 0.06 {
            darkSampleCount += 1
          }
        }
      }
      #expect(sampledPixelCount > 0)

      let backgroundCoordinates = [
        (x: 8, y: 8),
        (x: width - 9, y: 8),
        (x: 8, y: height - 9),
        (x: width - 9, y: height - 9),
        (x: width / 2, y: height / 2),
      ]
      let backgroundSamples = try backgroundCoordinates.map { coordinate in
        let color = try #require(
          image.colorAt(x: coordinate.x, y: coordinate.y)?.usingColorSpace(.sRGB)
        )
        return RGBSample(
          red: color.redComponent,
          green: color.greenComponent,
          blue: color.blueComponent
        )
      }

      return PixelStatistics(
        brightSampleRatio: Double(brightSampleCount) / Double(sampledPixelCount),
        darkSampleRatio: Double(darkSampleCount) / Double(sampledPixelCount),
        backgroundSamples: backgroundSamples
      )
    }

    private func appendAccessibility(
      _ object: AnyObject,
      depth: Int,
      lines: inout [String],
      visited: inout Set<ObjectIdentifier>
    ) {
      guard depth < 20 else { return }
      let objectID = ObjectIdentifier(object)
      guard visited.insert(objectID).inserted else { return }

      let role: String
      let label: String?
      let identifier: String?
      let children: [Any]
      if let view = object as? NSView {
        role = view.accessibilityRole()?.rawValue ?? "AXUnknown"
        label = view.accessibilityLabel()
        identifier = view.accessibilityIdentifier()
        children = view.accessibilityChildren() ?? view.subviews
      } else if let element = object as? NSAccessibilityElement {
        role = element.accessibilityRole()?.rawValue ?? "AXUnknown"
        label = element.accessibilityLabel()
        identifier = element.accessibilityIdentifier()
        children = element.accessibilityChildren() ?? []
      } else {
        return
      }

      let indentation = String(repeating: "  ", count: depth)
      let values = [
        "role=\(role)",
        label.map { "label=\($0)" },
        identifier.map { "identifier=\($0)" },
      ].compactMap { $0 }
      lines.append(indentation + values.joined(separator: " "))
      for child in children {
        appendAccessibility(child as AnyObject, depth: depth + 1, lines: &lines, visited: &visited)
      }
    }
  }
#endif
